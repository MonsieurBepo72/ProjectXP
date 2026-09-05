-- ============================================================================
-- PROJECT XP - MODERATION DEGRADED MODE V1
-- Base de travail : commit 0e4dacdaeacf93b3f9e6cb7dd1567bf31f52961a
--
-- Objectif :
--   - conserver exactement le hard-block lexical existant ;
--   - ne plus confondre une panne technique SQL avec un contenu interdit ;
--   - permettre aux inserts du backend service_role de continuer en mode degrade ;
--   - garder les inserts directs/non-backend en mode strict (fail-closed).
--
-- Aucun changement de lexique, aucun changement Steam, aucun secret.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1) Copie STRICTE de la logique actuelle.
--    Cette fonction garde le comportement fail-closed original.
-- ---------------------------------------------------------------------------

create or replace function public.project_xp_assert_message_allowed_strict(
  p_content text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_text text;
  v_compact_text text;
  v_term text;
  v_compact_term text;
  v_blocked record;
begin
  v_text :=
    public.project_xp_moderation_normalize(
      p_content
    );

  if v_text = '' then
    return;
  end if;

  v_compact_text :=
    replace(
      v_text,
      ' ',
      ''
    );

  for v_blocked in
    select
      term,
      compact_match
    from public.moderation_blocked_terms
    where active = true
  loop
    v_term :=
      public.project_xp_moderation_normalize(
        v_blocked.term
      );

    if v_term = '' then
      continue;
    end if;

    if position(
      ' ' || v_term || ' '
      in
      ' ' || v_text || ' '
    ) > 0 then
      raise exception
        'PROJECT_XP_CONTENT_BLOCKED'
        using errcode = 'P0001';
    end if;

    if v_blocked.compact_match then
      v_compact_term :=
        replace(
          v_term,
          ' ',
          ''
        );

      if char_length(v_compact_term) >= 5
         and position(
           v_compact_term
           in
           v_compact_text
         ) > 0 then
        raise exception
          'PROJECT_XP_CONTENT_BLOCKED'
          using errcode = 'P0001';
      end if;
    end if;
  end loop;
end;
$$;

-- La fonction stricte est un detail serveur. On ne l'expose pas aux clients.
revoke all
on function public.project_xp_assert_message_allowed_strict(text)
from public, anon, authenticated;

grant execute
on function public.project_xp_assert_message_allowed_strict(text)
to service_role;

-- ---------------------------------------------------------------------------
-- 2) RPC utilise par send-moderated-message.
--
--    - P0001 + PROJECT_XP_CONTENT_BLOCKED : on RELEVE l'erreur => vrai blocage.
--    - toute autre erreur technique       : WARNING + retour normal => degrade.
--
--    La signature reste identique, donc le code 2.4.8 n'a pas besoin d'etre
--    remplace ni redeploye pour profiter de cette correction.
-- ---------------------------------------------------------------------------

create or replace function public.project_xp_assert_message_allowed(
  p_content text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform
    public.project_xp_assert_message_allowed_strict(
      p_content
    );
exception
  when sqlstate 'P0001' then
    if sqlerrm = 'PROJECT_XP_CONTENT_BLOCKED' then
      raise;
    end if;

    raise warning
      'PROJECT_XP_MODERATION_DEGRADED sqlstate=% message=%',
      sqlstate,
      sqlerrm;

    return;

  when others then
    raise warning
      'PROJECT_XP_MODERATION_DEGRADED sqlstate=% message=%',
      sqlstate,
      sqlerrm;

    return;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Triggers : distinction backend de confiance / insert direct.
--
--    Edge Function (service_role) : utilise le wrapper degrade.
--    Client direct / SQL ordinaire : utilise la fonction stricte.
--
--    Ainsi une panne de moderation ne bloque pas l'Edge Function, mais elle
--    n'ouvre pas non plus une voie de contournement par insert direct client.
-- ---------------------------------------------------------------------------

create or replace function public.project_xp_moderate_tavern_message()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    perform
      public.project_xp_assert_message_allowed(
        new.content
      );
  else
    perform
      public.project_xp_assert_message_allowed_strict(
        new.content
      );
  end if;

  return new;
end;
$$;

create or replace function public.project_xp_moderate_private_message()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    perform
      public.project_xp_assert_message_allowed(
        new.content
      );
  else
    perform
      public.project_xp_assert_message_allowed_strict(
        new.content
      );
  end if;

  return new;
end;
$$;

commit;
