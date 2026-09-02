-- PROJECT XP — CLOUD FOUNDATION V1.10.0
--
-- Objectif : rendre les données personnelles essentielles récupérables sur un
-- autre appareil sans supprimer le cache local historique.
--
-- Le Cloud est réservé aux comptes Supabase PERMANENTS. Les utilisateurs
-- anonymes continuent de fonctionner avec les mécanismes existants.

begin;

-- =============================================================================
-- PROFIL PRIVÉ + AVATAR PRIVÉ
-- =============================================================================

create table if not exists public.project_xp_cloud_profiles (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  project_xp_user_id text not null unique,
  profile_data jsonb not null default '{}'::jsonb,
  profile_updated_at timestamptz,
  avatar_data jsonb,
  avatar_photo_path text,
  avatar_updated_at timestamptz,
  library_initialized boolean not null default false,
  activity_initialized boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.project_xp_cloud_profiles
  add column if not exists library_initialized boolean not null default false,
  add column if not exists activity_initialized boolean not null default false;

alter table public.project_xp_cloud_profiles enable row level security;

grant select, insert, update, delete
  on public.project_xp_cloud_profiles
  to authenticated;

drop policy if exists project_xp_cloud_profiles_select_own
  on public.project_xp_cloud_profiles;
create policy project_xp_cloud_profiles_select_own
  on public.project_xp_cloud_profiles
  for select
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_cloud_profiles_insert_own
  on public.project_xp_cloud_profiles;
create policy project_xp_cloud_profiles_insert_own
  on public.project_xp_cloud_profiles
  for insert
  to authenticated
  with check (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.project_xp_cloud_accounts account
      where account.auth_user_id = auth.uid()
        and account.project_xp_user_id = project_xp_cloud_profiles.project_xp_user_id
    )
  );

drop policy if exists project_xp_cloud_profiles_update_own
  on public.project_xp_cloud_profiles;
create policy project_xp_cloud_profiles_update_own
  on public.project_xp_cloud_profiles
  for update
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  )
  with check (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.project_xp_cloud_accounts account
      where account.auth_user_id = auth.uid()
        and account.project_xp_user_id = project_xp_cloud_profiles.project_xp_user_id
    )
  );

drop policy if exists project_xp_cloud_profiles_delete_own
  on public.project_xp_cloud_profiles;
create policy project_xp_cloud_profiles_delete_own
  on public.project_xp_cloud_profiles
  for delete
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

-- =============================================================================
-- BIBLIOTHÈQUE
-- =============================================================================

create table if not exists public.project_xp_game_library (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  project_xp_user_id text not null,
  game_id text not null,
  game_data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (auth_user_id, game_id)
);

create index if not exists project_xp_game_library_updated_idx
  on public.project_xp_game_library(auth_user_id, updated_at desc);

alter table public.project_xp_game_library enable row level security;

grant select, insert, update, delete
  on public.project_xp_game_library
  to authenticated;

drop policy if exists project_xp_game_library_select_own
  on public.project_xp_game_library;
create policy project_xp_game_library_select_own
  on public.project_xp_game_library
  for select
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_game_library_insert_own
  on public.project_xp_game_library;
create policy project_xp_game_library_insert_own
  on public.project_xp_game_library
  for insert
  to authenticated
  with check (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.project_xp_cloud_accounts account
      where account.auth_user_id = auth.uid()
        and account.project_xp_user_id = project_xp_game_library.project_xp_user_id
    )
  );

drop policy if exists project_xp_game_library_update_own
  on public.project_xp_game_library;
create policy project_xp_game_library_update_own
  on public.project_xp_game_library
  for update
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  )
  with check (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.project_xp_cloud_accounts account
      where account.auth_user_id = auth.uid()
        and account.project_xp_user_id = project_xp_game_library.project_xp_user_id
    )
  );

drop policy if exists project_xp_game_library_delete_own
  on public.project_xp_game_library;
create policy project_xp_game_library_delete_own
  on public.project_xp_game_library
  for delete
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

