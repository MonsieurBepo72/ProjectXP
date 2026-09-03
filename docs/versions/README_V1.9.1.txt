PROJECT XP — V1.9.1 — MOT DE PASSE OUBLIÉ / ACTIVATION CLOUD
==============================================================

Base : V1.9.0 Cloud Identity.
Cette version ajoute le parcours sécurisé « Mot de passe oublié ? » directement
sur l'écran Compte Cloud, sans créer un nouveau compte et sans changer l'UID
Supabase social existant.

FICHIERS MODIFIÉS
-----------------
lib/screens/cloud_identity_screen.dart
lib/services/cloud_identity_service.dart

AUCUNE NOUVELLE MIGRATION SQL.
AUCUNE NOUVELLE DÉPENDANCE FLUTTER.
AUCUN NOUVEAU SECRET SUPABASE.

PARCOURS AJOUTÉ
---------------
Compte Cloud
  -> MOT DE PASSE OUBLIÉ ?
  -> confirmation de l'adresse e-mail du compte
  -> envoi du code via le template « Change email address » déjà configuré
  -> saisie du code à 6 chiffres
  -> choix + confirmation d'un nouveau mot de passe
  -> validation Supabase de l'e-mail
  -> nouveau mot de passe enregistré sur le même utilisateur Supabase
  -> hash local Project XP remplacé par le même nouveau mot de passe
  -> mapping project_xp_cloud_accounts créé
  -> COMPTE CLOUD ACTIF

SÉCURITÉ
--------
L'ancien mot de passe n'est jamais récupéré ni affiché.
La réinitialisation n'est autorisée qu'après vérification du code envoyé à
l'adresse e-mail déjà associée au compte local Project XP.

Le nouveau mot de passe garde les règles Project XP existantes :
- 10 caractères minimum ;
- au moins une lettre ;
- au moins un chiffre ;
- au moins un caractère spécial.

INSTALLATION
------------
Extraire ce ZIP dans la racine du projet :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Accepter le remplacement des 2 fichiers.

Puis :
flutter analyze
flutter run

TEST CONSEILLÉ
--------------
Hall -> Ordinateur -> roue dentée -> Compte & sécurité -> Compte Cloud Project XP

1. Appuyer sur « MOT DE PASSE OUBLIÉ ? ».
2. Confirmer l'envoi du code.
3. Vérifier la réception du mail.
4. Entrer le code à 6 chiffres.
5. Choisir un nouveau mot de passe valide et le confirmer.
6. Appuyer sur « RÉINITIALISER ET ACTIVER ».
7. Vérifier l'affichage « COMPTE CLOUD ACTIF ».

IMPORTANT
---------
Ne pas supprimer le compte local et ne pas se déconnecter de la session
Supabase anonyme avant ce test : le but est précisément de convertir la même
identité existante en identité Cloud permanente.
