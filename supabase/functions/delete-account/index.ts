import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const DELETE_CONFIRMATION = 'DELETE_PROJECT_XP_ACCOUNT_PERMANENTLY'
const PRIVATE_AVATAR_BUCKET = 'project-xp-private-avatars'

type JsonRecord = Record<string, unknown>

type CleanupIssue = {
  area: string
  message: string
}

function jsonResponse(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  })
}

function env(name: string) {
  return Deno.env.get(name)?.trim() ?? ''
}

function getSupabaseAdminKey() {
  const legacyKey = env('SUPABASE_SERVICE_ROLE_KEY')
  if (legacyKey) {
    return legacyKey
  }

  const rawSecretKeys = env('SUPABASE_SECRET_KEYS')
  if (!rawSecretKeys) {
    throw new Error('Clé serveur Supabase introuvable.')
  }

  const parsed = JSON.parse(rawSecretKeys) as Record<string, string>
  const preferred = String(parsed.default ?? '').trim()
  if (preferred) {
    return preferred
  }

  const fallback = Object.values(parsed)
    .map((value) => String(value ?? '').trim())
    .find((value) => value.length > 0)

  if (!fallback) {
    throw new Error('Aucune clé serveur Supabase utilisable.')
  }

  return fallback
}

function serviceClient() {
  const url = env('SUPABASE_URL')
  if (!url) {
    throw new Error('SUPABASE_URL introuvable.')
  }

  return createClient(url, getSupabaseAdminKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })
}

function missingRelation(error: unknown) {
  if (!error || typeof error !== 'object') {
    return false
  }

  const row = error as JsonRecord
  const code = String(row.code ?? '').trim()
  const message = String(row.message ?? '').toLowerCase()

  return code === '42P01' ||
    code === 'PGRST205' ||
    message.includes('does not exist') ||
    message.includes('schema cache')
}

function recordCleanupError(
  issues: CleanupIssue[],
  area: string,
  error: unknown,
  optional = false,
) {
  if (optional && missingRelation(error)) {
    console.warn(`Suppression compte : ${area} absent, ignoré.`)
    return
  }

  const message = error && typeof error === 'object'
    ? String((error as JsonRecord).message ?? error)
    : String(error ?? 'Erreur inconnue')

  issues.push({ area, message })
  console.error(`Suppression compte : ${area} : ${message}`)
}

async function deleteEq(
  client: ReturnType<typeof createClient>,
  table: string,
  column: string,
  value: string,
  issues: CleanupIssue[],
  optional = false,
) {
  const { error } = await client
    .from(table)
    .delete()
    .eq(column, value)

  if (error) {
    recordCleanupError(issues, table, error, optional)
  }
}

async function deleteOr(
  client: ReturnType<typeof createClient>,
  table: string,
  filter: string,
  issues: CleanupIssue[],
  optional = false,
) {
  const { error } = await client
    .from(table)
    .delete()
    .or(filter)

  if (error) {
    recordCleanupError(issues, table, error, optional)
  }
}

function chunks<T>(values: T[], size = 100) {
  const result: T[][] = []
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size))
  }
  return result
}

async function deleteIn(
  client: ReturnType<typeof createClient>,
  table: string,
  column: string,
  values: string[],
  issues: CleanupIssue[],
  optional = false,
) {
  if (values.length === 0) {
    return
  }

  for (const batch of chunks(values)) {
    const { error } = await client
      .from(table)
      .delete()
      .in(column, batch)

    if (error) {
      recordCleanupError(issues, table, error, optional)
      return
    }
  }
}

async function selectIdsOr(
  client: ReturnType<typeof createClient>,
  table: string,
  filter: string,
  issues: CleanupIssue[],
  optional = false,
) {
  const { data, error } = await client
    .from(table)
    .select('id')
    .or(filter)

  if (error) {
    recordCleanupError(issues, table, error, optional)
    return <string>[]
  }

  return (Array.isArray(data) ? data : [])
    .map((row) => String((row as JsonRecord).id ?? '').trim())
    .filter((value) => value.length > 0)
}

