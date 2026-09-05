import { createClient } from 'npm:@supabase/supabase-js@2';
import { francAll } from 'npm:franc@6.2.0';
import { Profanity } from 'npm:@2toad/profanity@3.3.0';
import { classifyLexicalRpcError } from './lexical_guard.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':
    'POST, OPTIONS',
  'Content-Type':
    'application/json; charset=utf-8',
};

const OPENAI_MODERATION_URL =
  'https://api.openai.com/v1/moderations';

const OPENAI_MODERATION_MODEL =
  'omni-moderation-latest';

// OpenAI reste un module optionnel.
// Tant que la variable n'est pas explicitement positionnee a "true",
// aucun appel reseau OpenAI n'est effectue.
const OPENAI_MODERATION_ENABLED =
  (Deno.env.get('OPENAI_MODERATION_ENABLED') ?? 'false')
    .trim()
    .toLowerCase() === 'true';

const MAX_CONTENT_LENGTH = 2000;

const MODERATION_PIPELINE_VERSION =
  '2.4.9';

const BUNDLED_PROFANITY_LANGUAGES =
  new Set<string>([
    'ar',
    'zh',
    'en',
    'fr',
    'de',
    'hi',
    'it',
    'ja',
    'ko',
    'pt',
    'ru',
    'es',
  ]);

const bundledProfanity =
  new Profanity(
    {
      languages: ['en'],
      wholeWord: true,
      unicodeWordBoundaries: true,
    },
  );

// Les très petits termes d'un énorme lexique mondial génèrent facilement
// des faux positifs. Les termes critiques courts restent couverts par
// moderation_blocked_terms (V1).
const MIN_STRICT_LEXICON_LENGTH =
  4;

const MAX_DETECTED_LANGUAGES =
  2;

const MAX_LEXICON_CANDIDATES = 9000;
const MAX_WORD_NGRAM = 5;
const MAX_SCRIPT_NGRAM = 10;

// -----------------------------------------------------------------------------
// POLITIQUE PROJECT XP V2.2
//
// 1. Hard-block V1 : termes critiques déjà validés.
// 2. Lexique mondial : 75 langues, action "context" par défaut.
// 3. OpenAI Moderation : décision contextuelle multilingue.
// 4. Un terme "context" ne bloque pas tout seul.
//    Il renforce le blocage lorsqu'OpenAI identifie réellement du harcèlement.
// 5. Un terme promu manuellement en "hard_block" bloque immédiatement.
//
// Cette séparation évite de transformer tous les jurons mondiaux en interdictions.
// -----------------------------------------------------------------------------

const HARD_BLOCK_CATEGORIES = new Set<string>([
  'hate',
  'hate/threatening',
  'harassment/threatening',
  'sexual',
  'sexual/minors',
  'illicit',
  'illicit/violent',
  'self-harm/instructions',
  'violence/graphic',
]);

const SAFETY_SIGNAL_CATEGORIES = new Set<string>([
  'self-harm',
  'self-harm/intent',
]);

const NON_SEGMENTED_SCRIPT =
  /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Thai}\p{Script=Khmer}\p{Script=Lao}\p{Script=Myanmar}]/u;

const SHORT_LANGUAGE_HINTS:
  Record<string, string> = {
  hi: 'en',
  hello: 'en',
  thanks: 'en',
  thx: 'en',
  bye: 'en',
  bonjour: 'fr',
  bonsoir: 'fr',
  salut: 'fr',
  coucou: 'fr',
  merci: 'fr',
  hola: 'es',
  gracias: 'es',
  ciao: 'it',
  grazie: 'it',
  'olá': 'pt',
  obrigado: 'pt',
  obrigada: 'pt',
  danke: 'de',
};

const FRANC_TO_PROJECT_LANGUAGE:
  Record<string, string> = {
  afr: 'af',
  sqi: 'sq',
  dzo: 'dz',
  amh: 'am',
  ara: 'ar',
  hye: 'hy',
  rom: 'rop',
  aze: 'az',
  eus: 'eu',
  bel: 'be',
  bul: 'bg',
  mya: 'my',
  khm: 'kh',
  cat: 'ca',
  ceb: 'ceb',
  zho: 'zh',
  hrv: 'hr',
  ces: 'cs',
  dan: 'da',
  nld: 'nl',
  eng: 'en',
  epo: 'eo',
  est: 'et',
  fil: 'fil',
  fin: 'fi',
  fra: 'fr',
  gla: 'gd',
  glg: 'gl',
  deu: 'de',
  ell: 'el',
  yid: 'yid',
  hin: 'hi',
  hun: 'hu',
  isl: 'is',
  ita: 'it',
  ind: 'id',
  jpn: 'ja',
  kab: 'kab',
  tlh: 'tlh',
  kor: 'ko',
  lat: 'la',
  lav: 'lv',
  lit: 'lt',
  mkd: 'mk',
  msa: 'ms',
  mal: 'ml',
  mlt: 'mt',
  mri: 'mi',
  mar: 'mr',
  mon: 'mn',
  nor: 'no',
  fas: 'fa',
  pih: 'pih',
  pol: 'pl',
  por: 'pt',
  ron: 'ro',
  rus: 'ru',
  smo: 'sm',
  srp: 'sr',
  slk: 'sk',
  slv: 'sl',
  spa: 'es',
  swe: 'sv',
  tam: 'ta',
  tel: 'te',
  tet: 'tet',
  tha: 'th',
  ton: 'to',
  tur: 'tr',
  ukr: 'uk',
  uzb: 'uz',
  vie: 'vi',
  cym: 'cy',
  zul: 'zu',
};

type ModerationDecision = {
  blocked: boolean;
  safetySignal: boolean;
  categories: string[];
  categoryScores: Record<string, number>;
  degraded: boolean;
};

type LexiconMatch = {
  term: string;
  normalized_term: string;
  language_code: string;
  action: string;
};

type LexiconDecision = {
  hardBlocked: boolean;
  strictBlocked: boolean;
  hasContextSignal: boolean;
  matchedLanguages: string[];
  matchedTermsCount: number;
  detectedLanguages: string[];
  degraded: boolean;
};

type BundledProfanitySignal = {
  matched: boolean;
  obfuscated: boolean;
  detectedLanguages: string[];
};

type ModernSlangSignal = {
  blocked: boolean;
  category:
    | 'modern_slang_directed'
    | 'modern_slang_obfuscated'
    | 'self_harm_directive'
    | 'none';
};

type MessageRateLimitDecision = {
  allowed: boolean;
  retryAfterSeconds: number;
  scope: string;
  burstRemaining: number;
  minuteRemaining: number;
};

const MODERN_DIRECTED_TERMS =
  new Set<string>([
    'pnj',
    'npc',
    'bot',
    'clown',
    'bouffon',
    'boloss',
    'cassos',
    'teube',
    'simp',
    'bop',
    'thot',
    'hoe',
    'loser',
    'noob',
    'goofy',
    'glazer',
    'unc',
    'pick me',
    'low iq',
    'zero iq',
    'brainrot',
    'bozo',
    'golem',
    'golmon',
    'matrixe',
    'fraude',
    'random',
    'corny',
  ]);

const MODERN_MILD_MOCKERY =
  new Set<string>([
    'cringe',
    'mid',
    'cooked',
    'zero aura',
    'negative aura',
    'skill issue',
    'ratio',
    'touch grass',
    'glazing',
    'chopped',
  ]);

const STRONG_ABBREVIATIONS =
  new Set<string>([
    'fdp',
    'ntm',
    'ftg',
    'tg',
    'vtff',
    'stfu',
  ]);

const STRONG_FULL_WORD_INSULTS =
  new Set<string>([
    'connard',
    'connasse',
    'salope',
    'pute',
    'enfoire',
    'batard',
    'tocard',
    'crevard',
    'ordure',
    'merdeux',
    'merdeuse',
  ]);

const CONTEXTUAL_FULL_WORD_INSULTS =
  new Set<string>([
    'con',
    'conne',
    'debile',
    'idiot',
    'idiote',
    'cretin',
    'cretine',
    'abruti',
    'abrutie',
    'minable',
  ]);

const CONTEXTUAL_FULL_PHRASE_INSULTS =
  new Set<string>([
    'fils de pute',
    'fille de pute',
    'trou du cul',
    'sac a merde',
    'sous merde',
  ]);

