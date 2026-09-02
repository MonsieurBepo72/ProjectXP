PROJECT XP — PORTAIL + BIBLIOTHÈQUE + STEAM V1.8.0
==================================================

OBJECTIF
--------
Faire du Terminal XP un vrai Portail des Aventuriers centré sur la vie gaming
personnelle du joueur, sans modifier visuellement le Hall.

CE QUI CHANGE DANS LE PORTAIL
-----------------------------
- Le titre devient uniquement : PORTAIL DES AVENTURIERS.
- Le vrai avatar Project XP remplace l'ancienne bulle générique.
- Le bloc AMIS disparaît de l'accueil du PC.
- Le bloc COMPAGNIE disparaît de l'accueil du PC.
- Ces fonctions restent à leur place naturelle : Communicateur / Compagnie.
- Une vraie Bibliothèque prend leur place.
- Le bloc EN COURS utilise maintenant les vraies données de la Bibliothèque.
- Le FIL D'AVENTURE montre les activités gaming du compte local :
  ajout de jeu, fin de jeu, nouveaux succès/trophées, platine.
- Le fil social des amis est volontairement gardé pour une étape suivante afin
  de ne pas mélanger les identités locales et l'identité Supabase anonyme
  actuelle de Project XP.

BIBLIOTHÈQUE V1
---------------
La Bibliothèque fonctionne réellement dès l'installation :

- Ajouter autant de jeux que souhaité.
- Retirer un jeu de la Bibliothèque.
- Plateformes :
  * Steam
  * PlayStation
  * Xbox
  * Epic Games
  * Nintendo
  * PC
  * Autre
- États :
  * À classer
  * À jouer
  * En cours
  * Terminé
  * Abandonné
- Favoris.
- Progression personnelle 0 à 100 %.
- Filtres par état + favoris.
- Temps de jeu Steam affiché lorsqu'il est synchronisé.

TROPHÉES / SUCCÈS
-----------------
PlayStation :
- Bronze obtenus / total
- Argent obtenus / total
- Or obtenus / total
- Platine obtenus / total

Xbox :
- Succès obtenus / total
- Gamerscore obtenu / total

Steam / Epic / PC / autres :
- Succès obtenus / total

Les valeurs peuvent être saisies manuellement pour toutes les plateformes.
Pour Steam, les succès peuvent aussi être synchronisés automatiquement.

SYNCHRONISATION STEAM — RÉELLE
------------------------------
La V1.8 contient une vraie intégration Steam via une Supabase Edge Function.

La clé Steam n'est JAMAIS placée dans l'APK.
Elle reste dans les secrets Supabase.

La synchro sait accepter :
- un SteamID64 ;
- une URL steamcommunity.com/profiles/... ;
- une URL steamcommunity.com/id/... ;
- un identifiant personnalisé Steam.

Elle utilise les Web APIs Steam pour :
- résoudre une URL personnalisée en SteamID ;
- récupérer la bibliothèque possédée ;
- récupérer le temps de jeu ;
- récupérer les succès d'un jeu Steam.

IMPORTANT : le profil Steam doit autoriser l'accès aux détails des jeux pour
que Steam renvoie la bibliothèque et les succès.

ACTIVATION DE STEAM
-------------------
1. Obtenir une clé Steam Web API utilisateur.
   Steam demande un compte Steam et un nom de domaine associé à la clé.
   N'utilise pas portal.projectxp.gg pour cette inscription si tu ne possèdes
   pas réellement ce domaine : l'adresse du faux navigateur n'est pour
   l'instant qu'un élément visuel de Project XP.

2. Installer / utiliser la CLI Supabase et lier le projet si ce n'est pas déjà
   fait.

3. Depuis la racine du projet, enregistrer la clé dans les secrets Supabase :

   supabase secrets set STEAM_WEB_API_KEY=TA_CLE_STEAM

4. Déployer la fonction :

   supabase functions deploy steam-sync

5. Dans Project XP :
   Terminal XP > Bibliothèque > CONNECTER / SYNCHRONISER STEAM

