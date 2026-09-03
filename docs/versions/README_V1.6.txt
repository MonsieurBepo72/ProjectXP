PROJECT XP — COMMUNICATEUR + COMPAGNIE V1.6
===========================================

Cette version corrige ensemble les problèmes remontés après la V1.5.

CE QUI CHANGE
-------------

1) BADGES / TÉLÉPHONE GLOBAL EN TEMPS RÉEL
- Le téléphone global écoute maintenant le vrai compteur du Centre de notifications.
- Une nouvelle invitation Compagnie reçue via Supabase fait monter le badge sans changer de page.
- Le téléphone global déclenche aussi son animation lorsqu'un nouveau compteur Notifications arrive.
- Le Hall écoute le même compteur Notifications en temps réel.

2) PAS DE TÉLÉPHONE EN DOUBLE DANS LE COMMUNICATEUR
- Quand le Communicateur XP est ouvert, le téléphone global reste masqué.
- Il reste également masqué dans Messages, Amis, Demandes et Notifications.
- La flèche de retour ramène normalement vers le Communicateur.

3) PSEUDOS DES MEMBRES DE COMPAGNIE
- Les membres arrivés depuis Supabase ne doivent plus retomber sur « Joueur ».
- TeamStorage récupère leur display_name public dans tavern_profiles et enrichit le cache legacy utilisé par l'écran équipe.
- Aucun compte distant n'est transformé en vrai compte de connexion local : ce sont uniquement des stubs legacy de résolution de pseudo.

4) INVITATIONS DEPUIS « TROUVER DES JOUEURS »
- Une équipe où le joueur est déjà membre est verrouillée : « Déjà membre de cette équipe ».
- Une invitation déjà en attente est verrouillée : « Invitation déjà en attente ».
- Une équipe pleine est verrouillée.
- Le message « Tu dois être Chef ou Admin » n'est affiché que si tu ne gères réellement aucune équipe.
- La fiche du joueur désactive aussi le bouton principal lorsque aucune invitation n'est possible :
  « DÉJÀ MEMBRE DE TON ÉQUIPE », « INVITATION DÉJÀ EN ATTENTE », etc.

5) FOND D'ÉCRAN PERSONNALISÉ DU COMMUNICATEUR
- Nouvelle icône Fond d'écran en haut à droite de l'accueil du Communicateur.
- « Choisir une image » ouvre la galerie du téléphone.
- L'image est copiée dans le stockage interne de Project XP afin de ne pas dépendre du fichier temporaire d'image_picker.
- Le réglage est enregistré par compte local.
- Un voile sombre automatique garde l'heure et les icônes lisibles.
- « Fond Project XP » restaure le fond par défaut.

IMPORTANT — SUPABASE REALTIME
-----------------------------

La V1.4/V1.5 a créé compagnie_team_invitations mais n'activait pas encore sa diffusion Realtime.

Si tu as DÉJÀ exécuté :
  supabase/compagnie_online_invitations_v1.sql

NE le relance pas pour cette étape.

Exécute maintenant UNE FOIS dans Supabase > SQL Editor :
  supabase/compagnie_notifications_realtime_v1.sql

Le script est idempotent : il vérifie d'abord si la table est déjà présente dans supabase_realtime.

INSTALLATION DE A À Z
---------------------

1. Extraire le ZIP à la racine :
   C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

2. Ouvrir Supabase > SQL Editor > New query.

3. Ouvrir localement :
   supabase/compagnie_notifications_realtime_v1.sql

4. Copier tout son contenu dans SQL Editor puis cliquer sur Run.
   Si Supabase affiche une erreur rouge : s'arrêter et envoyer l'erreur avant de continuer.

5. Dans PowerShell, à la racine du projet :
   flutter analyze

6. Si l'analyse est propre, lancer l'app sur les deux téléphones avec leur cible adb/flutter respective.

TEST 1 — BADGE GLOBAL
---------------------
Tel2 reste sur une page normale de Project XP où le petit téléphone global est visible.
Tel1 : Trouver des joueurs > Tel2 > inviter dans une Compagnie.
Résultat attendu sur Tel2 sans changer de page :
- badge Notifications qui augmente sur le téléphone global ;
- animation du téléphone global.

TEST 2 — COMMUNICATEUR SANS TÉLÉPHONE EN DOUBLE
------------------------------------------------
Tel2 : Communicateur > Amis, puis Demandes, puis Notifications, puis Messages.
Résultat attendu : aucun petit téléphone global en haut à droite dans ces quatre sous-écrans.

TEST 3 — PSEUDO ÉQUIPE
----------------------
Après que Tel2 a rejoint l'équipe :
Tel1 > Mes équipes > ouvrir l'équipe > actualiser.
Résultat attendu : le vrai pseudo public de Tel2 est affiché à la place de « Joueur ».

TEST 4 — RÉINVITATION
---------------------
Tel1 > Trouver des joueurs > rouvrir Tel2.
- si Tel2 est déjà membre de toutes les équipes gérées : bouton « DÉJÀ MEMBRE DE TON ÉQUIPE » désactivé ;
- si une invitation est encore pending : bouton « INVITATION DÉJÀ EN ATTENTE » désactivé ;
- si plusieurs équipes sont gérées, seules celles réellement disponibles peuvent être choisies.

TEST 5 — FOND D'ÉCRAN
---------------------
Communicateur > icône Fond d'écran en haut à droite > Choisir une image.
Sélectionner par exemple la même photo utilisée comme fond du vrai téléphone.
Résultat attendu : elle devient le fond du Communicateur avec un voile sombre de lisibilité.

NOTE
----
Android ne permet pas de récupérer proprement et universellement le vrai wallpaper système sans permissions intrusives sur les versions récentes. La sélection depuis la galerie reproduit donc le même résultat visuel sans demander une permission disproportionnée.
