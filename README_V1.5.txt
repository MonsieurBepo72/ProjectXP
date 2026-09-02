PROJECT XP — CENTRE DE NOTIFICATIONS V1.5

BASE
- Cette version est construite sur Compagnie Online Invitations V1.4.
- Le filtre « Afficher les amis » et les invitations Compagnie cross-device sont conservés.
- project_xp_intro.png et le splash ne sont pas concernés.

CE QUE V1.5 AJOUTE

1. Le bouton « Notifications » du Communicateur XP ouvre désormais un vrai écran.
2. Les Messages restent uniquement dans « Messages ».
3. Les demandes d'amis reçues restent uniquement dans « Demandes ».
4. Le Centre de notifications contient :
   - invitations Compagnie reçues avec REJOINDRE / REFUSER ;
   - demandes pour rejoindre une Compagnie avec ACCEPTER / REFUSER ;
   - confirmation lorsqu'un joueur accepte une invitation Compagnie ;
   - confirmation positive lorsqu'un joueur accepte une demande d'ami,
     si la ligne acceptée est encore disponible dans Supabase.
5. AUCUNE notification n'est créée lorsqu'un ami te retire de ses amis.
6. Le bloc Notifications possède son propre badge.
7. Le badge global du téléphone dans le Hall reste la somme :
   Notifications + Messages non lus + Demandes d'amis reçues.

INSTALLATION

1. Extraire le ZIP à la racine :
   C:\Users\MonsieurBepo\Desktop\ProjectXP\project_xp

2. Le SQL de V1.4 est inclus par sécurité dans :
   supabase/compagnie_online_invitations_v1.sql

   Si tu l'as DÉJÀ exécuté avec succès dans Supabase pour la V1.4,
   ne fais rien de plus dans Supabase pour cette V1.5.

3. Dans PowerShell, à la racine du projet :
   flutter analyze

4. Si l'analyse est propre :
   flutter run -d 192.168.1.15:5555

TEST PRIORITAIRE À DEUX TÉLÉPHONES

A. Tel1 invite Tel2 dans une Compagnie.
B. Tel2 revient dans le Hall : le téléphone doit avoir un badge.
C. Tel2 ouvre Communicateur XP > Notifications.
D. L'invitation doit apparaître dans « À TRAITER ».
E. Appuyer sur REJOINDRE.
F. L'invitation doit disparaître de « À TRAITER ».
G. Tel1 ouvre/actualise Notifications :
   « Tel2 a rejoint <nom de la Compagnie> » doit apparaître dans
   « Activité récente ».

SOCIAL
- Les demandes d'amis reçues ne sont PAS dupliquées dans Notifications.
- Les messages privés ne sont PAS dupliqués dans Notifications.
- Si Supabase conserve les lignes friend_requests avec status='accepted',
  l'expéditeur voit « X a accepté ta demande d'ami » dans Activité récente.
- Si la base supprime ces lignes à l'acceptation, cette catégorie reste vide :
  V1.5 n'invente aucun faux événement.
