-- PROJECT XP — V1.9.0
-- Identité Cloud stable + fondation des comptes de plateformes.
--
-- Cette migration NE remplace aucune table existante de Taverne/Compagnie.
-- Elle ajoute seulement la correspondance entre l'utilisateur Supabase
-- et l'ID historique Project XP déjà utilisé localement.

create table if not exists public.project_xp_cloud_accounts (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  project_xp_user_id text not null unique,
  username text not null,
  email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.project_xp_cloud_accounts
  enable row level security;

drop policy if exists
  "project_xp_cloud_accounts_select_own"
  on public.project_xp_cloud_accounts;

create policy
  "project_xp_cloud_accounts_select_own"
on public.project_xp_cloud_accounts
for select
to authenticated
using (
  auth.uid() = auth_user_id
);

drop policy if exists
  "project_xp_cloud_accounts_insert_own"
  on public.project_xp_cloud_accounts;

create policy
  "project_xp_cloud_accounts_insert_own"
on public.project_xp_cloud_accounts
for insert
to authenticated
with check (
  auth.uid() = auth_user_id
  and coalesce(
    (auth.jwt() ->> 'is_anonymous')::boolean,
    false
  ) = false
);

drop policy if exists
  "project_xp_cloud_accounts_update_own"
  on public.project_xp_cloud_accounts;

create policy
  "project_xp_cloud_accounts_update_own"
on public.project_xp_cloud_accounts
for update
to authenticated
using (
  auth.uid() = auth_user_id
)
with check (
  auth.uid() = auth_user_id
  and coalesce(
    (auth.jwt() ->> 'is_anonymous')::boolean,
    false
  ) = false
);

-- ---------------------------------------------------------------------------
-- COMPTES DE PLATEFORMES
--
-- Aucun mot de passe Steam/Xbox/PlayStation/Epic ne sera stocké ici.
-- On conservera seulement les identifiants publics/tokenisés nécessaires
-- après une authentification officielle de la plateforme.
-- ---------------------------------------------------------------------------

create table if not exists public.project_xp_external_accounts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  provider_user_id text not null,
  display_name text,
  metadata jsonb not null default '{}'::jsonb,
  connected_at timestamptz not null default now(),
  last_sync_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (auth_user_id, provider),
  unique (provider, provider_user_id)
);

alter table public.project_xp_external_accounts
  enable row level security;

drop policy if exists
  "project_xp_external_accounts_select_own"
  on public.project_xp_external_accounts;

create policy
  "project_xp_external_accounts_select_own"
on public.project_xp_external_accounts
for select
to authenticated
using (
  auth.uid() = auth_user_id
);

drop policy if exists
  "project_xp_external_accounts_insert_own"
  on public.project_xp_external_accounts;

create policy
  "project_xp_external_accounts_insert_own"
on public.project_xp_external_accounts
for insert
to authenticated
with check (
  auth.uid() = auth_user_id
  and coalesce(
    (auth.jwt() ->> 'is_anonymous')::boolean,
    false
  ) = false
);

drop policy if exists
  "project_xp_external_accounts_update_own"
  on public.project_xp_external_accounts;

create policy
  "project_xp_external_accounts_update_own"
on public.project_xp_external_accounts
for update
to authenticated
using (
  auth.uid() = auth_user_id
)
with check (
  auth.uid() = auth_user_id
  and coalesce(
    (auth.jwt() ->> 'is_anonymous')::boolean,
    false
  ) = false
);

drop policy if exists
  "project_xp_external_accounts_delete_own"
  on public.project_xp_external_accounts;

create policy
  "project_xp_external_accounts_delete_own"
on public.project_xp_external_accounts
for delete
to authenticated
using (
  auth.uid() = auth_user_id
);

create index if not exists
  project_xp_external_accounts_auth_user_idx
on public.project_xp_external_accounts (
  auth_user_id
);

create index if not exists
  project_xp_external_accounts_provider_idx
on public.project_xp_external_accounts (
  provider,
  provider_user_id
);