-- Remplacement transactionnel de la Bibliothèque complète.
-- Cela permet de conserver correctement les suppressions tout en laissant
-- l'application fusionner les modifications jeu par jeu avant l'appel.
create or replace function public.project_xp_replace_game_library(
  p_entries jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_project_xp_user_id text;
begin
  if v_auth_user_id is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return false;
  end if;

  select account.project_xp_user_id
    into v_project_xp_user_id
  from public.project_xp_cloud_accounts account
  where account.auth_user_id = v_auth_user_id;

  if v_project_xp_user_id is null then
    return false;
  end if;

  delete from public.project_xp_game_library
  where auth_user_id = v_auth_user_id;

  insert into public.project_xp_game_library (
    auth_user_id,
    project_xp_user_id,
    game_id,
    game_data,
    updated_at
  )
  select
    v_auth_user_id,
    v_project_xp_user_id,
    item.value ->> 'id',
    item.value,
    coalesce(
      nullif(item.value ->> 'updatedAt', '')::timestamptz,
      now()
    )
  from jsonb_array_elements(
    coalesce(p_entries, '[]'::jsonb)
  ) as item(value)
  where coalesce(item.value ->> 'id', '') <> '';

  insert into public.project_xp_cloud_profiles (
    auth_user_id,
    project_xp_user_id,
    library_initialized,
    updated_at
  )
  values (
    v_auth_user_id,
    v_project_xp_user_id,
    true,
    now()
  )
  on conflict (auth_user_id) do update
  set library_initialized = true,
      updated_at = now();

  return true;
end;
$$;

revoke all on function public.project_xp_replace_game_library(jsonb)
  from public;
grant execute on function public.project_xp_replace_game_library(jsonb)
  to authenticated;

-- =============================================================================
-- FIL D'AVENTURE
-- =============================================================================

create table if not exists public.project_xp_gaming_activity (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  project_xp_user_id text not null,
  event_id text not null,
  event_data jsonb not null,
  created_at timestamptz not null default now(),
  primary key (auth_user_id, event_id)
);

create index if not exists project_xp_gaming_activity_created_idx
  on public.project_xp_gaming_activity(auth_user_id, created_at desc);

alter table public.project_xp_gaming_activity enable row level security;

grant select, insert, update, delete
  on public.project_xp_gaming_activity
  to authenticated;

drop policy if exists project_xp_gaming_activity_select_own
  on public.project_xp_gaming_activity;
create policy project_xp_gaming_activity_select_own
  on public.project_xp_gaming_activity
  for select
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_gaming_activity_insert_own
  on public.project_xp_gaming_activity;
create policy project_xp_gaming_activity_insert_own
  on public.project_xp_gaming_activity
  for insert
  to authenticated
  with check (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.project_xp_cloud_accounts account
      where account.auth_user_id = auth.uid()
        and account.project_xp_user_id = project_xp_gaming_activity.project_xp_user_id
    )
  );

drop policy if exists project_xp_gaming_activity_update_own
  on public.project_xp_gaming_activity;
create policy project_xp_gaming_activity_update_own
  on public.project_xp_gaming_activity
  for update
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  )
  with check (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.project_xp_cloud_accounts account
      where account.auth_user_id = auth.uid()
        and account.project_xp_user_id = project_xp_gaming_activity.project_xp_user_id
    )
  );

drop policy if exists project_xp_gaming_activity_delete_own
  on public.project_xp_gaming_activity;
create policy project_xp_gaming_activity_delete_own
  on public.project_xp_gaming_activity
  for delete
  to authenticated
  using (
    auth.uid() = auth_user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create or replace function public.project_xp_replace_gaming_activity(
  p_events jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_project_xp_user_id text;
begin
  if v_auth_user_id is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return false;
  end if;

  select account.project_xp_user_id
    into v_project_xp_user_id
  from public.project_xp_cloud_accounts account
  where account.auth_user_id = v_auth_user_id;

  if v_project_xp_user_id is null then
    return false;
  end if;

  delete from public.project_xp_gaming_activity
  where auth_user_id = v_auth_user_id;

  insert into public.project_xp_gaming_activity (
    auth_user_id,
    project_xp_user_id,
    event_id,
    event_data,
    created_at
  )
  select
    v_auth_user_id,
    v_project_xp_user_id,
    item.value ->> 'id',
    item.value,
    coalesce(
      nullif(item.value ->> 'createdAt', '')::timestamptz,
      now()
    )
  from jsonb_array_elements(
    coalesce(p_events, '[]'::jsonb)
  ) as item(value)
  where coalesce(item.value ->> 'id', '') <> ''
    and lower(coalesce(item.value ->> 'title', ''))
      not like '%rejoint ta bibliothèque%';

  insert into public.project_xp_cloud_profiles (
    auth_user_id,
    project_xp_user_id,
    activity_initialized,
    updated_at
  )
  values (
    v_auth_user_id,
    v_project_xp_user_id,
    true,
    now()
  )
  on conflict (auth_user_id) do update
  set activity_initialized = true,
      updated_at = now();

  return true;
end;
$$;

revoke all on function public.project_xp_replace_gaming_activity(jsonb)
  from public;
grant execute on function public.project_xp_replace_gaming_activity(jsonb)
  to authenticated;

-- =============================================================================
-- PHOTO D'AVATAR PRIVÉE
-- =============================================================================

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'project-xp-private-avatars',
  'project-xp-private-avatars',
  false,
  10485760,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists project_xp_private_avatar_select_own
  on storage.objects;
create policy project_xp_private_avatar_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'project-xp-private-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_private_avatar_insert_own
  on storage.objects;
create policy project_xp_private_avatar_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'project-xp-private-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_private_avatar_update_own
  on storage.objects;
create policy project_xp_private_avatar_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'project-xp-private-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  )
  with check (
    bucket_id = 'project-xp-private-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists project_xp_private_avatar_delete_own
  on storage.objects;
create policy project_xp_private_avatar_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'project-xp-private-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

commit;
