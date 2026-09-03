import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type JsonRecord = Record<string, unknown>

function jsonResponse(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  })
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

async function steamJson(url: URL) {
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'ProjectXP/1.0',
    },
  })

  const text = await response.text()
  let data: unknown = null

  try {
    data = JSON.parse(text)
  } catch (_) {
    // Une erreur lisible sera générée ci-dessous.
  }

  if (!response.ok) {
    throw new Error(
      `Steam HTTP ${response.status}${
        text ? `: ${text.substring(0, 220)}` : ''
      }`,
    )
  }

  return data
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

async function loadSchema(appId: string, apiKey: string) {
  const schemaById = new Map<string, JsonRecord>()
  let gameName = ''

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

    if (game && typeof game === 'object') {
      const gameRecord = game as JsonRecord
      gameName = String(gameRecord.gameName ?? '').trim()

      const availableGameStats = gameRecord.availableGameStats
      const schemaAchievements =
        availableGameStats &&
        typeof availableGameStats === 'object'
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
    }
  } catch (_) {
    // Le schéma est un enrichissement. L'état joueur peut rester exploitable.
  }

  return { schemaById, gameName }
}

type PlayerAchievementLoad = {
  rows: JsonRecord[] | null
  gameName: string
  source: string
  error: string
}

async function loadPlayerAchievements(
  steamId: string,
  appId: string,
  apiKey: string,
): Promise<PlayerAchievementLoad> {
  const errors: string[] = []

  // Source principale : endpoint dédié aux succès.
  try {
    const playerUrl = new URL(
      'https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/',
    )
    playerUrl.searchParams.set('key', apiKey)
    playerUrl.searchParams.set('steamid', steamId)
    playerUrl.searchParams.set('appid', appId)
    playerUrl.searchParams.set('l', 'french')

    const raw = await steamJson(playerUrl)
    const playerstats =
      raw && typeof raw === 'object'
        ? (raw as JsonRecord).playerstats
        : null

    if (playerstats && typeof playerstats === 'object') {
      const stats = playerstats as JsonRecord

      if (stats.success !== false) {
        return {
          rows: Array.isArray(stats.achievements)
            ? stats.achievements
                .filter(
                  (item) =>
                    item != null &&
                    typeof item === 'object',
                )
                .map((item) => item as JsonRecord)
            : [],
          gameName: String(stats.gameName ?? '').trim(),
          source: 'GetPlayerAchievements',
          error: '',
        }
      }

      const message = String(stats.error ?? '').trim()
      if (message) {
        errors.push(message)
      }
    } else {
      errors.push('Réponse GetPlayerAchievements invalide')
    }
  } catch (error) {
    errors.push(
      error instanceof Error ? error.message : String(error),
    )
  }

  // Fallback V1.10.3a : certains jeux répondent mal au premier endpoint alors
  // que GetUserStatsForGame expose bien les accomplissements du joueur.
  try {
    const statsUrl = new URL(
      'https://api.steampowered.com/ISteamUserStats/GetUserStatsForGame/v2/',
    )
    statsUrl.searchParams.set('key', apiKey)
    statsUrl.searchParams.set('steamid', steamId)
    statsUrl.searchParams.set('appid', appId)

    const raw = await steamJson(statsUrl)
    const playerstats =
      raw && typeof raw === 'object'
        ? (raw as JsonRecord).playerstats
        : null

    if (playerstats && typeof playerstats === 'object') {
      const stats = playerstats as JsonRecord
      const sourceRows = Array.isArray(stats.achievements)
        ? stats.achievements
        : []

      if (sourceRows.length > 0) {
        const rows: JsonRecord[] = []

        for (const item of sourceRows) {
          if (!item || typeof item !== 'object') {
            continue
          }

          const row = item as JsonRecord
          const id = String(
            row.name ?? row.apiname ?? '',
          ).trim()

          if (!id) {
            continue
          }

          rows.push({
            apiname: id,
            achieved:
              Number(row.achieved ?? row.achieved_at ?? 0) > 0
                ? 1
                : 0,
            unlocktime: Number(row.unlocktime ?? 0),
          })
        }

        return {
          rows,
          gameName: String(stats.gameName ?? '').trim(),
          source: 'GetUserStatsForGame',
          error: '',
        }
      }

      errors.push('GetUserStatsForGame sans accomplissement')
    }
  } catch (error) {
    errors.push(
      error instanceof Error ? error.message : String(error),
    )
  }

  return {
    rows: null,
    gameName: '',
    source: '',
    error: errors
      .filter((value) => value.trim().length > 0)
      .join(' / '),
  }
}

