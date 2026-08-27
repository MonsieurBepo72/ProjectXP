-- ============================================================================
-- PROJECT XP - CONTRÔLES V2.2
-- Ces requêtes ne modifient rien.
-- ============================================================================


-- 1. État de l'import.
select
  source_key,
  display_name,
  license_name,
  source_revision,
  import_enabled,
  imported_at,
  term_count,
  language_count
from public.moderation_lexicon_sources
where source_key = 'ldnoobwv2';


-- 2. Nombre réel de termes.
select
  count(*) as total_terms
from public.moderation_global_lexicon
where source_key = 'ldnoobwv2'
  and active = true;


-- 3. Couverture par langue.
select
  language_code,
  count(*) as terms
from public.moderation_global_lexicon
where source_key = 'ldnoobwv2'
  and active = true
group by language_code
order by terms desc,
         language_code asc;


-- 4. Répartition des actions.
select
  action,
  count(*) as terms
from public.moderation_global_lexicon
where active = true
group by action
order by action;
