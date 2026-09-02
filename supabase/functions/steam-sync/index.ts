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
    // Keep null so the caller gets a clean error.
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

async function syncAchievements(body: JsonRecord, apiKey: string) {
  const steamId = String(body.steamId ?? '').trim()
  const appId = String(body.appId ?? '').trim()

  if (!/^\d{17}$/.test(steamId) || !/^\d+$/.test(appId)) {
    return jsonResponse(
      { ok: false, error: 'SteamID ou AppID invalide.' },
      400,
    )
  }

  const url = new URL(
    'https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/',
  )
  url.searchParams.set('key', apiKey)
  url.searchParams.set('steamid', steamId)
  url.searchParams.set('appid', appId)
  url.searchParams.set('l', 'french')

  const raw = await steamJson(url)
  const playerstats =
    raw && typeof raw === 'object'
      ? (raw as JsonRecord).playerstats
      : null

  if (!playerstats || typeof playerstats !== 'object') {
    throw new Error('Réponse de succès Steam invalide.')
  }

  const stats = playerstats as JsonRecord
  if (stats.success === false) {
    return jsonResponse({
      ok: false,
      error: String(
        stats.error ??
          'Les succès de ce jeu sont privés ou ce jeu n’utilise pas les succès Steam.',
      ),
    })
  }

  const achievements = Array.isArray(stats.achievements)
    ? stats.achievements
    : []

  let unlocked = 0
  for (const item of achievements) {
    if (
      item &&
      typeof item === 'object' &&
      Number((item as JsonRecord).achieved ?? 0) === 1
    ) {
      unlocked += 1
    }
  }

  return jsonResponse({
    ok: true,
    steamId,
    appId,
    gameName: String(stats.gameName ?? ''),
    unlocked,
    total: achievements.length,
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

  const apiKey = Deno.env.get('STEAM_WEB_API_KEY')?.trim() ?? ''
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
