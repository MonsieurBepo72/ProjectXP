PROJECT XP — V1.10.2
BIBLIOTHÈQUE MULTI-PLATEFORMES

OBJECTIF
Une fiche Project XP = un jeu, avec plusieurs plateformes possibles.
Exemple : Rocket League peut contenir PlayStation + Steam + Xbox dans la même fiche.

CE QUI CHANGE

1) Fusion des doublons Steam / bibliothèque existante
- Les doublons stricts de titre issus d'une plateforme importée sont regroupés.
- Exemple attendu : Rocket League PlayStation + Rocket League Steam => une seule fiche.
- La fiche la plus riche en métadonnées (IGDB, résumé, cover, année...) est conservée.
- Les connexions plateformes sont ajoutées à cette fiche au lieu de créer une nouvelle fiche.
- Les IDs officiels de plateforme restent séparés.
- Deux IDs officiels différents pour une même plateforme ne sont jamais fusionnés automatiquement.

2) Plusieurs plateformes dans une seule fiche
Chaque plateforme possède désormais son propre profil :
- plateforme ;
- ID externe officiel quand disponible ;
- temps de jeu ;
- dernière activité détectée ;
- résumé de trophées/succès ;
- liste détaillée des accomplissements ;
- état manuel / confirmé par la plateforme ;
- date de dernière synchro.

Les anciens champs restent compatibles afin de ne pas casser les sauvegardes V1.10.1.

3) Progression : plus de moyenne frustrante
- Pas de barre globale moyenne.
- Chaque plateforme possède sa propre progression.
- Project XP met en avant la MEILLEURE COMPLÉTION.
- Si une plateforme est à 100 %, le 100 % reste valorisé même si une autre plateforme est à 20 %.
- Le statut personnel (À jouer / En cours / Terminé / Abandonné) est séparé de la complétion trophées/succès.
- Un jeu Terminé n'est donc plus forcé à 100 % de trophées.
- Un 100 % de succès ne force plus automatiquement l'état Terminé.

4) Recherche dans la Bibliothèque
Une barre de recherche apparaît en haut de la liste.
Elle recherche dans :
- le titre du jeu ;
- les plateformes liées.

5) Tri
Les tris existants sont conservés.
Les tris de progression utilisent maintenant la meilleure complétion connue.
Les tris de temps de jeu utilisent le total des plateformes liées.

6) « À classer »
- L'état interne legacy existe encore pour relire les imports.
- Il n'est plus affiché comme filtre.
- Il n'est plus affiché comme badge sur les cartes.
- Il n'est plus proposé comme état utilisateur dans la fiche.
Un jeu importé sans état reste simplement sans état visible jusqu'à ce que le joueur en choisisse un.

7) Succès Steam détaillés
- Une fiche liée à Steam garde son bouton de synchro.
- Ouvrir une fiche Steam déclenche une actualisation automatique si :
  * elle n'a jamais été synchronisée ; ou
  * sa dernière synchro date de plus de 15 minutes.
- Les succès Steam restent propres à Steam : ils ne font jamais avancer PlayStation/Xbox.
- La liste détaillée peut être cochée manuellement.
- Une future synchro Steam ne supprime pas une coche manuelle.
- Si Steam confirme ensuite le succès, la validation devient officiellement « Confirmé par Steam ».
- Les nouveaux succès peuvent alimenter le Fil d'Aventure avec leur vrai nom.

8) Progression manuelle conservée
Si aucune liste détaillée n'est disponible pour une plateforme :
- PlayStation : Bronze / Argent / Or / Platine peuvent toujours être renseignés ;
- Xbox : succès + Gamerscore ;
- autres plateformes : succès obtenus / total.
Cela évite de perdre les fonctions manuelles avant les futures intégrations officielles.

PAS DE MIGRATION SQL
Le modèle multi-plateformes est stocké dans le JSON game_data déjà prévu par la Cloud Foundation.
Aucun `supabase db push` n'est nécessaire.

PAS DE NOUVEAU DÉPLOIEMENT EDGE FUNCTION
La fonction steam-sync V1.10.1 déjà déployée renvoie les données nécessaires.
Aucun `supabase functions deploy` n'est nécessaire pour cette version.

INSTALLATION

1. Extraire ce ZIP à la racine :
   C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

2. Accepter le remplacement des 4 fichiers Dart.

3. Vérifier :
   flutter analyze

4. Si « No issues found! », fermer complètement Project XP puis relancer l'app.

TEST CONSEILLÉ

A. Ouvrir Ma Bibliothèque.
   - Rocket League / Project Zomboid en doublon doivent être regroupés automatiquement
     lorsque le doublon est strictement identifiable.
   - Une seule carte doit afficher plusieurs badges de plateformes.

B. Utiliser la nouvelle barre de recherche.
   - Rechercher un jeu Steam que tu pensais absent.

C. Ouvrir Rocket League.
   - La fiche doit montrer les plateformes liées séparément.
   - Chaque plateforme a sa propre barre de complétion.
   - La meilleure complétion est mise en avant sans moyenne globale.

D. Si Steam est lié :
   - l'ouverture de la fiche peut synchroniser les succès automatiquement ;
   - sinon utiliser l'icône Cloud Sync sur la carte ;
   - cocher manuellement un succès non obtenu ;
   - ENREGISTRER ;
   - resynchroniser Steam ;
   - la coche manuelle doit rester tant que Steam ne la confirme pas.

LIMITES VOLONTAIRES DE V1.10.2
- PlayStation/Xbox ne sont pas encore connectés à une API officielle Project XP :
  leur progression reste manuelle pour le moment.
- Les DLC sont préparés au niveau du modèle d'accomplissement (groupName),
  mais les barres Jeu principal / DLC ne sont pas encore affichées.
- La traduction française automatique du résumé IGDB n'est pas incluse dans ce patch.
- La fusion automatique reste volontairement prudente :
  des éditions au nom différent (ex. Standard vs Complete Edition) ne seront pas fusionnées aveuglément.
