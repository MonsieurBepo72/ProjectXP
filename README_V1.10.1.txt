PROJECT XP — V1.10.1
Bibliothèque : favoris rapides, tris, progression cohérente et succès/trophées détaillés

BASE REQUISE
- V1.10.0 Cloud Foundation déjà installée.
- Migration 20260902201500_project_xp_cloud_foundation_v1.sql déjà poussée.

IMPORTANT
Cette version n'ajoute AUCUNE migration SQL.
Les succès/trophées détaillés sont stockés dans le JSON du jeu déjà sauvegardé dans
project_xp_game_library : ils suivent donc automatiquement la synchro Cloud V1.10.

FICHIERS À REMPLACER
- lib/models/game_library_entry.dart
- lib/screens/game_library_screen.dart
- lib/services/game_library_service.dart
- lib/services/steam_sync_service.dart
- supabase/functions/steam-sync/index.ts

CE QUI CHANGE
1) Favori directement dans la liste
- Une étoile est maintenant cliquable sur chaque carte.
- Plus besoin d'ouvrir la fiche juste pour ajouter/retirer un favori.
- La modification passe par GameLibraryService et donc par le Cloud V1.10.

2) Tri de la Bibliothèque
- Activité récente
- Nom A -> Z
- Nom Z -> A
- Progression décroissante / croissante
- Temps de jeu décroissant / croissant

3) Progression plus logique
- À classer : progression verrouillée à 0 %.
- À jouer : progression verrouillée à 0 %.
- En cours : slider actif.
- 100 % en En cours => passe automatiquement le jeu en Terminé.
- Terminé : progression verrouillée à 100 %.
- Abandonné : conserve le pourcentage atteint mais verrouille le slider.
  Pour reprendre : repasser le jeu en En cours.

4) Liste détaillée des succès/trophées
Le modèle accepte maintenant une liste par jeu avec :
- identifiant plateforme,
- nom,
- description,
- icône,
- état débloqué par la plateforme,
- état coché manuellement,
- dates de déblocage,
- type de trophée prévu pour PlayStation,
- groupe prévu pour une future séparation jeu principal / DLC.

5) Validation manuelle SANS casser la synchro
Règle de fusion :
- Si Steam dit « débloqué », Steam gagne et le succès devient officiellement confirmé.
- Si Steam dit « verrouillé » mais que le joueur l'a coché dans Project XP, la coche
  manuelle reste présente.
- Une nouvelle synchro n'efface donc pas une validation manuelle.
- Quand Steam confirme ensuite ce même succès, Project XP retire simplement le statut
  « manuel » et le remplace par la confirmation officielle.
- Un succès confirmé par la plateforme ne peut pas être décoché manuellement.

6) Fil d'Aventure avec vrais noms
Quand un succès détaillé passe de verrouillé à obtenu, le Fil peut maintenant créer :
  Succès « NOM DU SUCCÈS » obtenu
  Rocket League • Steam
ou
  Succès « NOM DU SUCCÈS » obtenu
  Rocket League • coché manuellement

La première synchro détaillée d'un jeu n'inonde PAS le Fil avec tous les succès
historiques déjà obtenus. Les nouveaux déblocages des synchronisations suivantes sont
annoncés.

7) Steam renvoie maintenant la liste détaillée
La Edge Function steam-sync combine :
- GetPlayerAchievements (état joueur + noms localisés),
- GetSchemaForGame (description/icône quand disponible),
avec la langue française demandée à Steam.

INSTALLATION
1. Extraire le ZIP à la racine du projet Flutter et accepter les remplacements.

2. Redéployer la Edge Function Steam :
   npx.cmd supabase functions deploy steam-sync

3. Vérifier Flutter :
   flutter analyze

4. Si analyse propre, lancer Tel1 :
   flutter run

TEST CONSEILLÉ
A. Favori rapide
- Cliquer l'étoile d'un jeu depuis la liste.
- Sortir/revenir : elle doit rester.

B. Tri
- Tester A -> Z puis Z -> A.

C. Progression
- À jouer : slider bloqué.
- En cours : slider actif.
- Monter à 100 % : l'état doit devenir Terminé.
- Abandonné : pourcentage conservé + slider bloqué.

D. Succès Steam
- Utiliser un jeu IMPORTÉ depuis Steam (pas seulement ajouté manuellement via IGDB).
- Cliquer sur l'icône de synchro des succès.
- Ouvrir la fiche : la liste détaillée doit apparaître.
- Cocher manuellement un succès encore verrouillé, puis ENREGISTRER.
- Le rouvrir : la coche doit rester.
- Resynchroniser Steam : la coche manuelle doit rester si Steam ne le confirme pas,
  ou devenir « Confirmé par Steam » si Steam le confirme.

NOTE ROCKET LEAGUE ACTUEL
Si Rocket League a été ajouté uniquement via le catalogue IGDB, sa fiche n'a pas encore
d'AppID Steam lié. La liste Steam détaillée apparaîtra quand le jeu sera importé/relié à
Steam. La future liaison de comptes devra fusionner le jeu manuel et le jeu plateforme
pour éviter les doublons.

À VENIR / PAS DANS CETTE V1.10.1
- Traduction/caching français des résumés IGDB.
- Vraie séparation visuelle Jeu principal / DLC avec barres distinctes.
- Connexion plateforme officielle dès l'onboarding (facultative).
- Synchronisation automatique intelligente au retour dans l'app.
- Réconciliation automatique jeu IGDB manuel <-> jeu de plateforme importé.
