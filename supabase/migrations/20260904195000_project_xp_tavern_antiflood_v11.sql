-- ============================================================================
-- PROJECT XP - ANTI-FLOOD TAVERNE V1.1
--
-- Ajuste uniquement la rafale de la Taverne :
--   Taverne : 3 messages / 5 s, 25 messages / 60 s
--   Privé   : 8 messages / 5 s, 40 messages / 60 s
--
-- Le RPC reste atomique et réservé au service_role.
-- ============================================================================

begin;

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
    v_burst_limit := 3;
    v_minute_limit := 25;
  else
    v_burst_limit := 8;
    v_minute_limit := 40;
  end if;

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

comment on function public.project_xp_consume_message_rate_limit(uuid, text)
is 'Atomically consumes message quota: Tavern 3/5s + 25/60s, private 8/5s + 40/60s.';

commit;
