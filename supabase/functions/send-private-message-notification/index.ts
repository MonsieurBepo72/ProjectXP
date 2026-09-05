import { createClient } from 'npm:@supabase/supabase-js@2'

type PrivateMessageRecord = {
  id: string
  conversation_id: string
  sender_id: string
  created_at?: string
}

type DatabaseWebhookPayload = {
  type: 'INSERT' | 'UPDATE' | 'DELETE'
  table: string
  schema: string
  record: PrivateMessageRecord
  old_record: PrivateMessageRecord | null
}

type FirebaseServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
  token_uri?: string
}

type JsonRecord = Record<string, unknown>

type DeliveryClaim = {
  available: boolean
  claimed: boolean
  state: string
}

let legacyWebhookWarningShown = false

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
) {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        'Content-Type':
            'application/json; charset=utf-8',
      },
    },
  )
}

function env(name: string): string {
  return Deno.env.get(name)?.trim() ?? ''
}

function getSupabaseAdminKey(): string {
  const legacyKey = env('SUPABASE_SERVICE_ROLE_KEY')
  if (legacyKey.length > 0) {
    return legacyKey
  }

  const rawSecretKeys = env('SUPABASE_SECRET_KEYS')
  if (!rawSecretKeys) {
    throw new Error(
      'Clé serveur Supabase introuvable.',
    )
  }

  const parsed =
      JSON.parse(rawSecretKeys) as Record<string, string>

  const defaultKey =
      String(parsed.default ?? '').trim()
  if (defaultKey.length > 0) {
    return defaultKey
  }

  const firstKey =
      Object.values(parsed)
        .map((value) => String(value ?? '').trim())
        .find((value) => value.length > 0)

  if (!firstKey) {
    throw new Error(
      'Aucune clé serveur Supabase utilisable.',
    )
  }

  return firstKey
}

function safeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder()
  const leftBytes = encoder.encode(left)
  const rightBytes = encoder.encode(right)

  if (leftBytes.length !== rightBytes.length) {
    return false
  }

  let difference = 0
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ rightBytes[index]
  }
  return difference === 0
}

function isLegacyAuthorizedWebhookRequest(
  req: Request,
): boolean {
  const providedKey =
      req.headers.get('apikey')?.trim() ?? ''

  if (providedKey.length === 0) {
    return false
  }

  const acceptedKeys: string[] = []

  const legacyKey = env('SUPABASE_SERVICE_ROLE_KEY')
  if (legacyKey.length > 0) {
    acceptedKeys.push(legacyKey)
  }

  const rawSecretKeys = env('SUPABASE_SECRET_KEYS')
  if (rawSecretKeys) {
    try {
      const parsed =
          JSON.parse(rawSecretKeys) as Record<string, string>

      for (const value of Object.values(parsed)) {
        const clean = String(value ?? '').trim()
        if (clean.length > 0) {
          acceptedKeys.push(clean)
        }
      }
    } catch (_) {
      console.error(
        'Impossible de lire SUPABASE_SECRET_KEYS.',
      )
    }
  }

  return acceptedKeys.some(
    (acceptedKey) => safeEqual(acceptedKey, providedKey),
  )
}

function isAuthorizedWebhookRequest(
  req: Request,
): boolean {
  const dedicatedSecret =
      env('PROJECT_XP_PRIVATE_MESSAGE_WEBHOOK_SECRET')

  if (dedicatedSecret.length > 0) {
    if (dedicatedSecret.length < 32) {
      console.error(
        'PROJECT_XP_PRIVATE_MESSAGE_WEBHOOK_SECRET doit faire au moins 32 caractères.',
      )
      return false
    }

    const providedSecret =
        req.headers
          .get('x-project-xp-webhook-secret')
          ?.trim() ?? ''

    return providedSecret.length > 0 &&
        safeEqual(dedicatedSecret, providedSecret)
  }

  // Compatibilité volontaire pendant la migration : tant que le secret dédié
  // n'est pas activé, le webhook existant continue de fonctionner avec la clé
  // serveur Supabase. INSTALLATION.txt explique l'ordre sûr pour basculer.
  if (!legacyWebhookWarningShown) {
    legacyWebhookWarningShown = true
    console.warn(
      'Webhook Project XP en mode compatibilité : configure le secret dédié.',
    )
  }

  return isLegacyAuthorizedWebhookRequest(req)
}

