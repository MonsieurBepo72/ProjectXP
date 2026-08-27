import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-project-xp-import-secret',
  'Access-Control-Allow-Methods':
    'POST, OPTIONS',
  'Content-Type':
    'application/json; charset=utf-8',
};

const IMPORTER_VERSION =
  '2.2.3';

const SOURCE_KEY =
  'ldnoobwv2';

const RAW_BASE_URL =
  'https://raw.githubusercontent.com/LDNOOBWV2/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words_V2/main/data';

const LANGUAGE_CODES =
  ["af","sq","dz","am","ar","hy","rop","az","eu","be","bg","my","kh","ca","ceb","zh","hr","cs","da","nl","en","eo","et","fil","fi","fr","gd","gl","de","el","yid","hi","hu","is","it","id","ja","kab","tlh","ko","la","lv","lt","mk","ms","ml","mt","mi","mr","mn","no","fa","pih","piy","pl","pt","ro","ru","sm","sr","sk","sl","es","sv","ta","te","tet","th","to","tr","uk","uz","vi","cy","zu"];

const LANGUAGES_PER_RUN = 5;

const UPSERT_BATCH_SIZE = 700;
const UPSERT_CONCURRENCY = 4;
const MAX_TERM_LENGTH = 200;

type LexiconRow = {
  source_key: string;
  language_code: string;
  term: string;
  normalized_term: string;
  action: 'context';
  active: true;
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(
      'ok',
      {
        headers: CORS_HEADERS,
      },
    );
  }

  if (req.method !== 'POST') {
    return jsonResponse(
      {
        status: 'error',
        code: 'method_not_allowed',
        importer_version:
          IMPORTER_VERSION,
      },
      405,
    );
  }

  const supabaseUrl =
    Deno.env.get('SUPABASE_URL') ?? '';

  const serviceRoleKey =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (
    supabaseUrl.length === 0 ||
    serviceRoleKey.length === 0
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'server_configuration',
        importer_version:
          IMPORTER_VERSION,
      },
      500,
    );
  }

  // -------------------------------------------------------------------------
  // SECRET ADMIN DÉDIÉ À CET IMPORT ONE-SHOT
  // -------------------------------------------------------------------------

  const expectedImportSecret =
    Deno.env.get(
      'MODERATION_IMPORT_SECRET',
    ) ?? '';

  const providedImportSecret =
    req.headers.get(
      'x-project-xp-import-secret',
    ) ?? '';

  if (
    expectedImportSecret.length < 24 ||
    providedImportSecret.length === 0 ||
    !safeEqual(
      expectedImportSecret,
      providedImportSecret,
    )
  ) {
    return jsonResponse(
      {
        status: 'error',
        code: 'admin_import_secret_required',
        importer_version:
          IMPORTER_VERSION,
      },
      401,
    );
  }

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
    data: sourceRow,
    error: sourceError,
  } =
    await adminClient
      .from(
        'moderation_lexicon_sources',
      )
      .select(
        'source_key, import_enabled, imported_at, term_count, language_count, imported_languages',
      )
      .eq(
        'source_key',
        SOURCE_KEY,
      )
      .maybeSingle();

  if (
    sourceError != null ||
    sourceRow == null
  ) {
    console.error(
      'V2.2.3 source row missing:',
      sourceError?.message,
    );

    return jsonResponse(
      {
        status: 'error',
        code: 'foundation_or_progress_patch_missing',
        importer_version:
          IMPORTER_VERSION,
      },
      200,
    );
  }

  if (sourceRow.import_enabled !== true) {
    return jsonResponse(
      {
        status: 'already_imported',
        importer_version:
          IMPORTER_VERSION,
        imported_at:
          sourceRow.imported_at,
        term_count:
          sourceRow.term_count,
        language_count:
          sourceRow.language_count,
      },
      200,
    );
  }

  const completedLanguages =
    new Set<string>(
      Array.isArray(
        sourceRow.imported_languages,
      )
        ? sourceRow.imported_languages
            .map(
              (value: unknown) =>
                String(value),
            )
        : [],
    );

  const pendingLanguages =
    LANGUAGE_CODES.filter(
      (languageCode) =>
        !completedLanguages.has(
          languageCode,
        ),
    );

  if (pendingLanguages.length === 0) {
    return await finalizeImport(
      adminClient,
      completedLanguages,
    );
  }

  const languagesThisRun =
    pendingLanguages.slice(
      0,
      LANGUAGES_PER_RUN,
    );

  const importedThisRun:
    Array<Record<string, unknown>> = [];

  for (
    const languageCode
    of languagesThisRun
  ) {
    try {
      console.log(
        `[${IMPORTER_VERSION}] downloading ${languageCode}`,
      );

      const text =
        await fetchLanguageFile(
          languageCode,
        );

      const rows =
        parseLanguageFile(
          languageCode,
          text,
        );

      console.log(
        `[${IMPORTER_VERSION}] ${languageCode}: ${rows.length} prepared terms`,
      );

      await upsertRows(
        adminClient,
        rows,
      );

      completedLanguages.add(
        languageCode,
      );

      const progressLanguages =
        LANGUAGE_CODES.filter(
          (code) =>
            completedLanguages.has(
              code,
            ),
        );

      const {
        error: progressError,
      } =
        await adminClient
          .from(
            'moderation_lexicon_sources',
          )
          .update(
            {
              imported_languages:
                progressLanguages,
              language_count:
                progressLanguages.length,
              updated_at:
                new Date().toISOString(),
            },
          )
          .eq(
            'source_key',
            SOURCE_KEY,
          );

      if (progressError != null) {
        throw new Error(
          `progress_failed:${progressError.message}`,
        );
      }

      importedThisRun.push(
        {
          language:
            languageCode,
          prepared_terms:
            rows.length,
        },
      );

      console.log(
        `[${IMPORTER_VERSION}] ${languageCode}: persisted (${progressLanguages.length}/${LANGUAGE_CODES.length})`,
      );
    } catch (error) {
      console.error(
        `[${IMPORTER_VERSION}] language ${languageCode} failed:`,
        error,
      );

      return jsonResponse(
        {
          status: 'partial_error',
          importer_version:
            IMPORTER_VERSION,
          failed_language:
            languageCode,
          imported_this_run:
            importedThisRun,
          languages_done:
            completedLanguages.size,
          languages_total:
            LANGUAGE_CODES.length,
          remaining_languages:
            LANGUAGE_CODES.length -
            completedLanguages.size,
        },
        200,
      );
    }
  }

  if (
    completedLanguages.size ===
    LANGUAGE_CODES.length
  ) {
    return await finalizeImport(
      adminClient,
      completedLanguages,
      importedThisRun,
    );
  }

  return jsonResponse(
    {
      status: 'partial',
      importer_version:
        IMPORTER_VERSION,
      imported_this_run:
        importedThisRun,
      languages_done:
        completedLanguages.size,
      languages_total:
        LANGUAGE_CODES.length,
      remaining_languages:
        LANGUAGE_CODES.length -
        completedLanguages.size,
      instruction:
        'Relancer exactement la même requête pour continuer.',
    },
    200,
  );
});

