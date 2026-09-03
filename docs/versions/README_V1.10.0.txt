PROJECT XP — CLOUD FOUNDATION V1.10.0
====================================

BASE
----
Construite sur le checkpoint GitHub :
7e62d791548712ca2bc949189956f2f7838536b5
"Checkpoint V1.9.1b - Portail, Bibliotheque IGDB et Compte Cloud"

OBJECTIF
--------
Faire de Supabase la source de vérité des données personnelles importantes,
sans supprimer les anciennes données locales.

V1.10.0 MET DANS LE CLOUD
-------------------------
- profil Project XP privé complet ;
- avatar manuel ;
- avatar photo en bucket PRIVÉ (jamais rendu public par cette migration) ;
- Bibliothèque de jeux ;
- progression / favoris / métadonnées de chaque jeu ;
- Fil d'Aventure.

RESTE LOCAL
-----------
- réglages audio ;
- vibrations ;
- réduction des animations ;
- fond personnalisé du Communicateur ;
- caches et préférences propres à l'appareil.

DÉJÀ CLOUD AVANT V1.10
----------------------
- messages privés / conversations ;
- amis ;
- profil Taverne public ;
- invitations Compagnie online ;
- partie online des Compagnies.

SÉCURITÉ / MIGRATION
--------------------
- Les SharedPreferences ne sont PAS effacées.
- Sur le premier lancement avec un compte Cloud permanent, les données locales
  existantes sont envoyées dans Supabase si le Cloud est vide.
- La Bibliothèque fusionne les jeux par ID et updatedAt lorsqu'une synchronisation
  en attente doit être résolue.
- Les suppressions de jeux sont mémorisées localement tant que le Cloud n'a pas
  confirmé la nouvelle Bibliothèque.
- Le profil privé et les fichiers d'avatar ne sont lisibles que par leur propriétaire
  via RLS.
- La photo d'avatar est stockée dans un bucket privé : elle n'est pas transformée
  en URL publique.

FICHIERS
--------
lib/services/cloud_data_service.dart                  NOUVEAU
lib/services/cloud_data_sync_service.dart             NOUVEAU
lib/services/profile_storage.dart                     MODIFIÉ
lib/services/avatar_storage.dart                      MODIFIÉ
lib/services/game_library_service.dart                MODIFIÉ
lib/services/project_xp_startup_service.dart          MODIFIÉ
supabase/migrations/20260902201500_project_xp_cloud_foundation_v1.sql  NOUVEAU

INSTALLATION
------------
1. Extraire le ZIP à la racine :
   C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

2. Vérifier la migration AVANT de pousser :
   npx.cmd supabase db push --dry-run

   Résultat attendu :
   20260902201500_project_xp_cloud_foundation_v1.sql

   Si d'autres migrations inattendues apparaissent : STOP.

3. Appliquer :
   npx.cmd supabase db push

4. Vérifier Flutter :
   flutter analyze

5. Lancer l'app :
   flutter run

TEST TEL1
---------
- Le compte Cloud doit rester ACTIF.
- Ouvrir le profil : pseudo/description/avatar doivent être inchangés.
- Ouvrir la Bibliothèque : les jeux existants doivent toujours être présents.
- Modifier un favori ou une progression, fermer complètement l'app, relancer :
  la modification doit rester présente.
- Le Fil d'Aventure existant ne doit pas récupérer les anciens événements
  "rejoint ta Bibliothèque".

APRÈS VALIDATION
----------------
V1.10.1 : brancher la connexion Cloud sur l'écran Auth puis tester la restauration
sur Tel2. Ce sera le vrai test multi-appareils du profil/avatar/Bibliothèque.
