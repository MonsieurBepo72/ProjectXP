import {
  classifyLexicalRpcError,
} from './lexical_guard.ts';

function assertDecision(
  input: unknown,
  expectedBlocked: boolean,
  expectedDegraded: boolean,
  label: string,
): void {
  const actual =
    classifyLexicalRpcError(input);

  if (
    actual.blocked !== expectedBlocked ||
    actual.degraded !== expectedDegraded
  ) {
    throw new Error(
      `${label}: blocked=${actual.blocked}, degraded=${actual.degraded}`,
    );
  }
}

Deno.test(
  'lexical guard - vrai signal SQL volontaire',
  () => {
    assertDecision(
      {
        code: 'P0001',
        message: 'PROJECT_XP_CONTENT_BLOCKED',
      },
      true,
      false,
      'signal volontaire',
    );
  },
);

Deno.test(
  'lexical guard - signal présent dans un message enrichi',
  () => {
    assertDecision(
      {
        code: 'P0001',
        message: 'RPC failed: PROJECT_XP_CONTENT_BLOCKED',
      },
      true,
      false,
      'message enrichi',
    );
  },
);

Deno.test(
  'lexical guard - autre P0001 = dégradé, pas bloqué',
  () => {
    assertDecision(
      {
        code: 'P0001',
        message: 'AUTRE_ERREUR_METIER',
      },
      false,
      true,
      'autre P0001',
    );
  },
);

Deno.test(
  'lexical guard - erreur PostgREST = dégradé',
  () => {
    assertDecision(
      {
        code: 'PGRST202',
        message: 'Function unavailable',
      },
      false,
      true,
      'PostgREST',
    );
  },
);

Deno.test(
  'lexical guard - mauvais code malgré le signal = dégradé',
  () => {
    assertDecision(
      {
        code: 'XX000',
        message: 'PROJECT_XP_CONTENT_BLOCKED',
      },
      false,
      true,
      'mauvais code',
    );
  },
);

Deno.test(
  'lexical guard - exception réseau = dégradé',
  () => {
    assertDecision(
      new Error('network timeout'),
      false,
      true,
      'réseau',
    );
  },
);

Deno.test(
  'lexical guard - aucune erreur = nominal',
  () => {
    assertDecision(
      null,
      false,
      false,
      'aucune erreur',
    );
  },
);
