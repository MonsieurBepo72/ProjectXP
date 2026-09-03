PROJECT XP — V1.10.2a
POLISH BIBLIOTHÈQUE + SUCCÈS/TROPHÉES

Cette passe s'appuie sur la V1.10.2 multi-plateformes déjà testée.

NOUVEAUTÉS

1. TRI / FILTRE DES SUCCÈS
Dans la fiche d'un jeu disposant d'une liste détaillée :
- TOUS
- OBTENUS
- À OBTENIR

Chaque filtre affiche aussi son compteur.

2. JEUX SANS TROPHÉE / SUCCÈS
Project XP n'affiche plus une fausse barre à 0 % lorsqu'une plateforme
synchronisée confirme qu'un jeu n'a aucun trophée/succès.

Pour Steam :
- si Steam indique explicitement que le jeu n'a pas de statistiques/succès,
  la fonction steam-sync renvoie maintenant un catalogue vide valide ;
- Project XP affiche simplement qu'il n'y a aucun succès à suivre ;
- aucune fausse progression n'est créée.

Pour une plateforme ajoutée manuellement dont Project XP ne connaît pas encore
les trophées/succès :
- aucune barre artificielle n'est affichée ;
- les valeurs manuelles restent accessibles uniquement via
  « RENSEIGNER MANUELLEMENT ».

3. NOM DU JEU VERROUILLÉ APRÈS SYNCHRONISATION
Dès qu'une fiche possède un identifiant officiel de plateforme (Steam
aujourd'hui, autres plateformes plus tard) :
- le champ « Nom du jeu » devient en lecture seule ;
- une icône cadenas indique le verrouillage ;
- GameLibraryService protège aussi le titre côté service, donc une modification
  venant de l'UI ne peut pas l'écraser ;
- un enrichissement IGDB peut encore mettre à jour la jaquette, le résumé,
  l'année et les genres, sans renommer une fiche déjà liée officiellement.

4. FUSION MULTI-PLATEFORMES CONSERVÉE
Le comportement V1.10.2 reste inchangé :
- une fiche = un jeu ;
- PlayStation + Steam + Xbox peuvent cohabiter dans la même fiche ;
- chaque plateforme garde ses propres trophées/succès et sa propre progression ;
- la meilleure complétion est valorisée, sans moyenne globale punitive.

INSTALLATION

Extraire le ZIP à la racine :
C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Accepter le remplacement des fichiers.

ÉTAPE 1
Redéployer steam-sync car son comportement pour les jeux sans succès a changé :

npx.cmd supabase functions deploy steam-sync

ÉTAPE 2
Vérifier Flutter :

flutter analyze

Résultat attendu :
No issues found!

TESTS CONSEILLÉS

A. Ouvrir Rocket League :
- vérifier PlayStation + Steam sur la même fiche ;
- vérifier que le nom du jeu est verrouillé ;
- vérifier les filtres TOUS / OBTENUS / À OBTENIR si les succès Steam sont chargés.

B. Ouvrir un jeu Steam qui ne possède pas de succès :
- aucune fausse barre à 0 % ne doit être affichée ;
- Project XP doit indiquer qu'aucun succès n'est à suivre.

C. Pour une plateforme manuelle sans données :
- pas de fausse progression ;
- le bouton « RENSEIGNER MANUELLEMENT » reste disponible si nécessaire.

AUCUNE MIGRATION SQL.
