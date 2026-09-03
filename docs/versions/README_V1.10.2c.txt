PROJECT XP — V1.10.2c
CORRECTIF COMPILATION

Corrige uniquement les 3 erreurs :
referenced_before_declaration
dans lib/services/game_library_service.dart.

CAUSE
Lors de l'ajout du verrouillage de jaquette, la création d'un nouveau jeu manuel
essayait par erreur de lire `entry.hasOfficialPlatformConnection`,
`entry.coverUrl` et `entry.coverFallbackUrls` à l'intérieur du constructeur
qui était justement en train de créer `entry`.

CORRECTION
Pour un nouveau jeu manuel :
- coverUrl utilise directement la jaquette fournie ;
- coverFallbackUrls conserve sa valeur par défaut vide.

Le verrouillage nom + jaquette après synchronisation reste appliqué dans
GameLibraryService.updateGame(), donc le comportement V1.10.2b n'est pas retiré.

INSTALLATION
Extraire ce ZIP à la racine :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Accepter le remplacement du fichier.

PUIS
flutter analyze

Aucun db push.
Aucun redéploiement de steam-sync nécessaire si la V1.10.2b a déjà été déployée.
