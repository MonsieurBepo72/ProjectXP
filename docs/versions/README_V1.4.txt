PROJECT XP — COMPAGNIE ONLINE INVITATIONS V1.4

ORDRE D'INSTALLATION

1. Dans Supabase > SQL Editor, exécuter :
   supabase/compagnie_online_invitations_v1.sql

2. Extraire ensuite le contenu du ZIP à la racine du projet Flutter.

3. Vérifier :
   flutter analyze

4. Lancer sur les deux téléphones.

TEST CONSEILLÉ

- Téléphone 1 : être Chef/Admin d'une équipe.
- Trouver des joueurs > ouvrir le profil du Téléphone 2.
- Appuyer sur « INVITER DANS UNE ÉQUIPE ».
- Choisir l'équipe.
- Téléphone 2 : ouvrir le Communicateur XP / invitations Compagnie,
  actualiser, puis accepter.
- Téléphone 2 : ouvrir « Mes équipes » : l'équipe doit apparaître.
- Téléphone 1 : actualiser « Mes équipes » : le compteur de membres doit
  refléter l'adhésion.

IMPORTANT

- Les invitations envoyées depuis les vrais profils Supabase sont maintenant
  cross-device.
- Les anciennes invitations entre comptes purement locaux restent compatibles.
- La recherche publique d'équipes et les demandes d'adhésion restent encore
  sur leur ancien fonctionnement : elles ne sont pas migrées dans cette V1.4.
