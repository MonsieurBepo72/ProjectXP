import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4'
import {
  exchangeRefreshTokenForAuthTokens,
  getTitleTrophies,
  getTitleTrophyGroups,
  getUserPlayedGames,
  getUserTrophiesEarnedForTitle,
  getUserTitles,
} from 'npm:psn-api@2.18.1'

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

async function platformEncryptionKey() {
  const serviceRole = env('SUPABASE_SERVICE_ROLE_KEY')
  if (!serviceRole) {
    throw new Error('Clé serveur Supabase absente.')
  }

  const material = new TextEncoder().encode(
    `project-xp|platform-credential|v1|${serviceRole}`,
  )
  const digest = await crypto.subtle.digest('SHA-256', material)

  return await crypto.subtle.importKey(
    'raw',
    digest,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  )
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = ''
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }
  return btoa(binary)
}

function base64ToBytes(value: string) {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index)
  }
  return bytes
}

async function encryptPlatformSecret(value: string) {
  const key = await platformEncryptionKey()
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const encrypted = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    new TextEncoder().encode(value),
  )

  return {
    cipherText: bytesToBase64(new Uint8Array(encrypted)),
    iv: bytesToBase64(iv),
  }
}

async function decryptPlatformSecret(
  cipherText: string,
  ivText: string,
) {
  const key = await platformEncryptionKey()
  const decrypted = await crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: base64ToBytes(ivText),
    },
    key,
    base64ToBytes(cipherText),
  )

  return new TextDecoder().decode(decrypted)
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === 'object'
    ? value as JsonRecord
    : {}
}

function numberValue(value: unknown) {
  const number = Number(value ?? 0)
  return Number.isFinite(number) ? number : 0
}

function cleanTitle(value: unknown) {
  return String(value ?? '')
    .replace(/[™®©]/g, '')
    .trim()
}

function canonicalTitle(value: unknown) {
  return cleanTitle(value)
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '')
}

