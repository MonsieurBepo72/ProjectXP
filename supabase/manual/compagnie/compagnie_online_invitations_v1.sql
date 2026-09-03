-- Project XP — Compagnie online invitations V1
-- Objectif : rendre les invitations d'équipe réellement cross-device tout en
-- gardant SharedPreferences comme cache/compatibilité pour l'ancien système.

create extension if not exists pgcrypto;

-- ============================================================================
-- ÉQUIPES ONLINE
--
-- Cette table ne sert pas encore à la recherche publique d'équipes : elle
-- synchronise uniquement les équipes du joueur courant afin que les invitations
-- et les adhésions puissent exister entre plusieurs appareils.
-- ============================================================================

create table if not exists public.compagnie_online_teams (
  id text primary key,
  name text not null,
  description text not null default '',
  games text[] not null default '{}'::text[],
  platforms text[] not null default '{}'::text[],
  max_members integer not null default 5 check (max_members between 2 and 20),
  recruitment_open boolean not null default true,
  owner_id uuid not null,
  owner_name text not null default 'Joueur',
  leader_id uuid,
  leader_name text,
  image_path text,
  member_ids uuid[] not null default '{}'::uuid[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint compagnie_online_teams_owner_is_member
    check (owner_id = any(member_ids)),
  constraint compagnie_online_teams_capacity
    check (cardinality(member_ids) <= max_members)
);

create index if not exists compagnie_online_teams_owner_idx
  on public.compagnie_online_teams(owner_id);

create index if not exists compagnie_online_teams_leader_idx
  on public.compagnie_online_teams(leader_id);

alter table public.compagnie_online_teams enable row level security;

-- L'app ne récupère que les équipes dont le compte Supabase courant fait partie.
-- Cela évite d'activer par accident la recherche d'équipes cross-device avant
-- que le système de demandes d'adhésion ne soit lui aussi migré.
drop policy if exists "compagnie teams read own memberships"
  on public.compagnie_online_teams;

create policy "compagnie teams read own memberships"
  on public.compagnie_online_teams
  for select
  to authenticated
  using (
    auth.uid() = owner_id
    or auth.uid() = leader_id
    or auth.uid() = any(member_ids)
  );

-- Aucun INSERT / UPDATE / DELETE direct : toutes les mutations sensibles passent
-- par les fonctions SECURITY DEFINER ci-dessous.

-- ============================================================================
-- INVITATIONS ONLINE
-- ============================================================================

create table if not exists public.compagnie_team_invitations (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.compagnie_online_teams(id) on delete cascade,
  team_name text not null,
  inviter_id uuid not null,
  inviter_name text not null default 'Joueur',
  invitee_id uuid not null,
  invitee_name text not null default 'Joueur',
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  handled_by_user_id uuid,
  created_at timestamptz not null default now(),
  handled_at timestamptz
);

create unique index if not exists compagnie_team_invitations_one_pending_idx
  on public.compagnie_team_invitations(team_id, invitee_id)
  where status = 'pending';

create index if not exists compagnie_team_invitations_invitee_idx
  on public.compagnie_team_invitations(invitee_id, created_at desc);

create index if not exists compagnie_team_invitations_inviter_idx
  on public.compagnie_team_invitations(inviter_id, created_at desc);

alter table public.compagnie_team_invitations enable row level security;

drop policy if exists "compagnie invitations visible to involved users"
  on public.compagnie_team_invitations;

create policy "compagnie invitations visible to involved users"
  on public.compagnie_team_invitations
  for select
  to authenticated
  using (
    auth.uid() = inviter_id
    or auth.uid() = invitee_id
    or exists (
      select 1
      from public.compagnie_online_teams t
      where t.id = compagnie_team_invitations.team_id
        and (
          t.owner_id = auth.uid()
          or t.leader_id = auth.uid()
        )
    )
  );

-- ============================================================================
-- OUTILS SQL
-- ============================================================================

create or replace function public.project_xp_uuid_array_from_jsonb(p_value jsonb)
returns uuid[]
language sql
immutable
as $$
  select coalesce(
    array_agg(distinct value::uuid),
    '{}'::uuid[]
  )
  from jsonb_array_elements_text(
    coalesce(p_value, '[]'::jsonb)
  );
$$;

revoke all on function public.project_xp_uuid_array_from_jsonb(jsonb) from public;

-- ============================================================================
-- SYNCHRONISER UNE ÉQUIPE LOCALE VERS SUPABASE
--
-- Création : seul le propriétaire courant peut créer la ligne.
-- Mise à jour : Chef ou Admin peuvent synchroniser les détails, mais cette
-- fonction ne modifie jamais les rôles ni la liste des membres d'une équipe
-- déjà existante. Cela évite qu'un cache local obsolète écrase une adhésion
-- acceptée sur un autre téléphone.
-- ============================================================================

create or replace function public.project_xp_sync_compagnie_team(p_team jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team_id text;
  v_name text;
  v_description text;
  v_games text[];
  v_platforms text[];
  v_max_members integer;
  v_recruitment_open boolean;
  v_owner_id uuid;
  v_owner_name text;
  v_leader_id uuid;
  v_leader_name text;
  v_image_path text;
  v_member_ids uuid[];
  v_created_at timestamptz;
  v_existing public.compagnie_online_teams%rowtype;
begin
  if v_uid is null or p_team is null then
    return false;
  end if;

  v_team_id := btrim(coalesce(p_team->>'id', ''));
  v_name := btrim(coalesce(p_team->>'name', ''));
  v_description := coalesce(p_team->>'description', '');
  v_games := coalesce(
    array(select jsonb_array_elements_text(coalesce(p_team->'games', '[]'::jsonb))),
    '{}'::text[]
  );
  v_platforms := coalesce(
    array(select jsonb_array_elements_text(coalesce(p_team->'platforms', '[]'::jsonb))),
    '{}'::text[]
  );
  v_max_members := greatest(2, least(20, coalesce((p_team->>'max_members')::integer, 5)));
  v_recruitment_open := coalesce((p_team->>'recruitment_open')::boolean, true);
  v_owner_id := nullif(p_team->>'owner_id', '')::uuid;
  v_owner_name := btrim(coalesce(p_team->>'owner_name', 'Joueur'));
  v_leader_id := nullif(p_team->>'leader_id', '')::uuid;
  v_leader_name := nullif(btrim(coalesce(p_team->>'leader_name', '')), '');
  v_image_path := nullif(coalesce(p_team->>'image_path', ''), '');
  v_member_ids := public.project_xp_uuid_array_from_jsonb(p_team->'member_ids');
  v_created_at := coalesce(
    nullif(p_team->>'created_at', '')::timestamptz,
    now()
  );

  if v_team_id = '' or v_name = '' or v_owner_id is null then
    return false;
  end if;

  if not (v_owner_id = any(v_member_ids)) then
    v_member_ids := array_append(v_member_ids, v_owner_id);
  end if;

  select *
  into v_existing
  from public.compagnie_online_teams
  where id = v_team_id
  for update;

  if not found then
    if v_owner_id <> v_uid then
      return false;
    end if;

    if cardinality(v_member_ids) > v_max_members then
      return false;
    end if;

    insert into public.compagnie_online_teams (
      id,
      name,
      description,
      games,
      platforms,
      max_members,
      recruitment_open,
      owner_id,
      owner_name,
      leader_id,
      leader_name,
      image_path,
      member_ids,
      created_at,
      updated_at
    ) values (
      v_team_id,
      v_name,
      v_description,
      v_games,
      v_platforms,
      v_max_members,
      v_recruitment_open,
      v_owner_id,
      coalesce(nullif(v_owner_name, ''), 'Joueur'),
      case when v_leader_id = v_uid then v_leader_id else null end,
      case when v_leader_id = v_uid then v_leader_name else null end,
      v_image_path,
      v_member_ids,
      v_created_at,
      now()
    );

    return true;
  end if;

  if v_existing.owner_id <> v_uid
     and v_existing.leader_id is distinct from v_uid then
    return false;
  end if;

  if cardinality(v_existing.member_ids) > v_max_members then
    return false;
  end if;

  update public.compagnie_online_teams
  set
    name = v_name,
    description = v_description,
    games = v_games,
    platforms = v_platforms,
    max_members = v_max_members,
    recruitment_open = v_recruitment_open,
    owner_name = case
      when v_existing.owner_id = v_uid and v_owner_name <> '' then v_owner_name
      else owner_name
    end,
    leader_name = case
      when v_existing.leader_id = v_uid then v_leader_name
      else leader_name
    end,
    image_path = v_image_path,
    updated_at = now()
  where id = v_team_id;

  return true;
exception
  when others then
    return false;
end;
$$;

-- ============================================================================
-- MUTATIONS D'ÉQUIPE
-- ============================================================================

create or replace function public.project_xp_set_compagnie_recruitment(
  p_team_id text,
  p_is_open boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  update public.compagnie_online_teams
  set recruitment_open = p_is_open,
      updated_at = now()
  where id = p_team_id
    and (owner_id = v_uid or leader_id = v_uid);

  return found;
end;
$$;

create or replace function public.project_xp_add_compagnie_member(
  p_team_id text,
  p_member_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team public.compagnie_online_teams%rowtype;
begin
  select * into v_team
  from public.compagnie_online_teams
  where id = p_team_id
  for update;

  if not found
     or (v_team.owner_id <> v_uid and v_team.leader_id is distinct from v_uid)
     or p_member_id is null
     or p_member_id = any(v_team.member_ids)
     or cardinality(v_team.member_ids) >= v_team.max_members then
    return false;
  end if;

  update public.compagnie_online_teams
  set member_ids = array_append(member_ids, p_member_id),
      updated_at = now()
  where id = p_team_id;

  return true;
end;
$$;

create or replace function public.project_xp_remove_compagnie_member(
  p_team_id text,
  p_member_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team public.compagnie_online_teams%rowtype;
begin
  select * into v_team
  from public.compagnie_online_teams
  where id = p_team_id
  for update;

  if not found
     or (v_team.owner_id <> v_uid and v_team.leader_id is distinct from v_uid)
     or p_member_id is null
     or p_member_id = v_team.owner_id
     or not (p_member_id = any(v_team.member_ids)) then
    return false;
  end if;

  update public.compagnie_online_teams
  set member_ids = array_remove(member_ids, p_member_id),
      leader_id = case when leader_id = p_member_id then null else leader_id end,
      leader_name = case when leader_id = p_member_id then null else leader_name end,
      updated_at = now()
  where id = p_team_id;

  return true;
end;
$$;

create or replace function public.project_xp_set_compagnie_leader(
  p_team_id text,
  p_leader_id uuid,
  p_leader_name text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team public.compagnie_online_teams%rowtype;
begin
  select * into v_team
  from public.compagnie_online_teams
  where id = p_team_id
  for update;

  if not found
     or v_team.owner_id <> v_uid
     or p_leader_id is null
     or p_leader_id = v_team.owner_id
     or not (p_leader_id = any(v_team.member_ids)) then
    return false;
  end if;

  update public.compagnie_online_teams
  set leader_id = p_leader_id,
      leader_name = nullif(btrim(coalesce(p_leader_name, '')), ''),
      updated_at = now()
  where id = p_team_id;

  return true;
end;
$$;

create or replace function public.project_xp_remove_compagnie_leader(
  p_team_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  update public.compagnie_online_teams
  set leader_id = null,
      leader_name = null,
      updated_at = now()
  where id = p_team_id
    and owner_id = v_uid
    and leader_id is not null;

  return found;
end;
$$;

create or replace function public.project_xp_transfer_compagnie_ownership(
  p_team_id text,
  p_new_owner_id uuid,
  p_new_owner_name text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team public.compagnie_online_teams%rowtype;
begin
  select * into v_team
  from public.compagnie_online_teams
  where id = p_team_id
  for update;

  if not found
     or v_team.owner_id <> v_uid
     or p_new_owner_id is null
     or p_new_owner_id = v_uid
     or not (p_new_owner_id = any(v_team.member_ids)) then
    return false;
  end if;

  update public.compagnie_online_teams
  set owner_id = p_new_owner_id,
      owner_name = coalesce(nullif(btrim(p_new_owner_name), ''), 'Joueur'),
      leader_id = case when leader_id = p_new_owner_id then null else leader_id end,
      leader_name = case when leader_id = p_new_owner_id then null else leader_name end,
      updated_at = now()
  where id = p_team_id;

  return true;
end;
$$;

create or replace function public.project_xp_leave_compagnie_team(
  p_team_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team public.compagnie_online_teams%rowtype;
begin
  select * into v_team
  from public.compagnie_online_teams
  where id = p_team_id
  for update;

  if not found
     or v_team.owner_id = v_uid
     or not (v_uid = any(v_team.member_ids)) then
    return false;
  end if;

  update public.compagnie_online_teams
  set member_ids = array_remove(member_ids, v_uid),
      leader_id = case when leader_id = v_uid then null else leader_id end,
      leader_name = case when leader_id = v_uid then null else leader_name end,
      updated_at = now()
  where id = p_team_id;

  return true;
end;
$$;

create or replace function public.project_xp_delete_compagnie_team(
  p_team_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  delete from public.compagnie_online_teams
  where id = p_team_id
    and owner_id = v_uid;

  return found;
end;
$$;

create or replace function public.project_xp_update_compagnie_display_name(
  p_display_name text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := nullif(btrim(coalesce(p_display_name, '')), '');
  v_changed boolean := false;
begin
  if v_uid is null or v_name is null then
    return false;
  end if;

  update public.compagnie_online_teams
  set owner_name = v_name,
      updated_at = now()
  where owner_id = v_uid;

  v_changed := found or v_changed;

  update public.compagnie_online_teams
  set leader_name = v_name,
      updated_at = now()
  where leader_id = v_uid;

  v_changed := found or v_changed;

  return v_changed;
end;
$$;

-- ============================================================================
-- INVITATIONS : ENVOI / ACCEPTATION / REFUS / ANNULATION
-- ============================================================================

create or replace function public.project_xp_send_compagnie_invitation(
  p_team_id text,
  p_invitee_id uuid,
  p_inviter_name text,
  p_invitee_name text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team public.compagnie_online_teams%rowtype;
begin
  if v_uid is null
     or p_invitee_id is null
     or p_invitee_id = v_uid then
    return 'invalid';
  end if;

  if not exists (
    select 1
    from public.tavern_profiles
    where id::text = p_invitee_id::text
  ) then
    return 'invalid';
  end if;

  select * into v_team
  from public.compagnie_online_teams
  where id = p_team_id
  for update;

  if not found then
    return 'invalid';
  end if;

  if v_team.owner_id <> v_uid
     and v_team.leader_id is distinct from v_uid then
    return 'not_allowed';
  end if;

  if p_invitee_id = any(v_team.member_ids) then
    return 'already_member';
  end if;

  if cardinality(v_team.member_ids) >= v_team.max_members then
    return 'team_full';
  end if;

  if exists (
    select 1
    from public.compagnie_team_invitations
    where team_id = p_team_id
      and invitee_id = p_invitee_id
      and status = 'pending'
  ) then
    return 'already_pending';
  end if;

  insert into public.compagnie_team_invitations (
    team_id,
    team_name,
    inviter_id,
    inviter_name,
    invitee_id,
    invitee_name,
    status
  ) values (
    p_team_id,
    v_team.name,
    v_uid,
    coalesce(nullif(btrim(p_inviter_name), ''), 'Joueur'),
    p_invitee_id,
    coalesce(nullif(btrim(p_invitee_name), ''), 'Joueur'),
    'pending'
  );

  return 'success';
exception
  when unique_violation then
    return 'already_pending';
  when others then
    return 'invalid';
end;
$$;

create or replace function public.project_xp_accept_compagnie_invitation(
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invitation public.compagnie_team_invitations%rowtype;
  v_team public.compagnie_online_teams%rowtype;
begin
  select * into v_invitation
  from public.compagnie_team_invitations
  where id = p_invitation_id
  for update;

  if not found
     or v_invitation.status <> 'pending'
     or v_invitation.invitee_id <> v_uid then
    return false;
  end if;

  select * into v_team
  from public.compagnie_online_teams
  where id = v_invitation.team_id
  for update;

  if not found then
    return false;
  end if;

  if not (v_uid = any(v_team.member_ids)) then
    if cardinality(v_team.member_ids) >= v_team.max_members then
      return false;
    end if;

    update public.compagnie_online_teams
    set member_ids = array_append(member_ids, v_uid),
        updated_at = now()
    where id = v_team.id;
  end if;

  update public.compagnie_team_invitations
  set status = 'accepted',
      handled_by_user_id = v_uid,
      handled_at = now()
  where id = p_invitation_id;

  return true;
end;
$$;

create or replace function public.project_xp_reject_compagnie_invitation(
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  update public.compagnie_team_invitations
  set status = 'rejected',
      handled_by_user_id = v_uid,
      handled_at = now()
  where id = p_invitation_id
    and invitee_id = v_uid
    and status = 'pending';

  return found;
end;
$$;

create or replace function public.project_xp_cancel_compagnie_invitation(
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invitation public.compagnie_team_invitations%rowtype;
begin
  select * into v_invitation
  from public.compagnie_team_invitations
  where id = p_invitation_id
  for update;

  if not found or v_invitation.status <> 'pending' then
    return false;
  end if;

  if v_invitation.inviter_id <> v_uid
     and not exists (
       select 1
       from public.compagnie_online_teams t
       where t.id = v_invitation.team_id
         and (t.owner_id = v_uid or t.leader_id = v_uid)
     ) then
    return false;
  end if;

  update public.compagnie_team_invitations
  set status = 'cancelled',
      handled_by_user_id = v_uid,
      handled_at = now()
  where id = p_invitation_id;

  return true;
end;
$$;

create or replace function public.project_xp_close_compagnie_invitation_as_accepted(
  p_team_id text,
  p_invitee_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (
    select 1
    from public.compagnie_online_teams t
    where t.id = p_team_id
      and (t.owner_id = v_uid or t.leader_id = v_uid)
  ) then
    return false;
  end if;

  update public.compagnie_team_invitations
  set status = 'accepted',
      handled_by_user_id = v_uid,
      handled_at = now()
  where team_id = p_team_id
    and invitee_id = p_invitee_id
    and status = 'pending';

  return true;
end;
$$;

-- ============================================================================
-- DROITS D'EXÉCUTION
-- ============================================================================

revoke all on function public.project_xp_sync_compagnie_team(jsonb) from public;
revoke all on function public.project_xp_set_compagnie_recruitment(text, boolean) from public;
revoke all on function public.project_xp_add_compagnie_member(text, uuid) from public;
revoke all on function public.project_xp_remove_compagnie_member(text, uuid) from public;
revoke all on function public.project_xp_set_compagnie_leader(text, uuid, text) from public;
revoke all on function public.project_xp_remove_compagnie_leader(text) from public;
revoke all on function public.project_xp_transfer_compagnie_ownership(text, uuid, text) from public;
revoke all on function public.project_xp_leave_compagnie_team(text) from public;
revoke all on function public.project_xp_delete_compagnie_team(text) from public;
revoke all on function public.project_xp_update_compagnie_display_name(text) from public;
revoke all on function public.project_xp_send_compagnie_invitation(text, uuid, text, text) from public;
revoke all on function public.project_xp_accept_compagnie_invitation(uuid) from public;
revoke all on function public.project_xp_reject_compagnie_invitation(uuid) from public;
revoke all on function public.project_xp_cancel_compagnie_invitation(uuid) from public;
revoke all on function public.project_xp_close_compagnie_invitation_as_accepted(text, uuid) from public;

grant execute on function public.project_xp_sync_compagnie_team(jsonb) to authenticated;
grant execute on function public.project_xp_set_compagnie_recruitment(text, boolean) to authenticated;
grant execute on function public.project_xp_add_compagnie_member(text, uuid) to authenticated;
grant execute on function public.project_xp_remove_compagnie_member(text, uuid) to authenticated;
grant execute on function public.project_xp_set_compagnie_leader(text, uuid, text) to authenticated;
grant execute on function public.project_xp_remove_compagnie_leader(text) to authenticated;
grant execute on function public.project_xp_transfer_compagnie_ownership(text, uuid, text) to authenticated;
grant execute on function public.project_xp_leave_compagnie_team(text) to authenticated;
grant execute on function public.project_xp_delete_compagnie_team(text) to authenticated;
grant execute on function public.project_xp_update_compagnie_display_name(text) to authenticated;
grant execute on function public.project_xp_send_compagnie_invitation(text, uuid, text, text) to authenticated;
grant execute on function public.project_xp_accept_compagnie_invitation(uuid) to authenticated;
grant execute on function public.project_xp_reject_compagnie_invitation(uuid) to authenticated;
grant execute on function public.project_xp_cancel_compagnie_invitation(uuid) to authenticated;
grant execute on function public.project_xp_close_compagnie_invitation_as_accepted(text, uuid) to authenticated;

grant select on public.compagnie_online_teams to authenticated;
grant select on public.compagnie_team_invitations to authenticated;
