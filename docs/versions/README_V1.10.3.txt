PROJECT XP — V1.10.3
COMPTES GAMING + SYNCHRONISATION GLOBALE + SYNC AU DÉMARRAGE

Cette version reprend les correctifs V1.10.2 / V1.10.2a / V1.10.2b / V1.10.2c
et remplace les éléments temporaires de connexion Steam par une vraie base de
connexion navigateur Steam.

============================================================
CE QUI CHANGE
============================================================

1) BOUTON « COMPTES » DANS MA BIBLIOTHÈQUE

Un bouton COMPTES apparaît au-dessus de SYNCHRONISER TOUT.

L'écran centralise les plateformes :
- Steam : connexion officielle activée ;
- PlayStation : emplacement préparé, connexion officielle à venir ;
- Xbox : emplacement préparé, connexion officielle à venir ;
- Nintendo : emplacement préparé, connexion officielle à venir ;
- Epic Games : emplacement préparé, connexion officielle à venir.

IMPORTANT : Project XP ne simule pas une connexion PlayStation/Xbox/Nintendo/Epic.
Tant que leur intégration officielle n'est pas construite, ces boutons restent
volontairement indisponibles.

2) CONNEXION STEAM VIA STEAM

Le joueur n'a plus à taper son pseudo, son URL de profil ou son SteamID.

Parcours :
COMPTES > Steam > CONNECTER
→ ouverture du navigateur
→ page officielle Steam
→ Steam confirme le SteamID
→ retour automatique dans Project XP
→ compte Steam enregistré côté Cloud Project XP

Le mot de passe Steam n'est jamais saisi dans Project XP.
Le SteamID n'est accepté comme liaison officielle qu'après validation OpenID par Steam.

La connexion utilise l'OpenID 2.0 officiel de Steam.

Une ancienne liaison locale issue de nos tests reste détectée pour ne pas casser
la synchro actuelle. L'écran COMPTES demande cependant de reconnecter Steam une
fois officiellement afin de sécuriser et cloudifier le lien.

3) DÉLIER STEAM

COMPTES > Steam > DÉLIER

Délier Steam :
- arrête les futures synchronisations Steam ;
- ne supprime PAS les jeux déjà présents ;
- ne supprime PAS les succès déjà enregistrés ;
- ne détruit PAS l'historique Project XP.

4) « SYNCHRONISER TOUT »

Le petit bouton de synchronisation sur chaque carte est supprimé.
Ouvrir une fiche ne déclenche plus une synchro réseau avant d'afficher la fiche.

Le bouton principal :
SYNCHRONISER TOUT

fait actuellement :
- bibliothèque Steam ;
- temps de jeu Steam ;
- activité récente Steam ;
- succès Steam de tous les jeux Steam liés ;
- détection des nouveaux succès ;
- Fil d'Aventure pour les nouveaux succès après la première baseline.

Les jeux sans succès et les jeux pour lesquels Steam ne fournit pas de données
n'arrêtent plus la file : Project XP continue avec les jeux suivants.

Quand PlayStation/Xbox/etc. auront leur connecteur officiel, ce même bouton pourra
orchestrer toutes les plateformes sans changer l'UX.

5) SYNCHRONISATION AU LANCEMENT DE L'APP

Project XP commence automatiquement une synchro gaming en arrière-plan une fois
le compte et la Bibliothèque Cloud restaurés.

Elle ne bloque jamais le Hall et ne retarde pas l'ouverture visuelle de l'app.

Stratégie pour rester fluide :
- bibliothèque Steam rafraîchie à chaque lancement ;
- priorité aux jeux dont l'activité Steam a changé ;
- puis jeux jamais synchronisés / données âgées de plus de 8 h ;
- maximum 24 fiches de succès par lancement en arrière-plan.

Pourquoi ne pas faire 148 appels de succès à CHAQUE lancement ?
Parce que ce serait inutilement lent, coûteux en réseau/batterie et plus exposé
aux limites de l'API Steam. Le bouton SYNCHRONISER TOUT force, lui, tous les jeux
quand le joueur le demande.

Il n'y a pas une « vérification » séparée avant la synchro : la synchro elle-même
récupère les données et Project XP compare ensuite avec ce qu'il connaît déjà.

6) FLUIDITÉ

