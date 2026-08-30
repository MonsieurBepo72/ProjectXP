# Changelog — Project XP

Les changements importants de Project XP sont consignés ici.

## [Unreleased]

### Taverne
- Polish V8.1 en cours : compteur de présence dynamique, alignements, couleurs de chat et comportement clavier.

### Sécurité / dépôt
- Durcissement du serveur local de génération d'avatar :
  - écoute sur localhost par défaut ;
  - exposition LAN uniquement sur opt-in explicite ;
  - jeton de développement obligatoire en mode LAN ;
  - limite de taille des requêtes.
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