function looksLikeNoStats(raw: string) {
  const value = raw.toLowerCase()

  return value.includes('no stats') ||
    value.includes('does not have stats') ||
    value.includes('no achievements') ||
    value.includes('requested app has no stats')
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

  const schema = await loadSchema(appId, apiKey)

  const player = await loadPlayerAchievements(
    steamId,
    appId,
    apiKey,
  )

  if (player.rows == null) {
    if (schema.schemaById.size === 0 &&
        looksLikeNoStats(player.error)) {
      return jsonResponse({
        ok: true,
        steamId,
        appId,
        gameName: schema.gameName,
        unlocked: 0,
        total: 0,
        achievements: [],
        noAchievements: true,
        playerProgressAvailable: true,
      })
    }

    if (schema.schemaById.size > 0) {
      return jsonResponse({
        ok: false,
        code: 'player_progress_unavailable',
        achievementCount: schema.schemaById.size,
        error:
          `Steam expose ${schema.schemaById.size} succès pour ce jeu, ` +
          `mais la progression du joueur est temporairement indisponible.` +
          (player.error ? ` ${player.error}` : ''),
      })
    }

    return jsonResponse({
      ok: false,
      code: 'steam_achievements_unavailable',
      error:
        player.error ||
        'Les succès de ce jeu sont privés ou indisponibles sur Steam.',
    })
  }

  const achievements: JsonRecord[] = []
  let unlocked = 0

  for (const playerRow of player.rows) {
    const id = String(
      playerRow.apiname ??
      playerRow.name ??
      '',
    ).trim()

    if (!id) {
      continue
    }

    const schemaRow = schema.schemaById.get(id)
    const isUnlocked =
      Number(playerRow.achieved ?? 0) === 1
    const unlockTime =
      Number(playerRow.unlocktime ?? 0)

    if (isUnlocked) {
      unlocked += 1
    }

    achievements.push({
      id,
      name: String(
        playerRow.name ??
          schemaRow?.displayName ??
          id,
      ),
      description: String(
        playerRow.description ??
          schemaRow?.description ??
          '',
      ),
      iconUrl: String(
        schemaRow?.icon ??
          schemaRow?.icongray ??
          '',
      ),
      hidden:
        Number(schemaRow?.hidden ?? 0) === 1,
      platformUnlocked: isUnlocked,
      platformUnlockedAt:
        isUnlocked && unlockTime > 0
          ? new Date(unlockTime * 1000).toISOString()
          : null,
    })
  }

  // Complète avec le schéma quand Steam renvoie une liste joueur partielle.
  for (const [id, schemaRow] of schema.schemaById.entries()) {
    if (achievements.some((item) => item.id === id)) {
      continue
    }

    achievements.push({
      id,
      name: String(schemaRow.displayName ?? id),
      description: String(schemaRow.description ?? ''),
      iconUrl: String(
        schemaRow.icongray ??
          schemaRow.icon ??
          '',
      ),
      hidden:
        Number(schemaRow.hidden ?? 0) === 1,
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
    gameName:
      player.gameName ||
      schema.gameName,
    unlocked,
    total: achievements.length,
    achievements,
    playerProgressAvailable: true,
    source: player.source,
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

  const apiKey =
    Deno.env.get('STEAM_WEB_API_KEY')?.trim() ?? ''

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

  try {
    const body = (await request.json()) as JsonRecord
    const action = String(body.action ?? '')

    if (action === 'library') {
      return await syncLibrary(body, apiKey)
    }

    if (action === 'achievements') {
      return await syncAchievements(body, apiKey)
    }

    return jsonResponse(
      { ok: false, error: 'Action Steam inconnue.' },
      400,
    )
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