- la synchro réseau est asynchrone ;
- le Hall n'attend pas la synchro gaming ;
- les succès sont sauvegardés en lot plutôt qu'une sauvegarde Cloud par jeu ;
- un jeu Steam indisponible ne bloque pas les suivants ;
- ouvrir une fiche ne lance plus automatiquement Steam ;
- le clavier ne prend plus le focus automatiquement dans la Bibliothèque ni
  dans la recherche catalogue.

7) JAQUETTES PIXELISÉES

Les mini-icônes Steam ne sont plus utilisées comme jaquettes.
Les anciens header.jpg horizontaux ne sont plus étirés en portrait.

Project XP préfère maintenant :
- jaquette IGDB/catalogue déjà existante ;
- capsule Steam verticale 600x900 HD ;
- capsule Steam verticale 600x900 standard ;
- sinon un placeholder Project XP propre.

Une petite image réussissant à charger n'est donc plus agrandie artificiellement.

8) NOM + JAQUETTE VERROUILLÉS APRÈS CONNEXION OFFICIELLE DU JEU

Les protections V1.10.2b/c restent présentes :
- nom non modifiable quand une fiche possède une connexion plateforme officielle ;
- jaquette non modifiable manuellement dans ce cas ;
- une jaquette catalogue propre déjà présente reste prioritaire lors d'une fusion.

============================================================
NOUVEAUX FICHIERS / FICHIERS MODIFIÉS
============================================================

pubspec.yaml
android/app/src/main/AndroidManifest.xml
ios/Runner/Info.plist

lib/models/game_library_entry.dart
lib/screens/game_library_screen.dart
lib/screens/gaming_accounts_screen.dart
lib/services/game_library_service.dart
lib/services/gaming_accounts_service.dart
lib/services/project_xp_startup_service.dart
lib/services/steam_sync_service.dart
lib/widgets/game_cover_image.dart

supabase/migrations/20260902233500_project_xp_platform_accounts_v1.sql
supabase/functions/platform-auth/index.ts
supabase/functions/steam-sync/index.ts

============================================================
INSTALLATION — À FAIRE DANS CET ORDRE
============================================================

1. Extraire ce ZIP à la racine :

C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

Accepter le remplacement des fichiers.

2. Nouvelles dépendances Flutter :

flutter pub get

3. Vérifier la migration Supabase :

npx.cmd supabase db push --dry-run

Résultat attendu :
la migration 20260902233500_project_xp_platform_accounts_v1.sql uniquement.

4. Si le dry-run est propre :

npx.cmd supabase db push

5. Déployer la nouvelle fonction d'authentification plateformes.

IMPORTANT : le callback venant du navigateur Steam n'a pas de JWT Project XP,
donc cette fonction doit être déployée avec --no-verify-jwt. La fonction vérifie
elle-même le JWT sur l'action de départ et vérifie ensuite cryptographiquement
la réponse OpenID auprès de Steam.

npx.cmd supabase functions deploy platform-auth --no-verify-jwt

6. steam-sync V1.10.2b reste compatible et n'a pas besoin d'être redéployé si
la V1.10.2b a déjà été déployée.

7. Vérifier Flutter :

flutter analyze

Résultat attendu :
No issues found!

8. Fermer complètement Project XP puis relancer.
Un hot reload ne suffit pas pour tester correctement les nouveaux deep links.

============================================================
PREMIER TEST CONSEILLÉ
============================================================

A. Ouvrir :
PC > Bibliothèque > COMPTES

B. Steam doit indiquer soit :
- Non lié
ou
- Ancienne liaison locale détectée

C. Appuyer CONNECTER sur Steam.
Le navigateur doit ouvrir une page steamcommunity.com.

D. Se connecter / confirmer côté Steam.
Le navigateur doit revenir automatiquement dans Project XP.

E. Steam doit alors apparaître comme compte lié avec le pseudo Steam si Steam
permet de le récupérer.

F. Revenir à la Bibliothèque puis appuyer SYNCHRONISER TOUT.
La progression doit afficher les jeux traités sans devoir ouvrir chaque fiche.

G. Fermer complètement puis relancer Project XP.
L'app doit rester fluide et la synchro gaming doit démarrer silencieusement en
arrière-plan.

============================================================
NOTE PRODUCTION
============================================================

Le retour navigateur utilise pour l'instant le schéma applicatif :
projectxp://platform-auth

C'est adapté à notre phase de développement Android/iOS. Avant publication à
grande échelle, lorsque Project XP possédera son vrai domaine, il sera préférable
de passer à des Android App Links / Universal Links vérifiés par domaine afin
de durcir encore le retour navigateur.
