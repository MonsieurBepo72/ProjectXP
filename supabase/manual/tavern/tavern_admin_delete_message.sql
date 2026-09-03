-- ============================================================================
-- PROJECT XP - ADMIN TAVERNE - SUPPRESSION D'UN MESSAGE
--
-- À exécuter une fois dans l'éditeur SQL Supabase après tavern_admin_reset.sql.
--
-- Sécurité :
-- - nécessite une session Supabase authentifiée ;
-- - vérifie project_admins côté PostgreSQL ;
-- - aucun DELETE direct n'est accordé au client ;
-- - retourne true uniquement si une ligne a réellement été supprimée.
-- ============================================================================

create or replace function public.project_xp_admin_delete_tavern_message(
  p_message_id uuid
)
returns boolean

language plpgsql

security definer

set search_path =
  public

as $$

declare

  v_deleted integer := 0;

begin

  if auth.uid() is null then

    raise exception
      'PROJECT_XP_AUTH_REQUIRED'

      using errcode = 'P0001';

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

      using errcode = 'P0001';

  end if;


  if p_message_id is null then

    return false;

  end if;


  delete from
    public.tavern_messages

  where
    id = p_message_id;


  get diagnostics
    v_deleted = row_count;


  return
    v_deleted = 1;

end;

$$;


revoke all
on function public.project_xp_admin_delete_tavern_message(uuid)
from public;


grant execute
on function public.project_xp_admin_delete_tavern_message(uuid)
to authenticated;


-- ============================================================================
-- FIN
-- ============================================================================
