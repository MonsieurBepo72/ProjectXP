PROJECT XP — BIBLIOTHÈQUE + CATALOGUE IGDB V1.8.1
=================================================

OBJECTIF
--------
Cette version corrige le principal manque de la V1.8.0 :
un jeu ajouté manuellement peut maintenant récupérer une vraie jaquette
et des métadonnées depuis un catalogue de jeux.

NOUVEAUTÉS
----------
1. AJOUT PAR RECHERCHE CATALOGUE
   - Taper le nom d'un jeu (ex: Rocket League).
   - Lancer la recherche.
   - Choisir le bon résultat.
   - Project XP récupère :
       * nom officiel
       * jaquette
       * année de sortie
       * genres
       * plateformes connues par le catalogue
       * résumé quand disponible
   - Choisir ensuite TA plateforme et ton statut personnel.

2. AJOUT MANUEL CONSERVÉ
   - Si le catalogue n'est pas configuré ou ne trouve rien,
     le bouton AJOUT MANUEL permet toujours d'ajouter le jeu.

3. JEUX DÉJÀ AJOUTÉS
   - Les jeux manuels existants (ex: Rocket League de V1.8.0)
     affichent une petite icône magique / recherche d'image.
   - Appuyer dessus permet de rechercher le jeu et d'ajouter
     la jaquette + les métadonnées SANS supprimer la fiche existante.
   - Statut, progression et trophées/succès personnels sont conservés.

4. FIL D'AVENTURE NETTOYÉ
   - "X rejoint ta Bibliothèque" n'est PLUS créé.
   - Les anciens événements de ce type sont automatiquement retirés
     du Fil d'Aventure au prochain chargement.
   - Le fil est réservé aux accomplissements :
       * trophées / succès
       * platines
       * jeux terminés
       * reprise d'un jeu abandonné
       * futurs accomplissements / quêtes

5. PORTAIL PC
   - Les miniatures de la Bibliothèque utilisent maintenant un format
     de jaquette vertical plus adapté aux covers IGDB.

CATALOGUE : IGDB
----------------
Project XP utilise IGDB via une Supabase Edge Function.
Les identifiants IGDB/Twitch ne sont JAMAIS stockés dans l'APK.

Fichiers ajoutés :
  lib/services/game_catalog_service.dart
  supabase/functions/game-catalog/index.ts

Fichiers modifiés :
  lib/models/game_library_entry.dart
  lib/services/game_library_service.dart
  lib/screens/game_library_screen.dart
  lib/screens/computer_screen.dart

Le reste de V1.8.0 est conservé, y compris la synchronisation Steam.

ACTIVER IGDB
------------
IGDB demande un compte Twitch + une application Twitch Developer.

1. Aller sur :
   https://dev.twitch.tv/console/apps

2. Créer une application.
   - OAuth Redirect URL : http://localhost
   - Client Type : Confidential

3. Récupérer :
   - Client ID
   - Client Secret

4. Depuis la racine du projet, enregistrer les secrets dans Supabase :

   supabase secrets set IGDB_CLIENT_ID=TON_CLIENT_ID
   supabase secrets set IGDB_CLIENT_SECRET=TON_CLIENT_SECRET

5. Déployer la fonction :

   supabase functions deploy game-catalog

6. Relancer Project XP puis :
   Bibliothèque > AJOUTER > rechercher "Rocket League".

IMPORTANT
---------
- IGDB indique que son API est gratuite pour un usage non commercial.
- Pour une utilisation commerciale, IGDB demande de les contacter pour
  un partenariat commercial. À revoir avant monétisation publique de Project XP.
- Sans les secrets et sans déploiement de la fonction, l'ajout manuel continue
  de fonctionner normalement.

STEAM
-----
La V1.8.1 conserve la V1.8.0 :

  supabase secrets set STEAM_WEB_API_KEY=TA_CLE_STEAM
  supabase functions deploy steam-sync

INSTALLATION FLUTTER
--------------------
Extraire le ZIP à la racine de :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Puis :

  flutter analyze

TEST CONSEILLÉ
--------------
A. Avant IGDB :
   1. Ouvrir le PC > Bibliothèque.
   2. Vérifier que Rocket League existe toujours.
   3. Vérifier que "rejoint ta Bibliothèque" a disparu du Fil d'Aventure.

B. Après configuration IGDB :
   1. Sur Rocket League existant, appuyer sur l'icône magique.
   2. Vérifier les résultats avec jaquettes.
   3. Choisir Rocket League.
   4. Vérifier que la fiche conserve plateforme/statut/progression.
   5. Vérifier que la jaquette apparaît dans la Bibliothèque ET sur le portail PC.

C. Nouvel ajout :
   1. AJOUTER.
   2. Rechercher un jeu.
   3. Sélectionner un résultat.
   4. Choisir plateforme + état.
   5. Ajouter.

AUCUN
-----
- nouveau package Flutter
- SQL Supabase
- secret API dans le code Flutter
