-- ============================================================================
-- PROJECT XP - ANTI-SPAM / RATE LIMIT MESSAGES V1
--
-- Protection serveur atomique pour send-moderated-message.
-- Deux fenêtres sont suivies séparément par utilisateur et par surface :
--   - burst : protection contre les rafales très rapides ;
--   - minute : protection contre le spam soutenu.
--
-- Quotas initiaux :
--   Taverne : 5 messages / 5 s, 25 messages / 60 s
--   Privé   : 8 messages / 5 s, 40 messages / 60 s
--
-- La table et le RPC ne sont accessibles qu'au service_role.
-- ============================================================================

begin;

create table if not exists public.project_xp_message_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  surface text not null
    check (surface in ('tavern', 'private')),
  burst_window_started_at timestamptz not null default clock_timestamp(),
  burst_count integer not null default 0
    check (burst_count >= 0),
  minute_window_started_at timestamptz not null default clock_timestamp(),
  minute_count integer not null default 0
    check (minute_count >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, surface)
);

alter table public.project_xp_message_rate_limits
  enable row level security;

revoke all
on table public.project_xp_message_rate_limits
from public,
     anon,
     authenticated;

grant select, insert, update, delete
on table public.project_xp_message_rate_limits
to service_role;

create or replace function public.project_xp_consume_message_rate_limit(
  p_user_id uuid,
  p_surface text
)
returns table (
  allowed boolean,
  retry_after_seconds integer,
  limit_scope text,
  burst_remaining integer,
  minute_remaining integer
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_surface text := lower(btrim(coalesce(p_surface, '')));

  v_burst_window interval := interval '5 seconds';
  v_minute_window interval := interval '60 seconds';

  v_burst_limit integer;
  v_minute_limit integer;

  v_burst_started timestamptz;
  v_burst_count integer;
  v_minute_started timestamptz;
  v_minute_count integer;

  v_burst_retry integer := 0;
  v_minute_retry integer := 0;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  if v_surface not in ('tavern', 'private') then
    raise exception 'invalid surface';
  end if;

  if v_surface = 'tavern' then
    v_burst_limit := 5;
    v_minute_limit := 25;
  else
    v_burst_limit := 8;
    v_minute_limit := 40;
  end if;

  -- Garantit qu'une ligne existe. En cas d'appels concurrents, l'un des INSERT
  -- attend la résolution du conflit avant le SELECT ... FOR UPDATE suivant.
  insert into public.project_xp_message_rate_limits (
    user_id,
    surface,
    burst_window_started_at,
    burst_count,
    minute_window_started_at,
    minute_count,
    updated_at
  )
  values (
    p_user_id,
    v_surface,
    v_now,
    0,
    v_now,
    0,
    v_now
  )
  on conflict (user_id, surface) do nothing;

  select
    rate.burst_window_started_at,
    rate.burst_count,
    rate.minute_window_started_at,
    rate.minute_count
  into
    v_burst_started,
    v_burst_count,
    v_minute_started,
    v_minute_count
  from public.project_xp_message_rate_limits as rate
  where rate.user_id = p_user_id
    and rate.surface = v_surface
  for update;

  -- Réinitialisation des fenêtres fixes expirées.
  if v_now >= v_burst_started + v_burst_window then
    v_burst_started := v_now;
    v_burst_count := 0;
  end if;

  if v_now >= v_minute_started + v_minute_window then
    v_minute_started := v_now;
    v_minute_count := 0;
  end if;

  if v_burst_count >= v_burst_limit then
    v_burst_retry :=
      greatest(
        1,
        ceil(
          extract(
            epoch from (
              (v_burst_started + v_burst_window) - v_now
            )
          )
        )::integer
      );
  end if;

  if v_minute_count >= v_minute_limit then
    v_minute_retry :=
      greatest(
        1,
        ceil(
          extract(
            epoch from (
              (v_minute_started + v_minute_window) - v_now
            )
          )
        )::integer
      );
  end if;

  if v_burst_retry > 0 or v_minute_retry > 0 then
    update public.project_xp_message_rate_limits
    set burst_window_started_at = v_burst_started,
        burst_count = v_burst_count,
        minute_window_started_at = v_minute_started,
        minute_count = v_minute_count,
        updated_at = v_now
    where user_id = p_user_id
      and surface = v_surface;

    allowed := false;
    retry_after_seconds :=
      greatest(v_burst_retry, v_minute_retry);
    limit_scope :=
      case
        when v_burst_retry > 0 and v_minute_retry > 0
          then 'burst_and_minute'
        when v_burst_retry > 0
          then 'burst'
        else 'minute'
      end;
    burst_remaining :=
      greatest(0, v_burst_limit - v_burst_count);
    minute_remaining :=
      greatest(0, v_minute_limit - v_minute_count);

    return next;
    return;
  end if;

  v_burst_count := v_burst_count + 1;
  v_minute_count := v_minute_count + 1;

  update public.project_xp_message_rate_limits
  set burst_window_started_at = v_burst_started,
      burst_count = v_burst_count,
      minute_window_started_at = v_minute_started,
      minute_count = v_minute_count,
      updated_at = v_now
  where user_id = p_user_id
    and surface = v_surface;

  allowed := true;
  retry_after_seconds := 0;
  limit_scope := 'ok';
  burst_remaining :=
    greatest(0, v_burst_limit - v_burst_count);
  minute_remaining :=
    greatest(0, v_minute_limit - v_minute_count);

  return next;
end;
$$;

revoke all
on function public.project_xp_consume_message_rate_limit(uuid, text)
from public,
     anon,
     authenticated;

grant execute
on function public.project_xp_consume_message_rate_limit(uuid, text)
to service_role;

comment on table public.project_xp_message_rate_limits
is 'Project XP server-side message anti-spam counters, private to service_role.';

comment on function public.project_xp_consume_message_rate_limit(uuid, text)
is 'Atomically consumes Tavern/private message quota for send-moderated-message.';

commit;
