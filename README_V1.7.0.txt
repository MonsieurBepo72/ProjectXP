PROJECT XP — CENTRE PROJECT XP V1.7.0
===========================================

OBJECTIF
-------
Le grand panneau "PROJECT XP" en haut du Hall devient cliquable SANS modifier
visuellement le Hall.

Le panneau ouvre un Centre Project XP avec 3 entrées :

1. PARAMÈTRES
   - Musique
   - Effets sonores
   - Vibrations
   - Notifications

2. OPTIONS
   - Réduire les animations
   - Demandes de confirmation
   - Conseils de Bjorn

3. COMPTE & SÉCURITÉ
   - Affichage du pseudo
   - Affichage / modification de l'e-mail
   - Changement du mot de passe
   - Connexion biométrique si disponible
   - Déconnexion

IMPORTANT
---------
- Aucun changement graphique du Hall.
- Aucun nouvel asset.
- Aucun nouveau package.
- Aucun SQL Supabase à exécuter.
- Les réglages réutilisent ComputerSettingsService déjà présent dans Project XP.
- Le compte/sécurité réutilise AuthService et BiometricAuthService déjà présents.

FICHIERS
--------
lib/screens/hall_screen.dart
lib/screens/project_xp_center_screen.dart

INSTALLATION
------------
Extraire le ZIP à la racine de :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Puis lancer :
flutter analyze

TEST RAPIDE
-----------
1. Ouvrir le Hall.
2. Appuyer directement sur le panneau "PROJECT XP" en haut.
3. Vérifier l'ouverture du Centre Project XP.
4. Tester un réglage audio puis revenir.
5. Tester Options.
6. Ouvrir Compte & sécurité.
7. Vérifier pseudo/e-mail.
8. Ne tester la déconnexion qu'en dernier.
