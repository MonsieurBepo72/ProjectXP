import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type JsonRecord = Record<string, unknown>

type RateLimitResult = {
  allowed: boolean
  remaining: number
  resetAt: string
  degraded: boolean
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

async function authenticatedUser(request: Request) {
  const authorization = request.headers.get('Authorization') ?? ''
  const token = authorization.startsWith('Bearer ')
    ? authorization.substring(7).trim()
    : ''

  if (!token) {
    return null
  }

  const client = serviceClient()
  const { data, error } = await client.auth.getUser(token)
  if (error || !data.user) {
    return null
  }

  // Les sessions anonymes Supabase restent volontairement autorisées :
  // Project XP les utilise déjà pour sa couche sociale et Steam fonctionne
  // aujourd'hui avec ce modèle. On valide l'identité sans casser ce flux.
  return data.user
}

async function consumeRateLimit(
  scope: string,
  subject: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  try {
    const client = serviceClient()
    const { data, error } = await client.rpc(
      'project_xp_consume_edge_rate_limit',
      {
        p_scope: scope,
        p_subject: subject,
        p_limit: limit,
        p_window_seconds: windowSeconds,
      },
    )

    if (error) {
      console.warn(
        'Garde-fou de quota Steam indisponible ; exécution conservée.',
      )
      return {
        allowed: true,
        remaining: limit,
        resetAt: '',
        degraded: true,
      }
    }

    const row = Array.isArray(data) ? data[0] : data
    if (!row || typeof row !== 'object') {
      return {
        allowed: true,
        remaining: limit,
        resetAt: '',
        degraded: true,
      }
    }

    const record = row as JsonRecord
    return {
      allowed: record.allowed === true,
      remaining: Number(record.remaining ?? 0),
      resetAt: String(record.reset_at ?? ''),
      degraded: false,
    }
  } catch (_) {
    console.warn(
      'Garde-fou de quota Steam indisponible ; exécution conservée.',
    )
    return {
      allowed: true,
      remaining: limit,
      resetAt: '',
      degraded: true,
    }
  }
}

function extractSteamReference(raw: string) {
  const value = raw.trim()

  if (/^\d{17}$/.test(value)) {
    return { steamId: value, vanity: null as string | null }
  }

  const profileMatch = value.match(
    /steamcommunity\.com\/profiles\/(\d{17})/i,
  )
  if (profileMatch) {
    return { steamId: profileMatch[1], vanity: null as string | null }
  }

  const vanityMatch = value.match(
    /steamcommunity\.com\/id\/([^/?#]+)/i,
  )
  if (vanityMatch) {
    return {
      steamId: null as string | null,
      vanity: decodeURIComponent(vanityMatch[1]),
    }
  }

  const clean = value
    .replace(/^https?:\/\//i, '')
    .replace(/^www\./i, '')
    .replace(/\/$/, '')

  return {
    steamId: null as string | null,
    vanity: clean,
  }
}

function sleep(milliseconds: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, milliseconds))
}

function isTransientSteamStatus(status: number) {
  return status === 429 ||
    status === 500 ||
    status === 502 ||
    status === 503 ||
    status === 504
}

function retryDelayMilliseconds(response: Response, attempt: number) {
  const rawRetryAfter = response.headers.get('Retry-After')?.trim() ?? ''
  const retryAfterSeconds = Number(rawRetryAfter)
  if (Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0) {
    return Math.min(Math.round(retryAfterSeconds * 1000), 2500)
  }

  return attempt === 0 ? 350 : 850
}

async function steamJson(url: URL) {
  const maxAttempts = 3

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    let response: Response

    try {
      response = await fetch(url, {
        headers: {
          Accept: 'application/json',
          'User-Agent': 'ProjectXP/1.0',
        },
      })
    } catch (error) {
      if (attempt + 1 < maxAttempts) {
        await sleep(attempt === 0 ? 350 : 850)
        continue
      }
      throw error
    }

    const text = await response.text()
    let data: unknown = null

    try {
      data = JSON.parse(text)
    } catch (_) {
      // Keep null so the caller gets a clean error.
    }

    if (response.ok) {
      return data
    }

    if (
      isTransientSteamStatus(response.status) &&
      attempt + 1 < maxAttempts
    ) {
      await sleep(retryDelayMilliseconds(response, attempt))
      continue
    }

    throw new Error(
      `Steam HTTP ${response.status}${
        text ? `: ${text.substring(0, 220)}` : ''
      }`,
    )
  }

  throw new Error('Steam n’a pas répondu après plusieurs tentatives.')
}

function isNoPlayerStatsError(raw: unknown) {
  const normalized = String(raw ?? '').toLowerCase()
  return normalized.includes('no stats') ||
    normalized.includes('does not have stats') ||
    normalized.includes('has no stats') ||
    normalized.includes('no achievements')
}

async function loadAchievementSchema(appId: string, apiKey: string) {
  const schemaById = new Map<string, JsonRecord>()

  try {
    const schemaUrl = new URL(
      'https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/',
    )
    schemaUrl.searchParams.set('key', apiKey)
    schemaUrl.searchParams.set('appid', appId)
    schemaUrl.searchParams.set('l', 'french')

    const schemaRaw = await steamJson(schemaUrl)
    const game =
      schemaRaw && typeof schemaRaw === 'object'
        ? (schemaRaw as JsonRecord).game
        : null
    const availableGameStats =
      game && typeof game === 'object'
        ? (game as JsonRecord).availableGameStats
        : null
    const schemaAchievements =
      availableGameStats && typeof availableGameStats === 'object'
        ? (availableGameStats as JsonRecord).achievements
        : null

    if (Array.isArray(schemaAchievements)) {
      for (const item of schemaAchievements) {
        if (!item || typeof item !== 'object') {
          continue
        }
        const row = item as JsonRecord
        const id = String(row.name ?? '').trim()
        if (id) {
          schemaById.set(id, row)
        }
      }
    }
  } catch (_) {
    // Le détail joueur reste exploitable même si le schéma Steam est indisponible.
  }

  return schemaById
}

function lockedAchievementsFromSchema(
  schemaById: Map<string, JsonRecord>,
) {
  const achievements: JsonRecord[] = []

  for (const [id, schema] of schemaById.entries()) {
    achievements.push({
      id,
      name: String(schema.displayName ?? id),
      description: String(schema.description ?? ''),
      iconUrl: String(schema.icongray ?? schema.icon ?? ''),
      hidden: Number(schema.hidden ?? 0) === 1,
      platformUnlocked: false,
      platformUnlockedAt: null,
    })
  }

  achievements.sort((a, b) =>
    String(a.name ?? '').localeCompare(
      String(b.name ?? ''),
      'fr',
      { sensitivity: 'base' },
    ),
  )

  return achievements
}

function noPlayerStatsResponse(
  steamId: string,
  appId: string,
  schemaById: Map<string, JsonRecord>,
) {
  const achievements = lockedAchievementsFromSchema(schemaById)

  return jsonResponse({
    ok: true,
    steamId,
    appId,
    gameName: '',
    unlocked: 0,
    total: achievements.length,
    achievements,
    noAchievements: achievements.length === 0,
    noPlayerStats: true,
  })
}

async function resolveSteamId(reference: string, apiKey: string) {
  const parsed = extractSteamReference(reference)
  if (parsed.steamId) {
    return parsed.steamId
  }

  if (!parsed.vanity) {
    throw new Error('Profil Steam invalide.')
  }

  const url = new URL(
    'https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/',
  )
  url.searchParams.set('key', apiKey)
  url.searchParams.set('vanityurl', parsed.vanity)

  const raw = await steamJson(url)
  const response =
    raw && typeof raw === 'object'
      ? (raw as JsonRecord).response
      : null

  if (!response || typeof response !== 'object') {
    throw new Error('Steam n’a pas reconnu ce profil.')
  }

  const result = response as JsonRecord
  const success = Number(result.success ?? 0)
  const steamId = String(result.steamid ?? '')

  if (success !== 1 || !/^\d{17}$/.test(steamId)) {
    throw new Error(
      String(result.message ?? 'Steam n’a pas reconnu ce profil.'),
    )
  }

  return steamId
}

async function syncLibrary(body: JsonRecord, apiKey: string) {
  const steamRef = String(body.steamRef ?? '').trim()
  if (!steamRef) {
    return jsonResponse(
      { ok: false, error: 'Profil Steam manquant.' },
      400,
    )
  }

  const steamId = await resolveSteamId(steamRef, apiKey)
  const url = new URL(
    'https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/',
  )
  url.searchParams.set('key', apiKey)
  url.searchParams.set('steamid', steamId)
  url.searchParams.set('include_appinfo', '1')
  url.searchParams.set('include_played_free_games', '1')
  url.searchParams.set('format', 'json')

  const raw = await steamJson(url)
  const response =
    raw && typeof raw === 'object'
      ? (raw as JsonRecord).response
      : null

  if (!response || typeof response !== 'object') {
    throw new Error('Réponse de bibliothèque Steam invalide.')
  }

  const result = response as JsonRecord
  const games = Array.isArray(result.games) ? result.games : []
  const gameCount = Number(result.game_count ?? games.length)

  if (gameCount === 0 && games.length === 0) {
    return jsonResponse({
      ok: true,
      steamId,
      gameCount: 0,
      games: [],
      warning:
        'Steam n’a renvoyé aucun jeu. Vérifie que les détails de jeux du profil sont publics.',
    })
  }

  return jsonResponse({
    ok: true,
    steamId,
    gameCount,
    games,
  })
}

async function syncAchievements(body: JsonRecord, apiKey: string) {
  const steamId = String(body.steamId ?? '').trim()
  const appId = String(body.appId ?? '').trim()

  if (!/^\d{17}$/.test(steamId) || !/^\d+$/.test(appId)) {
    return jsonResponse(
      { ok: false, error: 'SteamID ou AppID invalide.' },
      400,
    )
  }

  // Le schéma officiel est demandé en premier. Cela permet de distinguer
  // "le joueur n'a pas encore de stats" de "ce jeu n'a aucun succès".
  // Sans ce garde-fou, Steam peut répondre "no stats" pour un jeu jamais
  // lancé alors que son catalogue de succès existe bel et bien.
  const schemaById = await loadAchievementSchema(appId, apiKey)

  const playerUrl = new URL(
    'https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/',
  )
  playerUrl.searchParams.set('key', apiKey)
  playerUrl.searchParams.set('steamid', steamId)
  playerUrl.searchParams.set('appid', appId)
  playerUrl.searchParams.set('l', 'french')

  let raw: unknown

  try {
    raw = await steamJson(playerUrl)
  } catch (error) {
    const steamError =
      error instanceof Error ? error.message : String(error ?? '')

    if (isNoPlayerStatsError(steamError)) {
      return noPlayerStatsResponse(steamId, appId, schemaById)
    }

    throw error
  }

  const playerstats =
    raw && typeof raw === 'object'
      ? (raw as JsonRecord).playerstats
      : null

  if (!playerstats || typeof playerstats !== 'object') {
    throw new Error('Réponse de succès Steam invalide.')
  }

  const stats = playerstats as JsonRecord
  if (stats.success === false) {
    const steamError = String(stats.error ?? '').trim()

    if (isNoPlayerStatsError(steamError)) {
      return noPlayerStatsResponse(steamId, appId, schemaById)
    }

    return jsonResponse({
      ok: false,
      error:
        steamError ||
        'Les succès de ce jeu sont privés ou indisponibles sur Steam.',
    })
  }

  const playerAchievements = Array.isArray(stats.achievements)
    ? stats.achievements
    : []

  const achievements: JsonRecord[] = []
  let unlocked = 0

  for (const item of playerAchievements) {
    if (!item || typeof item !== 'object') {
      continue
    }

    const player = item as JsonRecord
    const id = String(player.apiname ?? '').trim()
    if (!id) {
      continue
    }

    const schema = schemaById.get(id)
    const isUnlocked = Number(player.achieved ?? 0) === 1
    const unlockTime = Number(player.unlocktime ?? 0)

    if (isUnlocked) {
      unlocked += 1
    }

    achievements.push({
      id,
      name: String(
        player.name ??
          schema?.displayName ??
          id,
      ),
      description: String(
        player.description ??
          schema?.description ??
          '',
      ),
      iconUrl: String(
        schema?.icon ??
          schema?.icongray ??
          '',
      ),
      hidden: Number(schema?.hidden ?? 0) === 1,
      platformUnlocked: isUnlocked,
      platformUnlockedAt:
        isUnlocked && unlockTime > 0
          ? new Date(unlockTime * 1000).toISOString()
          : null,
    })
  }

  for (const [id, schema] of schemaById.entries()) {
    if (achievements.some((item) => item.id === id)) {
      continue
    }

    achievements.push({
      id,
      name: String(schema.displayName ?? id),
      description: String(schema.description ?? ''),
      iconUrl: String(schema.icongray ?? schema.icon ?? ''),
      hidden: Number(schema.hidden ?? 0) === 1,
      platformUnlocked: false,
      platformUnlockedAt: null,
    })
  }

  achievements.sort((a, b) =>
    String(a.name ?? '').localeCompare(
      String(b.name ?? ''),
      'fr',
      { sensitivity: 'base' },
    ),
  )

  return jsonResponse({
    ok: true,
    steamId,
    appId,
    gameName: String(stats.gameName ?? ''),
    unlocked,
    total: achievements.length,
    achievements,
  })
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
    const user = await authenticatedUser(request)
    if (!user) {
      return jsonResponse(
        { ok: false, error: 'Session Project XP invalide.' },
        401,
      )
    }

    const body = (await request.json()) as JsonRecord
    const action = String(body.action ?? '')

    let rateLimit: RateLimitResult
    if (action === 'library') {
      rateLimit = await consumeRateLimit(
        'steam-sync.library',
        user.id,
        12,
        600,
      )
    } else if (action === 'achievements') {
      // Très volontairement large : "Synchroniser tout" peut parcourir une
      // grosse bibliothèque et ne doit pas être cassé par la sécurité.
      rateLimit = await consumeRateLimit(
        'steam-sync.achievements',
        user.id,
        600,
        600,
      )
    } else {
      return jsonResponse(
        { ok: false, error: 'Action Steam inconnue.' },
        400,
      )
    }

    if (!rateLimit.allowed) {
      return jsonResponse(
        {
          ok: false,
          error:
            'Trop de requêtes Steam. Réessaie dans quelques instants.',
          retryAfter: rateLimit.resetAt,
        },
        429,
      )
    }

    const apiKey = env('STEAM_WEB_API_KEY')
    if (!apiKey) {
      return jsonResponse(
        {
          ok: false,
          error:
            'STEAM_WEB_API_KEY n’est pas configurée dans les secrets Supabase.',
        },
        503,
      )
    }

    if (action === 'library') {
      return await syncLibrary(body, apiKey)
    }

    return await syncAchievements(body, apiKey)
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : 'Erreur Steam inconnue.'

    return jsonResponse(
      { ok: false, error: message },
      502,
    )
  }
})
