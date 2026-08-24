import { createClient } from 'npm:@supabase/supabase-js@2'

type PrivateMessageRecord = {
  id: string
  conversation_id: string
  sender_id: string
  content: string
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

function getSupabaseAdminKey(): string {
  const legacyKey =
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  if (legacyKey && legacyKey.trim().length > 0) {
    return legacyKey
  }

  const rawSecretKeys =
      Deno.env.get('SUPABASE_SECRET_KEYS')

  if (!rawSecretKeys) {
    throw new Error(
      'Clé serveur Supabase introuvable.',
    )
  }

  const parsed =
      JSON.parse(rawSecretKeys) as Record<string, string>

  const defaultKey = parsed.default

  if (defaultKey && defaultKey.trim().length > 0) {
    return defaultKey
  }

  const firstKey =
      Object.values(parsed).find(
        (value) =>
            typeof value === 'string' &&
            value.trim().length > 0,
      )

  if (!firstKey) {
    throw new Error(
      'Aucune clé serveur Supabase utilisable.',
    )
  }

  return firstKey
}

function isAuthorizedWebhookRequest(
  req: Request,
): boolean {
  const providedKey =
      req.headers.get('apikey')?.trim() ?? ''

  if (providedKey.length === 0) {
    return false
  }

  const acceptedKeys: string[] = []

  const legacyKey =
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
        ?.trim()

  if (
    legacyKey &&
    legacyKey.length > 0
  ) {
    acceptedKeys.push(
      legacyKey,
    )
  }

  const rawSecretKeys =
      Deno.env.get('SUPABASE_SECRET_KEYS')

  if (rawSecretKeys) {
    try {
      const parsed =
          JSON.parse(
            rawSecretKeys,
          ) as Record<string, string>

      for (
        const value
        of Object.values(parsed)
      ) {
        if (
          typeof value === 'string' &&
          value.trim().length > 0
        ) {
          acceptedKeys.push(
            value.trim(),
          )
        }
      }
    } catch (error) {
      console.error(
        'Impossible de lire SUPABASE_SECRET_KEYS :',
        error,
      )
    }
  }

  return acceptedKeys.includes(
    providedKey,
  )
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
  const now =
      Math.floor(Date.now() / 1000)

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
      await tokenResponse.json()

  if (
    !tokenResponse.ok ||
    typeof tokenBody.access_token !== 'string'
  ) {
    console.error(
      'Erreur OAuth Firebase :',
      tokenBody,
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
                title:
                    'Nouveau message',
                body:
                    `${senderName} t’a envoyé un message.`,
              },
              data: {
                type:
                    'private_message',
                conversation_id:
                    conversationId,
                sender_id:
                    senderId,
                sender_name:
                    senderName,
              },
              android: {
                priority: 'high',
                notification: {
                  channel_id:
                      'project_xp_alerts',
                  sound: 'default',
                },
              },
            },
          }),
        },
      )

  const responseText =
      await response.text()

  if (!response.ok) {
    console.error(
      'Erreur FCM :',
      response.status,
      responseText,
    )
  }

  return {
    ok: response.ok,
    status: response.status,
    responseText,
  }
}

Deno.serve(
  async (req: Request) => {
    if (req.method !== 'POST') {
      return jsonResponse(
        {
          error:
              'Méthode non autorisée.',
        },
        405,
      )
    }

    // Le Database Webhook envoie la clé serveur Supabase
    // dans le header "apikey". La vérification JWT de la
    // plateforme doit être désactivée pour cette fonction,
    // puis l'authentification est contrôlée ici.
    if (!isAuthorizedWebhookRequest(req)) {
      return jsonResponse(
        {
          error:
              'Webhook non autorisé.',
        },
        401,
      )
    }

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
          reason:
              'Événement non concerné.',
        })
      }

      const message =
          payload.record

      if (
        !message?.id ||
        !message.conversation_id ||
        !message.sender_id
      ) {
        return jsonResponse(
          {
            error:
                'Message privé incomplet.',
          },
          400,
        )
      }

      const supabaseUrl =
          Deno.env.get('SUPABASE_URL')

      if (!supabaseUrl) {
        throw new Error(
          'SUPABASE_URL introuvable.',
        )
      }

      const supabaseAdmin =
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

      // On relit le message dans la base.
      // Cela évite de faire confiance uniquement
      // au contenu reçu par le webhook.
      const {
        data: storedMessage,
        error: messageError,
      } =
          await supabaseAdmin
            .from('private_messages')
            .select(
              'id, conversation_id, sender_id, content',
            )
            .eq(
              'id',
              message.id,
            )
            .single()

      if (
        messageError ||
        !storedMessage
      ) {
        console.error(
          'Message introuvable :',
          messageError,
        )

        return jsonResponse(
          {
            error:
                'Message privé introuvable.',
          },
          404,
        )
      }

      const {
        data: conversation,
        error: conversationError,
      } =
          await supabaseAdmin
            .from('private_conversations')
            .select(
              'id, user_a, user_b',
            )
            .eq(
              'id',
              storedMessage.conversation_id,
            )
            .single()

      if (
        conversationError ||
        !conversation
      ) {
        console.error(
          'Conversation introuvable :',
          conversationError,
        )

        return jsonResponse(
          {
            error:
                'Conversation privée introuvable.',
          },
          404,
        )
      }

      let recipientId = ''

      if (
        storedMessage.sender_id ===
        conversation.user_a
      ) {
        recipientId =
            conversation.user_b
      } else if (
        storedMessage.sender_id ===
        conversation.user_b
      ) {
        recipientId =
            conversation.user_a
      } else {
        return jsonResponse(
          {
            error:
                'Expéditeur hors de la conversation.',
          },
          403,
        )
      }

      const {
        data: senderProfile,
      } =
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

      // Dans les zones privées de Project XP, le surnom choisi
      // par le destinataire est prioritaire sur le pseudo public.
      const {
        data: aliasRow,
      } =
          await supabaseAdmin
            .from('friend_aliases')
            .select('nickname')
            .eq(
              'owner_id',
              recipientId,
            )
            .eq(
              'friend_id',
              storedMessage.sender_id,
            )
            .maybeSingle()

      const senderAlias =
          aliasRow?.nickname
            ?.toString()
            .trim() ??
          ''

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
            .eq(
              'user_id',
              recipientId,
            )

      if (tokenError) {
        console.error(
          'Erreur lecture tokens :',
          tokenError,
        )

        throw new Error(
          'Impossible de lire les appareils du destinataire.',
        )
      }

      const tokens =
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
            )

      if (tokens.length === 0) {
        return jsonResponse({
          ok: true,
          sent: 0,
          reason:
              'Aucun appareil FCM enregistré pour le destinataire.',
        })
      }

      const rawServiceAccount =
          Deno.env.get(
            'FIREBASE_SERVICE_ACCOUNT_JSON',
          )

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

      const results = []

      for (const token of tokens) {
        const result =
            await sendFcmNotification({
              serviceAccount,
              accessToken,
              token,
              senderName,
              senderId:
                  storedMessage.sender_id,
              conversationId:
                  storedMessage.conversation_id,
            })

        results.push(result)
      }

      const sent =
          results.filter(
            (result) => result.ok,
          ).length

      console.log(
        `Notifications privées envoyées : ${sent}/${tokens.length}`,
      )

      return jsonResponse({
        ok: sent > 0,
        sent,
        total: tokens.length,
      })
    } catch (error) {
      console.error(
        'send-private-message-notification :',
        error,
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
