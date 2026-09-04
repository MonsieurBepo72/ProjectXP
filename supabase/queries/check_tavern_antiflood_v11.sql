-- ============================================================================
-- PROJECT XP - CONTROLE ANTI-FLOOD TAVERNE V1.1
--
-- Attendu :
--   1 -> true  / burst_remaining 2
--   2 -> true  / burst_remaining 1
--   3 -> true  / burst_remaining 0
--   4 -> false / limit_scope burst / retry_after_seconds > 0
--
-- Tout est annulé à la fin par ROLLBACK.
-- ============================================================================

select
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

create temporary table project_xp_antiflood_probe_user (
  user_id uuid primary key
) on commit drop;

insert into project_xp_antiflood_probe_user(user_id)
select id
from auth.users
order by created_at
limit 1;

do $$
begin
  if not exists (
    select 1
    from project_xp_antiflood_probe_user
  ) then
    raise exception 'Aucun utilisateur auth disponible pour le test.';
  end if;
end;
$$;

delete from public.project_xp_message_rate_limits
where user_id = (
  select user_id
  from project_xp_antiflood_probe_user
)
and surface = 'tavern';

create temporary table project_xp_antiflood_probe (
  call_number integer not null,
  allowed boolean not null,
  retry_after_seconds integer not null,
  limit_scope text not null,
  burst_remaining integer not null,
  minute_remaining integer not null
) on commit drop;

insert into project_xp_antiflood_probe
select 1, d.*
from project_xp_antiflood_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) d;

insert into project_xp_antiflood_probe
select 2, d.*
from project_xp_antiflood_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) d;

insert into project_xp_antiflood_probe
select 3, d.*
from project_xp_antiflood_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) d;

insert into project_xp_antiflood_probe
select 4, d.*
from project_xp_antiflood_probe_user u
cross join lateral public.project_xp_consume_message_rate_limit(
  u.user_id,
  'tavern'
) d;

select
  call_number,
  allowed,
  retry_after_seconds,
  limit_scope,
  burst_remaining,
  minute_remaining
from project_xp_antiflood_probe
order by call_number;

rollback;
