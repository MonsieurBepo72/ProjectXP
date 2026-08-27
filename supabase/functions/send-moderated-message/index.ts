import { createClient } from 'npm:@supabase/supabase-js@2';
import { francAll } from 'npm:franc@6.2.0';
import { Profanity } from 'npm:@2toad/profanity@3.3.0';

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

const MAX_CONTENT_LENGTH = 2000;

const MODERATION_PIPELINE_VERSION =
  '2.4.4';

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
  // V2.2 : les quatre contrôles indépendants partent en parallèle.
  // ---------------------------------------------------------------------------

  const lexicalPromise =
    adminClient.rpc(
      'project_xp_assert_message_allowed',
      {
        p_content: content,
      },
    );

  const lexiconPromise =
    scanGlobalLexicon(
      adminClient,
      content,
    );

  // ---------------------------------------------------------------------------
  // V2.4 : OpenAI Moderation est temporairement sorti du chemin critique.
  //
  // Nos tests réels renvoient HTTP 429 et ajoutent près d'une seconde avant
  // chaque envoi. On garde la fonction dans le fichier pour pouvoir la
  // réactiver plus tard lorsque le quota/API sera réglé, mais elle n'est plus
  // appelée lors de l'envoi.
  // ---------------------------------------------------------------------------

  const moderationPromise =
    Promise.resolve<ModerationDecision>(
      {
        blocked: false,
        safetySignal: false,
        categories: [],
        categoryScores: {},
        degraded: true,
      },
    );

  const bundledProfanitySignal =
    scanBundledProfanity(
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
          lexicalBlocked:
            lexicalResult.error != null,
          bundledProfanitySignal,
          lexicon,
          moderation,
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
        lexicalBlocked:
          lexicalResult.error != null,
        bundledProfanitySignal,
        lexicon,
        moderation,
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
        moderation.degraded ||
        lexicon.degraded,
    },
    200,
  );
});

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

  if (
    input.bundledProfanitySignal.obfuscated
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

  return [
    ...detected,
  ].slice(
    0,
    MAX_DETECTED_LANGUAGES,
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
