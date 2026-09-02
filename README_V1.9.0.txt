PROJECT XP — IDENTITÉ CLOUD V1.9.0
==================================

OBJECTIF
--------
Poser la fondation correcte avant de connecter Steam/Xbox/PlayStation/Epic.

La V1.9.0 NE remplace PAS brutalement le système de compte actuel.
Elle transforme progressivement l'identité Supabase anonyme déjà utilisée
par le social en identité permanente, tout en conservant son même UID.

POURQUOI C'EST IMPORTANT
------------------------
Aujourd'hui :
- compte Project XP principal = local ;
- identité Supabase sociale = anonyme.

Après activation Cloud :
- même utilisateur Supabase social ;
- e-mail vérifié ;
- mot de passe Supabase ;
- mapping stable entre auth.uid() et l'ID historique Project XP ;
- table prête pour les futurs comptes Steam/Xbox/etc.

NOUVEAUX FICHIERS
-----------------
lib/services/cloud_identity_service.dart
lib/screens/cloud_identity_screen.dart

MIGRATION
---------
supabase/migrations/20260901223500_project_xp_cloud_identity_v1.sql

FICHIER MODIFIÉ
---------------
lib/screens/computer_screen.dart

UTILISATION DANS L'APP
----------------------
Ordinateur
→ ⚙
→ Compte & sécurité
→ Compte Cloud Project XP

Le joueur :
1. confirme son mot de passe Project XP ;
2. reçoit un code à son adresse e-mail ;
3. entre le code ;
4. le même utilisateur Supabase anonyme devient permanent ;
5. Project XP crée le mapping Cloud.

IMPORTANT : CONFIGURATION E-MAIL SUPABASE
-----------------------------------------
Pour le test OTP de cette V1.9.0, le template d'e-mail de changement d'adresse
doit contenir le token à 6 chiffres ({{ .Token }}), pas uniquement un lien.

Dans Supabase Dashboard :
Authentication
→ Email Templates
→ Change Email Address

Le corps du message doit afficher {{ .Token }}.

Il faut également autoriser la liaison manuelle des identités :
Authentication
→ Settings / General configuration
→ Allow manual linking = ON

BASE DE DONNÉES
---------------
Après extraction du ZIP :

1. Vérifier la migration :
npx.cmd supabase db push --dry-run

2. Si la seule migration proposée est :
20260901223500_project_xp_cloud_identity_v1.sql

alors :
npx.cmd supabase db push

3. Puis :
flutter analyze

AUCUN SECRET SUPPLÉMENTAIRE
---------------------------
Cette étape ne demande aucune nouvelle clé API.

CE QUI EST DÉJÀ PRÉPARÉ POUR LA SUITE
-------------------------------------
La table project_xp_external_accounts est créée pour accueillir :
- SteamID ;
- Xbox ID ;
- PlayStation ID ;
- Epic account ID ;
sans stocker leurs mots de passe.

CloudIdentityService contient aussi la restauration d'un compte Cloud
sur un nouvel appareil. L'étape suivante branchera cette restauration
sur l'écran de connexion, après validation de la conversion V1.9.

SÉCURITÉ
--------
- le mot de passe local est vérifié avant la conversion ;
- l'e-mail doit être vérifié par Supabase ;
- les tables utilisent RLS ;
- un utilisateur ne peut lire/modifier que ses propres liaisons ;
- aucune clé Steam/IGDB n'est stockée dans Flutter.
