-- Project XP - Sécurité Edge V1
-- 2026-09-04
--
-- Objectifs :
--   1. quotas atomiques par utilisateur / fonction pour protéger les APIs tierces ;
--   2. idempotence avec lease pour le webhook de notifications privées ;
--   3. aucun accès direct depuis anon/authenticated à ces tables techniques.

begin;

-- ---------------------------------------------------------------------------
-- RATE LIMITS EDGE FUNCTIONS
-- ---------------------------------------------------------------------------

create table if not exists public.project_xp_edge_rate_limits (
  scope text not null,
  subject text not null,
  window_started_at timestamptz not null default clock_timestamp(),
  hit_count integer not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  constraint project_xp_edge_rate_limits_pkey
    primary key (scope, subject),
  constraint project_xp_edge_rate_limits_hit_count_check
    check (hit_count >= 0)
);

alter table public.project_xp_edge_rate_limits
  enable row level security;

revoke all on table public.project_xp_edge_rate_limits
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.project_xp_edge_rate_limits
  to service_role;

create or replace function public.project_xp_consume_edge_rate_limit(
  p_scope text,
  p_subject text,
  p_limit integer,
  p_window_seconds integer
)
returns table (
  allowed boolean,
  remaining integer,
  reset_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_started timestamptz;
  v_count integer;
  v_reset timestamptz;
begin
  if p_scope is null or btrim(p_scope) = '' or char_length(p_scope) > 120 then
    raise exception 'invalid rate-limit scope';
  end if;

  if p_subject is null or btrim(p_subject) = '' or char_length(p_subject) > 160 then
    raise exception 'invalid rate-limit subject';
  end if;

  if p_limit < 1 or p_limit > 10000 then
    raise exception 'invalid rate-limit maximum';
  end if;

  if p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'invalid rate-limit window';
  end if;

  -- Sérialise uniquement une même paire scope/utilisateur. Deux utilisateurs
  -- différents ne se bloquent jamais mutuellement.
  perform pg_advisory_xact_lock(
    hashtextextended(
      btrim(p_scope) || chr(31) || btrim(p_subject),
      0
    )
  );

  select
    rate.window_started_at,
    rate.hit_count
  into
    v_started,
    v_count
  from public.project_xp_edge_rate_limits as rate
  where rate.scope = btrim(p_scope)
    and rate.subject = btrim(p_subject)
  for update;

  if not found or
      v_now >= v_started + make_interval(secs => p_window_seconds) then
    insert into public.project_xp_edge_rate_limits (
      scope,
      subject,
      window_started_at,
      hit_count,
      updated_at
    ) values (
      btrim(p_scope),
      btrim(p_subject),
      v_now,
      1,
      v_now
    )
    on conflict (scope, subject)
    do update set
      window_started_at = excluded.window_started_at,
      hit_count = 1,
      updated_at = excluded.updated_at;

    return query
      select
        true,
        greatest(p_limit - 1, 0),
        v_now + make_interval(secs => p_window_seconds);
    return;
  end if;

  v_reset :=
    v_started + make_interval(secs => p_window_seconds);

  if v_count >= p_limit then
    return query
      select false, 0, v_reset;
    return;
  end if;

  update public.project_xp_edge_rate_limits
  set
    hit_count = hit_count + 1,
    updated_at = v_now
  where scope = btrim(p_scope)
    and subject = btrim(p_subject);

  return query
    select
      true,
      greatest(p_limit - (v_count + 1), 0),
      v_reset;
end;
$$;

revoke all on function public.project_xp_consume_edge_rate_limit(
  text,
  text,
  integer,
  integer
) from public, anon, authenticated;

grant execute on function public.project_xp_consume_edge_rate_limit(
  text,
  text,
  integer,
  integer
) to service_role;

-- ---------------------------------------------------------------------------
-- IDEMPOTENCE DES NOTIFICATIONS PRIVÉES
-- ---------------------------------------------------------------------------

create table if not exists public.project_xp_private_message_notification_deliveries (
  message_id text primary key,
  delivery_state text not null default 'processing',
  lease_until timestamptz,
  attempt_count integer not null default 1,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint project_xp_private_message_notification_state_check
    check (delivery_state in ('processing', 'sent', 'failed')),
  constraint project_xp_private_message_notification_attempt_check
    check (attempt_count >= 1)
);

create index if not exists
  project_xp_private_message_notification_deliveries_updated_idx
on public.project_xp_private_message_notification_deliveries (updated_at);

alter table public.project_xp_private_message_notification_deliveries
  enable row level security;

revoke all on table public.project_xp_private_message_notification_deliveries
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.project_xp_private_message_notification_deliveries
  to service_role;

create or replace function public.project_xp_claim_private_message_notification(
  p_message_id text,
  p_lease_seconds integer default 120
)
returns table (
  claimed boolean,
  delivery_state text,
  attempt_count integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_state text;
  v_lease_until timestamptz;
  v_attempts integer;
begin
  if p_message_id is null or btrim(p_message_id) = '' or
      char_length(p_message_id) > 200 then
    raise exception 'invalid private-message id';
  end if;

  if p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'invalid notification lease';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'project-xp-private-message-notification:' || btrim(p_message_id),
      0
    )
  );

  select
    delivery.delivery_state,
    delivery.lease_until,
    delivery.attempt_count
  into
    v_state,
    v_lease_until,
    v_attempts
  from public.project_xp_private_message_notification_deliveries as delivery
  where delivery.message_id = btrim(p_message_id)
  for update;

  if not found then
    insert into public.project_xp_private_message_notification_deliveries (
      message_id,
      delivery_state,
      lease_until,
      attempt_count,
      last_error,
      created_at,
      updated_at
    ) values (
      btrim(p_message_id),
      'processing',
      v_now + make_interval(secs => p_lease_seconds),
      1,
      null,
      v_now,
      v_now
    );

    return query select true, 'processing'::text, 1;
    return;
  end if;

  if v_state = 'sent' then
    return query select false, 'sent'::text, v_attempts;
    return;
  end if;

  if v_state = 'processing' and
      v_lease_until is not null and
      v_lease_until > v_now then
    return query select false, 'processing'::text, v_attempts;
    return;
  end if;

  update public.project_xp_private_message_notification_deliveries as delivery
  set
    delivery_state = 'processing',
    lease_until = v_now + make_interval(secs => p_lease_seconds),
    attempt_count = delivery.attempt_count + 1,
    last_error = null,
    updated_at = v_now
  where delivery.message_id = btrim(p_message_id)
  returning delivery.attempt_count into v_attempts;

  return query select true, 'processing'::text, v_attempts;