const SELF_HARM_DIRECTIVES =
  new Set<string>([
    'kill yourself',
    'go kill yourself',
    'suicide toi',
    'suicidez vous',
    'tue toi',
    'tuez vous',
    'va te pendre',
    'vas te pendre',
    'allez vous pendre',
  ]);

const INTENSIFIERS =
  new Set<string>([
    'sale',
    'gros',
    'grosse',
    'espece de',
    'pauvre',
    'putain de',
    'vieux',
    'vieille',
  ]);

const CONFUSABLES:
  Record<string, string> = {
  'а': 'a',
  'е': 'e',
  'о': 'o',
  'р': 'p',
  'с': 'c',
  'х': 'x',
  'у': 'y',
  'і': 'i',
  'ј': 'j',
  'к': 'k',
  'м': 'm',
  'т': 't',
  'в': 'b',
  'α': 'a',
  'ο': 'o',
  'ρ': 'p',
  'χ': 'x',
  'κ': 'k',
  'τ': 't',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(
      'ok',
      {
        headers: corsHeaders,
      },
    );
  }

  if (req.method !== 'POST') {
    return jsonResponse(
      {
        status: 'error',
        code: 'method_not_allowed',
      },
      405,
    );
  }

  const supabaseUrl =
    Deno.env.get('SUPABASE_URL') ?? '';

  const supabaseAnonKey =
    Deno.env.get('SUPABASE_ANON_KEY') ?? '';

  const serviceRoleKey =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (
    supabaseUrl.length === 0 ||
    supabaseAnonKey.length === 0 ||
    serviceRoleKey.length === 0
  ) {
    console.error(
      'Variables Supabase serveur manquantes.',
    );

    return jsonResponse(
      {
        status: 'error',
        code: 'server_configuration',
      },
      500,
    );
  }

  const authorization =
    req.headers.get('Authorization') ?? '';

  if (!authorization.startsWith('Bearer ')) {
    return jsonResponse(
      {
        status: 'error',
        code: 'authentication_required',
      },
      401,
    );
  }

  const token =
    authorization
      .substring('Bearer '.length)
      .trim();

  if (token.length === 0) {
    return jsonResponse(
      {
        status: 'error',
        code: 'authentication_required',
      },
      401,
    );
  }

  const userClient =
    createClient(
      supabaseUrl,
      supabaseAnonKey,
      {
        global: {
          headers: {
            Authorization:
              `Bearer ${token}`,
          },
        },
      },
    );

  const adminClient =
    createClient(
      supabaseUrl,
      serviceRoleKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

  const {
    data: userData,
    error: userError,
  } =
    await userClient.auth.getUser(
      token,
    );

  const user =
    userData.user;

  if (
    userError != null ||
    user == null
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'invalid_session',
      },
      401,
    );
  }

  let payload: Record<string, unknown>;

  try {
    payload =
      await req.json();
  } catch {
    return jsonResponse(
      {
        status: 'error',
        code: 'invalid_json',
      },
      400,
    );
  }

  const surface =
    cleanString(
      payload.surface,
    );

  const content =
    cleanString(
      payload.content,
    );

  if (
    content.length === 0 ||
    content.length > MAX_CONTENT_LENGTH
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'invalid_content',
      },
      200,
    );
  }

  if (
    surface !== 'tavern' &&
    surface !== 'private'
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'invalid_surface',
      },
      200,
    );
  }

  // ---------------------------------------------------------------------------
  // V2.4.8 : anti-spam serveur.
  //
  // Le quota est consommé avant les contrôles de modération coûteux afin
  // qu'un client compromis ne puisse pas contourner la protection locale.
  // Le RPC est atomique côté PostgreSQL et séparé entre Taverne et privé.
  // ---------------------------------------------------------------------------

  const rateLimit =
    await consumeMessageRateLimit(
      adminClient,
      user.id,
      surface,
    );

  if (rateLimit == null) {
    return jsonResponse(
      {
        status: 'error',
        code: 'rate_limit_unavailable',
      },
      503,
    );
  }

  if (!rateLimit.allowed) {
    console.warn(
      `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
      `rate_limited=true ` +
      `surface=${surface} ` +
      `scope=${rateLimit.scope} ` +
      `retry_after=${rateLimit.retryAfterSeconds}`,
    );

    return rateLimitedResponse(
      rateLimit.retryAfterSeconds,
      rateLimit.scope,
    );
  }

  // ---------------------------------------------------------------------------
  // V2.2 : les quatre contrôles indépendants partent en parallèle.
  // ---------------------------------------------------------------------------

  const lexicalPromise =
    adminClient
      .rpc(
        'project_xp_assert_message_allowed',
        {
          p_content: content,
        },
      )
      .then(
        ({ error }) =>
          classifyLexicalRpcError(error),
        (error) =>
          classifyLexicalRpcError(error),
      );

  const lexiconPromise =
    scanGlobalLexicon(
      adminClient,
      content,
    );

  // ---------------------------------------------------------------------------
  // V2.4.7 : OpenAI Moderation reste disponible comme module optionnel.
  // Aucun appel n'est effectué tant que OPENAI_MODERATION_ENABLED n'est pas true.
  // ---------------------------------------------------------------------------

  const moderationPromise =
    moderateWithOpenAI(
      content,
    );

  const bundledProfanitySignal =
    scanBundledProfanity(
      content,
    );

  const modernSlangSignal =
    scanModernSlangV246(
      content,
    );

  if (surface === 'tavern') {
    const channelId =
      cleanString(
        payload.channel_id,
      );

    if (channelId.length === 0) {
      return jsonResponse(
        {
          status: 'error',
          code: 'invalid_channel',
        },
        200,
      );
    }

    const channelPromise =
      adminClient
        .from('tavern_channels')
        .select('id')
        .eq(
          'id',
          channelId,
        )
        .maybeSingle();

    const [
      lexicalResult,
      lexicon,
      moderation,
      channelResult,
    ] = await Promise.all([
      lexicalPromise,
      lexiconPromise,
      moderationPromise,
      channelPromise,
    ]);

    const blocked =
      await resolveBlockingDecision(
        adminClient,
        {
          userId: user.id,
          surface,
          content,
          lexicalBlocked: lexicalResult.blocked,
          bundledProfanitySignal,
          lexicon,
          moderation,
          modernSlangSignal,
        },
      );

    if (blocked) {
      return blockedResponse();
    }

    if (
      channelResult.error != null ||
      channelResult.data == null
    ) {
      return jsonResponse(
        {
          status: 'error',
          code: 'channel_not_found',
        },
        200,
      );
    }

    await logSafetySignalIfNeeded(
      adminClient,
      {
        userId: user.id,
        surface,
        content,
        moderation,
      },
    );

    const {
      error: insertError,
    } =
      await adminClient
        .from('tavern_messages')
        .insert(
          {
            channel_id:
              channelId,
            author_id:
              user.id,
            content,
          },
        );

    if (insertError != null) {
      console.error(
        'Insertion Taverne impossible :',
        insertError.message,
      );

      return jsonResponse(
        {
          status: 'error',
          code: 'insert_failed',
        },
        200,
      );
    }

    return jsonResponse(
      {
        status: 'sent',
        moderation_pipeline:
          MODERATION_PIPELINE_VERSION,
        moderation_degraded:
          lexicalResult.degraded ||
          moderation.degraded ||
          lexicon.degraded,
      },
      200,
    );
  }

  const conversationId =
    cleanString(
      payload.conversation_id,
    );

  if (conversationId.length === 0) {
    return jsonResponse(
      {
        status: 'error',
        code: 'invalid_conversation',
      },
      200,
    );
  }

  const conversationPromise =
    adminClient
      .from('private_conversations')
      .select(
        'id, user_a, user_b',
      )
      .eq(
        'id',
        conversationId,
      )
      .maybeSingle();

  const [
    lexicalResult,
    lexicon,
    moderation,
    conversationResult,
  ] = await Promise.all([
    lexicalPromise,
    lexiconPromise,
    moderationPromise,
    conversationPromise,
  ]);

  const blocked =
    await resolveBlockingDecision(
      adminClient,
      {
        userId: user.id,
        surface,
        content,
        lexicalBlocked: lexicalResult.blocked,
        bundledProfanitySignal,
        lexicon,
        moderation,
        modernSlangSignal,
      },
    );

  if (blocked) {
    return blockedResponse();
  }

  const conversation =
    conversationResult.data;

  if (
    conversationResult.error != null ||
    conversation == null
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'conversation_not_found',
      },
      200,
    );
  }

  const userA =
    cleanString(
      conversation.user_a,
    );

  const userB =
    cleanString(
      conversation.user_b,
    );

  if (
    user.id !== userA &&
    user.id !== userB
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'conversation_forbidden',
      },
      403,
    );
  }

  await logSafetySignalIfNeeded(
    adminClient,
    {
      userId: user.id,
      surface,
      content,
      moderation,
    },
  );

  const {
    error: insertError,
  } =
    await adminClient
      .from('private_messages')
      .insert(
        {
          conversation_id:
            conversationId,
          sender_id:
            user.id,
          content,
        },
      );

  if (insertError != null) {
    console.error(
      'Insertion message privé impossible :',
      insertError.message,
    );

    return jsonResponse(
      {
        status: 'error',
        code: 'insert_failed',
      },
      200,
    );
  }

  return jsonResponse(
    {
      status: 'sent',
      moderation_pipeline:
        MODERATION_PIPELINE_VERSION,
      moderation_degraded:
        lexicalResult.degraded ||
        moderation.degraded ||
        lexicon.degraded,
    },
    200,
  );
});

async function consumeMessageRateLimit(
  adminClient:
    ReturnType<typeof createClient>,
  userId: string,
  surface: string,
): Promise<MessageRateLimitDecision | null> {
  try {
    const {
      data,
      error,
    } =
      await adminClient.rpc(
        'project_xp_consume_message_rate_limit',
        {
          p_user_id:
            userId,
          p_surface:
            surface,
        },
      );

    if (error != null) {
      console.error(
        'Rate limit serveur indisponible :',
        error.message,
      );

      return null;
    }

    const raw =
      Array.isArray(data)
        ? data[0]
        : data;

    if (
      raw == null ||
      typeof raw !== 'object'
    ) {
      console.error(
        'Réponse rate limit serveur invalide.',
      );

      return null;
    }

    const row =
      raw as Record<string, unknown>;

    if (
      row.allowed !== true &&
      row.allowed !== false
    ) {
      console.error(
        'Décision rate limit serveur invalide.',
      );

      return null;
    }

    const retryAfterRaw =
      Number(
        row.retry_after_seconds ??
        0,
      );

    const burstRemainingRaw =
      Number(
        row.burst_remaining ??
        0,
      );

    const minuteRemainingRaw =
      Number(
        row.minute_remaining ??
        0,
      );

    return {
      allowed:
        row.allowed,
      retryAfterSeconds:
        Number.isFinite(
            retryAfterRaw,
          )
          ? Math.max(
              0,
              Math.ceil(
                retryAfterRaw,
              ),
            )
          : 0,
      scope:
        cleanString(
          row.limit_scope,
        ) || 'unknown',
      burstRemaining:
        Number.isFinite(
            burstRemainingRaw,
          )
          ? Math.max(
              0,
              Math.floor(
                burstRemainingRaw,
              ),
            )
          : 0,
      minuteRemaining:
        Number.isFinite(
            minuteRemainingRaw,
          )
          ? Math.max(
              0,
              Math.floor(
                minuteRemainingRaw,
              ),
            )
          : 0,
    };
  } catch (error) {
    console.error(
      'Contrôle rate limit impossible :',
      error,
    );

    return null;
  }
}

async function resolveBlockingDecision(
  adminClient:
    ReturnType<typeof createClient>,
  input: {
    userId: string;
    surface: string;
    content: string;
    lexicalBlocked: boolean;
    bundledProfanitySignal: BundledProfanitySignal;
    lexicon: LexiconDecision;
    moderation: ModerationDecision;
    modernSlangSignal: ModernSlangSignal;
  },
): Promise<boolean> {
  if (input.lexicalBlocked) {
    await logModerationEvent(
      adminClient,
      {
        userId:
          input.userId,
        surface:
          input.surface,
        decision:
          'blocked',
        categories: [
          'lexical_hard_block',
        ],
        content:
          input.content,
      },
    );

    return true;
  }

  if (input.lexicon.hardBlocked) {
    await logModerationEvent(
      adminClient,
      {
        userId:
          input.userId,
        surface:
          input.surface,
        decision:
          'blocked',
        categories: [
          'global_lexicon_hard_block',
        ],
        content:
          input.content,
      },
    );

    return true;
  }

  // -------------------------------------------------------------------------
  // V2.4.6.2 — MOTEUR CONTEXTUEL SERVEUR
  //
  // Même logique que celle validée dans l'application :
  // slang moderne, mots complets, accords/conjugaisons et faux positifs.
  // -------------------------------------------------------------------------

  if (
    input.modernSlangSignal.blocked
  ) {
    await logModerationEvent(
      adminClient,
      {
        userId:
          input.userId,
        surface:
          input.surface,
        decision:
          'blocked',
        categories: [
          input.modernSlangSignal.category,
        ],
        content:
          input.content,
      },
    );

    return true;
  }

  // Si V2.4.6.2 reconnaît une famille contextuelle mais choisit de l'autoriser,
  // l'ancien heuristique ne doit pas repasser derrière et la rebloquer.
  const modernContextHandled =
    isModernContextSensitiveContent(
      input.content,
    );

  // -------------------------------------------------------------------------
  // V2.4.1 — VULGARITÉ VS INSULTE DIRIGÉE
  //
  // Un gros mot seul n'est pas automatiquement une violation.
  //
  // Exemples voulus :
  //   "Putain ce boss est difficile" -> autorisé.
  //   "T'es vraiment un connard"     -> bloqué.
  //
  // Une tentative d'obfuscation du type c.o.n.n.a.r.d est bloquée
  // directement : l'intention est explicitement de contourner le filtre.
  // -------------------------------------------------------------------------

  const explanatoryModernUse =
    modernContextHandled &&
    isModernExplicitExplanatoryUse(
      input.content,
    );

  if (
    input.bundledProfanitySignal.obfuscated &&
    !explanatoryModernUse
  ) {
    await logModerationEvent(
      adminClient,
      {
        userId:
          input.userId,
        surface:
          input.surface,
        decision:
          'blocked',
        categories: [
          'profanity_obfuscation',
        ],
        content:
          input.content,
      },
    );

    return true;
  }

  const profanitySignal =
    input.bundledProfanitySignal.matched ||
    input.lexicon.hasContextSignal ||
    input.lexicon.strictBlocked;

  const directedAbuse =
    profanitySignal &&
    !modernContextHandled &&
    looksLikeDirectedAbuse(
      input.content,
      [
        ...new Set([
          ...input.bundledProfanitySignal
              .detectedLanguages,
          ...input.lexicon
              .detectedLanguages,
        ]),
      ],
    );

  if (directedAbuse) {
    await logModerationEvent(
      adminClient,
      {
        userId:
          input.userId,
        surface:
          input.surface,
        decision:
          'blocked',
        categories: [
          'directed_profanity',
        ],
        content:
          input.content,
      },
    );

    return true;
  }

  if (input.moderation.blocked) {
    await logModerationEvent(
      adminClient,
      {
        userId:
          input.userId,
        surface:
          input.surface,
        decision:
          'blocked',
        categories:
          input.moderation.categories,
        content:
          input.content,
      },
    );

    return true;
  }

  return false;
}

async function scanGlobalLexicon(
  adminClient:
    ReturnType<typeof createClient>,
  content: string,
): Promise<LexiconDecision> {
  try {
    const candidates =
      buildLexiconCandidates(
        content,
      );

    const detectedLanguages =
      detectProjectLanguages(
        content,
      );

    if (candidates.length === 0) {
      return {
        hardBlocked: false,
        strictBlocked: false,
        hasContextSignal: false,
        matchedLanguages: [],
        matchedTermsCount: 0,
        detectedLanguages,
        degraded: false,
      };
    }

    const {
      data,
      error,
    } =
      await adminClient.rpc(
        'project_xp_match_global_lexicon_v23',
        {
          p_candidates:
            candidates,
          p_languages:
            detectedLanguages,
        },
      );

    if (error != null) {
      console.error(
        'Lexique mondial indisponible :',
        error.message,
      );

      return {
        hardBlocked: false,
        strictBlocked: false,
        hasContextSignal: false,
        matchedLanguages: [],
        matchedTermsCount: 0,
        detectedLanguages,
        degraded: true,
      };
    }

    const rows =
      Array.isArray(data)
        ? data as LexiconMatch[]
        : [];

    const hardBlocked =
      rows.some(
        (row) =>
          row.action ===
          'hard_block',
      );

    const hasContextSignal =
      rows.some(
        (row) =>
          row.action ===
          'context',
      );

    const strictBlocked =
      rows.some(
        (row) => {
          if (
            row.action ===
            'vulgarity'
          ) {
            return false;
          }

          const compactLength =
            Array.from(
              row.normalized_term
                .replace(
                  /\s+/gu,
                  '',
                ),
            ).length;

          return (
            row.action ===
              'hard_block' ||
            compactLength >=
              MIN_STRICT_LEXICON_LENGTH
          );
        },
      );

    const matchedLanguages =
      [
        ...new Set(
          rows.map(
            (row) =>
              row.language_code,
          ),
        ),
      ];

    console.log(
      `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
      `detected_languages=${detectedLanguages.join(',') || 'unknown'} ` +
      `lexicon_matches=${rows.length} ` +
      `strict_blocked=${strictBlocked}`,
    );

    return {
      hardBlocked,
      strictBlocked,
      hasContextSignal,
      matchedLanguages,
      matchedTermsCount:
        rows.length,
      detectedLanguages,
      degraded: false,
    };
  } catch (error) {
    console.error(
      'Scan lexique mondial impossible :',
      error,
    );

    return {
      hardBlocked: false,
      strictBlocked: false,
      hasContextSignal: false,
      matchedLanguages: [],
      matchedTermsCount: 0,
      detectedLanguages: [],
      degraded: true,
    };
  }
}

