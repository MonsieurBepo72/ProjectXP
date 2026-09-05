export type LexicalRpcDecision = {
  blocked: boolean;
  degraded: boolean;
  code: string;
};

type LexicalRpcErrorLike = {
  code?: unknown;
  message?: unknown;
  details?: unknown;
  hint?: unknown;
};

const BLOCK_SIGNAL =
  'PROJECT_XP_CONTENT_BLOCKED';

export function classifyLexicalRpcError(
  error: unknown,
): LexicalRpcDecision {
  if (error == null) {
    return {
      blocked: false,
      degraded: false,
      code: '',
    };
  }

  const candidate =
    typeof error === 'object'
      ? error as LexicalRpcErrorLike
      : {};

  const code =
    cleanText(candidate.code);

  const diagnosticText = [
    cleanText(candidate.message),
    cleanText(candidate.details),
    cleanText(candidate.hint),
    error instanceof Error
      ? error.message.trim()
      : typeof error === 'string'
        ? error.trim()
        : '',
  ]
    .filter((value) => value.length > 0)
    .join(' | ');

  const blocked =
    code === 'P0001' &&
    diagnosticText.includes(
      BLOCK_SIGNAL,
    );

  return {
    blocked,
    degraded: !blocked,
    code,
  };
}

function cleanText(
  value: unknown,
): string {
  return typeof value === 'string'
    ? value.trim()
    : '';
}
