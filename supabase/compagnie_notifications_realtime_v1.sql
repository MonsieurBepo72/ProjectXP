-- PROJECT XP — COMPAGNIE / CENTRE DE NOTIFICATIONS — REALTIME V1
-- À exécuter UNE FOIS dans Supabase > SQL Editor après
-- compagnie_online_invitations_v1.sql.
--
-- Cette migration n'efface aucune donnée. Elle rend simplement les changements
-- d'invitations Compagnie visibles en temps réel par les clients autorisés RLS.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'compagnie_team_invitations'
  ) then
    alter publication supabase_realtime
      add table public.compagnie_team_invitations;
  end if;
end
$$;
