PROJECT XP — V1.10.1a
Correctif ciblé du dialogue de connexion Steam.

Fichier remplacé :
- lib/screens/game_library_screen.dart

Correction :
- le TextEditingController du dialogue Steam appartient désormais au State du dialogue ;
- il est détruit uniquement lorsque le dialogue est réellement retiré de l'arbre Flutter ;
- suppression du dispose via Future.whenComplete après Navigator.pop ;
- le clavier est fermé avant la fermeture du dialogue.

Aucune migration SQL.
Aucun redéploiement de fonction Supabase nécessaire.

Après extraction :
1. flutter analyze
2. relancer complètement l'app (pas seulement hot reload)
3. retester CONNECTER STEAM