async function finalizeImport(
  adminClient:
    ReturnType<typeof createClient>,
  completedLanguages: Set<string>,
  importedThisRun:
    Array<Record<string, unknown>> = [],
): Promise<Response> {
  const {
    count,
    error: countError,
  } =
    await adminClient
      .from(
        'moderation_global_lexicon',
      )
      .select(
        'id',
        {
          count: 'exact',
          head: true,
        },
      )
      .eq(
        'source_key',
        SOURCE_KEY,
      );

  if (countError != null) {
    console.error(
      `[${IMPORTER_VERSION}] final count failed:`,
      countError.message,
    );

    return jsonResponse(
      {
        status: 'error',
        code: 'final_count_failed',
        importer_version:
          IMPORTER_VERSION,
      },
      200,
    );
  }

  const storedCount =
    count ?? 0;

  const {
    error: finalizeError,
  } =
    await adminClient
      .from(
        'moderation_lexicon_sources',
      )
      .update(
        {
          import_enabled:
            false,
          imported_at:
            new Date().toISOString(),
          term_count:
            storedCount,
          language_count:
            completedLanguages.size,
          imported_languages:
            LANGUAGE_CODES,
          updated_at:
            new Date().toISOString(),
        },
      )
      .eq(
        'source_key',
        SOURCE_KEY,
      );

  if (finalizeError != null) {
    console.error(
      `[${IMPORTER_VERSION}] finalize failed:`,
      finalizeError.message,
    );

    return jsonResponse(
      {
        status: 'error',
        code: 'finalize_failed',
        importer_version:
          IMPORTER_VERSION,
      },
      200,
    );
  }

  console.log(
    `[${IMPORTER_VERSION}] import complete: ${storedCount} terms / ${completedLanguages.size} languages`,
  );

  return jsonResponse(
    {
      status: 'imported',
      importer_version:
        IMPORTER_VERSION,
      source:
        SOURCE_KEY,
      stored_terms:
        storedCount,
      languages:
        completedLanguages.size,
      imported_this_run:
        importedThisRun,
    },
    200,
  );
}

