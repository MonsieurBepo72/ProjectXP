CORRECTIF SCRIPT WINDOWS CRLF
=============================
Ce paquet remplace le premier ZIP V1.10.3a dont le script pouvait echouer sur les retours a la ligne Windows (CRLF).
Il est re-executable : si main.dart a deja ete modifie par la premiere tentative, il le detecte et continue sans doubler le patch.

PROJECT XP — V1.10.3a
SYNC GLOBALE PERSISTANTE + SUCCÈS STEAM + COVERS IGDB
=====================================================

CORRECTIONS
-----------

1. La synchronisation Steam devient globale :
   - elle ne dépend plus de l'écran Bibliothèque ;
   - changer de page ne l'interrompt plus ;
   - rouvrir la Bibliothèque récupère immédiatement la progression courante.

2. Bandeau discret global :
   - début / progression de synchro ;
   - fin réussie ;
   - échec avec message lisible.

3. Résumé corrigé :
   - "jeux vérifiés" au lieu de l'ancien libellé trompeur "succès vérifiés" ;
   - nombre total de succès connus ajouté ;
   - les jeux en erreur sont conservés avec leur raison.

4. Succès Steam :
   - GetPlayerAchievements reste la source principale ;
   - fallback GetUserStatsForGame ajouté ;
   - GetSchemaForGame reste utilisé pour noms, descriptions, icônes et catalogue ;
   - si Steam expose un catalogue mais refuse temporairement la progression du
     joueur, Project XP le dit explicitement au lieu de confondre ce cas avec
     "aucun succès".
   - une erreur est retentée une fois avant d'être classée à revoir.

5. Covers :
   - les vrais assets Steam restent prioritaires ;
   - si toutes les covers connues échouent réellement à l'affichage,
     une recherche IGDB ciblée est lancée uniquement pour ce jeu ;
   - correspondance stricte par titre, avec année/plateforme comme score ;
   - la cover IGDB trouvée est sauvegardée dans la Bibliothèque ;
   - cooldown de 12 h après un échec pour éviter les requêtes répétitives.

INSTALLATION
------------

1. Extraire le ZIP à la racine :
   C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

2. Dans PowerShell, depuis cette racine :

   powershell -ExecutionPolicy Bypass -File .\APPLIQUER_V1.10.3a.ps1

3. Redéployer steam-sync (OBLIGATOIRE car sa logique a changé) :

   npx.cmd supabase functions deploy steam-sync

4. Vérifier Flutter :

   flutter analyze

   Résultat attendu :
   No issues found!

5. Fermer complètement Project XP puis relancer.

TESTS PRIORITAIRES
------------------

A. Lancer l'app.
   → le bandeau "Synchronisation..." doit apparaître discrètement.

B. Ouvrir Bibliothèque pendant la sync.
   → SYNCHRONISER TOUT doit montrer l'état courant.

C. Changer de page.
   → la synchro doit continuer.

D. Revenir Bibliothèque.
   → la progression courante doit toujours être affichée.

E. PALWORLD :
   → vérifier que les succès remontent désormais.
   → si Steam refuse encore la progression, le diagnostic doit indiquer
     explicitement que Steam expose bien un catalogue de succès.

F. MECHA CHAMELEON / BOXROOM :
   → laisser la carte apparaître ;
   → si les capsules Steam sont absentes, Project XP tente automatiquement IGDB ;
   → la cover doit apparaître si une correspondance exacte existe.

AUCUN NOUVEAU SQL
-----------------
Cette V1.10.3a n'ajoute aucune migration Supabase.