6. Entrer le profil Steam.

7. Une fois les jeux importés, l'icône nuage sur un jeu Steam synchronise ses
   succès.

POURQUOI LES SUCCÈS STEAM NE SONT PAS TOUS SYNCHRONISÉS EN MASSE
----------------------------------------------------------------
Steam expose les succès jeu par jeu. Une bibliothèque peut contenir plusieurs
centaines ou milliers de jeux. Lancer plusieurs centaines d'appels d'un coup
serait inutilement lourd et risquerait le throttling.

V1.8 choisit donc :
- bibliothèque + temps de jeu : synchronisation globale ;
- succès : synchronisation à la demande par jeu.

On pourra ensuite automatiser intelligemment les succès des jeux récemment
joués ou en cours, sans marteler l'API.

PLAYSTATION / XBOX / EPIC / NINTENDO
------------------------------------
La saisie manuelle est entièrement fonctionnelle pour ces plateformes.

Aucune synchronisation non officielle / scraping fragile n'a été intégrée.
L'objectif est que Project XP reste publiable, durable et ne dépende pas d'une
API privée pouvant disparaître ou bloquer les comptes utilisateurs.

Xbox possède des APIs de succès mais leur usage demande une authentification
Xbox Live et un cadre d'accès Xbox/Partner adapté. Ce n'est pas encore activé
ici.

PlayStation / Epic / Nintendo : aucune interface publique officielle adaptée à
notre besoin n'a été suffisamment confirmée pour être ajoutée proprement dans
cette V1.8.

STOCKAGE DE LA BIBLIOTHÈQUE
---------------------------
Pour cette première version, la Bibliothèque est enregistrée localement avec
SharedPreferences, séparément pour chaque compte local Project XP.

Pourquoi pas Supabase tout de suite ?
Le système de compte Project XP et la session sociale Supabase ne sont pas
encore la même identité : Supabase utilise actuellement une session anonyme.
Mettre la Bibliothèque cloud dessus maintenant pourrait attribuer les jeux au
mauvais compte lors d'un changement de compte local.

La bonne étape suivante sera d'unifier l'identité Project XP / Supabase, puis
on pourra synchroniser la Bibliothèque entre appareils et activer un vrai fil
d'activité des amis.

FICHIERS DE CETTE VERSION
-------------------------
lib/models/game_library_entry.dart
lib/services/game_library_service.dart
lib/services/steam_sync_service.dart
lib/screens/game_library_screen.dart
lib/screens/computer_screen.dart
lib/screens/hall_screen.dart
lib/screens/project_xp_center_screen.dart
supabase/functions/steam-sync/index.ts

AUCUN NOUVEAU PACKAGE FLUTTER
-----------------------------
La synchro utilise supabase_flutter déjà présent dans Project XP.

INSTALLATION FLUTTER
--------------------
Extraire le ZIP à la racine de :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Puis :
flutter analyze

TEST SANS STEAM
---------------
1. Ouvrir le Hall : aucun changement visuel attendu.
2. Ouvrir le Terminal XP.
3. Vérifier : PORTAIL DES AVENTURIERS.
4. Vérifier le vrai avatar.
5. Ouvrir MA BIBLIOTHÈQUE.
6. Ajouter un jeu PlayStation.
7. Mettre En cours et une progression.
8. Ajouter des trophées.
9. Revenir au portail : le jeu doit apparaître dans EN COURS et la Bibliothèque.
10. Modifier les trophées : le Fil d'Aventure doit enregistrer l'activité.
11. Retirer le jeu si souhaité.

TEST STEAM APRÈS DÉPLOIEMENT
----------------------------
1. Connecter un profil Steam dont les détails de jeux sont publics.
2. Vérifier l'import des jeux et du temps joué.
3. Ouvrir un jeu Steam possédant des succès.
4. Appuyer sur l'icône de synchronisation des succès.
5. Vérifier le compteur de succès et le Fil d'Aventure.
