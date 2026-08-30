# Changelog — Project XP

Les changements importants de Project XP sont consignés ici.

## [Unreleased]

### Taverne
- V8.1.3 — edge-to-edge et identité de chat :
  - décor du header étendu derrière la barre d’état Android ;
  - flèche retour, compteur de présence et Communicateur alignés sur la zone sûre ;
  - téléphone global laissé à sa position commune aux autres écrans ;
  - nouveau bouton « Ma couleur de chat » directement dans la Taverne ;
  - palette Project XP + couleur RGB personnalisée ;
  - couleur appliquée immédiatement uniquement aux messages du joueur courant ;
  - synchronisation de la couleur dans son propre profil public Taverne.

- V8.1.1 — polish chirurgical :
  - contrôles du header réalignés et légèrement abaissés ;
  - retour au Hall rendu plus discret ;
  - onglet « Quêtes & Aventures » recalé ;
  - décor de la Taverne fixe pendant l’ouverture du clavier ;
  - barre de saisie recentrée dans son cadre ;
  - fond central moins opaque pour mieux laisser vivre le décor ;
  - bulles dimensionnées selon le contenu ;
  - couleurs de chat personnalisables librement ;
  - suppression individuelle des messages réservée aux administrateurs via RPC sécurisé.

### Sécurité / dépôt
- Durcissement du serveur local de génération d'avatar :
  - écoute sur localhost par défaut ;
  - exposition LAN uniquement sur opt-in explicite ;
  - jeton de développement obligatoire en mode LAN ;
  - comparaison de jeton à temps constant ;
  - limites de taille du JSON et de l’image décodée ;
  - validation base64, MIME et signature de fichier ;
  - timeouts OpenAI et fermeture forcée du client HTTP ;
  - logs d’erreur réduits pour éviter les données sensibles.
- Les tokens FCM ne sont plus écrits en clair dans les logs.
- Protection Git renforcée contre les fichiers de sauvegarde et résidus de debug.
- Documentation sécurité ajoutée.

## 2026-08-30

### Maintenance
- Références d'asset obsolètes corrigées.
- `.gitignore` renforcé pour les secrets, keystores et credentials.
- README Project XP ajouté.
- Dépendances inutilisées supprimées.
- Démarrage Firebase rendu tolérant aux plateformes non encore configurées.
- Signature Android release séparée de la clé debug.
- Fichiers Dart vides et inutilisés supprimés.

### Modération
- Base client V2.4.6.2 validée pour slang, grammaire et contexte.
