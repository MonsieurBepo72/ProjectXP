-- ============================================================================
-- PROJECT XP - MODÉRATION V2.4.6.2
-- RPC LEXIQUE MONDIAL V2.3 / CORRECTION D'ALIGNEMENT EDGE FUNCTION
--
-- L'Edge Function send-moderated-message appelle :
--   public.project_xp_match_global_lexicon_v23(p_candidates, p_languages)
--
-- La fondation V2.2 historique ne créait que :
--   public.project_xp_match_global_lexicon(p_candidates)
--
-- Cette migration ajoute donc le RPC réellement attendu par l'Edge Function.
-- Elle ne supprime pas le RPC historique et ne modifie aucune donnée du lexique.
-- ============================================================================

begin;

-- Une éventuelle ancienne variante de même signature est remplacée proprement.
drop function if exists public.project_xp_match_global_lexicon_v23(text[], text[]);

create function public.project_xp_match_global_lexicon_v23(
  p_candidates text[],
  p_languages text[]
)
returns table (
  term text,
  normalized_term text,
  language_code text,
  action text
)
language sql
stable
security definer
set search_path = public
as $$
  with requested_languages as (
    select distinct lower(btrim(value)) as language_code
    from unnest(
      coalesce(
        p_languages,
        array[]::text[]
      )
    ) as value
    where btrim(value) <> ''
  )
  select
    l.term,
    l.normalized_term,
    l.language_code,
    l.action
  from public.moderation_global_lexicon as l
  where l.active = true
    and l.normalized_term = any(
      coalesce(
        p_candidates,
        array[]::text[]
      )
    )
    and (
      -- Un hard-block a été validé comme suffisamment grave et non ambigu :
      -- il ne dépend pas d'une détection de langue potentiellement imparfaite.
      l.action = 'hard_block'
      or not exists (
        select 1
        from requested_languages
      )
      or lower(l.language_code) in (
        select language_code
        from requested_languages
      )
    )
  order by
    case l.action
      when 'hard_block' then 0
      when 'context' then 1
      else 2
    end,
    char_length(l.normalized_term) desc
  limit 100;
$$;

-- Le téléphone ne doit jamais pouvoir interroger directement le lexique mondial.
revoke all
on function public.project_xp_match_global_lexicon_v23(text[], text[])
from public,
     anon,
     authenticated;

grant execute
on function public.project_xp_match_global_lexicon_v23(text[], text[])
to service_role;

comment on function public.project_xp_match_global_lexicon_v23(text[], text[])
is 'Project XP moderation: indexed worldwide lexicon lookup used by send-moderated-message V2.4.6.2.';

commit;
