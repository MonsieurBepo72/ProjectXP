-- PROJECT XP - CONTRÔLE PROGRESSION IMPORT V2.2.3

select
  source_key,
  import_enabled,
  imported_at,
  term_count,
  language_count,
  cardinality(imported_languages) as imported_languages_count,
  imported_languages
from public.moderation_lexicon_sources
where source_key = 'ldnoobwv2';

select
  count(*) as total_terms
from public.moderation_global_lexicon
where source_key = 'ldnoobwv2';
