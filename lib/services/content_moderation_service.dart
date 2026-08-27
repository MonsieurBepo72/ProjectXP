import 'supabase_service.dart';

class ContentModerationResult {
  const ContentModerationResult({
    required this.blocked,
  });

  final bool blocked;

  static const ContentModerationResult allowed =
      ContentModerationResult(
    blocked: false,
  );

  static const ContentModerationResult denied =
      ContentModerationResult(
    blocked: true,
  );
}

class ContentModerationService {
  ContentModerationService._();

  static const Duration _cacheDuration =
      Duration(
    minutes: 5,
  );

  static DateTime? _lastLoadAt;

  static List<_ModerationTerm>? _cachedTerms;

  // ===========================================================================
  // LISTE DE SECOURS
  //
  // Supabase reste la source principale afin qu'on puisse modifier la liste
  // sans republier l'application. Cette petite liste locale sert uniquement de
  // filet de sécurité si la table de modération est momentanément inaccessible.
  //
  // Elle vise des insultes identitaires très graves et volontairement peu
  // ambiguës. Les jurons ordinaires ne sont pas bloqués.
  // ===========================================================================

  static const List<_ModerationTerm> _fallbackTerms =
      <_ModerationTerm>[
    _ModerationTerm(
      'bougnoule',
      compactMatch: true,
    ),
    _ModerationTerm(
      'bicot',
      compactMatch: true,
    ),
    _ModerationTerm(
      'youpin',
      compactMatch: true,
    ),
    _ModerationTerm(
      'chinetoque',
      compactMatch: true,
    ),
    _ModerationTerm(
      'nègre',
      compactMatch: true,
    ),
    _ModerationTerm(
      'sale arabe',
      compactMatch: true,
    ),
    _ModerationTerm(
      'sale juif',
      compactMatch: true,
    ),
    _ModerationTerm(
      'sale noir',
      compactMatch: true,
    ),
    _ModerationTerm(
      'sale asiatique',
      compactMatch: true,
    ),
    _ModerationTerm(
      'pédé',
      compactMatch: false,
    ),
    _ModerationTerm(
      'gouine',
      compactMatch: true,
    ),
    _ModerationTerm(
      'nigger',
      compactMatch: true,
    ),
    _ModerationTerm(
      'nigga',
      compactMatch: true,
    ),
    _ModerationTerm(
      'faggot',
      compactMatch: true,
    ),
    _ModerationTerm(
      'kike',
      compactMatch: false,
    ),
    _ModerationTerm(
      'chink',
      compactMatch: true,
    ),
    _ModerationTerm(
      'spic',
      compactMatch: false,
    ),
    _ModerationTerm(
      'wetback',
      compactMatch: true,
    ),
    _ModerationTerm(
      'tranny',
      compactMatch: true,
    ),
    _ModerationTerm(
      'raghead',
      compactMatch: true,
    ),
  ];

  // ===========================================================================
  // CONTRÔLE
  //
  // V2.1 : le premier contrôle est 100 % local et synchrone. Il ne bloque donc
  // jamais l'affichage optimiste du message en attendant une requête réseau.
  // Le serveur reste l'autorité finale avant publication aux autres joueurs.
  // ===========================================================================

  static ContentModerationResult checkTextImmediate(
    String text,
  ) {
    return _checkTextAgainstTerms(
      text,
      _cachedTerms ?? _fallbackTerms,
    );
  }

  static Future<ContentModerationResult> checkText(
    String text,
  ) async {
    final ContentModerationResult immediate =
        checkTextImmediate(
      text,
    );

    if (immediate.blocked) {
      return immediate;
    }

    final List<_ModerationTerm> terms =
        await _loadTerms();

    return _checkTextAgainstTerms(
      text,
      terms,
    );
  }

  static Future<void> warmUp() async {
    await _loadTerms();
  }

  static ContentModerationResult _checkTextAgainstTerms(
    String text,
    List<_ModerationTerm> terms,
  ) {
    final String normalized =
        _normalize(
      text,
    );

    if (normalized.isEmpty) {
      return ContentModerationResult.allowed;
    }

    final String paddedText =
        ' $normalized ';

    final String compactText =
        normalized.replaceAll(
      ' ',
      '',
    );

    for (final _ModerationTerm term in terms) {
      final String normalizedTerm =
          _normalize(
        term.term,
      );

      if (normalizedTerm.isEmpty) {
        continue;
      }

      if (paddedText.contains(
        ' $normalizedTerm ',
      )) {
        return ContentModerationResult.denied;
      }

      if (term.compactMatch) {
        final String compactTerm =
            normalizedTerm.replaceAll(
          ' ',
          '',
        );

        if (compactTerm.length >= 5 &&
            compactText.contains(
              compactTerm,
            )) {
          return ContentModerationResult.denied;
        }
      }
    }

    return ContentModerationResult.allowed;
  }

  // ===========================================================================
  // CHARGEMENT DE LA LISTE SUPABASE
  // ===========================================================================

  static Future<List<_ModerationTerm>> _loadTerms() async {
    final DateTime now =
        DateTime.now();

    final DateTime? lastLoadAt =
        _lastLoadAt;

    final List<_ModerationTerm>? cached =
        _cachedTerms;

    if (cached != null &&
        lastLoadAt != null &&
        now.difference(
              lastLoadAt,
            ) <
            _cacheDuration) {
      return cached;
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from(
                'moderation_blocked_terms',
              )
              .select(
                'term, compact_match',
              )
              .eq(
                'active',
                true,
              );

      final List<_ModerationTerm> loaded =
          <_ModerationTerm>[];

      for (final dynamic item in response) {
        if (item is! Map) {
          continue;
        }

        final String term =
            item['term']
                    ?.toString()
                    .trim() ??
                '';

        if (term.isEmpty) {
          continue;
        }

        loaded.add(
          _ModerationTerm(
            term,
            compactMatch:
                item['compact_match'] == true,
          ),
        );
      }

      if (loaded.isNotEmpty) {
        _cachedTerms = loaded;
        _lastLoadAt = now;

        return loaded;
      }
    } catch (_) {
      // La liste locale prend le relais.
    }

    _cachedTerms =
        _fallbackTerms;

    _lastLoadAt =
        now;

    return _fallbackTerms;
  }

  // ===========================================================================
  // NORMALISATION
  //
  // - minuscules ;
  // - accents français/européens courants ;
  // - quelques substitutions "leet" ;
  // - ponctuation transformée en espaces ;
  // - espaces multiples supprimés.
  // ===========================================================================

  static String _normalize(
    String input,
  ) {
    String value =
        input.toLowerCase();

    const Map<String, String> replacements =
        <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'æ': 'ae',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'œ': 'oe',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      '0': 'o',
      '1': 'i',
      '3': 'e',
      '4': 'a',
      '5': 's',
      '7': 't',
      '@': 'a',
      r'$': 's',
      '€': 'e',
    };

    for (final MapEntry<String, String> entry
        in replacements.entries) {
      value = value.replaceAll(
        entry.key,
        entry.value,
      );
    }

    value = value.replaceAll(
      RegExp(
        r'[^a-z0-9]+',
      ),
      ' ',
    );

    value = value.replaceAll(
      RegExp(
        r'\s+',
      ),
      ' ',
    );

    return value.trim();
  }
}

class _ModerationTerm {
  const _ModerationTerm(
    this.term, {
    required this.compactMatch,
  });

  final String term;
  final bool compactMatch;
}
