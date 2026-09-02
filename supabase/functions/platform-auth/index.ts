import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4'

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

function appRedirect(params: Record<string, string>) {
  const url = new URL('projectxp://platform-auth')
  for (const [key, value] of Object.entries(params)) {
    if (value) {
      url.searchParams.set(key, value)
    }
  }
  return Response.redirect(url.toString(), 302)
}

function env(name: string) {
  return Deno.env.get(name)?.trim() ?? ''
}

function serviceClient() {
  const url = env('SUPABASE_URL')
  const serviceRole = env('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !serviceRole) {
    throw new Error('Configuration Supabase serveur incomplète.')
  }
  return createClient(url, serviceRole, {
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
  if (error || !data.user || data.user.is_anonymous) {
    return null
  }
  return data.user
}

async function startSteam(request: Request) {
  const user = await authenticatedUser(request)
  if (!user) {
    return jsonResponse(
      {
        ok: false,
        error:
          'Un compte Cloud Project XP actif est nécessaire pour lier Steam.',
      },
      401,
    )
  }

  const client = serviceClient()
  const { data: mapping, error: mappingError } = await client
    .from('project_xp_cloud_accounts')
    .select('project_xp_user_id')
    .eq('auth_user_id', user.id)
    .maybeSingle()

  const projectXpUserId =
    String(mapping?.project_xp_user_id ?? '').trim()

  if (mappingError || !projectXpUserId) {
    return jsonResponse(
      {
        ok: false,
        error:
          'Le compte Cloud Project XP doit être finalisé avant de lier Steam.',
      },
      409,
    )
  }

  const flowId = crypto.randomUUID()
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString()

  const { error: insertError } = await client
    .from('project_xp_platform_auth_flows')
    .insert({
      id: flowId,
      auth_user_id: user.id,
      project_xp_user_id: projectXpUserId,
      provider: 'steam',
      expires_at: expiresAt,
    })

  if (insertError) {
    throw new Error(`Flux Steam impossible : ${insertError.message}`)
  }

  const supabaseUrl = env('SUPABASE_URL')
  const callbackUrl =
    `${supabaseUrl}/functions/v1/platform-auth` +
    `?callback=steam&flow=${encodeURIComponent(flowId)}`

  const realm = `${supabaseUrl}/functions/v1/platform-auth`
  const authUrl = new URL('https://steamcommunity.com/openid/login')
  authUrl.searchParams.set('openid.ns', 'http://specs.openid.net/auth/2.0')
  authUrl.searchParams.set('openid.mode', 'checkid_setup')
  authUrl.searchParams.set(
    'openid.return_to',
    callbackUrl,
  )
  authUrl.searchParams.set('openid.realm', realm)
  authUrl.searchParams.set(
    'openid.identity',
    'http://specs.openid.net/auth/2.0/identifier_select',
  )
  authUrl.searchParams.set(
    'openid.claimed_id',
    'http://specs.openid.net/auth/2.0/identifier_select',
  )

  return jsonResponse({
    ok: true,
    provider: 'steam',
    authUrl: authUrl.toString(),
    expiresAt,
  })
}

async function verifySteamOpenId(url: URL) {
  const verification = new URLSearchParams()

  for (const [key, value] of url.searchParams.entries()) {
    if (key.startsWith('openid.')) {
      verification.set(key, value)
    }
  }

  verification.set('openid.mode', 'check_authentication')

  const response = await fetch(
    'https://steamcommunity.com/openid/login',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: verification.toString(),
    },
  )

  if (!response.ok) {
    return false
  }

  const text = await response.text()
  return /(^|\n)is_valid:true(\n|$)/.test(text)
}

async function readSteamProfile(steamId: string) {
  const key = env('STEAM_WEB_API_KEY')
  if (!key) {
    return { displayName: '', avatarUrl: '' }
  }

  try {
    const url = new URL(
      'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/',
    )
    url.searchParams.set('key', key)
    url.searchParams.set('steamids', steamId)

    const response = await fetch(url)
    if (!response.ok) {
      return { displayName: '', avatarUrl: '' }
    }

    const raw = await response.json() as JsonRecord
    const responseBody = raw.response
    if (!responseBody || typeof responseBody !== 'object') {
      return { displayName: '', avatarUrl: '' }
    }

    const players = (responseBody as JsonRecord).players
    if (!Array.isArray(players) || players.length === 0) {
      return { displayName: '', avatarUrl: '' }
    }

    const player = players[0] as JsonRecord
    return {
      displayName: String(player.personaname ?? '').trim(),
      avatarUrl: String(player.avatarfull ?? '').trim(),
    }
  } catch (_) {
    return { displayName: '', avatarUrl: '' }
  }
}

async function steamCallback(url: URL) {
  const flowId = url.searchParams.get('flow')?.trim() ?? ''
  if (!flowId) {
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: 'Flux Steam introuvable.',
    })
  }

  if (url.searchParams.get('openid.mode') === 'cancel') {
    return appRedirect({
      provider: 'steam',
      status: 'cancelled',
    })
  }

  const client = serviceClient()
  const { data: flow, error: flowError } = await client
    .from('project_xp_platform_auth_flows')
    .select(
      'id, auth_user_id, project_xp_user_id, provider, expires_at, used_at',
    )
    .eq('id', flowId)
    .eq('provider', 'steam')
    .maybeSingle()

  if (flowError || !flow) {
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: 'La demande de connexion Steam a expiré.',
    })
  }

  if (flow.used_at) {
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: 'Cette connexion Steam a déjà été utilisée.',
    })
  }

  if (Date.parse(String(flow.expires_at)) < Date.now()) {
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: 'La demande de connexion Steam a expiré.',
    })
  }

  const valid = await verifySteamOpenId(url)
  if (!valid) {
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: 'Steam n’a pas pu confirmer cette connexion.',
    })
  }

  const claimedId =
    url.searchParams.get('openid.claimed_id')?.trim() ?? ''
  const match = claimedId.match(
    /^https?:\/\/steamcommunity\.com\/openid\/id\/(\d+)$/,
  )
  const steamId = match?.[1] ?? ''

  if (!steamId) {
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: 'SteamID invalide.',
    })
  }

  const profile = await readSteamProfile(steamId)
  const now = new Date().toISOString()

  const { error: upsertError } = await client
    .from('project_xp_platform_accounts')
    .upsert(
      {
        auth_user_id: flow.auth_user_id,
        project_xp_user_id: flow.project_xp_user_id,
        provider: 'steam',
        provider_user_id: steamId,
        display_name: profile.displayName || null,
        avatar_url: profile.avatarUrl || null,
        linked_at: now,
        updated_at: now,
      },
      { onConflict: 'auth_user_id,provider' },
    )

  if (upsertError) {
    const conflict = upsertError.code === '23505'
    return appRedirect({
      provider: 'steam',
      status: 'error',
      message: conflict
        ? 'Ce compte Steam est déjà lié à un autre compte Project XP.'
        : 'Impossible d’enregistrer le compte Steam.',
    })
  }

  await client
    .from('project_xp_platform_auth_flows')
    .update({ used_at: now })
    .eq('id', flowId)

  return appRedirect({
    provider: 'steam',
    status: 'success',
  })
}

serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(request.url)

    if (request.method === 'GET' && url.searchParams.get('callback') === 'steam') {
      return await steamCallback(url)
    }

    if (request.method !== 'POST') {
      return jsonResponse(
        { ok: false, error: 'Méthode non autorisée.' },
        405,
      )
    }

    const body = await request.json() as JsonRecord
    const action = String(body.action ?? '')

    if (action === 'steam_start') {
      return await startSteam(request)
    }

    return jsonResponse(
      { ok: false, error: 'Action plateforme inconnue.' },
      400,
    )
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Erreur plateforme inconnue.'
    return jsonResponse({ ok: false, error: message }, 502)
  }
})