async function fetchLanguageFile(
  languageCode: string,
): Promise<string> {
  const url =
    `${RAW_BASE_URL}/${languageCode}.txt`;

  let lastError:
    unknown = null;

  for (
    let attempt = 1;
    attempt <= 3;
    attempt += 1
  ) {
    const controller =
      new AbortController();

    const timeout =
      setTimeout(
        () => controller.abort(),
        12000,
      );

    try {
      const response =
        await fetch(
          url,
          {
            signal:
              controller.signal,
            headers: {
              'User-Agent':
                'Project-XP-Moderation-V2.2.3',
            },
          },
        );

      if (!response.ok) {
        throw new Error(
          `HTTP ${response.status}`,
        );
      }

      return await response.text();
    } catch (error) {
      lastError = error;

      if (attempt < 3) {
        await sleep(
          350 * attempt,
        );
      }
    } finally {
      clearTimeout(
        timeout,
      );
    }
  }

  throw new Error(
    `download_failed:${languageCode}:${String(lastError)}`,
  );
}

function parseLanguageFile(
  languageCode: string,
  text: string,
): LexiconRow[] {
  const uniqueRows =
    new Map<string, LexiconRow>();

  for (
    const rawLine
    of text.split(/\r?\n/u)
  ) {
    const term =
      rawLine
        .replace(
          /^\uFEFF/u,
          '',
        )
        .trim();

    if (
      term.length === 0 ||
      term.startsWith('#') ||
      term.length > MAX_TERM_LENGTH
    ) {
      continue;
    }

    const normalizedTerm =
      normalizeLexiconText(
        term,
      );

    if (
      normalizedTerm.length === 0 ||
      Array.from(
        normalizedTerm
          .replace(/\s+/gu, ''),
      ).length < 2
    ) {
      continue;
    }

    if (
      !uniqueRows.has(
        normalizedTerm,
      )
    ) {
      uniqueRows.set(
        normalizedTerm,
        {
          source_key:
            SOURCE_KEY,
          language_code:
            languageCode,
          term,
          normalized_term:
            normalizedTerm,

          // La source mondiale reste un signal contextuel par défaut.
          // Aucun terme externe n'est transformé aveuglément en hard-block.
          action:
            'context',
          active:
            true,
        },
      );
    }
  }

  return [
    ...uniqueRows.values(),
  ];
}

async function upsertRows(
  adminClient:
    ReturnType<typeof createClient>,
  rows: LexiconRow[],
): Promise<void> {
  const chunks:
    LexiconRow[][] = [];

  for (
    let index = 0;
    index < rows.length;
    index += UPSERT_BATCH_SIZE
  ) {
    chunks.push(
      rows.slice(
        index,
        index + UPSERT_BATCH_SIZE,
      ),
    );
  }

  for (
    let offset = 0;
    offset < chunks.length;
    offset += UPSERT_CONCURRENCY
  ) {
    const group =
      chunks.slice(
        offset,
        offset + UPSERT_CONCURRENCY,
      );

    const results =
      await Promise.all(
        group.map(
          (chunk) =>
            adminClient
              .from(
                'moderation_global_lexicon',
              )
              .upsert(
                chunk,
                {
                  onConflict:
                    'source_key,language_code,normalized_term',
                  ignoreDuplicates:
                    true,
                },
              ),
        ),
      );

    for (
      const result
      of results
    ) {
      if (result.error != null) {
        throw new Error(
          `upsert_failed:${result.error.message}`,
        );
      }
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

function safeEqual(
  expected: string,
  provided: string,
): boolean {
  const encoder =
    new TextEncoder();

  const expectedBytes =
    encoder.encode(
      expected,
    );

  const providedBytes =
    encoder.encode(
      provided,
    );

  const maxLength =
    Math.max(
      expectedBytes.length,
      providedBytes.length,
    );

  let difference =
    expectedBytes.length ^
    providedBytes.length;

  for (
    let index = 0;
    index < maxLength;
    index += 1
  ) {
    const a =
      index < expectedBytes.length
        ? expectedBytes[index]
        : 0;

    const b =
      index < providedBytes.length
        ? providedBytes[index]
        : 0;

    difference |=
      a ^ b;
  }

  return difference === 0;
}

function sleep(
  milliseconds: number,
): Promise<void> {
  return new Promise(
    (resolve) => {
      setTimeout(
        resolve,
        milliseconds,
      );
    },
  );
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
        CORS_HEADERS,
    },
  );
}
