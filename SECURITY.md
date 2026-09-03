# Sécurité — Project XP

## Principe

Project XP distingue strictement les **configurations clientes publiables** des **secrets serveur**.

### Autorisé côté client

- URL publique Supabase.
- Clé Supabase `sb_publishable_...` / clé `anon` legacy.
- Configuration Firebase cliente.

Ces valeurs ne constituent pas une frontière de sécurité. Pour Supabase, la protection des données repose notamment sur **Row Level Security (RLS)**, les policies et l'identité de l'utilisateur.

### Interdit dans le client ou dans Git

- Clé Supabase `service_role` / `sb_secret_...`.
- `OPENAI_API_KEY`.
- Compte de service Firebase / clé privée.
- Keystore Android et mots de passe de signature.
- Tokens administrateur ou secrets de webhook.
- Credentials de base de données.

Les secrets serveur doivent rester dans les variables d'environnement ou dans Supabase Secrets.

## Supabase

Avant une bêta publique :

1. vérifier que RLS est activé sur chaque table exposée ;
2. relire les policies `anon` et `authenticated` ;
3. vérifier les fonctions Edge et leurs contrôles d'authentification ;
4. contrôler le Security Advisor Supabase ;
5. confirmer qu'aucune clé serveur n'est présente dans le client ou l'historique Git.

## Signalement

En cas de découverte d'une vulnérabilité ou d'un secret exposé, ne pas publier le secret dans une issue publique. Prévenir le propriétaire du dépôt par un canal privé et révoquer/faire tourner le secret concerné.


## Administration de la Taverne

La suppression individuelle et la réinitialisation des messages de la Taverne
doivent passer par des fonctions PostgreSQL `SECURITY DEFINER` qui vérifient
`auth.uid()` dans `public.project_admins`.

La présence d'un bouton admin dans Flutter ne constitue jamais une autorisation.

## Notifications

Les tokens FCM identifient une installation et ne doivent jamais être écrits
en clair dans les logs, rapports de crash ou outils d'observabilité.