function platformAgnosticTitle(value: unknown) {
  return cleanTitle(value)
    .replace(/\b(?:ps4|ps5|playstation\s*4|playstation\s*5)\b/gi, ' ')
    .replace(/\b(?:trophy|trophies|trophy\s*set)\b/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function trophyGroupFor(
  groups: Map<string, Group>,
  title: string,
) {
  const exact = groups.get(canonicalTitle(title))
  if (exact) {
    return exact
  }

  const relaxedKey = canonicalTitle(platformAgnosticTitle(title))
  if (!relaxedKey) {
    return groupFor(groups, title)
  }

  const matches = [...groups.values()].filter(
    (candidate) =>
      canonicalTitle(platformAgnosticTitle(candidate.title)) === relaxedKey,
  )

  // On ne fusionne que si la correspondance est unique. Cela évite de
  // mélanger Remake / Remastered / éditions réellement différentes.
  if (matches.length === 1) {
    return matches[0]
  }

  return groupFor(groups, title)
}

function parseDurationMinutes(raw: unknown) {
  const value = String(raw ?? '').trim()
  if (!value) {
    return 0
  }

  const match = value.match(
    /^P(?:(\d+(?:\.\d+)?)D)?T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$/,
  )

  if (!match) {
    return 0
  }

  const days = Number(match[1] ?? 0)
  const hours = Number(match[2] ?? 0)
  const minutes = Number(match[3] ?? 0)
  const seconds = Number(match[4] ?? 0)

  return Math.max(
    0,
    Math.round(
      days * 24 * 60 +
      hours * 60 +
      minutes +
      seconds / 60,
    ),
  )
}

function latestIso(current: string, candidate: unknown) {
  const value = String(candidate ?? '').trim()
  if (!value) {
    return current
  }

  if (!current) {
    return value
  }

  const currentTime = Date.parse(current)
  const candidateTime = Date.parse(value)

  if (!Number.isFinite(candidateTime)) {
    return current
  }

  if (!Number.isFinite(currentTime) || candidateTime > currentTime) {
    return value
  }

  return current
}

function choosePlayedCover(title: JsonRecord) {
  const localized =
    String(title.localizedImageUrl ?? '').trim()
  const normal =
    String(title.imageUrl ?? '').trim()

  const concept = asRecord(title.concept)
  const media = asRecord(concept.media)
  const images = Array.isArray(media.images)
    ? media.images
    : []

  const preferredTypes = [
    'PORTRAIT',
    'COVER',
    'BOX',
    'MASTER',
    'KEYART',
  ]

  for (const preferredType of preferredTypes) {
    for (const rawImage of images) {
      const image = asRecord(rawImage)
      const type = String(image.type ?? '').toUpperCase()
      const url = String(image.url ?? '').trim()

      if (url && type.includes(preferredType)) {
        return url
      }
    }
  }

  if (localized) {
    return localized
  }
  if (normal) {
    return normal
  }

  for (const rawImage of images) {
    const image = asRecord(rawImage)
    const url = String(image.url ?? '').trim()
    if (url) {
      return url
    }
  }

  return ''
}

type TrophySetRef = {
  npCommunicationId: string
  npServiceName: 'trophy' | 'trophy2'
  title: string
  platform: string
}

type Group = {
  key: string
  title: string
  coverUrl: string
  playtimeMinutes: number
  lastPlayedAt: string
  titleIds: Set<string>
  conceptIds: Set<string>
  trophyIds: Set<string>
  trophySets: TrophySetRef[]
  platforms: Set<string>
  bronzeUnlocked: number
  bronzeTotal: number
  silverUnlocked: number
  silverTotal: number
  goldUnlocked: number
  goldTotal: number
  platinumUnlocked: number
  platinumTotal: number
  progressWeight: number
  progressWeightedSum: number
}

function emptyGroup(key: string, title: string): Group {
  return {
    key,
    title,
    coverUrl: '',
    playtimeMinutes: 0,
    lastPlayedAt: '',
    titleIds: new Set<string>(),
    conceptIds: new Set<string>(),
    trophyIds: new Set<string>(),
    trophySets: [],
    platforms: new Set<string>(),
    bronzeUnlocked: 0,
    bronzeTotal: 0,
    silverUnlocked: 0,
    silverTotal: 0,
    goldUnlocked: 0,
    goldTotal: 0,
    platinumUnlocked: 0,
    platinumTotal: 0,
    progressWeight: 0,
    progressWeightedSum: 0,
  }
}

function groupFor(
  groups: Map<string, Group>,
  title: string,
) {
  const key = canonicalTitle(title)
  if (!key) {
    return null
  }

  const current = groups.get(key)
  if (current) {
    if (!current.title && title) {
      current.title = title
    }
    return current
  }

  const created = emptyGroup(key, title)
  groups.set(key, created)
  return created
}

async function loadPlayedGames(accessToken: string) {
  const result: JsonRecord[] = []
  let offset = 0

  for (let page = 0; page < 10; page += 1) {
    const response = await getUserPlayedGames(
      { accessToken },
      'me',
      {
        limit: 200,
        offset,
        categories:
          'ps4_game,ps5_native_game,pspc_game,unknown',
      },
    ) as unknown as JsonRecord

    const titles = Array.isArray(response.titles)
      ? response.titles
      : []

    for (const title of titles) {
      result.push(asRecord(title))
    }

    if (titles.length === 0) {
      break
    }

    const total = numberValue(response.totalItemCount)
    const nextOffset = numberValue(response.nextOffset)

    if (result.length >= total || nextOffset <= offset) {
      break
    }

    offset = nextOffset
  }

  return result
}

async function loadTrophyTitles(accessToken: string) {
  const result: JsonRecord[] = []
  let offset = 0

  for (let page = 0; page < 5; page += 1) {
    const response = await getUserTitles(
      { accessToken },
      'me',
      {
        limit: 800,
        offset,
      },
    ) as unknown as JsonRecord

    const titles = Array.isArray(response.trophyTitles)
      ? response.trophyTitles
      : []

    for (const title of titles) {
      result.push(asRecord(title))
    }

    if (titles.length === 0) {
      break
    }

    const total = numberValue(response.totalItemCount)
    const nextOffset = numberValue(response.nextOffset)

    if (result.length >= total || nextOffset <= offset) {
      break
    }

    offset = nextOffset
  }

  return result
}

function playStationPlatformsFromPlayedCategory(value: unknown) {
  const category = String(value ?? '').trim().toLowerCase()
  switch (category) {
    case 'ps5_native_game':
    case 'ps5_game':
      return ['PlayStation 5']
    case 'ps4_game':
      return ['PlayStation 4']
    case 'pspc_game':
      return ['PC (PlayStation)']
    default:
      return []
  }
}

function playStationPlatformsFromTitleId(value: unknown) {
  const raw = String(value ?? '').trim().toUpperCase()
  if (!raw) {
    return []
  }

  const prefixMatch = raw.match(/^([A-Z]{4})/)
  const prefix = prefixMatch?.[1] ?? ''
  if (!prefix) {
    return []
  }

  // Fallback conservateur pour les jeux dont l'API "played games" ne
  // fournit pas de category précise (cas fréquent sur d'anciens titres ou
  // certains contenus sans trophées). On ne couvre que des familles de
  // Title IDs suffisamment caractéristiques pour ne pas inventer une console.
  const ps5Prefixes = new Set([
    'PPSA',
    'ELJM',
    'ECAS',
    'ELAS',
  ])
  if (ps5Prefixes.has(prefix)) {
    return ['PlayStation 5']
  }

  const ps4Prefixes = new Set([
    'CUSA',
    'PCJS',
    'PLJM',
    'PLJS',
    'PCKS',
    'PLKS',
    'PCAS',
    'PLAS',
  ])
  if (ps4Prefixes.has(prefix)) {
    return ['PlayStation 4']
  }

  const vitaPrefixes = new Set([
    'PCSA',
    'PCSE',
    'PCSB',
    'PCSF',
    'PCSC',
    'PCSG',
    'PCSD',
    'PCSH',
    'VLJM',
  ])
  if (vitaPrefixes.has(prefix)) {
    return ['PS Vita']
  }

  const ps3Prefixes = new Set([
    'BCJS',
    'BLJS',
    'BCUS',
    'BLUS',
    'BCES',
    'BLES',
    'BCAS',
    'BLAS',
    'BCKS',
    'BLKS',
  ])
  if (ps3Prefixes.has(prefix)) {
    return ['PlayStation 3']
  }

  const pspPrefixes = new Set([
    'UCJS',
    'ULJS',
    'UCUS',
    'ULUS',
    'UCES',
    'ULES',
    'UCKS',
    'ULKS',
    'UCAS',
    'ULAS',
  ])
  if (pspPrefixes.has(prefix)) {
    return ['PSP']
  }

  return []
}

function playStationPlatformsFromTrophyPlatform(value: unknown) {
  const raw = String(value ?? '').trim().toUpperCase()
  if (!raw) {
    return []
  }

  const result = new Set<string>()
  if (raw.includes('PS5')) result.add('PlayStation 5')
  if (raw.includes('PS4')) result.add('PlayStation 4')
  if (raw.includes('PS3')) result.add('PlayStation 3')
  if (
    raw.includes('PSVITA') ||
    raw.includes('PS VITA') ||
    raw.includes('VITA')
  ) {
    result.add('PS Vita')
  }
  if (raw.includes('PSP')) result.add('PSP')

  return [...result]
}

function playStationPlatformSortValue(value: string) {
  switch (value) {
    case 'PlayStation 3':
      return 30
    case 'PSP':
      return 35
    case 'PS Vita':
      return 40
    case 'PlayStation 4':
      return 50
    case 'PlayStation 5':
      return 60
    case 'PC (PlayStation)':
      return 70
    default:
      return 999
  }
}

function normalizeGames(
  playedGames: JsonRecord[],
  trophyTitles: JsonRecord[],
) {
  const groups = new Map<string, Group>()

  for (const played of playedGames) {
    const title = cleanTitle(
      played.localizedName || played.name,
    )
    const group = groupFor(groups, title)
    if (!group) {
      continue
    }

    for (const platform of playStationPlatformsFromPlayedCategory(
      played.category,
    )) {
      group.platforms.add(platform)
    }

    const titleId = String(played.titleId ?? '').trim()
    for (const platform of playStationPlatformsFromTitleId(titleId)) {
      group.platforms.add(platform)
    }

    if (titleId && !group.titleIds.has(titleId)) {
      group.titleIds.add(titleId)
      group.playtimeMinutes += parseDurationMinutes(
        played.playDuration,
      )
    }

    const concept = asRecord(played.concept)
    const conceptId = String(concept.id ?? '').trim()
    if (conceptId) {
      group.conceptIds.add(conceptId)
    }

    const cover = choosePlayedCover(played)
    if (!group.coverUrl && cover) {
      group.coverUrl = cover
    }

    group.lastPlayedAt = latestIso(
      group.lastPlayedAt,
      played.lastPlayedDateTime,
    )
  }

  for (const trophy of trophyTitles) {
    const title = cleanTitle(trophy.trophyTitleName)
    const group = trophyGroupFor(groups, title)
    if (!group) {
      continue
    }

    const communicationId =
      String(trophy.npCommunicationId ?? '').trim()
    if (communicationId && !group.trophyIds.has(communicationId)) {
      group.trophyIds.add(communicationId)

      const platform = String(trophy.trophyTitlePlatform ?? '').trim()
      for (const precisePlatform of
        playStationPlatformsFromTrophyPlatform(platform)) {
        group.platforms.add(precisePlatform)
      }
      group.trophySets.push({
        npCommunicationId: communicationId,
        npServiceName: platform.toUpperCase().includes('PS5')
          ? 'trophy2'
          : 'trophy',
        title: title || group.title,
        platform,
      })

      const defined = asRecord(trophy.definedTrophies)
      const earned = asRecord(trophy.earnedTrophies)

      const bronzeTotal = numberValue(defined.bronze)
      const silverTotal = numberValue(defined.silver)
      const goldTotal = numberValue(defined.gold)
      const platinumTotal = numberValue(defined.platinum)

      const bronzeUnlocked = numberValue(earned.bronze)
      const silverUnlocked = numberValue(earned.silver)
      const goldUnlocked = numberValue(earned.gold)
      const platinumUnlocked = numberValue(earned.platinum)

      group.bronzeTotal += bronzeTotal
      group.silverTotal += silverTotal
      group.goldTotal += goldTotal
      group.platinumTotal += platinumTotal

      group.bronzeUnlocked += bronzeUnlocked
      group.silverUnlocked += silverUnlocked
      group.goldUnlocked += goldUnlocked
      group.platinumUnlocked += platinumUnlocked

      const trophyCount =
        bronzeTotal +
        silverTotal +
        goldTotal +
        platinumTotal

      if (trophyCount > 0) {
        group.progressWeight += trophyCount
        group.progressWeightedSum +=
          numberValue(trophy.progress) * trophyCount
      }
    }

    if (!group.coverUrl) {
      group.coverUrl =
        String(trophy.trophyTitleIconUrl ?? '').trim()
    }

    group.lastPlayedAt = latestIso(
      group.lastPlayedAt,
      trophy.lastUpdatedDateTime,
    )
  }

  const games = [...groups.values()]
    .filter((group) => group.title.trim().length > 0)
    .map((group) => {
      const total =
        group.bronzeTotal +
        group.silverTotal +
        group.goldTotal +
        group.platinumTotal

      const unlocked =
        group.bronzeUnlocked +
        group.silverUnlocked +
        group.goldUnlocked +
        group.platinumUnlocked

      const progressKnown = group.progressWeight > 0 || total > 0
      const progressPercent = group.progressWeight > 0
        ? Math.round(
          group.progressWeightedSum / group.progressWeight,
        )
        : total > 0
        ? Math.round((unlocked / total) * 100)
        : 0

      const trophyIds = [...group.trophyIds].sort()
      const conceptIds = [...group.conceptIds].sort()
      const titleIds = [...group.titleIds].sort()

      const externalId = trophyIds.length > 0
        ? `trophy:${trophyIds.join('|')}`
        : conceptIds.length > 0
        ? `concept:${conceptIds.join('|')}`
        : `title:${titleIds.join('|')}`

      return {
        title: group.title,
        externalId,
        coverUrl: group.coverUrl || null,
        playtimeMinutes: group.playtimeMinutes,
        lastPlayedAt: group.lastPlayedAt || null,
        progressKnown,
        progressPercent: Math.max(
          0,
          Math.min(100, progressPercent),
        ),
        trophies: {
          unlocked,
          total,
          bronzeUnlocked: group.bronzeUnlocked,
          bronzeTotal: group.bronzeTotal,
          silverUnlocked: group.silverUnlocked,
          silverTotal: group.silverTotal,
          goldUnlocked: group.goldUnlocked,
          goldTotal: group.goldTotal,
          platinumUnlocked: group.platinumUnlocked,
          platinumTotal: group.platinumTotal,
        },
        trophySets: group.trophySets,
        platforms: [...group.platforms].sort((a, b) => {
          const byOrder =
            playStationPlatformSortValue(a) -
            playStationPlatformSortValue(b)
          return byOrder === 0 ? a.localeCompare(b) : byOrder
        }),
      }
    })

  games.sort((a, b) => {
    const aTime = Date.parse(String(a.lastPlayedAt ?? '')) || 0
    const bTime = Date.parse(String(b.lastPlayedAt ?? '')) || 0
    return bTime - aTime
  })

  return games
}


type TrophyDetailRequest = {
  clientKey: string
  npCommunicationId: string
  npServiceName: 'trophy' | 'trophy2'
  title: string
}

function trophyDetailRequest(value: unknown): TrophyDetailRequest | null {
  const item = asRecord(value)
  const clientKey = String(item.clientKey ?? '').trim()
  const npCommunicationId = String(item.npCommunicationId ?? '').trim()
  const rawServiceName = String(item.npServiceName ?? '').trim()
  const title = cleanTitle(item.title)

  if (!clientKey || !npCommunicationId) {
    return null
  }

  if (rawServiceName !== 'trophy' && rawServiceName !== 'trophy2') {
    return null
  }

  // Les identifiants PSN modernes commencent généralement par NPWR. On ne
  // bloque pas les anciens formats, mais on refuse les chaînes manifestement
  // anormales afin d'éviter de transformer l'Edge Function en proxy arbitraire.
  if (
    npCommunicationId.length < 4 ||
    npCommunicationId.length > 96 ||
    !/^[A-Za-z0-9._:-]+$/.test(npCommunicationId)
  ) {
    return null
  }

  return {
    clientKey,
    npCommunicationId,
    npServiceName: rawServiceName,
    title,
  }
}

async function loadAllTitleTrophies(
  accessToken: string,
  request: TrophyDetailRequest,
) {
  const result: JsonRecord[] = []
  let offset = 0

  for (let page = 0; page < 20; page += 1) {
    const response = await getTitleTrophies(
      { accessToken },
      request.npCommunicationId,
      'all',
      {
        npServiceName: request.npServiceName,
        limit: 200,
        offset,
      },
    ) as unknown as JsonRecord

    const trophies = Array.isArray(response.trophies)
      ? response.trophies
      : []

    for (const trophy of trophies) {
      result.push(asRecord(trophy))
    }

    if (trophies.length === 0) {
      break
    }

    const total = numberValue(response.totalItemCount)
    const nextOffset = numberValue(response.nextOffset)
    if (result.length >= total || nextOffset <= offset) {
      break
    }
    offset = nextOffset
  }

  return result
}

async function loadAllUserTrophies(
  accessToken: string,
  request: TrophyDetailRequest,
) {
  const result: JsonRecord[] = []
  let offset = 0

  for (let page = 0; page < 20; page += 1) {
    const response = await getUserTrophiesEarnedForTitle(
      { accessToken },
      'me',
      request.npCommunicationId,
      'all',
      {
        npServiceName: request.npServiceName,
        limit: 200,
        offset,
      },
    ) as unknown as JsonRecord

    const trophies = Array.isArray(response.trophies)
      ? response.trophies
      : []

    for (const trophy of trophies) {
      result.push(asRecord(trophy))
    }

    if (trophies.length === 0) {
      break
    }

    const total = numberValue(response.totalItemCount)
    const nextOffset = numberValue(response.nextOffset)
    if (result.length >= total || nextOffset <= offset) {
      break
    }
    offset = nextOffset
  }

  return result
}

function trophyKind(value: unknown) {
  const kind = String(value ?? '').trim().toLowerCase()
  if (
    kind === 'bronze' ||
    kind === 'silver' ||
    kind === 'gold' ||
    kind === 'platinum'
  ) {
    return kind
  }
  return 'generic'
}

async function loadTrophySetDetails(
  accessToken: string,
  request: TrophyDetailRequest,
) {
  const [groupsResponse, titleTrophies, userTrophies] = await Promise.all([
    getTitleTrophyGroups(
      { accessToken },
      request.npCommunicationId,
      { npServiceName: request.npServiceName },
    ) as unknown as Promise<JsonRecord>,
    loadAllTitleTrophies(accessToken, request),
    loadAllUserTrophies(accessToken, request),
  ])

  const groupNames = new Map<string, string>()
  const groups = Array.isArray(groupsResponse.trophyGroups)
    ? groupsResponse.trophyGroups
    : []

  for (const rawGroup of groups) {
    const group = asRecord(rawGroup)
    const id = String(group.trophyGroupId ?? '').trim()
    if (!id) {
      continue
    }
    const name = cleanTitle(group.trophyGroupName)
    groupNames.set(id, name)
  }

  const earnedById = new Map<string, JsonRecord>()
  for (const trophy of userTrophies) {
    const id = String(trophy.trophyId ?? '').trim()
    if (id) {
      earnedById.set(id, trophy)
    }
  }

  const achievementDetails = titleTrophies.map((trophy) => {
    const trophyId = String(trophy.trophyId ?? '').trim()
    const earned = earnedById.get(trophyId)
    const groupId = String(trophy.trophyGroupId ?? 'default').trim() || 'default'
    const groupName = groupId === 'default'
      ? null
      : (groupNames.get(groupId) || `DLC ${groupId}`)
    const isEarned = earned?.earned === true

    return {
      id: `${request.npCommunicationId}:${trophyId}`,
      name: cleanTitle(trophy.trophyName) || 'Trophée',
      description: String(trophy.trophyDetail ?? '').trim(),
      iconUrl: String(trophy.trophyIconUrl ?? '').trim() || null,
      hidden: trophy.trophyHidden === true,
      kind: trophyKind(trophy.trophyType),
      scoreValue: 0,
      groupName,
      platformUnlocked: isEarned,
      manuallyUnlocked: false,
      platformUnlockedAt: isEarned
        ? String(earned?.earnedDateTime ?? '').trim() || null
        : null,
      manuallyUnlockedAt: null,
    }
  })

  return achievementDetails
}

async function withPlayStationAccess(request: Request) {
  const user = await authenticatedUser(request)
  if (!user) {
    throw new Error('PROJECT_XP_AUTH_REQUIRED')
  }

  const client = serviceClient()
  const { data: credential, error: credentialError } = await client
    .from('project_xp_platform_credentials')
    .select('secret_ciphertext, secret_iv, expires_at')
    .eq('auth_user_id', user.id)
    .eq('provider', 'playstation')
    .maybeSingle()

  if (credentialError || !credential) {
    throw new Error('PROJECT_XP_RECONNECT_REQUIRED')
  }

  const refreshToken = await decryptPlatformSecret(
    String(credential.secret_ciphertext ?? ''),
    String(credential.secret_iv ?? ''),
  )
  if (!refreshToken) {
    throw new Error('PROJECT_XP_RECONNECT_REQUIRED')
  }

  const authorization = await exchangeRefreshTokenForAuthTokens(refreshToken)
  const accessToken = String(authorization.accessToken ?? '').trim()
  if (!accessToken) {
    throw new Error('PROJECT_XP_RECONNECT_REQUIRED')
  }

  const nextRefreshToken =
    String(authorization.refreshToken ?? '').trim() || refreshToken

  if (nextRefreshToken !== refreshToken) {
    const encrypted = await encryptPlatformSecret(nextRefreshToken)
    const refreshSeconds = Number(authorization.refreshTokenExpiresIn ?? 0)
    const expiresAt = Number.isFinite(refreshSeconds) && refreshSeconds > 0
      ? new Date(Date.now() + refreshSeconds * 1000).toISOString()
      : credential.expires_at

    await client
      .from('project_xp_platform_credentials')
      .update({
        secret_ciphertext: encrypted.cipherText,
        secret_iv: encrypted.iv,
        expires_at: expiresAt,
        updated_at: new Date().toISOString(),
      })
      .eq('auth_user_id', user.id)
      .eq('provider', 'playstation')
  }

  return { user, client, accessToken }
}

async function syncPlayStationDetails(
  request: Request,
  body: JsonRecord,
) {
  const rawSets = Array.isArray(body.trophySets)
    ? body.trophySets
    : []

  if (rawSets.length === 0 || rawSets.length > 12) {
    return jsonResponse(
      {
        ok: false,
        error: 'Lot de trophées PlayStation invalide.',
      },
      400,
    )
  }

  const trophySets = rawSets
    .map(trophyDetailRequest)
    .filter((item): item is TrophyDetailRequest => item !== null)

  if (trophySets.length !== rawSets.length) {
    return jsonResponse(
      {
        ok: false,
        error: 'Un identifiant de trophées PlayStation est invalide.',
      },
      400,
    )
  }

  let access: Awaited<ReturnType<typeof withPlayStationAccess>>
  try {
    access = await withPlayStationAccess(request)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (
      message === 'PROJECT_XP_AUTH_REQUIRED' ||
      message === 'PROJECT_XP_RECONNECT_REQUIRED' ||
      message.toLowerCase().includes('invalid_grant') ||
      message.toLowerCase().includes('unauthorized') ||
      message.includes('401')
    ) {
      return jsonResponse(
        {
          ok: false,
          error:
            'La session PlayStation a expiré. Reconnecte ton compte depuis COMPTES.',
        },
        401,
      )
    }
    throw error
  }

  const results: JsonRecord[] = new Array(trophySets.length)
  let nextIndex = 0

  async function worker() {
    while (true) {
      const index = nextIndex
      nextIndex += 1
      if (index >= trophySets.length) {
        return
      }

      const trophySet = trophySets[index]
      try {
        const achievementDetails = await loadTrophySetDetails(
          access.accessToken,
          trophySet,
        )
        results[index] = {
          clientKey: trophySet.clientKey,
          ok: true,
          npCommunicationId: trophySet.npCommunicationId,
          achievementDetails,
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        results[index] = {
          clientKey: trophySet.clientKey,
          ok: false,
          npCommunicationId: trophySet.npCommunicationId,
          error: message,
        }
      }
    }
  }

  await Promise.all([worker(), worker(), worker()])

  return jsonResponse({
    ok: true,
    provider: 'playstation',
    results,
  })
}

async function syncPlayStation(request: Request) {
  const user = await authenticatedUser(request)
  if (!user) {
    return jsonResponse(
      {
        ok: false,
        error:
          'Un compte Cloud Project XP actif est nécessaire pour synchroniser PlayStation.',
      },
      401,
    )
  }

  const client = serviceClient()

  const { data: credential, error: credentialError } = await client
    .from('project_xp_platform_credentials')
    .select(
      'secret_ciphertext, secret_iv, expires_at',
    )
    .eq('auth_user_id', user.id)
    .eq('provider', 'playstation')
    .maybeSingle()

  if (credentialError || !credential) {
    return jsonResponse(
      {
        ok: false,
        error:
          'Reconnecte ton compte PlayStation depuis COMPTES avant de synchroniser.',
      },
      401,
    )
  }

  try {
    const refreshToken = await decryptPlatformSecret(
      String(credential.secret_ciphertext ?? ''),
      String(credential.secret_iv ?? ''),
    )

    if (!refreshToken) {
      throw new Error('Jeton PlayStation vide.')
    }

    const authorization =
      await exchangeRefreshTokenForAuthTokens(refreshToken)

    const accessToken =
      String(authorization.accessToken ?? '').trim()

    if (!accessToken) {
      return jsonResponse(
        {
          ok: false,
          error:
            'La session PlayStation a expiré. Reconnecte ton compte depuis COMPTES.',
        },
        401,
      )
    }

    const nextRefreshToken =
      String(authorization.refreshToken ?? '').trim() ||
      refreshToken

    if (nextRefreshToken !== refreshToken) {
      const encrypted =
        await encryptPlatformSecret(nextRefreshToken)
      const refreshSeconds = Number(
        authorization.refreshTokenExpiresIn ?? 0,
      )
      const expiresAt = Number.isFinite(refreshSeconds) &&
          refreshSeconds > 0
        ? new Date(
          Date.now() + refreshSeconds * 1000,
        ).toISOString()
        : credential.expires_at

      await client
        .from('project_xp_platform_credentials')
        .update({
          secret_ciphertext: encrypted.cipherText,
          secret_iv: encrypted.iv,
          expires_at: expiresAt,
          updated_at: new Date().toISOString(),
        })
        .eq('auth_user_id', user.id)
        .eq('provider', 'playstation')
    }

    const [playedGames, trophyTitles] = await Promise.all([
      loadPlayedGames(accessToken),
      loadTrophyTitles(accessToken),
    ])

    const games = normalizeGames(
      playedGames,
      trophyTitles,
    )

    await client
      .from('project_xp_platform_accounts')
      .update({
        updated_at: new Date().toISOString(),
      })
      .eq('auth_user_id', user.id)
      .eq('provider', 'playstation')

    return jsonResponse({
      ok: true,
      provider: 'playstation',
      games,
      playedCount: playedGames.length,
      trophyTitleCount: trophyTitles.length,
    })
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : String(error)

    const lower = message.toLowerCase()

    if (
      lower.includes('unauthorized') ||
      lower.includes('invalid_grant') ||
      lower.includes('401') ||
      lower.includes('refresh')
    ) {
      return jsonResponse(
        {
          ok: false,
          error:
            'La session PlayStation a expiré. Reconnecte ton compte depuis COMPTES.',
        },
        401,
      )
    }

    if (
      lower.includes('429') ||
      lower.includes('rate limit')
    ) {
      return jsonResponse(
        {
          ok: false,
          error:
            'PlayStation limite temporairement les requêtes. Réessaie dans quelques minutes.',
        },
        429,
      )
    }

    return jsonResponse(
      {
        ok: false,
        error:
          'PlayStation n’a pas pu synchroniser la bibliothèque pour le moment.',
      },
      502,
    )
  }
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
    const body = await request.json() as JsonRecord
    const action = String(body.action ?? '')

    if (action === 'sync') {
      return await syncPlayStation(request)
    }

    if (action === 'details') {
      return await syncPlayStationDetails(request, body)
    }

    return jsonResponse(
      { ok: false, error: 'Action PlayStation inconnue.' },
      400,
    )
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Erreur PlayStation inconnue.'

    return jsonResponse(
      {
        ok: false,
        error: message,
      },
      502,
    )
  }
})
