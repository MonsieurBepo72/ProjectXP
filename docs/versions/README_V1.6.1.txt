PROJECT XP — COMMUNICATEUR + COMPAGNIE V1.6.1

Cette version corrige les retours après test de la V1.6 :

1. Fond d'écran : chaque nouvelle image a désormais un fichier unique.
   Flutter ne peut plus réafficher la première photo depuis son cache.

2. Icônes adaptatives : la couleur moyenne du fond choisi est analysée
   localement. Les tuiles, bordures et pictogrammes du Communicateur
   s'accordent automatiquement au fond tout en gardant du contraste.

3. Téléphone global / actions : le mini Communicateur est légèrement
   descendu sous la ligne des actions AppBar pour ne plus engloutir des
   boutons comme « Modifier l'équipe ».

4. Avatars de Compagnie : AvatarStorage sait maintenant récupérer les
   avatars publics Supabase des membres distants. AvatarRenderer accepte
   aussi une avatar_url distante pour les avatars photo.

5. Présence en ligne : reconnexion Realtime réparée. Le service retracke
   l'utilisateur après reconnexion réseau, ne le met plus hors ligne sur
   un simple état Android « inactive », et vérifie périodiquement la présence.

AUCUN NOUVEAU SQL N'EST NÉCESSAIRE pour cette V1.6.1.

INSTALLATION
- Extraire à la racine du projet.
- flutter analyze
- Installer la même version sur Tel1 et Tel2.

TESTS RAPIDES
A. Fond : choisir photo A, réinitialiser, choisir photo B -> B doit s'afficher.
B. Icônes : comparer un fond clair puis sombre -> les tuiles/icônes doivent s'adapter.
C. Compagnie : ouvrir une équipe -> le bouton Modifier et le téléphone ne doivent plus se superposer.
D. Membres : le pseudo ET l'avatar du membre distant doivent être visibles.
E. Présence : laisser Tel1 au premier plan, ouvrir Trouver des joueurs sur Tel2 -> Tel1 doit être En ligne. Tester aussi après Wi-Fi off/on ou retour d'un sélecteur système.