async function selectMessageIdsForConversations(
  client: ReturnType<typeof createClient>,
  conversationIds: string[],
  userId: string,
  issues: CleanupIssue[],
) {
  const ids = new Set<string>()

  for (const batch of chunks(conversationIds)) {
    const { data, error } = await client
      .from('private_messages')
      .select('id')
      .in('conversation_id', batch)

    if (error) {
      recordCleanupError(
        issues,
        'private_messages (lecture conversations)',
        error,
        true,
      )
      break
    }

    for (const row of Array.isArray(data) ? data : []) {
      const id = String((row as JsonRecord).id ?? '').trim()
      if (id) ids.add(id)
    }
  }

  const { data: sent, error: sentError } = await client
    .from('private_messages')
    .select('id')
    .eq('sender_id', userId)

  if (sentError) {
    recordCleanupError(
      issues,
      'private_messages (lecture auteur)',
      sentError,
      true,
    )
  } else {
    for (const row of Array.isArray(sent) ? sent : []) {
      const id = String((row as JsonRecord).id ?? '').trim()
      if (id) ids.add(id)
    }
  }

  return [...ids]
}

async function removePrivateMessaging(
  client: ReturnType<typeof createClient>,
  userId: string,
  issues: CleanupIssue[],
) {
  const conversationIds = await selectIdsOr(
    client,
    'private_conversations',
    `user_a.eq.${userId},user_b.eq.${userId}`,
    issues,
    true,
  )

  const messageIds = await selectMessageIdsForConversations(
    client,
    conversationIds,
    userId,
    issues,
  )

  // La table technique d'idempotence n'a pas de FK vers private_messages.
  // On retire donc ses traces avant de supprimer les messages.
  await deleteIn(
    client,
    'project_xp_private_message_notification_deliveries',
    'message_id',
    messageIds,
    issues,
    true,
  )

  await deleteIn(
    client,
    'private_messages',
    'conversation_id',
    conversationIds,
    issues,
    true,
  )

  await deleteEq(
    client,
    'private_messages',
    'sender_id',
    userId,
    issues,
    true,
  )

  await deleteIn(
    client,
    'private_conversations',
    'id',
    conversationIds,
    issues,
    true,
  )
}

async function removeCompagnieMemberships(
  client: ReturnType<typeof createClient>,
  userId: string,
  issues: CleanupIssue[],
) {
  // Les équipes dont le compte supprimé est propriétaire disparaissent :
  // il n'est pas acceptable de transférer une propriété sans consentement.
  const { error: ownedDeleteError } = await client
    .from('compagnie_online_teams')
    .delete()
    .eq('owner_id', userId)

  if (ownedDeleteError) {
    recordCleanupError(
      issues,
      'compagnie_online_teams (propriétaire)',
      ownedDeleteError,
      true,
    )
  }

  const rowsById = new Map<string, JsonRecord>()

  const { data: memberRows, error: memberError } = await client
    .from('compagnie_online_teams')
    .select('id, owner_id, leader_id, leader_name, member_ids')
    .contains('member_ids', [userId])

  if (memberError) {
    recordCleanupError(
      issues,
      'compagnie_online_teams (membre)',
      memberError,
      true,
    )
  } else {
    for (const row of Array.isArray(memberRows) ? memberRows : []) {
      const record = row as JsonRecord
      const id = String(record.id ?? '').trim()
      if (id) rowsById.set(id, record)
    }
  }

  const { data: leaderRows, error: leaderError } = await client
    .from('compagnie_online_teams')
    .select('id, owner_id, leader_id, leader_name, member_ids')
    .eq('leader_id', userId)

  if (leaderError) {
    recordCleanupError(
      issues,
      'compagnie_online_teams (admin)',
      leaderError,
      true,
    )
  } else {
    for (const row of Array.isArray(leaderRows) ? leaderRows : []) {
      const record = row as JsonRecord
      const id = String(record.id ?? '').trim()
      if (id) rowsById.set(id, record)
    }
  }

  for (const [teamId, row] of rowsById.entries()) {
    if (String(row.owner_id ?? '').trim() === userId) {
      continue
    }

    const rawMembers = Array.isArray(row.member_ids)
      ? row.member_ids
      : []
    const memberIds = rawMembers
      .map((value) => String(value ?? '').trim())
      .filter((value) => value.length > 0 && value !== userId)

    const wasLeader = String(row.leader_id ?? '').trim() === userId

    const { error } = await client
      .from('compagnie_online_teams')
      .update({
        member_ids: memberIds,
        ...(wasLeader
          ? { leader_id: null, leader_name: null }
          : {}),
        updated_at: new Date().toISOString(),
      })
      .eq('id', teamId)

    if (error) {
      recordCleanupError(
        issues,
        `compagnie_online_teams (${teamId})`,
        error,
        true,
      )
    }
  }
}

