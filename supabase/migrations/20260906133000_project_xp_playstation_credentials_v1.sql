-- PROJECT XP — Suite 0.4 / 04B1
-- Jetons de renouvellement des plateformes sensibles.
-- Aucun accès client direct : lecture/écriture réservées aux Edge Functions
-- via la service-role Supabase.

begin;

create table if not exists public.project_xp_platform_credentials (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  secret_ciphertext text not null,
  secret_iv text not null,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (auth_user_id, provider),
  foreign key (auth_user_id, provider)
    references public.project_xp_platform_accounts(auth_user_id, provider)
    on delete cascade
);

alter table public.project_xp_platform_credentials enable row level security;

revoke all on public.project_xp_platform_credentials from anon, authenticated;

-- Défense supplémentaire : même si des privilèges sont accordés par erreur
-- plus tard, aucune policy client n'est créée sur cette table.
drop policy if exists project_xp_platform_credentials_select_own
  on public.project_xp_platform_credentials;
drop policy if exists project_xp_platform_credentials_insert_own
  on public.project_xp_platform_credentials;
drop policy if exists project_xp_platform_credentials_update_own
  on public.project_xp_platform_credentials;
drop policy if exists project_xp_platform_credentials_delete_own
  on public.project_xp_platform_credentials;

create index if not exists project_xp_platform_credentials_provider_idx
  on public.project_xp_platform_credentials(provider);

commit;
