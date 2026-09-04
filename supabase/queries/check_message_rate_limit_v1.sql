-- ============================================================================
-- PROJECT XP - CONTROLE RATE LIMIT MESSAGES V1.2
--
-- Test volontairement explicite : 7 instructions SQL distinctes.
-- Cela évite toute mutualisation possible d'un appel de fonction par le planner.
-- Tout est annulé à la fin par ROLLBACK.
-- ============================================================================

-- 1. Structure et droits.
select
  to_regclass(
    'public.project_xp_message_rate_limits'
  ) as rate_limit_table,
  has_function_privilege(
    'service_role',
    'public.project_xp_consume_message_rate_limit(uuid,text)',
    'EXECUTE'
  ) as service_role_can_execute,
  has_function_privilege(
    'authenticated',
    'public.project_xp_consume_message_rate_limit(uuid,text)',
    'EXECUTE'
  ) as authenticated_can_execute,
  has_function_privilege(
    'anon',
    'public.project_xp_consume_message_rate_limit(uuid,text)',
    'EXECUTE'
  ) as anon_can_execute;

begin;

create temporary table project_xp_rate_limit_probe (
  call_number integer not null,
  allowed boolean not null,
  retry_after_seconds integer not null,
  limit_scope text not null,
  burst_remaining integer not null,
  minute_remaining integer not null
) on commit drop;

-- On choisit un utilisateur de test existant.
create temporary table project_xp_rate_limit_probe_user (
  user_id uuid primary key
) on commit drop;

insert into project_xp_rate_limit_probe_user(user_id)
select id
from auth.users
order by created_at
limit 1;

do $$
begin
  if not exists (
    select 1
    from project_xp_rate_limit_probe_user
  ) then
    raise exception 'Aucun utilisateur auth disponible pour le test.';
  end if;
end;
$$;

delete from public.project_xp_message_rate_limits
where user_id = (
  select user_id
  from project_xp_rate_limit_probe_user
)
and surface = 'tavern';

-- 7 consommations réellement séparées.
insert into project_xp_rate_limit_probe
select
  1,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

insert into project_xp_rate_limit_probe
select
  2,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

insert into project_xp_rate_limit_probe
select
  3,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

insert into project_xp_rate_limit_probe
select
  4,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

insert into project_xp_rate_limit_probe
select
  5,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

insert into project_xp_rate_limit_probe
select
  6,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

insert into project_xp_rate_limit_probe
select
  7,
  decision.allowed,
  decision.retry_after_seconds,
  decision.limit_scope,
  decision.burst_remaining,
  decision.minute_remaining
from project_xp_rate_limit_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) decision;

select
  call_number,
  allowed,
  retry_after_seconds,
  limit_scope,
  burst_remaining,
  minute_remaining
from project_xp_rate_limit_probe
order by call_number;

-- État réel du compteur après les 7 instructions.
select
  surface,
  burst_count,
  minute_count,
  burst_window_started_at,
  minute_window_started_at
from public.project_xp_message_rate_limits
where user_id = (
  select user_id
  from project_xp_rate_limit_probe_user
)
and surface = 'tavern';

rollback;
