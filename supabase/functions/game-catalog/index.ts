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
  resetAt: string
}

let cachedToken = ''
let cachedTokenExpiresAt = 0

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

  // Les sessions anonymes sont compatibles avec l'architecture actuelle.
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
        'Garde-fou de quota catalogue indisponible ; exécution conservée.',
      )
      return { allowed: true, resetAt: '' }
    }

    const row = Array.isArray(data) ? data[0] : data
    if (!row || typeof row !== 'object') {
      return { allowed: true, resetAt: '' }
    }

    const record = row as JsonRecord
    return {
      allowed: record.allowed === true,
      resetAt: String(record.reset_at ?? ''),
    }
  } catch (_) {
    console.warn(
      'Garde-fou de quota catalogue indisponible ; exécution conservée.',
    )
    return { allowed: true, resetAt: '' }
  }
}

function asRecord(value: unknown): JsonRecord | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null
  }
  return value as JsonRecord
}

function escapeSearch(value: string) {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
}

async function getAccessToken(
  clientId: string,
  clientSecret: string,
) {
  const now = Date.now()
  if (cachedToken && now < cachedTokenExpiresAt - 60_000) {
    return cachedToken
  }

  const url = new URL('https://id.twitch.tv/oauth2/token')
  url.searchParams.set('client_id', clientId)
  url.searchParams.set('client_secret', clientSecret)
  url.searchParams.set('grant_type', 'client_credentials')

  const response = await fetch(url, {
    method: 'POST',
    headers: { Accept: 'application/json' },
  })

  const text = await response.text()
  let raw: unknown = null

  try {
    raw = JSON.parse(text)
  } catch (_) {
    // Une erreur propre sera renvoyée juste après.
  }

  if (!response.ok) {
    throw new Error(
      `Twitch OAuth ${response.status}${
        text ? `: ${text.substring(0, 220)}` : ''
      }`,
    )
  }

  const data = asRecord(raw)
  const token = String(data?.access_token ?? '')
  const expiresIn = Number(data?.expires_in ?? 0)

  if (!token) {
    throw new Error('Twitch n’a pas renvoyé de jeton IGDB valide.')
  }

  cachedToken = token
  cachedTokenExpiresAt =
    Date.now() + Math.max(60, expiresIn) * 1000

  return cachedToken
}

async function igdbRequest(
  endpoint: string,
  body: string,
  clientId: string,
  clientSecret: string,
) {
  const token = await getAccessToken(clientId, clientSecret)

  const response = await fetch(
    `https://api.igdb.com/v4/${endpoint}`,
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'text/plain',
        'Client-ID': clientId,
        Authorization: `Bearer ${token}`,
        'User-Agent': 'ProjectXP/1.0',
      },
      body,
    },
  )

  const text = await response.text()
  let raw: unknown = null

  try {
    raw = JSON.parse(text)
  } catch (_) {
    // Une erreur propre sera renvoyée plus bas.
  }

  if (!response.ok) {
    throw new Error(
      `IGDB HTTP ${response.status}${
        text ? `: ${text.substring(0, 240)}` : ''
      }`,
    )
  }

  if (!Array.isArray(raw)) {
    throw new Error('IGDB a renvoyé une réponse invalide.')
  }

  return raw
}

function readNames(value: unknown) {
  if (!Array.isArray(value)) {
    return [] as string[]
  }

  const names: string[] = []
  for (const item of value) {
    const record = asRecord(item)
    const name = String(record?.name ?? '').trim()
    if (name && !names.includes(name)) {
      names.push(name)
    }
  }
  return names
}

function mapGame(value: unknown) {
  const game = asRecord(value)
  if (!game) {
    return null
  }

  const id = String(game.id ?? '')
  const title = String(game.name ?? '').trim()
  if (!id || !title) {
    return null
  }

  const cover = asRecord(game.cover)
  const imageId = String(cover?.image_id ?? '').trim()
  const coverUrl = imageId
    ? `https://images.igdb.com/igdb/image/upload/t_cover_big_2x/${imageId}.jpg`
    : null

  const releaseTimestamp = Number(game.first_release_date ?? 0)
  const releaseYear = releaseTimestamp > 0
    ? new Date(releaseTimestamp * 1000).getUTCFullYear()
    : null

  const summary = String(game.summary ?? '').trim()

  return {
    id,
    title,
    coverUrl,
    summary: summary || null,
    releaseYear,
    genres: readNames(game.genres),
    platforms: readNames(game.platforms),
  }
}

async function searchGames(
  body: JsonRecord,
  clientId: string,
  clientSecret: string,
) {
  const query = String(body.query ?? '').trim()
  if (query.length < 2) {
    return jsonResponse(
      {
        ok: false,
        error: 'Entre au moins 2 caractères pour rechercher un jeu.',
      },
      400,
    )
  }

  const safe = escapeSearch(query.substring(0, 100))
  const requestBody = [
    'fields id,name,summary,first_release_date,',
    'cover.image_id,genres.name,platforms.name;',
    `search "${safe}";`,
    'where version_parent = null;',
    'limit 15;',
  ].join(' ')

  const raw = await igdbRequest(
    'games',
    requestBody,
    clientId,
    clientSecret,
  )

  const results = raw
    .map(mapGame)
    .filter((item) => item !== null)

  return jsonResponse({
    ok: true,
    provider: 'IGDB',
    results,
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

    if (action !== 'search') {
      return jsonResponse(
        { ok: false, error: 'Action catalogue inconnue.' },
        400,
      )
    }

    const userRateLimit = await consumeRateLimit(
      'game-catalog.search.user',
      user.id,
      30,
      60,
    )
    if (!userRateLimit.allowed) {
      return jsonResponse(
        {
          ok: false,
          error:
            'Trop de recherches de jeux. Réessaie dans quelques instants.',
          retryAfter: userRateLimit.resetAt,
        },
        429,
      )
    }

    // IGDB applique son propre quota au niveau de l'application. Ce second
    // compteur protège donc la clé Project XP, pas seulement un utilisateur.
    const providerRateLimit = await consumeRateLimit(
      'game-catalog.search.provider',
      'igdb',
      8,
      2,
    )
    if (!providerRateLimit.allowed) {
      return jsonResponse(
        {
          ok: false,
          error:
            'Le catalogue est très sollicité. Réessaie dans un instant.',
          retryAfter: providerRateLimit.resetAt,
        },
        429,
      )
    }

    const clientId = env('IGDB_CLIENT_ID')
    const clientSecret = env('IGDB_CLIENT_SECRET')

    if (!clientId || !clientSecret) {
      return jsonResponse(
        {
          ok: false,
          error:
            'IGDB_CLIENT_ID / IGDB_CLIENT_SECRET ne sont pas configurés dans Supabase.',
        },
        503,
      )
    }

    return await searchGames(
      body,
      clientId,
      clientSecret,
    )
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : 'Erreur catalogue inconnue.'

    return jsonResponse(
      { ok: false, error: message },
      502,
    )
  }
})
