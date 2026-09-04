-- ============================================================================
-- PROJECT XP - CONTRÔLE RPC LEXIQUE MONDIAL V2.3
-- Lecture seule : cette requête ne modifie rien.
-- ============================================================================

-- 1. Le RPC attendu par send-moderated-message existe-t-il avec la bonne
--    signature ?
select
  p.oid::regprocedure::text as rpc_signature
from pg_proc p
join pg_namespace n
  on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'project_xp_match_global_lexicon_v23';

-- 2. Vérification des droits : seul service_role doit pouvoir l'exécuter.
select
  has_function_privilege(
    'service_role',
    'public.project_xp_match_global_lexicon_v23(text[],text[])',
    'EXECUTE'
  ) as service_role_can_execute,
  has_function_privilege(
    'authenticated',
    'public.project_xp_match_global_lexicon_v23(text[],text[])',
    'EXECUTE'
  ) as authenticated_can_execute,
  has_function_privilege(
    'anon',
    'public.project_xp_match_global_lexicon_v23(text[],text[])',
    'EXECUTE'
  ) as anon_can_execute;

-- 3. Probe réel sur le premier terme actif du lexique.
--    Si le lexique est importé, cette requête doit retourner au moins la ligne
--    choisie comme probe. Un hard_block reste détectable même si la langue
--    fournie ne correspond pas ; context/vulgarity restent filtrés par langue.
with probe as (
  select
    normalized_term,
    language_code
  from public.moderation_global_lexicon
  where active = true
  order by
    case action
      when 'hard_block' then 0
      when 'context' then 1
      else 2
    end,
    id
  limit 1
)
select match.*
from probe
cross join lateral public.project_xp_match_global_lexicon_v23(
  array[probe.normalized_term],
  array[probe.language_code]
) as match;