end;
$$;

revoke all on function public.project_xp_claim_private_message_notification(
  text,
  integer
) from public, anon, authenticated;

grant execute on function public.project_xp_claim_private_message_notification(
  text,
  integer
) to service_role;

create or replace function public.project_xp_finish_private_message_notification(
  p_message_id text,
  p_success boolean,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_message_id is null or btrim(p_message_id) = '' then
    return;
  end if;

  update public.project_xp_private_message_notification_deliveries
  set
    delivery_state = case
      when p_success then 'sent'
      else 'failed'
    end,
    lease_until = null,
    last_error = case
      when p_success then null
      else left(coalesce(nullif(btrim(p_error), ''), 'delivery_failed'), 300)
    end,
    updated_at = clock_timestamp()
  where message_id = btrim(p_message_id);
end;
$$;

revoke all on function public.project_xp_finish_private_message_notification(
  text,
  boolean,
  text
) from public, anon, authenticated;

grant execute on function public.project_xp_finish_private_message_notification(
  text,
  boolean,
  text
) to service_role;

comment on table public.project_xp_edge_rate_limits is
  'Compteurs techniques serveur pour limiter les Edge Functions Project XP.';

comment on table public.project_xp_private_message_notification_deliveries is
  'État idempotent des notifications FCM privées Project XP.';

commit;
