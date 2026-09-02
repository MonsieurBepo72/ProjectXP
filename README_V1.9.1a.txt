PROJECT XP — V1.9.1a DIAGNOSTIC SUPABASE

But : afficher temporairement l'erreur Auth Supabase exacte lorsque
"Mot de passe oublié ?" échoue avant l'envoi du code.

Fichier remplacé :
- lib/services/cloud_identity_service.dart

Aucune migration SQL.
Aucun nouveau package.
Aucun secret à modifier.
Aucun changement de données utilisateur.

Test :
1. Extraire ce ZIP à la racine du projet Project XP et remplacer le fichier.
2. flutter analyze
3. flutter run
4. Compte Cloud Project XP -> Mot de passe oublié ? -> Envoyer le code
5. Copier le message commençant par "DIAGNOSTIC SUPABASE :".

Cette version est volontairement temporaire : le message brut Supabase sera
remplacé par un message utilisateur propre après identification de la cause.
