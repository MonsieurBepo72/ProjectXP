-- PROJECT XP - VERIFICATION NON DESTRUCTIVE
-- Cette requete ne modifie aucune donnee persistante.

select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'project_xp_assert_message_allowed',
    'project_xp_assert_message_allowed_strict',
    'project_xp_moderate_tavern_message',
    'project_xp_moderate_private_message'
  )
order by p.proname;

select
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as enabled
from pg_trigger
where not tgisinternal
  and tgname in (
    'trg_project_xp_moderate_tavern_message',
    'trg_project_xp_moderate_private_message'
  )
order by tgname;

select
  position(
    'project_xp_assert_message_allowed_strict'
    in pg_get_functiondef(
      'public.project_xp_moderate_tavern_message()'::regprocedure
    )
  ) > 0 as tavern_uses_strict_path,
  position(
    'auth.jwt()'
    in pg_get_functiondef(
      'public.project_xp_moderate_tavern_message()'::regprocedure
    )
  ) > 0 as tavern_checks_backend_role,
  position(
    'project_xp_assert_message_allowed_strict'
    in pg_get_functiondef(
      'public.project_xp_moderate_private_message()'::regprocedure
    )
  ) > 0 as private_uses_strict_path,
  position(
    'auth.jwt()'
    in pg_get_functiondef(
      'public.project_xp_moderate_private_message()'::regprocedure
    )
  ) > 0 as private_checks_backend_role;

-- Verifie que le RPC accepte toujours un message neutre.
select public.project_xp_assert_message_allowed(
  'Project XP moderation verification message'
);

-- Verifie qu'un terme actif du hard-block declenche toujours le signal exact.
do $$
declare
  v_term text;
begin
  select term
  into v_term
  from public.moderation_blocked_terms
  where active = true
  order by id
  limit 1;

  if v_term is null then
    raise notice 'Aucun terme hard-block actif : test de blocage ignore.';
    return;
  end if;

  begin
    perform public.project_xp_assert_message_allowed(v_term);
    raise exception 'TEST_FAILED_EXPECTED_CONTENT_BLOCK';
  exception
    when sqlstate 'P0001' then
      if sqlerrm = 'PROJECT_XP_CONTENT_BLOCKED' then
        raise notice 'Hard-block lexical : OK';
      else
        raise;
      end if;
  end;
end;
$$;
