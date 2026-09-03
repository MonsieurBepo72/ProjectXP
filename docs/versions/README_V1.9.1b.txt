PROJECT XP — V1.9.1b — Code OTP Supabase

Correctif ciblé : l'écran Compte Cloud n'impose plus uniquement 6 chiffres.
Supabase a envoyé un OTP de 8 chiffres pendant le flux de changement d'e-mail.

Le champ accepte maintenant les codes OTP de 6 OU 8 chiffres afin de rester compatible
avec les différents flux/configurations Supabase, sans modifier la logique de vérification.

Fichier remplacé :
- lib/screens/cloud_identity_screen.dart

Installation : extraire le contenu du ZIP à la racine du projet Project XP et accepter le remplacement.
Puis lancer : flutter analyze