function base64UrlEncode(
  bytes: Uint8Array,
): string {
  let binary = ''

  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }

  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '')
}

function stringToBase64Url(
  value: string,
): string {
  return base64UrlEncode(
    new TextEncoder().encode(value),
  )
}

function pemToArrayBuffer(
  pem: string,
): ArrayBuffer {
  const base64 = pem
    .replace(
      '-----BEGIN PRIVATE KEY-----',
      '',
    )
    .replace(
      '-----END PRIVATE KEY-----',
      '',
    )
    .replace(/\s/g, '')

  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)

  for (
    let index = 0;
    index < binary.length;
    index++
  ) {
    bytes[index] =
        binary.charCodeAt(index)
  }

  return bytes.buffer
}

async function createGoogleAccessToken(
  serviceAccount: FirebaseServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const payload = {
    iss: serviceAccount.client_email,
    scope:
        'https://www.googleapis.com/auth/firebase.messaging',
    aud:
        serviceAccount.token_uri ??
        'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const unsignedToken =
      `${stringToBase64Url(
        JSON.stringify(header),
      )}.${stringToBase64Url(
        JSON.stringify(payload),
      )}`

  const privateKey =
      await crypto.subtle.importKey(
        'pkcs8',
        pemToArrayBuffer(
          serviceAccount.private_key,
        ),
        {
          name: 'RSASSA-PKCS1-v1_5',
          hash: 'SHA-256',
        },
        false,
        ['sign'],
      )

  const signature =
      await crypto.subtle.sign(
        'RSASSA-PKCS1-v1_5',
        privateKey,
        new TextEncoder().encode(
          unsignedToken,
        ),
      )

  const signedJwt =
      `${unsignedToken}.${base64UrlEncode(
        new Uint8Array(signature),
      )}`

  const tokenResponse =
      await fetch(
        serviceAccount.token_uri ??
            'https://oauth2.googleapis.com/token',
        {
          method: 'POST',
          headers: {
            'Content-Type':
                'application/x-www-form-urlencoded',
          },
          body: new URLSearchParams({
            grant_type:
                'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion: signedJwt,
          }),
        },
      )

  const tokenBody =
      await tokenResponse.json() as JsonRecord

  if (
    !tokenResponse.ok ||
    typeof tokenBody.access_token !== 'string'
  ) {
    console.error(
      'Erreur OAuth Firebase HTTP',
      tokenResponse.status,
    )

    throw new Error(
      'Impossible de créer le jeton OAuth Firebase.',
    )
  }

  return tokenBody.access_token
}

async function sendFcmNotification({
  serviceAccount,
  accessToken,
  token,
  senderName,
  senderId,
  conversationId,
}: {
  serviceAccount: FirebaseServiceAccount
  accessToken: string
  token: string
  senderName: string
  senderId: string
  conversationId: string
}) {
  const response =
      await fetch(
        `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization:
                `Bearer ${accessToken}`,
            'Content-Type':
                'application/json; charset=utf-8',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title: 'Nouveau message',
                body:
                    `${senderName} t’a envoyé un message.`,
              },
              data: {
                type: 'private_message',
                conversation_id: conversationId,
                sender_id: senderId,
                sender_name: senderName,
              },
              android: {
                priority: 'high',
                notification: {
                  channel_id: 'project_xp_alerts',
                  sound: 'default',
                },
              },
            },
          }),
        },
      )

  // On ne journalise volontairement ni le token appareil ni la réponse FCM.
  if (!response.ok) {
    console.error(
      'Erreur FCM HTTP',
      response.status,
    )
  }

  return response.ok
}

async function claimDelivery(
  supabaseAdmin: ReturnType<typeof createClient>,
  messageId: string,
): Promise<DeliveryClaim> {
  try {
    const { data, error } = await supabaseAdmin.rpc(
      'project_xp_claim_private_message_notification',
      {
        p_message_id: messageId,
        p_lease_seconds: 120,
      },
    )

    if (error) {
      console.warn(
        'Idempotence notification indisponible ; envoi conservé.',
      )
      return {
        available: false,
        claimed: true,
        state: 'degraded',
      }
    }

    const row = Array.isArray(data) ? data[0] : data
    if (!row || typeof row !== 'object') {
      return {
        available: false,
        claimed: true,
        state: 'degraded',
      }
    }

    const record = row as JsonRecord
    return {
      available: true,
      claimed: record.claimed === true,
      state: String(record.delivery_state ?? ''),
    }
  } catch (_) {
    console.warn(
      'Idempotence notification indisponible ; envoi conservé.',
    )
    return {
      available: false,
      claimed: true,
      state: 'degraded',
    }
  }
}

async function finishDelivery(
  supabaseAdmin: ReturnType<typeof createClient>,
  messageId: string,
  success: boolean,
  errorCode: string | null = null,
) {
  try {
    const { error } = await supabaseAdmin.rpc(
      'project_xp_finish_private_message_notification',
      {
        p_message_id: messageId,
        p_success: success,
        p_error: errorCode,
      },
    )

    if (error) {
      console.warn(
        'Finalisation idempotence notification indisponible.',
      )
    }
  } catch (_) {
    console.warn(
      'Finalisation idempotence notification indisponible.',
    )
  }
}

Deno.serve(
  async (req: Request) => {
    if (req.method !== 'POST') {
      return jsonResponse(
        { error: 'Méthode non autorisée.' },
        405,
      )
    }

    // verify_jwt reste désactivé pour ce Database Webhook. L'authentification
    // dédiée est contrôlée ici, avec fallback compatible pendant la migration.
    if (!isAuthorizedWebhookRequest(req)) {
      return jsonResponse(
        { error: 'Webhook non autorisé.' },
        401,
      )
    }

    let supabaseAdmin:
        ReturnType<typeof createClient> | null = null
    let claimedMessageId = ''
    let deliveryClaimed = false

    try {
      const payload =
          await req.json() as DatabaseWebhookPayload

      if (
        payload.type !== 'INSERT' ||
        payload.schema !== 'public' ||
        payload.table !== 'private_messages'
      ) {
        return jsonResponse({
          ignored: true,
          reason: 'Événement non concerné.',
        })
      }

      const message = payload.record

      if (
        !message?.id ||
        !message.conversation_id ||
        !message.sender_id
      ) {
        return jsonResponse(
          { error: 'Message privé incomplet.' },
          400,
        )
      }

      const supabaseUrl = env('SUPABASE_URL')
      if (!supabaseUrl) {
        throw new Error('SUPABASE_URL introuvable.')
      }

      supabaseAdmin =
          createClient(
            supabaseUrl,
            getSupabaseAdminKey(),
            {
              auth: {
                persistSession: false,
                autoRefreshToken: false,
              },
            },
          )

      // On relit les données sensibles côté serveur et on ne fait pas confiance
      // au contenu fourni dans le payload du webhook.
      const {
        data: storedMessage,
        error: messageError,
      } =
          await supabaseAdmin
            .from('private_messages')
            .select(
              'id, conversation_id, sender_id',
            )
            .eq('id', message.id)
            .single()

      if (messageError || !storedMessage) {
        return jsonResponse(
          { error: 'Message privé introuvable.' },
          404,
        )
      }

      const {
        data: conversation,
        error: conversationError,
      } =
          await supabaseAdmin
            .from('private_conversations')
            .select('id, user_a, user_b')
            .eq(
              'id',
              storedMessage.conversation_id,
            )
            .single()

      if (
        conversationError ||
        !conversation
      ) {
        return jsonResponse(
          { error: 'Conversation privée introuvable.' },
          404,
        )
      }

      let recipientId = ''

      if (
        storedMessage.sender_id ===
        conversation.user_a
      ) {
        recipientId = conversation.user_b
      } else if (
        storedMessage.sender_id ===
        conversation.user_b
      ) {
        recipientId = conversation.user_a
      } else {
        return jsonResponse(
          { error: 'Expéditeur hors de la conversation.' },
          403,
        )
      }

      // Le message est authentique et rattaché à la conversation : on peut
      // maintenant prendre un lease atomique avant tout envoi FCM.
      const claim = await claimDelivery(
        supabaseAdmin,
        String(storedMessage.id),
      )

      if (!claim.claimed) {
        return jsonResponse({
          ok: true,
          ignored: true,
          reason:
              claim.state === 'sent'
                ? 'Notification déjà envoyée.'
                : 'Notification déjà en cours de traitement.',
        })
      }

      claimedMessageId = String(storedMessage.id)
      deliveryClaimed = claim.available

      const { data: senderProfile } =
          await supabaseAdmin
            .from('tavern_profiles')
            .select('display_name')
            .eq(
              'id',
              storedMessage.sender_id,
            )
            .maybeSingle()

      const publicSenderName =
          senderProfile?.display_name
            ?.toString()
            .trim() ||
          'Un aventurier'

      const { data: aliasRow } =
          await supabaseAdmin
            .from('friend_aliases')
            .select('nickname')
            .eq('owner_id', recipientId)
            .eq(
              'friend_id',
              storedMessage.sender_id,
            )
            .maybeSingle()

      const senderAlias =
          aliasRow?.nickname
            ?.toString()
            .trim() ?? ''

      const senderName =
          senderAlias.length > 0
            ? senderAlias
            : publicSenderName

      const {
        data: tokenRows,
        error: tokenError,
      } =
          await supabaseAdmin
            .from('push_device_tokens')
            .select('token')
            .eq('user_id', recipientId)

      if (tokenError) {
        throw new Error(
          'Impossible de lire les appareils du destinataire.',
        )
      }

      const tokens =
          Array.from(
            new Set(
              (tokenRows ?? [])
                .map(
                  (row) =>
                      row.token
                        ?.toString()
                        .trim(),
                )
                .filter(
                  (token): token is string =>
                      Boolean(token),
                ),
            ),
          )

      if (tokens.length === 0) {
        if (deliveryClaimed) {
          await finishDelivery(
            supabaseAdmin,
            claimedMessageId,
            true,
          )
        }

        return jsonResponse({
          ok: true,
          sent: 0,
          reason:
              'Aucun appareil FCM enregistré pour le destinataire.',
        })
      }

      const rawServiceAccount =
          env('FIREBASE_SERVICE_ACCOUNT_JSON')

      if (!rawServiceAccount) {
        throw new Error(
          'Secret FIREBASE_SERVICE_ACCOUNT_JSON introuvable.',
        )
      }

      const serviceAccount =
          JSON.parse(
            rawServiceAccount,
          ) as FirebaseServiceAccount

      if (
        !serviceAccount.project_id ||
        !serviceAccount.client_email ||
        !serviceAccount.private_key
      ) {
        throw new Error(
          'Compte de service Firebase incomplet.',
        )
      }

      const accessToken =
          await createGoogleAccessToken(
            serviceAccount,
          )

      let sent = 0
      for (const token of tokens) {
        const ok = await sendFcmNotification({
          serviceAccount,
          accessToken,
          token,
          senderName,
          senderId: storedMessage.sender_id,
          conversationId:
              storedMessage.conversation_id,
        })

        if (ok) {
          sent += 1
        }
      }

      // Dès qu'un appareil a reçu la notification, on considère le message
      // traité afin qu'un retry webhook ne duplique pas l'alerte déjà visible.
      if (deliveryClaimed) {
        await finishDelivery(
          supabaseAdmin,
          claimedMessageId,
          sent > 0,
          sent > 0 ? null : 'fcm_delivery_failed',
        )
      }

      console.log(
        `Notifications privées envoyées : ${sent}/${tokens.length}`,
      )

      return jsonResponse({
        ok: sent > 0,
        sent,
        total: tokens.length,
      })
    } catch (error) {
      if (
        supabaseAdmin != null &&
        deliveryClaimed &&
        claimedMessageId.length > 0
      ) {
        await finishDelivery(
          supabaseAdmin,
          claimedMessageId,
          false,
          'processing_error',
        )
      }

      console.error(
        'send-private-message-notification : erreur de traitement.',
      )

      return jsonResponse(
        {
          error:
              error instanceof Error
                ? error.message
                : 'Erreur serveur inconnue.',
        },
        500,
      )
    }
  },
)
