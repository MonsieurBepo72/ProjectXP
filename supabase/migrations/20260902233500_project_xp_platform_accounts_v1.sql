-- PROJECT XP — V1.10.3
-- Comptes gaming officiels liés au compte Cloud Project XP.

begin;

create table if not exists public.project_xp_platform_accounts (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  project_xp_user_id text not null,
  provider text not null,
  provider_user_id text not null,
  display_name text,
  avatar_url text,
  linked_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (auth_user_id, provider)
);

create unique index if not exists project_xp_platform_accounts_provider_user_unique
  on public.project_xp_platform_accounts(provider, provider_user_id);

alter table public.project_xp_platform_accounts enable row level security;

revoke all on public.project_xp_platform_accounts from anon;
grant select, delete on public.project_xp_platform_accounts to authenticated;

drop policy if exists project_xp_platform_accounts_select_own
  on public.project_xp_platform_accounts;
create policy project_xp_platform_accounts_select_own
  on public.project_xp_platform_accounts
  for select
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_platform_accounts_delete_own
  on public.project_xp_platform_accounts;
create policy project_xp_platform_accounts_delete_own
  on public.project_xp_platform_accounts
  for delete
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

-- Flux courts utilisés uniquement côté serveur pour relier un navigateur Steam
-- à la bonne session Cloud Project XP. Aucun accès client direct n'est accordé.
create table if not exists public.project_xp_platform_auth_flows (
  id uuid primary key,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  project_xp_user_id text not null,
  provider text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists project_xp_platform_auth_flows_expiry_idx
  on public.project_xp_platform_auth_flows(expires_at);

alter table public.project_xp_platform_auth_flows enable row level security;
revoke all on public.project_xp_platform_auth_flows from anon, authenticated;

commit;
