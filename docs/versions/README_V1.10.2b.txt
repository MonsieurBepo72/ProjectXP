PROJECT XP — V1.10.2b
JAQUETTES VERROUILLÉES + FALLBACKS AUTOMATIQUES

Cette version REMPLACE la V1.10.2a.
Si V1.10.2a n'a pas encore été installée/déployée, installe uniquement ce ZIP.

CE QUI CHANGE

1) JAQUETTE VERROUILLÉE APRÈS SYNCHRONISATION
Dès qu'une fiche possède un identifiant officiel de plateforme :
- le bouton « Corriger la jaquette / les infos » disparaît ;
- le joueur ne peut plus remplacer la jaquette manuellement ;
- GameLibraryService protège aussi la jaquette côté service ;
- le nom reste également verrouillé comme prévu en V1.10.2a.

Une fiche déjà enrichie via IGDB avant la synchro conserve sa jaquette catalogue.

2) JEUX STEAM SANS JAQUETTE : FALLBACK AUTOMATIQUE
Pour un jeu lié à Steam, Project XP essaie automatiquement plusieurs images :
- jaquette catalogue existante (si elle existe) ;
- capsule Steam verticale 600x900 haute définition ;
- capsule Steam verticale standard ;
- ancien header Steam ;
- icône Steam du jeu quand elle est disponible après une resynchronisation.

Si une source renvoie une image manquante, Project XP essaie la suivante sans
demander au joueur de changer la jaquette.

3) ANCIENS JEUX DÉJÀ IMPORTÉS
Même les entrées importées avant cette version bénéficient immédiatement des
fallbacks basés sur leur Steam AppID.

Une resynchronisation Steam est toutefois conseillée une fois après installation :
elle permet aussi de récupérer l'URL d'icône Steam comme dernier filet de sécurité.

4) POLISH V1.10.2a CONSERVÉ
Ce ZIP contient également :
- filtres succès : TOUS / OBTENUS / À OBTENIR ;
- pas de fausse barre pour les jeux réellement sans trophée/succès ;
- nom verrouillé après connexion officielle ;
- modèle multi-plateformes et meilleure complétion.

INSTALLATION

Extraire à la racine :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Accepter le remplacement des fichiers.

AUCUNE MIGRATION SQL.

ÉTAPE 1
Comme cette version embarque aussi le correctif V1.10.2a de steam-sync,
redéployer la fonction (une fois suffit) :

npx.cmd supabase functions deploy steam-sync

ÉTAPE 2
Vérifier Flutter :

flutter analyze

Résultat attendu :
No issues found!

ÉTAPE 3
Fermer complètement Project XP puis le relancer.

TESTS CONSEILLÉS
- Ouvrir Rocket League : plus d'action permettant de changer sa jaquette
  une fois Steam lié.
- Vérifier que sa jaquette IGDB existante reste intacte.
- Chercher un jeu Steam qui n'avait pas de jaquette : Project XP doit essayer
  automatiquement les différentes sources.
- Faire une seule resynchronisation de la bibliothèque Steam pour enrichir
  les fallbacks d'icône des 148 jeux déjà importés.
