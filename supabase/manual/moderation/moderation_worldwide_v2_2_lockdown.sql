-- ============================================================================
-- PROJECT XP - MODÉRATION V2.2 - LOCKDOWN FINAL
--
-- NE PAS EXÉCUTER AVANT :
--   - import du lexique réussi ;
--   - Edge Function send-moderated-message V2.2 déployée ;
--   - message normal testé ;
--   - message bloqué testé ;
--   - message privé testé.
--
-- Ce script empêche ensuite l'application cliente d'insérer directement
-- dans les tables de messages. Les insertions passent par l'Edge Function.
-- ============================================================================


revoke insert
on public.tavern_messages
from anon,
     authenticated;


revoke insert
on public.private_messages
from anon,
     authenticated;


-- La grosse base de lexique et les événements de modération restent
-- strictement côté serveur.
revoke all
on public.moderation_global_lexicon
from anon,
     authenticated;


revoke all
on public.moderation_lexicon_sources
from anon,
     authenticated;


revoke all
on public.moderation_events
from anon,
     authenticated;


-- ============================================================================
-- FIN
-- ============================================================================