async function listStorageFilesRecursively(
  client: ReturnType<typeof createClient>,
  prefix: string,
  issues: CleanupIssue[],
): Promise<string[]> {
  const result: string[] = []
  let offset = 0

  while (true) {
    const { data, error } = await client.storage
      .from(PRIVATE_AVATAR_BUCKET)
      .list(prefix, {
        limit: 100,
        offset,
        sortBy: { column: 'name', order: 'asc' },
      })

    if (error) {
      const message = error.message?.toLowerCase() ?? ''
      if (
        message.includes('bucket not found') ||
        message.includes('not found')
      ) {
        return result
      }

      recordCleanupError(
        issues,
        'stockage avatar privé',
        error,
        false,
      )
      return result
    }

    const rows = Array.isArray(data) ? data : []
    if (rows.length === 0) {
      break
    }

    for (const item of rows) {
      const name = String(item.name ?? '').trim()
      if (!name) continue

      const path = prefix ? `${prefix}/${name}` : name

      // Supabase renvoie les dossiers avec id = null.
      if (item.id == null) {
        result.push(
          ...(await listStorageFilesRecursively(client, path, issues)),
        )
      } else {
        result.push(path)
      }
    }

    if (rows.length < 100) {
      break
    }
    offset += rows.length
  }

  return result
}

async function removePrivateAvatarStorage(
  client: ReturnType<typeof createClient>,
  userId: string,
  issues: CleanupIssue[],
) {
  const paths = await listStorageFilesRecursively(
    client,
    userId,
    issues,
  )

  for (const batch of chunks(paths)) {
    const { error } = await client.storage
      .from(PRIVATE_AVATAR_BUCKET)
      .remove(batch)

    if (error) {
      recordCleanupError(
        issues,
        'stockage avatar privé',
        error,
        false,
      )
      return
    }
  }
}

async function validateProjectXpMapping(
  client: ReturnType<typeof createClient>,
  user: { id: string; is_anonymous?: boolean; email?: string | null },
  requestedProjectXpUserId: string,
) {
  if (user.is_anonymous === true) {
    return { ok: true, error: '' }
  }

  const { data, error } = await client
    .from('project_xp_cloud_accounts')
    .select('project_xp_user_id')
    .eq('auth_user_id', user.id)
    .maybeSingle()

  if (error) {
    return {
      ok: false,
      error: 'Impossible de vérifier le lien Cloud du compte.',
    }
  }

  if (!data || typeof data !== 'object') {
    return {
      ok: false,
      error:
        'Le lien Cloud Project XP est incomplet. La suppression a été bloquée par sécurité.',
    }
  }

  const mapped = String((data as JsonRecord).project_xp_user_id ?? '').trim()
  if (!mapped || mapped !== requestedProjectXpUserId) {
    return {
      ok: false,
      error:
        'Sécurité : le compte Cloud ne correspond pas au compte Project XP demandé.',
    }
  }

  return { ok: true, error: '' }
}

serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (request.method !== 'POST') {
    return jsonResponse(
      { ok: false, error: 'Méthode non autorisée.' },
      405,
    )
  }

  try {
    const authorization = request.headers.get('Authorization') ?? ''
    const token = authorization.startsWith('Bearer ')
      ? authorization.substring(7).trim()
      : ''

    if (!token) {
      return jsonResponse(
        { ok: false, error: 'Session Project XP invalide.' },
        401,
      )
    }

    const client = serviceClient()
    const { data: userData, error: userError } =
      await client.auth.getUser(token)
    const user = userData.user

    if (userError || !user) {
      return jsonResponse(
        { ok: false, error: 'Session Project XP invalide.' },
        401,
      )
    }

    let body: JsonRecord
    try {
      body = (await request.json()) as JsonRecord
    } catch (_) {
      return jsonResponse(
        { ok: false, error: 'Confirmation de suppression invalide.' },
        400,
      )
    }

    const confirmation = String(body.confirmation ?? '').trim()
    const requestedProjectXpUserId =
      String(body.projectXpUserId ?? '').trim()

    if (
      confirmation !== DELETE_CONFIRMATION ||
      requestedProjectXpUserId.length === 0 ||
      requestedProjectXpUserId.length > 160
    ) {
      return jsonResponse(
        { ok: false, error: 'Confirmation de suppression invalide.' },
        400,
      )
    }

    const mapping = await validateProjectXpMapping(
      client,
      user,
      requestedProjectXpUserId,
    )

    if (!mapping.ok) {
      return jsonResponse(
        { ok: false, error: mapping.error },
        409,
      )
    }

    const userId = user.id
    const issues: CleanupIssue[] = []

    // Fichiers privés d'abord : supprimer auth.users ne supprime pas les objets
    // Storage automatiquement.
    await removePrivateAvatarStorage(client, userId, issues)

    // Conversations et traces de notification associées.
    await removePrivateMessaging(client, userId, issues)

    // Messages publics et journal de modération : moderation_events utilise
    // ON DELETE SET NULL, donc une suppression explicite est nécessaire pour
    // respecter une demande de suppression complète.
    await deleteEq(
      client,
      'tavern_messages',
      'author_id',
      userId,
      issues,
      true,
    )
    await deleteEq(
      client,
      'moderation_events',
      'user_id',
      userId,
      issues,
      true,
    )

    // Relations sociales.
    await deleteOr(
      client,
      'friend_aliases',
      `owner_id.eq.${userId},friend_id.eq.${userId}`,
      issues,
      true,
    )
    await deleteOr(
      client,
      'friend_requests',
      `sender_id.eq.${userId},receiver_id.eq.${userId}`,
      issues,
      true,
    )
    await deleteOr(
      client,
      'friendships',
      `user_a.eq.${userId},user_b.eq.${userId}`,
      issues,
      true,
    )

    // Compagnie : efface les équipes possédées par l'utilisateur, et le retire
    // des équipes des autres sans transférer implicitement de propriété.
    await deleteOr(
      client,
      'compagnie_team_invitations',
      `inviter_id.eq.${userId},invitee_id.eq.${userId},handled_by_user_id.eq.${userId}`,
      issues,
      true,
    )
    await removeCompagnieMemberships(client, userId, issues)

    // Notifications et limites techniques.
    await deleteEq(
      client,
      'push_device_tokens',
      'user_id',
      userId,
      issues,
      true,
    )
    await deleteEq(
      client,
      'project_xp_edge_rate_limits',
      'subject',
      userId,
      issues,
      true,
    )

    // Les jetons de plateforme, notamment le refresh token PlayStation chiffré,
    // sont explicitement supprimés avant le compte Auth. Les FK en cascade
    // restent une défense supplémentaire.
    await deleteEq(
      client,
      'project_xp_platform_credentials',
      'auth_user_id',
      userId,
      issues,
      true,
    )
    await deleteEq(
      client,
      'project_xp_platform_auth_flows',
      'auth_user_id',
      userId,
      issues,
      true,
    )
    await deleteEq(
      client,
      'project_xp_platform_accounts',
      'auth_user_id',
      userId,
      issues,
      true,
    )

    // Le profil Taverne est supprimé après les messages/relations qui peuvent
    // encore s'appuyer sur son UUID.
    await deleteEq(
      client,
      'tavern_profiles',
      'id',
      userId,
      issues,
      true,
    )

    if (issues.length > 0) {
      return jsonResponse(
        {
          ok: false,
          error:
            'Certaines données Project XP n’ont pas pu être supprimées. ' +
            'Le compte a été conservé pour permettre de réessayer sans perdre le contrôle de tes données.',
          cleanupIssues: issues.map((issue) => issue.area),
        },
        500,
      )
    }

    // DERNIÈRE opération : les tables Cloud principales liées à auth.users
    // utilisent ON DELETE CASCADE. Une fois ce point franchi, l'identité de
    // connexion n'existe plus et l'e-mail peut être réutilisé pour un nouveau
    // compte selon la configuration Auth du projet.
    const { error: deleteUserError } =
      await client.auth.admin.deleteUser(userId)

    if (deleteUserError) {
      console.error(
        'Suppression auth.users impossible :',
        deleteUserError.message,
      )
      return jsonResponse(
        {
          ok: false,
          error:
            'Les données liées ont été nettoyées, mais l’identité de connexion n’a pas pu être supprimée. Réessaie dans un instant.',
        },
        500,
      )
    }

    return jsonResponse({ ok: true })
  } catch (error) {
    console.error('Suppression compte Project XP impossible :', error)
    return jsonResponse(
      {
        ok: false,
        error:
          'La suppression du compte Project XP est temporairement indisponible.',
      },
      500,
    )
  }
})
