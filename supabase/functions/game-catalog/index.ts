import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

type JsonRecord = Record<string, unknown>

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

  const clientId =
    Deno.env.get('IGDB_CLIENT_ID')?.trim() ?? ''
  const clientSecret =
    Deno.env.get('IGDB_CLIENT_SECRET')?.trim() ?? ''

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

  try {
    const body = (await request.json()) as JsonRecord
    const action = String(body.action ?? '')

    if (action === 'search') {
      return await searchGames(
        body,
        clientId,
        clientSecret,
      )
    }

    return jsonResponse(
      { ok: false, error: 'Action catalogue inconnue.' },
      400,
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