function scanBundledProfanity(
  content: string,
): BundledProfanitySignal {
  const detectedLanguages =
    detectProjectLanguages(
      content,
    );

  const supportedLanguages =
    detectedLanguages.filter(
      (language) =>
        BUNDLED_PROFANITY_LANGUAGES.has(
          language,
        ),
    );

  if (supportedLanguages.length === 0) {
    return {
      matched: false,
      obfuscated: false,
      detectedLanguages,
    };
  }

  try {
    const directMatch =
      bundledProfanity.exists(
        content,
        supportedLanguages,
      );

    if (directMatch) {
      console.log(
        `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
        `bundled_profanity=true ` +
        `languages=${supportedLanguages.join(',')}`,
      );

      return {
        matched: true,
        obfuscated: false,
        detectedLanguages,
      };
    }

    const deLeeted =
      normalizeBasicLeet(
        content,
      );

    if (
      deLeeted !== content &&
      bundledProfanity.exists(
        deLeeted,
        supportedLanguages,
      )
    ) {
      console.log(
        `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
        `bundled_profanity=true ` +
        `languages=${supportedLanguages.join(',')} ` +
        `leet=true`,
      );

      return {
        matched: true,
        obfuscated: true,
        detectedLanguages,
      };
    }

    const collapsed =
      collapseSeparatedLetters(
        deLeeted,
      );

    const punctuationReconstructed =
      collapsed !== deLeeted;

    if (punctuationReconstructed) {
      console.log(
        `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
        `obfuscation_reconstructed=true ` +
        `languages=${supportedLanguages.join(',')}`,
      );
    }

    if (
      punctuationReconstructed &&
      bundledProfanity.exists(
        collapsed,
        supportedLanguages,
      )
    ) {
      console.log(
        `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
        `bundled_profanity=true ` +
        `languages=${supportedLanguages.join(',')} ` +
        `punctuation_obfuscation=true`,
      );

      return {
        matched: true,
        obfuscated: true,
        detectedLanguages,
      };
    }
  } catch (error) {
    console.error(
      `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
      `bundled profanity unavailable:`,
      error,
    );
  }

  return {
    matched: false,
    obfuscated: false,
    detectedLanguages,
  };
}

function collapseSeparatedLetters(
  value: string,
): string {
  // -------------------------------------------------------------------------
  // V2.4.4 — PARSEUR D'OBFUSCATION
  //
  // On n'utilise plus une regex complexe pour reconstruire les mots du type :
  //
  //   c.o.n.n.a.r.d
  //   c . o . n . n . a . r . d
  //   c-o-n-n-a-r-d
  //
  // Le parseur lit les caractères un par un.
  //
  // Une suite n'est compactée que si :
  // - elle contient au moins 4 lettres ;
  // - chaque séparation entre deux lettres contient au moins
  //   un signe de ponctuation ou un symbole.
  //
  // Ainsi, de simples espaces entre des mots normaux ne sont jamais supprimés.
  // -------------------------------------------------------------------------

  const chars =
    Array.from(
      value,
    );

  const isLetter =
    (char: string): boolean =>
      /^\p{L}$/u.test(
        char,
      );

  const isLetterOrNumber =
    (char: string): boolean =>
      /^[\p{L}\p{N}]$/u.test(
        char,
      );

  const isPunctuationOrSymbol =
    (char: string): boolean =>
      /^[\p{P}\p{S}]$/u.test(
        char,
      );

  let result = '';
  let index = 0;

  while (index < chars.length) {
    const current =
      chars[index];

    if (
      !isLetter(current) ||
      (
        index > 0 &&
        isLetterOrNumber(
          chars[index - 1],
        )
      )
    ) {
      result += current;
      index += 1;
      continue;
    }

    const letters: string[] = [
      current,
    ];

    let cursor =
      index + 1;

    let runEnd =
      index + 1;

    while (
      cursor <
      chars.length
    ) {
      const separatorStart =
        cursor;

      let separatorHasPunctuation =
        false;

      while (
        cursor <
          chars.length &&
        !isLetterOrNumber(
          chars[cursor],
        )
      ) {
        if (
          isPunctuationOrSymbol(
            chars[cursor],
          )
        ) {
          separatorHasPunctuation =
            true;
        }

        cursor += 1;
      }

      if (
        !separatorHasPunctuation ||
        cursor >=
          chars.length ||
        !isLetter(
          chars[cursor],
        )
      ) {
        cursor =
          separatorStart;
        break;
      }

      letters.push(
        chars[cursor],
      );

      cursor += 1;
      runEnd =
        cursor;
    }

    if (
      letters.length >= 4 &&
      (
        runEnd >=
          chars.length ||
        !isLetterOrNumber(
          chars[runEnd],
        )
      )
    ) {
      result +=
        letters.join('');

      index =
        runEnd;

      continue;
    }

    result += current;
    index += 1;
  }

  return result;
}

function looksLikeDirectedAbuse(
  content: string,
  detectedLanguages: string[],
): boolean {
  const normalized =
    content
      .normalize('NFKC')
      .toLowerCase();

  const languagePatterns:
    Record<string, RegExp[]> = {
    fr: [
      /\btu\b/u,
      /\btoi\b/u,
      /\bvous\b/u,
      /\bt['’]es\b/u,
      /\bt['’]est\b/u,
      /\bton\b/u,
      /\bta\b/u,
      /\btes\b/u,
    ],
    en: [
      /\byou\b/u,
      /\byou['’]?re\b/u,
      /\byoure\b/u,
      /\byour\b/u,
      /\bu\b/u,
    ],
    es: [
      /\btú\b/u,
      /\btu\b/u,
      /\beres\b/u,
      /\busted\b/u,
      /\bustedes\b/u,
      /\bvos\b/u,
      /\bsos\b/u,
    ],
    de: [
      /\bdu\b/u,
      /\bdich\b/u,
      /\bdein(?:e|er|en|em|es)?\b/u,
      /\bihr\b/u,
      /\bbist\b/u,
    ],
    it: [
      /\btu\b/u,
      /\bsei\b/u,
      /\bte\b/u,
      /\bvoi\b/u,
      /\btuo\b/u,
      /\btua\b/u,
    ],
    pt: [
      /\btu\b/u,
      /\bvocê\b/u,
      /\bvoce\b/u,
      /\bvocês\b/u,
      /\bvoces\b/u,
      /\bés\b/u,
      /\bseu\b/u,
      /\bsua\b/u,
    ],
    ru: [
      /ты/u,
      /тебя/u,
      /тебе/u,
      /твой/u,
      /вы/u,
    ],
    ar: [
      /أنت/u,
      /انت/u,
      /انتي/u,
      /أنتم/u,
      /انتم/u,
    ],
    zh: [
      /你/u,
      /妳/u,
      /你们/u,
      /你們/u,
    ],
    ja: [
      /お前/u,
      /あなた/u,
      /てめえ/u,
      /貴様/u,
    ],
    ko: [
      /너/u,
      /니가/u,
      /네가/u,
      /당신/u,
    ],
    hi: [
      /तुम/u,
      /तू/u,
      /आप/u,
      /तेरा/u,
      /तुम्हारा/u,
    ],
  };

  const patterns =
    detectedLanguages.flatMap(
      (language) =>
        languagePatterns[
          language
        ] ?? [],
    );

  // Si la détection de langue est incertaine, on garde aussi un petit
  // socle multilingue des pronoms de ciblage les plus courants.
  if (patterns.length === 0) {
    patterns.push(
      /\btu\b/u,
      /\btoi\b/u,
      /\byou\b/u,
      /\btú\b/u,
      /\bdu\b/u,
      /你/u,
      /お前/u,
      /너/u,
      /ты/u,
      /أنت/u,
      /तुम/u,
    );
  }

  const targeted =
    patterns.some(
      (pattern) =>
        pattern.test(
          normalized,
        ),
    );

  if (targeted) {
    console.log(
      `[Project XP ${MODERATION_PIPELINE_VERSION}] ` +
      `directed_abuse_heuristic=true ` +
      `languages=${detectedLanguages.join(',') || 'unknown'}`,
    );
  }

  return targeted;
}

// ============================================================================
// V2.4.6 - SLANG MODERNE / CONTOURNEMENTS
// ============================================================================

function scanModernSlangV246(
  content: string,
): ModernSlangSignal {
  const raw =
    String(
      content ?? '',
    );

  if (
    raw.trim().length === 0
  ) {
    return allowedModernSlang();
  }

  const hasMention =
    /(^|\s)@[a-z0-9_]{2,}/iu
      .test(
        raw,
      );

  const variants =
    buildModernVariants(
      raw,
    );

  for (
    const normalized
    of variants
  ) {
    if (
      normalized.length === 0
    ) {
      continue;
    }

    const directlyTargeted =
      hasMention ||
      looksModernDirectlyTargeted(
        normalized,
      );

    if (
      containsAnyModernPhrase(
        normalized,
        SELF_HARM_DIRECTIVES,
      )
    ) {
      return blockedModernSlang(
        'self_harm_directive',
      );
    }

    if (
      containsModernAbbreviation(
        normalized,
        'kys',
      ) &&
      (
        directlyTargeted ||
        isShortModernAttack(
          normalized,
        )
      )
    ) {
      return blockedModernSlang(
        'self_harm_directive',
      );
    }

    const insultingFrame =
      looksModernInsultFrame(
        normalized,
      );

    const humanTargetFrame =
      looksModernHumanTargetFrame(
        normalized,
      );

    const quotedOrExplained =
      looksModernQuotedOrExplanatoryUse(
        normalized,
      );

    const intensified =
      containsAnyModernPhrase(
        normalized,
        INTENSIFIERS,
      );

    if (
      (
        containsStrongModernFullWordInsult(
          normalized,
        ) ||
        containsContextualModernFullPhraseInsult(
          normalized,
        )
      ) &&
      !quotedOrExplained &&
      (
        directlyTargeted ||
        insultingFrame ||
        humanTargetFrame ||
        intensified ||
        isStandaloneModernContextualFullPhrase(
          normalized,
        ) ||
        isShortModernAttack(
          normalized,
        )
      )
    ) {
      return blockedModernSlang(
        'modern_slang_directed',
      );
    }

    if (
      containsContextualModernFullWordInsult(
        normalized,
      ) &&
      !quotedOrExplained &&
      (
        directlyTargeted ||
        insultingFrame ||
        humanTargetFrame ||
        intensified ||
        isShortModernAttack(
          normalized,
        )
      )
    ) {
      return blockedModernSlang(
        'modern_slang_directed',
      );
    }

    if (
      containsFrenchModernInsultGrammar(
        normalized,
        {
          directlyTargeted,
          insultingFrame,
          humanTargetFrame,
          quotedOrExplained,
        },
      )
    ) {
      return blockedModernSlang(
        'modern_slang_directed',
      );
    }

    for (
      const abbreviation
      of STRONG_ABBREVIATIONS
    ) {
      if (
        !containsModernAbbreviation(
          normalized,
          abbreviation,
        )
      ) {
        continue;
      }

      if (
        directlyTargeted ||
        insultingFrame ||
        intensified ||
        isShortModernAttack(
          normalized,
        )
      ) {
        return blockedModernSlang(
          variants.length > 1
            ? 'modern_slang_obfuscated'
            : 'modern_slang_directed',
        );
      }
    }

    const hasDirectedSlang =
      containsModernDirectedTerm(
        normalized,
      );

    if (
      hasDirectedSlang &&
      (
        directlyTargeted ||
        insultingFrame ||
        intensified
      )
    ) {
      return blockedModernSlang(
        'modern_slang_directed',
      );
    }

    const hasMildMockery =
      containsAnyModernPhrase(
        normalized,
        MODERN_MILD_MOCKERY,
      );

    if (
      hasMildMockery &&
      insultingFrame &&
      (
        directlyTargeted ||
        intensified
      )
    ) {
      return blockedModernSlang(
        'modern_slang_directed',
      );
    }
  }

  return allowedModernSlang();
}

function blockedModernSlang(
  category:
    ModernSlangSignal['category'],
): ModernSlangSignal {
  return {
    blocked: true,
    category,
  };
}

function allowedModernSlang():
  ModernSlangSignal {
  return {
    blocked: false,
    category: 'none',
  };
}

function buildModernVariants(
  input: string,
): string[] {
  const result =
    new Set<string>();

  const normalized =
    normalizeModern(
      input,
    );

  if (
    normalized.length === 0
  ) {
    return [];
  }

  result.add(
    normalized,
  );

  const repeatTwo =
    collapseModernRepeatsToTwo(
      normalized,
    );

  result.add(
    repeatTwo,
  );

  const repeatOne =
    collapseModernRepeatsToOne(
      normalized,
    );

  result.add(
    repeatOne,
  );

  result.add(
    collapseModernSeparatedLetters(
      repeatTwo,
    ),
  );

  result.add(
    collapseModernSeparatedLetters(
      repeatOne,
    ),
  );

  return [
    ...result,
  ].filter(
    (value) =>
      value.trim().length > 0,
  );
}

function normalizeModern(
  input: string,
): string {
  let value =
    input
      .normalize(
        'NFKC',
      )
      .toLowerCase()
      .normalize(
        'NFKD',
      )
      .replace(
        /[\u0300-\u036f]/gu,
        '',
      );

  value =
    Array.from(
      value,
    )
      .map(
        (character) =>
          CONFUSABLES[
            character
          ] ??
          character,
      )
      .join('');

  return value
    .replace(/0/g, 'o')
    .replace(/1/g, 'i')
    .replace(/3/g, 'e')
    .replace(/4/g, 'a')
    .replace(/5/g, 's')
    .replace(/7/g, 't')
    .replace(/@/g, 'a')
    .replace(/\$/g, 's')
    .replace(/€/g, 'e')
    .replace(
      /[^a-z0-9]+/gu,
      ' ',
    )
    .replace(
      /\s+/gu,
      ' ',
    )
    .trim();
}

function collapseModernRepeatsToTwo(
  input: string,
): string {
  return input.replace(
    /([a-z])\1{2,}/gu,
    '$1$1',
  );
}

function collapseModernRepeatsToOne(
  input: string,
): string {
  return input.replace(
    /([a-z])\1+/gu,
    '$1',
  );
}

function collapseModernSeparatedLetters(
  input: string,
): string {
  const tokens =
    input
      .split(
        /\s+/gu,
      )
      .filter(
        Boolean,
      );

  if (tokens.length < 3) {
    return input;
  }

  const output:
    string[] = [];

  let index = 0;

  while (
    index < tokens.length
  ) {
    if (
      !/^[a-z]$/u.test(
        tokens[index],
      )
    ) {
      output.push(
        tokens[index],
      );

      index += 1;
      continue;
    }

    let cursor =
      index;

    while (
      cursor <
        tokens.length &&
      /^[a-z]$/u.test(
        tokens[cursor],
      )
    ) {
      cursor += 1;
    }

    const runLength =
      cursor - index;

    if (runLength >= 3) {
      output.push(
        tokens
          .slice(
            index,
            cursor,
          )
          .join(''),
      );
    } else {
      output.push(
        ...tokens.slice(
          index,
          cursor,
        ),
      );
    }

    index =
      cursor;
  }

  return output.join(
    ' ',
  );
}

function containsAnyModernPhrase(
  normalized: string,
  phrases: Set<string>,
): boolean {
  for (
    const phrase
    of phrases
  ) {
    if (
      containsWholeModernPhrase(
        normalized,
        phrase,
      )
    ) {
      return true;
    }
  }

  return false;
}

function containsWholeModernPhrase(
  normalized: string,
  phrase: string,
): boolean {
  const cleanPhrase =
    normalizeModern(
      phrase,
    );

  if (
    cleanPhrase.length === 0
  ) {
    return false;
  }

  return (
    ` ${normalized} `
  ).includes(
    ` ${cleanPhrase} `,
  );
}

function containsModernAbbreviation(
  normalized: string,
  abbreviation: string,
): boolean {
  if (
    containsWholeModernPhrase(
      normalized,
      abbreviation,
    )
  ) {
    return true;
  }

  const letters =
    Array.from(
      abbreviation,
    )
      .map(
        escapeRegExp,
      )
      .join(
        '\\s+',
      );

  return new RegExp(
    `(?:^|\\s)${letters}(?:\\s|$)`,
    'u',
  ).test(
    normalized,
  );
}

function escapeRegExp(
  value: string,
): string {
  return value.replace(
    /[.*+?^${}()|[\]\\]/gu,
    '\\$&',
  );
}

function containsStrongModernFullWordInsult(
  normalized: string,
): boolean {
  if (
    containsAnyModernPhrase(
      normalized,
      STRONG_FULL_WORD_INSULTS,
    )
  ) {
    return true;
  }

  const patterns: RegExp[] = [
    /\bconn(?:ard|ards|asse|asses)\b/u,
    /\bsalopes?\b/u,
    /\bputes?\b/u,
    /\benfoire(?:s|e|es)?\b/u,
    /\bbatard(?:s|e|es)?\b/u,
    /\btocard(?:s|e|es)?\b/u,
    /\bcrevard(?:s|e|es)?\b/u,
    /\bordures?\b/u,
    /\bmerdeu(?:x|se|ses)\b/u,
    /\bencul(?:e|es|ee|ees)\b/u,
  ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function containsContextualModernFullWordInsult(
  normalized: string,
): boolean {
  if (
    containsAnyModernPhrase(
      normalized,
      CONTEXTUAL_FULL_WORD_INSULTS,
    )
  ) {
    return true;
  }

  const patterns: RegExp[] = [
    /\bcon(?:s|ne|nes)?\b/u,
    /\bdebiles?\b/u,
    /\bidiot(?:s|e|es)?\b/u,
    /\bcretin(?:s|e|es)?\b/u,
    /\babruti(?:s|e|es)?\b/u,
    /\bminables?\b/u,
  ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function containsContextualModernFullPhraseInsult(
  normalized: string,
): boolean {
  if (
    containsAnyModernPhrase(
      normalized,
      CONTEXTUAL_FULL_PHRASE_INSULTS,
    )
  ) {
    return true;
  }

  const patterns: RegExp[] = [
    /\bfils de putes?\b/u,
    /\bfilles? de putes?\b/u,
    /\btrous? du cul\b/u,
    /\bsacs? a merde\b/u,
    /\bsous merdes?\b/u,
  ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function isStandaloneModernContextualFullPhrase(
  normalized: string,
): boolean {
  const value =
    normalized.trim();

  const patterns: RegExp[] = [
    /^fils de putes?$/u,
    /^filles? de putes?$/u,
    /^trous? du cul$/u,
    /^sacs? a merde$/u,
    /^sous merdes?$/u,
  ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        value,
      ),
  );
}

function containsFrenchModernInsultGrammar(
  normalized: string,
  context: {
    directlyTargeted: boolean;
    insultingFrame: boolean;
    humanTargetFrame: boolean;
    quotedOrExplained: boolean;
  },
): boolean {
  if (
    context.quotedOrExplained
  ) {
    return false;
  }

  const alwaysAbusivePatterns:
    RegExp[] = [
      /\bniqu(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) (?:mere|meres|famille|darone|daronne)\b/u,
      /\bferm(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) gueules?\b/u,
      /\b(?:ta|ton|tes|votre|vos) gueules?\b/u,
      /\b(?:va|vas|allez|aller|irai|iras|irez|iront) (?:te|vous) faire foutre\b/u,
      /\b(?:va|vas|allez|aller|irai|iras|irez|iront) (?:te|vous) faire (?:enculer|niquer)\b/u,
      /\b(?:fuck you|fuck u)\b/u,
      /\b(?:t|te|vous) niqu(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient)\b/u,
      /\b(?:t|te|vous) encul(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient)\b/u,
      /\b(?:sale|gros|grosse|pauvre|espece de) (?:con|conne|connard|connasse|debile|idiot|idiote|cretin|cretine|abruti|abrutie|salope|pute|batard|batarde|tocard|tocarde|clown|bot|pnj|npc)s?\b/u,
      /\b(?:grosse?|sale) merde\b/u,
    ];

  if (
    alwaysAbusivePatterns.some(
      (pattern) =>
        pattern.test(
          normalized,
        ),
    )
  ) {
    return true;
  }

  if (
    containsContextualModernFullPhraseInsult(
      normalized,
    ) &&
    (
      context.directlyTargeted ||
      context.insultingFrame ||
      context.humanTargetFrame ||
      isStandaloneModernContextualFullPhrase(
        normalized,
      ) ||
      isShortModernAttack(
        normalized,
      )
    )
  ) {
    return true;
  }

  return false;
}

function containsModernDirectedTerm(
  normalized: string,
): boolean {
  for (
    const term
    of MODERN_DIRECTED_TERMS
  ) {
    const clean =
      normalizeModern(
        term,
      );

    if (
      clean.length === 0
    ) {
      continue;
    }

    if (
      clean.includes(
        ' ',
      )
    ) {
      if (
        containsWholeModernPhrase(
          normalized,
          clean,
        )
      ) {
        return true;
      }

      continue;
    }

    const pattern =
      new RegExp(
        `(?:^|\\s)${escapeRegExp(clean)}(?:s|es)?(?:\\s|$)`,
        'u',
      );

    if (
      pattern.test(
        normalized,
      )
    ) {
      return true;
    }
  }

  const extraPatterns:
    RegExp[] = [
      /\bbouffon(?:s|ne|nes)?\b/u,
      /\bclowns?\b/u,
      /\bgolmons?\b/u,
      /\bgolems?\b/u,
      /\bmatrixe(?:s)?\b/u,
      /\bfraudes?\b/u,
    ];

  return extraPatterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function looksModernQuotedOrExplanatoryUse(
  normalized: string,
): boolean {
  const patterns: RegExp[] = [
    /\bc est quoi\b/u,
    /\bca veut dire quoi\b/u,
    /\bque veut dire\b/u,
    /\bqu est ce que veut dire\b/u,
    /\ble mot\b/u,
    /\bl expression\b/u,
    /\bla definition\b/u,
    /\bdefinition de\b/u,
    /\bcomment on ecrit\b/u,
    /\bcomment ecrire\b/u,
    /\bcomment ca s ecrit\b/u,
    /\bexemple de\b/u,
    /\bcitation\b/u,
  ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function looksModernHumanTargetFrame(
  normalized: string,
): boolean {
  const patterns: RegExp[] = [
    /\bil (?:est|etait|sera|serait)(?: vraiment)?(?: un)?\b/u,
    /\belle (?:est|etait|sera|serait)(?: vraiment)?(?: une)?\b/u,
    /\bils (?:sont|etaient|seront|seraient)(?: vraiment)?(?: des)?\b/u,
    /\belles (?:sont|etaient|seront|seraient)(?: vraiment)?(?: des)?\b/u,
    /\bce (?:mec|gars|type|joueur|joueuse) (?:est|etait|sera|serait)\b/u,
    /\bcette (?:meuf|fille|joueuse) (?:est|etait|sera|serait)\b/u,
    /\bquel(?:le)? (?:con|conne|connard|connasse|debile|idiot|idiote|cretin|cretine|abruti|abrutie|salope|pute|batard|batarde|tocard|tocarde)\b/u,
  ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function looksModernDirectlyTargeted(
  normalized: string,
): boolean {
  const patterns:
    RegExp[] = [
      /\btu\b/u,
      /\btoi\b/u,
      /\bvous\b/u,
      /\bt es\b/u,
      /\bton\b/u,
      /\bta\b/u,
      /\btes\b/u,
      /\byou\b/u,
      /\byou are\b/u,
      /\byoure\b/u,
      /\byour\b/u,
      /\bu r\b/u,
    ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function looksModernInsultFrame(
  normalized: string,
): boolean {
  const patterns:
    RegExp[] = [
      /\bt es(?: vraiment)?(?: un| une)?\b/u,
      /\btu es(?: vraiment)?(?: un| une)?\b/u,
      /\btoi t es\b/u,
      /\bvous etes(?: un| une)?\b/u,
      /\byou are(?: a| an)?\b/u,
      /\byoure(?: a| an)?\b/u,
      /\bu r(?: a| an)?\b/u,
      /\bferm(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) gueules?\b/u,
      /\bferme la\b/u,
      /\b(?:degage|degagez)\b/u,
    ];

  return patterns.some(
    (pattern) =>
      pattern.test(
        normalized,
      ),
  );
}

function isShortModernAttack(
  normalized: string,
): boolean {
  return normalized
    .split(
      /\s+/gu,
    )
    .filter(
      Boolean,
    )
    .length <= 2;
}


// Reconnaît les familles évaluées par le moteur V2.4.6.2, même lorsque
// la décision finale est "autorisé". Cela évite que l'ancien filtre brut
// écrase ensuite une décision contextuelle déjà prise.
function isModernContextSensitiveContent(
  content: string,
): boolean {
  const variants =
    buildModernVariants(
      content,
    );

  for (
    const normalized
    of variants
  ) {
    if (
      normalized.length === 0
    ) {
      continue;
    }

    if (
      containsStrongModernFullWordInsult(
        normalized,
      ) ||
      containsContextualModernFullWordInsult(
        normalized,
      ) ||
      containsContextualModernFullPhraseInsult(
        normalized,
      ) ||
      containsModernDirectedTerm(
        normalized,
      ) ||
      containsAnyModernPhrase(
        normalized,
        MODERN_MILD_MOCKERY,
      )
    ) {
      return true;
    }

    for (
      const abbreviation
      of STRONG_ABBREVIATIONS
    ) {
      if (
        containsModernAbbreviation(
          normalized,
          abbreviation,
        )
      ) {
        return true;
      }
    }

    if (
      containsModernAbbreviation(
        normalized,
        'kys',
      ) ||
      /\b(?:niqu|encul)[a-z]{0,16}\b/u
        .test(
          normalized,
        )
    ) {
      return true;
    }
  }

  return false;
}

function isModernExplicitExplanatoryUse(
  content: string,
): boolean {
  const normalized =
    normalizeModern(
      content,
    );

  return (
    normalized.length > 0 &&
    looksModernQuotedOrExplanatoryUse(
      normalized,
    )
  );
}

function detectProjectLanguages(
  content: string,
): string[] {
  const detected =
    new Set<string>();

  // -------------------------------------------------------------------------
  // Scripts très discriminants : priorité à eux pour les messages courts.
  // -------------------------------------------------------------------------

  if (
    /\p{Script=Hiragana}|\p{Script=Katakana}/u.test(
      content,
    )
  ) {
    detected.add('ja');
  }

  if (
    /\p{Script=Hangul}/u.test(
      content,
    )
  ) {
    detected.add('ko');
  }

  if (
    /\p{Script=Han}/u.test(
      content,
    ) &&
    !detected.has(
      'ja',
    )
  ) {
    detected.add('zh');
  }

  if (
    /\p{Script=Arabic}/u.test(
      content,
    )
  ) {
    detected.add('ar');
    detected.add('fa');
  }

  if (
    /\p{Script=Devanagari}/u.test(
      content,
    )
  ) {
    detected.add('hi');
    detected.add('mr');
  }

  if (
    /\p{Script=Tamil}/u.test(
      content,
    )
  ) {
    detected.add('ta');
  }

  if (
    /\p{Script=Telugu}/u.test(
      content,
    )
  ) {
    detected.add('te');
  }

  if (
    /\p{Script=Malayalam}/u.test(
      content,
    )
  ) {
    detected.add('ml');
  }

  if (
    /\p{Script=Thai}/u.test(
      content,
    )
  ) {
    detected.add('th');
  }

  if (
    /\p{Script=Khmer}/u.test(
      content,
    )
  ) {
    detected.add('kh');
  }

  if (
    /\p{Script=Myanmar}/u.test(
      content,
    )
  ) {
    detected.add('my');
  }

  if (
    /\p{Script=Armenian}/u.test(
      content,
    )
  ) {
    detected.add('hy');
  }

  if (
    /\p{Script=Ethiopic}/u.test(
      content,
    )
  ) {
    detected.add('am');
  }

  if (
    /\p{Script=Cyrillic}/u.test(
      content,
    )
  ) {
    // franc départage généralement le cyrillique ensuite.
    // Ces deux langues sont ajoutées comme filet de sécurité.
    detected.add('ru');
    detected.add('uk');
  }

  // -------------------------------------------------------------------------
  // Détection linguistique statistique pour les langues latines et le reste.
  // francAll renvoie des codes ISO-639-3 classés par probabilité.
  // -------------------------------------------------------------------------

  try {
    const ranked =
      francAll(
        content,
        {
          minLength: 3,
        },
      );

    for (
      const [francCode]
      of ranked
    ) {
      const projectCode =
        FRANC_TO_PROJECT_LANGUAGE[
          francCode
        ];

      if (
        projectCode == null
      ) {
        continue;
      }

      detected.add(
        projectCode,
      );

      if (
        detected.size >=
        MAX_DETECTED_LANGUAGES
      ) {
        break;
      }
    }
  } catch (_) {
    // La modération reste fonctionnelle même si la détection échoue.
  }

  // -------------------------------------------------------------------------
  // Fallback conservateur pour quelques messages très courts et non ambigus.
  // On ne devine jamais une langue pour des termes universels comme "gg",
  // "ok" ou "yo" : ils restent volontairement "unknown".
  // -------------------------------------------------------------------------

  if (detected.size === 0) {
    const shortHint =
      detectShortLanguageHint(
        content,
      );

    if (shortHint != null) {
      detected.add(
        shortHint,
      );
    }
  }

  return [
    ...detected,
  ].slice(
    0,
    MAX_DETECTED_LANGUAGES,
  );
}

function detectShortLanguageHint(
  content: string,
): string | null {
  const normalized =
    content
      .normalize('NFKC')
      .toLowerCase()
      .replace(
        /[\p{P}\p{S}]+/gu,
        ' ',
      )
      .replace(
        /\s+/gu,
        ' ',
      )
      .trim();

  if (normalized.length === 0) {
    return null;
  }

  return (
    SHORT_LANGUAGE_HINTS[
      normalized
    ] ?? null
  );
}

function buildLexiconCandidates(
  content: string,
): string[] {
  const result =
    new Set<string>();

  const variants =
    new Set<string>();

  const normalized =
    normalizeLexiconText(
      content,
    );

  if (normalized.length > 0) {
    variants.add(
      normalized,
    );
  }

  const deLeeted =
    normalizeLexiconText(
      normalizeBasicLeet(
        content,
      ),
    );

  if (deLeeted.length > 0) {
    variants.add(
      deLeeted,
    );
  }

  for (const variant of variants) {
    addVariantCandidates(
      result,
      variant,
    );

    if (
      result.size >=
      MAX_LEXICON_CANDIDATES
    ) {
      break;
    }
  }

  return [
    ...result,
  ].slice(
    0,
    MAX_LEXICON_CANDIDATES,
  );
}

function addVariantCandidates(
  result: Set<string>,
  normalized: string,
): void {
  const tokens =
    normalized
      .split(/\s+/gu)
      .filter(
        (token) =>
          token.length > 0,
      );

  // Mots individuels.
  for (const token of tokens) {
    if (
      result.size >=
      MAX_LEXICON_CANDIDATES
    ) {
      return;
    }

    if (
      Array.from(token).length >= 2
    ) {
      result.add(
        token,
      );
    }

    if (
      NON_SEGMENTED_SCRIPT.test(
        token,
      )
    ) {
      addScriptNgrams(
        result,
        token,
      );
    }
  }

  // Expressions de 2 à 5 mots.
  for (
    let size = 2;
    size <= MAX_WORD_NGRAM;
    size += 1
  ) {
    for (
      let start = 0;
      start + size <= tokens.length;
      start += 1
    ) {
      if (
        result.size >=
        MAX_LEXICON_CANDIDATES
      ) {
        return;
      }

      const candidate =
        tokens
          .slice(
            start,
            start + size,
          )
          .join(' ');

      if (
        candidate.length <= 200
      ) {
        result.add(
          candidate,
        );
      }
    }
  }
}

function addScriptNgrams(
  result: Set<string>,
  token: string,
): void {
  const chars =
    Array.from(
      token,
    );

  const maxSize =
    Math.min(
      MAX_SCRIPT_NGRAM,
      chars.length,
    );

  for (
    let size = 2;
    size <= maxSize;
    size += 1
  ) {
    for (
      let start = 0;
      start + size <= chars.length;
      start += 1
    ) {
      if (
        result.size >=
        MAX_LEXICON_CANDIDATES
      ) {
        return;
      }

      result.add(
        chars
          .slice(
            start,
            start + size,
          )
          .join(''),
      );
    }
  }
}

function normalizeLexiconText(
  value: string,
): string {
  return value
    .normalize('NFKC')
    .toLowerCase()
    .replace(
      /[\p{P}\p{S}]+/gu,
      ' ',
    )
    .replace(
      /\s+/gu,
      ' ',
    )
    .trim();
}

function normalizeBasicLeet(
  value: string,
): string {
  return value
    .replace(/0/g, 'o')
    .replace(/1/g, 'i')
    .replace(/3/g, 'e')
    .replace(/4/g, 'a')
    .replace(/5/g, 's')
    .replace(/7/g, 't')
    .replace(/@/g, 'a')
    .replace(/\$/g, 's')
    .replace(/€/g, 'e');
}

async function moderateWithOpenAI(
  content: string,
): Promise<ModerationDecision> {
  if (!OPENAI_MODERATION_ENABLED) {
    return {
      blocked: false,
      safetySignal: false,
      categories: [],
      categoryScores: {},
      degraded: false,
    };
  }

  const apiKey =
    Deno.env.get(
      'OPENAI_API_KEY',
    ) ?? '';

  if (apiKey.length === 0) {
    console.error(
      'OPENAI_API_KEY absente : modération contextuelle en mode dégradé.',
    );

    return {
      blocked: false,
      safetySignal: false,
      categories: [],
      categoryScores: {},
      degraded: true,
    };
  }

  const controller =
    new AbortController();

  const timeout =
    setTimeout(
      () => controller.abort(),
      5000,
    );

  try {
    const response =
      await fetch(
        OPENAI_MODERATION_URL,
        {
          method: 'POST',
          headers: {
            Authorization:
              `Bearer ${apiKey}`,
            'Content-Type':
              'application/json',
          },
          body: JSON.stringify(
            {
              model:
                OPENAI_MODERATION_MODEL,
              input:
                content,
            },
          ),
          signal:
            controller.signal,
        },
      );

    if (!response.ok) {
      console.error(
        'OpenAI Moderation HTTP',
        response.status,
      );

      return {
        blocked: false,
        safetySignal: false,
        categories: [],
        categoryScores: {},
        degraded: true,
      };
    }

    const raw =
      await response.json();

    const result =
      raw?.results?.[0];

    const categoryMap =
      result?.categories;

    if (
      categoryMap == null ||
      typeof categoryMap !== 'object'
    ) {
      return {
        blocked: false,
        safetySignal: false,
        categories: [],
        categoryScores: {},
        degraded: true,
      };
    }

    const activeCategories =
      Object.entries(
        categoryMap as Record<string, unknown>,
      )
        .filter(
          ([, value]) =>
            value === true,
        )
        .map(
          ([key]) => key,
        );

    const rawScores =
      result?.category_scores;

    const categoryScores:
      Record<string, number> = {};

    if (
      rawScores != null &&
      typeof rawScores === 'object'
    ) {
      for (
        const [
          key,
          value,
        ] of Object.entries(
          rawScores as Record<string, unknown>,
        )
      ) {
        if (
          typeof value === 'number' &&
          Number.isFinite(value)
        ) {
          categoryScores[key] =
            value;
        }
      }
    }

    const blocked =
      activeCategories.some(
        (category) =>
          HARD_BLOCK_CATEGORIES.has(
            category,
          ),
      );

    const safetySignal =
      activeCategories.some(
        (category) =>
          SAFETY_SIGNAL_CATEGORIES.has(
            category,
          ),
      );

    return {
      blocked,
      safetySignal,
      categories:
        activeCategories,
      categoryScores,
      degraded: false,
    };
  } catch (error) {
    console.error(
      'OpenAI Moderation indisponible :',
      error,
    );

    return {
      blocked: false,
      safetySignal: false,
      categories: [],
      categoryScores: {},
      degraded: true,
    };
  } finally {
    clearTimeout(
      timeout,
    );
  }
}

async function logSafetySignalIfNeeded(
  adminClient:
    ReturnType<typeof createClient>,
  input: {
    userId: string;
    surface: string;
    content: string;
    moderation: ModerationDecision;
  },
): Promise<void> {
  if (
    !input.moderation.safetySignal
  ) {
    return;
  }

  await logModerationEvent(
    adminClient,
    {
      userId:
        input.userId,
      surface:
        input.surface,
      decision:
        'safety_signal',
      categories:
        input.moderation.categories,
      content:
        input.content,
    },
  );
}

async function logModerationEvent(
  adminClient:
    ReturnType<typeof createClient>,
  input: {
    userId: string;
    surface: string;
    decision: string;
    categories: string[];
    content: string;
  },
): Promise<void> {
  try {
    const contentHash =
      await sha256(
        input.content,
      );

    await adminClient
      .from(
        'moderation_events',
      )
      .insert(
        {
          user_id:
            input.userId,
          surface:
            input.surface,
          decision:
            input.decision,
          categories:
            [
              ...new Set(
                input.categories,
              ),
            ],
          content_sha256:
            contentHash,
        },
      );
  } catch (error) {
    console.error(
      'Log modération impossible :',
      error,
    );
  }
}

async function sha256(
  text: string,
): Promise<string> {
  const bytes =
    new TextEncoder()
      .encode(
        text,
      );

  const digest =
    await crypto.subtle.digest(
      'SHA-256',
      bytes,
    );

  return Array.from(
    new Uint8Array(
      digest,
    ),
  )
    .map(
      (value) =>
        value
          .toString(16)
          .padStart(
            2,
            '0',
          ),
    )
    .join('');
}

function rateLimitedResponse(
  retryAfterSeconds: number,
  scope: string,
): Response {
  const safeRetry =
    Math.max(
      1,
      Math.ceil(
        retryAfterSeconds,
      ),
    );

  return new Response(
    JSON.stringify(
      {
        status: 'error',
        code: 'rate_limited',
        retry_after_seconds:
          safeRetry,
        limit_scope:
          scope,
        moderation_pipeline:
          MODERATION_PIPELINE_VERSION,
      },
    ),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        'Retry-After':
          safeRetry.toString(),
      },
    },
  );
}

function blockedResponse():
  Response {
  return jsonResponse(
    {
      status: 'blocked',
      reason: 'content_policy',
      moderation_pipeline:
        MODERATION_PIPELINE_VERSION,
    },
    200,
  );
}

function cleanString(
  value: unknown,
): string {
  return value
    ?.toString()
    .trim() ?? '';
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(
    JSON.stringify(
      body,
    ),
    {
      status,
      headers:
        corsHeaders,
    },
  );
}
