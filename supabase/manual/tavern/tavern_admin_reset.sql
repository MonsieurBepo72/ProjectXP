-- ============================================================================
-- PROJECT XP - ADMIN TAVERNE
--
-- Ce script crée :
--   - une table privée d'administrateurs ;
--   - un RPC pour savoir si le joueur actuel est admin ;
--   - un RPC sécurisé pour supprimer TOUS les messages publics de la Taverne.
--
-- IMPORTANT :
-- Après avoir exécuté ce script, il faudra ajouter TON compte Project XP
-- dans public.project_admins. On fera cette petite étape ensemble.
-- ============================================================================


-- ============================================================================
-- TABLE DES ADMINISTRATEURS
-- ============================================================================

create table if not exists public.project_admins (
  user_id uuid primary key
    references auth.users(id)
    on delete cascade,

  created_at timestamptz not null
    default now()
);


alter table public.project_admins
enable row level security;


-- Un administrateur authentifié peut seulement voir SA propre ligne.
-- Personne ne peut s'ajouter lui-même depuis l'application.

drop policy if exists
  "project_admin_can_read_self"
on public.project_admins;


create policy
  "project_admin_can_read_self"
on public.project_admins
for select
to authenticated
using (
  user_id = auth.uid()
);


grant select
on public.project_admins
to authenticated;


-- ============================================================================
-- SAVOIR SI LE JOUEUR ACTUEL EST ADMIN
-- ============================================================================

create or replace function public.project_xp_is_admin()
returns boolean

language sql

stable

security definer

set search_path =
  public

as $$

  select
    auth.uid() is not null

    and exists (
      select
        1

      from
        public.project_admins

      where
        user_id = auth.uid()
    );

$$;


revoke all
on function public.project_xp_is_admin()
from public;


grant execute
on function public.project_xp_is_admin()
to authenticated;


-- ============================================================================
-- RÉINITIALISER LA TAVERNE
-- ============================================================================

create or replace function public.project_xp_admin_reset_tavern()
returns integer

language plpgsql

security definer

set search_path =
  public

as $$

declare

  v_deleted integer :=
    0;

begin

  if auth.uid() is null then

    raise exception
      'PROJECT_XP_AUTH_REQUIRED'

      using errcode =
        'P0001';

  end if;


  if not exists (
    select
      1

    from
      public.project_admins

    where
      user_id = auth.uid()
  ) then

    raise exception
      'PROJECT_XP_ADMIN_REQUIRED'

      using errcode =
        'P0001';

  end if;


  delete from
    public.tavern_messages;


  get diagnostics
    v_deleted =
      row_count;


  return
    v_deleted;

end;

$$;


revoke all
on function public.project_xp_admin_reset_tavern()
from public;


grant execute
on function public.project_xp_admin_reset_tavern()
to authenticated;


-- ============================================================================
-- FIN
-- ============================================================================
