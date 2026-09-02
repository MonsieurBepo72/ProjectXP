PROJECT XP — PORTAIL TERMINAL V1.7.1
=======================================

OBJECTIF
--------
Transformer l'ordinateur du Hall en faux navigateur / Portail Project XP,
sans modifier visuellement le Hall.

NOUVELLE LOGIQUE
----------------
HALL
  - Le panneau PROJECT XP redevient comme avant : aucune fonction ajoutée.
  - L'ordinateur reste le point d'entrée du Terminal XP.

ORDINATEUR / TERMINAL XP
  - Interface de faux navigateur intégrée en Flutter.
  - Adresse affichée : portal.projectxp.gg
    (adresse d'univers / habillage visuel, pas un vrai site Internet).
  - Accueil "PROJECT XP — LE PORTAIL DES AVENTURIERS".
  - Bonjour + vrai pseudo du compte.
  - Accès direct au vrai Profil.
  - Emplacements préparés pour :
      * Jeu en cours / Bibliothèque
      * Quête active
      * Amis
      * Compagnie
      * Actualités Project XP
      * Niveau / XP
  - Les systèmes pas encore développés n'affichent PAS de fausses données.

ENGRENAGE
---------
Le bouton engrenage du navigateur ouvre :
  1. PARAMÈTRES
     - Musique
     - Effets sonores
     - Vibrations
     - Notifications

  2. OPTIONS
     - Réduire les animations
     - Confirmations
     - Conseils de Bjorn

  3. COMPTE & SÉCURITÉ
     - Pseudo / e-mail
     - Changement e-mail
     - Changement mot de passe
     - Biométrie
     - Déconnexion

Toutes ces fonctions réutilisent le code Project XP déjà existant.

COMPATIBILITÉ V1.7.0
--------------------
project_xp_center_screen.dart est conservé sous forme de compatibilité.
Si une ancienne route essaie encore de l'ouvrir, elle redirige vers
le Terminal XP au lieu de conserver le doublon du Centre Project XP.

FICHIERS
--------
lib/screens/hall_screen.dart
lib/screens/computer_screen.dart
lib/screens/project_xp_center_screen.dart

AUCUN
-----
- nouveau package
- nouvel asset
- SQL Supabase
- modification de base de données

INSTALLATION
------------
Extraire le ZIP à la racine de :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Puis lancer :
flutter analyze

TEST CONSEILLÉ
--------------
1. Ouvrir le Hall : vérifier qu'il est visuellement identique.
2. Appuyer sur le panneau PROJECT XP : il ne doit plus ouvrir le Centre V1.7.0.
3. Ouvrir l'ordinateur.
4. Vérifier le faux navigateur et portal.projectxp.gg.
5. Vérifier que le vrai pseudo apparaît.
6. Appuyer sur l'icône Profil : le Profil existant doit s'ouvrir.
7. Appuyer sur l'engrenage.
8. Tester Paramètres.
9. Tester Options.
10. Tester Compte & sécurité.
11. Ne tester Déconnexion qu'en dernier.

NOTE
----
Le domaine portal.projectxp.gg affiché dans l'interface est pour l'instant
un élément visuel du faux navigateur. Aucun domaine ni hébergement Internet
n'est nécessaire pour cette version.

HOTFIX V1.7.1a
---------------
- Corrige Colors.white46 (inexistant dans Flutter) par Color(0x75FFFFFF).
- Aucun autre changement fonctionnel ou visuel.
