-- ============================================================================
-- PROJECT XP - MODÉRATION V2.2.3
-- PATCH DE PROGRESSION POUR IMPORT PAR LOTS
--
-- Cette migration ne supprime rien et ne touche pas aux messages.
-- Elle ajoute uniquement la liste des langues déjà importées.
-- ============================================================================

alter table public.moderation_lexicon_sources
add column if not exists imported_languages text[]
not null
default '{}'::text[];


-- État actuel après migration.
select
  source_key,
  import_enabled,
  imported_at,
  term_count,
  language_count,
  cardinality(imported_languages) as imported_languages_count
from public.moderation_lexicon_sources
where source_key = 'ldnoobwv2';
