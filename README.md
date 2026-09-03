# Project XP

Project XP est une application sociale gaming / RPG fantasy développée avec Flutter.
Le Hall sert de hub principal, la Taverne de salon public, et le Communicateur regroupe les interactions sociales et les messages.

## État actuel

- **Android :** plateforme de développement et de test principale.
- **iOS :** cible prévue, mais Firebase iOS et la signature Apple ne sont pas encore configurés.
- **Web :** squelette Flutter conservé pour une future version web, mais cette plateforme n'est pas encore supportée.
- **Desktop :** Windows, Linux et macOS desktop ne sont pas ciblés ; leurs dossiers Flutter ont été retirés du projet.
- **Backend :** Supabase (auth/data/realtime/Edge Functions) + Firebase/FCM pour les notifications.

## Prérequis

- Flutter compatible avec le SDK Dart déclaré dans `pubspec.yaml`.
- Android SDK / Android Studio pour Android.
- Pour iOS plus tard : macOS + Xcode + compte Apple Developer + configuration FlutterFire iOS.

## Installation locale

```powershell
flutter pub get
flutter analyze
flutter devices
flutter run -d <device-id>
```

Appareils de test utilisés pendant le développement :

- HD1910 (Android 12)
- SM G928F (Android 7 / API 24 minimum)

## Architecture principale

```text
lib/
  screens/      écrans Flutter (Hall, Taverne, téléphone, profils...)
  services/     auth, Supabase, présence, modération, notifications...
  models/       modèles de données
  widgets/      composants réutilisables
assets/
  images/       Hall, Taverne, avatars et visuels
  audio/        musique et effets sonores
supabase/
  functions/    Edge Functions
  migrations/   migrations Supabase officielles
  queries/      requêtes SQL de contrôle / diagnostic
  manual/       scripts SQL historiques ou appliqués manuellement
```

## Configuration et secrets

Les **secrets serveur ne doivent jamais être commités**. `.gitignore` protège notamment les fichiers `.env`, clés privées, keystores et comptes de service.

Les valeurs Firebase/Supabase présentes dans le client sont des configurations clientes/publishable. La sécurité des données repose notamment sur les règles Firebase et les policies RLS Supabase.

Les Edge Functions utilisent les secrets stockés côté Supabase (`Deno.env`) : service role, OpenAI, compte de service Firebase, etc.

## Signature Android release

Le build `release` n'utilise plus automatiquement la clé debug. Pour préparer une publication, créer un keystore privé puis un fichier local `android/key.properties` (ignoré par Git) :

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=C:/chemin/vers/project-xp-release.jks
```

Tant que ce fichier n'existe pas, les builds debug continuent normalement et un build release ne reçoit pas de signature de production.

## iOS (prévu, pas encore configuré)

Avant une bêta iPhone :

1. choisir/verrouiller l'identifiant de bundle définitif ;
2. enregistrer l'app iOS dans Firebase / FlutterFire ;
3. générer les options Firebase iOS et `GoogleService-Info.plist` ;
4. configurer Signing & Capabilities dans Xcode ;
5. tester notifications, biométrie, permissions et navigation sur un vrai iPhone ;
6. préparer App Store Connect / TestFlight.

**Important :** l'identifiant actuel `com.example.project_xp` est encore un identifiant de développement. Ne pas le renommer à la légère : le changement doit être coordonné avec Firebase et les stores.

## Modération

La modération client a atteint la version **V2.4.6.2** (slang, grammaire, contexte et réduction des faux positifs). Les fonctions serveur Supabase existent également ; le lockdown final doit être effectué seulement après validation complète de la couche serveur.

## Git / workflow

Avant toute grosse modification :

```powershell
git status
flutter analyze
```

Après validation sur appareils réels :

```powershell
git add <fichiers>
git commit -m "Description claire"
git push origin main
```

Éviter de committer des builds, secrets, keystores ou fichiers temporaires.

## Direction produit

Priorités actuelles :

1. finaliser le polish de la Taverne ;
2. consolider amis / demandes / blocages / permissions MP ;
3. enrichir les profils et la personnalisation ;
4. développer progression, XP, quêtes et hauts faits ;
5. préparer ensuite les étapes de bêta et publication Android/iOS.
