import 'dart:async';

import 'package:flutter/material.dart';

import 'project_xp_communicator_ui_service.dart';
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

  // Le SnackBar standard de Flutter reste plusieurs secondes à l'écran.
  // Pour un refus de modération, Project XP le retire rapidement afin de
  // prévenir le joueur sans masquer inutilement la conversation.
  static const Duration _blockedSnackBarVisibleDuration =
      Duration(
    milliseconds: 1100,
  );

  static Timer? _blockedSnackBarDismissTimer;

  static ContentModerationResult _blockedResult() {
    _scheduleBlockedSnackBarDismissal();

    return ContentModerationResult.denied;
  }

  static void _scheduleBlockedSnackBarDismissal() {
    _blockedSnackBarDismissTimer?.cancel();

    _blockedSnackBarDismissTimer = Timer(
      _blockedSnackBarVisibleDuration,
      () {
        final BuildContext? context =
            projectXpNavigatorKey.currentContext;

        if (context == null) {
          return;
        }

        ScaffoldMessenger.maybeOf(
          context,
        )?.hideCurrentSnackBar();
      },
    );
  }

  // ===========================================================================
  // PROJECT XP MODERATION V2.4.6.2
  //
  // - conserve le filet de sécurité V2.4.5 ;
  // - détecte le slang moderne uniquement lorsqu'il devient une attaque ;
  // - détecte plusieurs contournements simples : leet, répétitions, lettres
  //   séparées et quelques homoglyphes Unicode fréquents ;
  // - évite de bloquer le slang neutre ("rizz", "slay", "banger", etc.) ;
  // - Supabase et l'Edge Function restent l'autorité finale.
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

  static const Set<String> _modernDirectedTerms =
      <String>{
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
  };

  static const Set<String> _mildModernMockery =
      <String>{
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
  };

  static const Set<String> _strongAbbreviations =
      <String>{
    'fdp',
    'ntm',
    'ftg',
    'tg',
    'vtff',
    'stfu',
  };

  static const Set<String> _criticalSelfHarmPhrases =
      <String>{
    'kill yourself',
    'go kill yourself',
    'suicide toi',
    'suicidez vous',
    'tue toi',
    'tuez vous',
    'va te pendre',
    'vas te pendre',
    'allez vous pendre',
  };


  // Insultes fortes peu ambiguës : elles sont bloquées même écrites
  // normalement, avec féminin/pluriel gérés par les expressions plus bas.
  static const Set<String> _strongFullWordInsults =
      <String>{
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
  };

  // Termes plus ambigus : on les bloque lorsqu'ils sont adressés à quelqu'un,
  // intégrés à une tournure insultante ou envoyés seuls comme attaque.
  static const Set<String> _contextualFullWordInsults =
      <String>{
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
  };

  static const Set<String> _contextualFullPhraseInsults =
      <String>{
    'fils de pute',
    'fille de pute',
    'trou du cul',
    'sac a merde',
    'sous merde',
  };

  static ContentModerationResult checkTextImmediate(
    String text,
  ) {
    if (_isModernSlangBlocked(text)) {
      return _blockedResult();
    }

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
        if (_shouldIgnoreContextualLexiconMatch(
          normalized,
          normalizedTerm,
        )) {
          continue;
        }

        return _blockedResult();
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
          if (_shouldIgnoreContextualLexiconMatch(
            normalized,
            normalizedTerm,
          )) {
            continue;
          }

          return _blockedResult();
        }
      }
    }

    return ContentModerationResult.allowed;
  }

  // ---------------------------------------------------------------------------
  // V2.4.6.2 - Contexte, mots complets, accords et conjugaisons.
  // ---------------------------------------------------------------------------

  static bool _isModernSlangBlocked(
    String input,
  ) {
    if (input.trim().isEmpty) {
      return false;
    }

    final bool hasMention =
        RegExp(
      r'(^|\s)@[a-zA-Z0-9_]{2,}',
      caseSensitive: false,
    ).hasMatch(
      input,
    );

    final List<String> variants =
        _modernVariants(
      input,
    );

    for (final String normalized in variants) {
      if (normalized.isEmpty) {
        continue;
      }

      final bool directTarget =
          hasMention ||
          _looksDirectlyTargeted(
            normalized,
          );

      if (_containsAnyPhrase(
        normalized,
        _criticalSelfHarmPhrases,
      )) {
        return true;
      }

      if (_containsAbbreviation(
            normalized,
            'kys',
          ) &&
          (directTarget ||
              _isShortStandaloneAttack(
                normalized,
              ))) {
        return true;
      }

      final bool insultingFrame =
          _looksLikeInsultFrame(
            normalized,
          );

      final bool humanTargetFrame =
          _looksLikeHumanTargetFrame(
        normalized,
      );

      final bool quotedOrExplained =
          _looksLikeQuotedOrExplanatoryUse(
        normalized,
      );

      final bool intensified =
          _containsAnyPhrase(
        normalized,
        const <String>{
          'sale',
          'gros',
          'grosse',
          'espece de',
          'pauvre',
          'putain de',
          'vieux',
          'vieille',
        },
      );

      if ((_containsStrongFullWordInsult(
                normalized,
              ) ||
              _containsContextualFullPhraseInsult(
                normalized,
              )) &&
          !quotedOrExplained &&
          (directTarget ||
              insultingFrame ||
              humanTargetFrame ||
              intensified ||
              _isStandaloneContextualFullPhrase(
                normalized,
              ) ||
              _isShortStandaloneAttack(
                normalized,
              ))) {
        return true;
      }

      if (_containsContextualFullWordInsult(
            normalized,
          ) &&
          !quotedOrExplained &&
          (directTarget ||
              insultingFrame ||
              humanTargetFrame ||
              intensified ||
              _isShortStandaloneAttack(
                normalized,
              ))) {
        return true;
      }

      if (_containsFrenchInsultGrammar(
        normalized,
        directTarget: directTarget,
        insultingFrame: insultingFrame,
        humanTargetFrame: humanTargetFrame,
        quotedOrExplained: quotedOrExplained,
      )) {
        return true;
      }

      for (final String abbreviation
          in _strongAbbreviations) {
        if (!_containsAbbreviation(
          normalized,
          abbreviation,
        )) {
          continue;
        }

        if (directTarget ||
            insultingFrame ||
            intensified ||
            _isShortStandaloneAttack(
              normalized,
            )) {
          return true;
        }
      }

      final bool hasDirectedSlang =
          _containsModernDirectedTerm(
        normalized,
      );

      if (hasDirectedSlang &&
          (directTarget ||
              insultingFrame ||
              intensified)) {
        return true;
      }

      final bool hasMildMockery =
          _containsAnyPhrase(
        normalized,
        _mildModernMockery,
      );

      if (hasMildMockery &&
          insultingFrame &&
          (directTarget || intensified)) {
        return true;
      }
    }

    return false;
  }

  static List<String> _modernVariants(
    String input,
  ) {
    final Set<String> result =
        <String>{};

    final String normalized =
        _normalizeModern(
      input,
    );

    if (normalized.isNotEmpty) {
      result.add(
        normalized,
      );

      final String repeated =
          _collapseExcessiveRepeats(
        normalized,
      );

      result.add(
        repeated,
      );

      result.add(
        _collapseSeparatedLetterRuns(
          repeated,
        ),
      );
    }

    return result
        .where(
          (String value) =>
              value.trim().isNotEmpty,
        )
        .toList(
          growable: false,
        );
  }

  static String _normalizeModern(
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

      // Homoglyphes Unicode courants utilisés pour contourner les filtres.
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

  static String _collapseExcessiveRepeats(
    String input,
  ) {
    return input.replaceAllMapped(
      RegExp(
        r'([a-z])\1{2,}',
      ),
      (Match match) {
        final String character =
            match.group(1) ?? '';

        return '$character$character';
      },
    );
  }

  static String _collapseSeparatedLetterRuns(
    String input,
  ) {
    final List<String> tokens =
        input
            .split(
              RegExp(
                r'\s+',
              ),
            )
            .where(
              (String token) =>
                  token.isNotEmpty,
            )
            .toList();

    if (tokens.length < 3) {
      return input;
    }

    final List<String> output =
        <String>[];

    int index = 0;

    while (index < tokens.length) {
      if (!_isSingleAsciiLetter(
        tokens[index],
      )) {
        output.add(
          tokens[index],
        );
        index += 1;
        continue;
      }

      int cursor = index;

      while (cursor < tokens.length &&
          _isSingleAsciiLetter(
            tokens[cursor],
          )) {
        cursor += 1;
      }

      final int runLength =
          cursor - index;

      if (runLength >= 3) {
        output.add(
          tokens
              .sublist(
                index,
                cursor,
              )
              .join(),
        );
      } else {
        output.addAll(
          tokens.sublist(
            index,
            cursor,
          ),
        );
      }

      index = cursor;
    }

    return output.join(' ');
  }

  static bool _isSingleAsciiLetter(
    String value,
  ) {
    return RegExp(
      r'^[a-z]$',
    ).hasMatch(
      value,
    );
  }

  static bool _containsAnyPhrase(
    String normalized,
    Set<String> phrases,
  ) {
    for (final String phrase in phrases) {
      if (_containsWholePhrase(
        normalized,
        phrase,
      )) {
        return true;
      }
    }

    return false;
  }

  static bool _containsWholePhrase(
    String normalized,
    String phrase,
  ) {
    final String cleanPhrase =
        _normalizeModern(
      phrase,
    );

    if (cleanPhrase.isEmpty) {
      return false;
    }

    return ' $normalized '.contains(
      ' $cleanPhrase ',
    );
  }

  static bool _containsAbbreviation(
    String normalized,
    String abbreviation,
  ) {
    if (_containsWholePhrase(
      normalized,
      abbreviation,
    )) {
      return true;
    }

    final String letters =
        abbreviation
            .split('')
            .map(
              RegExp.escape,
            )
            .join(
              r'\s+',
            );

    return RegExp(
      '(?:^|\\s)$letters(?:\\s|\$)',
    ).hasMatch(
      normalized,
    );
  }

  static bool _containsStrongFullWordInsult(
    String normalized,
  ) {
    if (_containsAnyPhrase(
      normalized,
      _strongFullWordInsults,
    )) {
      return true;
    }

    final List<RegExp> patterns =
        <RegExp>[
      // Féminins / pluriels / variantes orthographiques normalisées.
      RegExp(r'\bconn(?:ard|ards|asse|asses)\b'),
      RegExp(r'\bsalopes?\b'),
      RegExp(r'\bputes?\b'),
      RegExp(r'\benfoire(?:s|e|es)?\b'),
      RegExp(r'\bbatard(?:s|e|es)?\b'),
      RegExp(r'\btocard(?:s|e|es)?\b'),
      RegExp(r'\bcrevard(?:s|e|es)?\b'),
      RegExp(r'\bordures?\b'),
      RegExp(r'\bmerdeu(?:x|se|ses)\b'),

      // "enculé / enculée / enculés / enculées" et le verbe "encule".
      // La normalisation retire l'accent, donc ces formes convergent ici.
      RegExp(r'\bencul(?:e|es|ee|ees)\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _containsContextualFullWordInsult(
    String normalized,
  ) {
    if (_containsAnyPhrase(
      normalized,
      _contextualFullWordInsults,
    )) {
      return true;
    }

    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\bcon(?:s|ne|nes)?\b'),
      RegExp(r'\bdebiles?\b'),
      RegExp(r'\bidiot(?:s|e|es)?\b'),
      RegExp(r'\bcretin(?:s|e|es)?\b'),
      RegExp(r'\babruti(?:s|e|es)?\b'),
      RegExp(r'\bminables?\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _containsContextualFullPhraseInsult(
    String normalized,
  ) {
    if (_containsAnyPhrase(
      normalized,
      _contextualFullPhraseInsults,
    )) {
      return true;
    }

    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\bfils de putes?\b'),
      RegExp(r'\bfilles? de putes?\b'),
      RegExp(r'\btrous? du cul\b'),
      RegExp(r'\bsacs? a merde\b'),
      RegExp(r'\bsous merdes?\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _isStandaloneContextualFullPhrase(
    String normalized,
  ) {
    final String value =
        normalized.trim();

    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'^fils de putes?$'),
      RegExp(r'^filles? de putes?$'),
      RegExp(r'^trous? du cul$'),
      RegExp(r'^sacs? a merde$'),
      RegExp(r'^sous merdes?$'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        value,
      ),
    );
  }

  static bool _containsFrenchInsultGrammar(
    String normalized, {
    required bool directTarget,
    required bool insultingFrame,
    required bool humanTargetFrame,
    required bool quotedOrExplained,
  }) {
    if (quotedOrExplained) {
      return false;
    }

    final List<RegExp> alwaysAbusivePatterns =
        <RegExp>[
      // Insultes explicitement dirigées vers la famille / personne.
      RegExp(r'\bniqu(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) (?:mere|meres|famille|darone|daronne)\b'),
      RegExp(r'\bferm(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) gueules?\b'),
      RegExp(r'\b(?:ta|ton|tes|votre|vos) gueules?\b'),
      RegExp(r'\b(?:va|vas|allez|aller|irai|iras|irez|iront) (?:te|vous) faire foutre\b'),
      RegExp(r'\b(?:va|vas|allez|aller|irai|iras|irez|iront) (?:te|vous) faire (?:enculer|niquer)\b'),
      RegExp(r'\b(?:fuck you|fuck u)\b'),

      // Verbes directement adressés à quelqu'un, avec conjugaisons.
      RegExp(r'\b(?:t|te|vous) niqu(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient)\b'),
      RegExp(r'\b(?:t|te|vous) encul(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient)\b'),

      // Constructions insultantes explicites.
      RegExp(r'\b(?:sale|gros|grosse|pauvre|espece de) (?:con|conne|connard|connasse|debile|idiot|idiote|cretin|cretine|abruti|abrutie|salope|pute|batard|batarde|tocard|tocarde|clown|bot|pnj|npc)s?\b'),
      RegExp(r'\b(?:grosse?|sale) merde\b'),
    ];

    if (alwaysAbusivePatterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    )) {
      return true;
    }

    // Les noms insultants restent contextuels : "fils de pute" seul ou
    // adressé à quelqu'un est bloqué, mais "c'est quoi fils de pute ?"
    // reste une utilisation explicative.
    if (_containsContextualFullPhraseInsult(
          normalized,
        ) &&
        (directTarget ||
            insultingFrame ||
            humanTargetFrame ||
            _isStandaloneContextualFullPhrase(
              normalized,
            ) ||
            _isShortStandaloneAttack(
              normalized,
            ))) {
      return true;
    }

    return false;
  }

  static bool _containsModernDirectedTerm(
    String normalized,
  ) {
    for (final String term
        in _modernDirectedTerms) {
      final String clean =
          _normalizeModern(
        term,
      );

      if (clean.isEmpty) {
        continue;
      }

      if (clean.contains(' ')) {
        if (_containsWholePhrase(
          normalized,
          clean,
        )) {
          return true;
        }

        continue;
      }

      final RegExp pattern =
          RegExp(
        '(?:^|\\s)${RegExp.escape(clean)}(?:s|es)?(?:\\s|\$)',
      );

      if (pattern.hasMatch(
        normalized,
      )) {
        return true;
      }
    }

    // Quelques féminins irréguliers.
    final List<RegExp> extraPatterns =
        <RegExp>[
      RegExp(r'\bbouffon(?:s|ne|nes)?\b'),
      RegExp(r'\bclowns?\b'),
      RegExp(r'\bgolmons?\b'),
      RegExp(r'\bgolems?\b'),
      RegExp(r'\bmatrixe(?:s)?\b'),
      RegExp(r'\bfraudes?\b'),
    ];

    return extraPatterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _looksLikeQuotedOrExplanatoryUse(
    String normalized,
  ) {
    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\bc est quoi\b'),
      RegExp(r'\bca veut dire quoi\b'),
      RegExp(r'\bque veut dire\b'),
      RegExp(r'\bqu est ce que veut dire\b'),
      RegExp(r'\ble mot\b'),
      RegExp(r'\bl expression\b'),
      RegExp(r'\bla definition\b'),
      RegExp(r'\bdefinition de\b'),
      RegExp(r'\bcomment on ecrit\b'),
      RegExp(r'\bcomment ecrire\b'),
      RegExp(r'\bcomment ca s ecrit\b'),
      RegExp(r'\bexemple de\b'),
      RegExp(r'\bcitation\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _looksLikeHumanTargetFrame(
    String normalized,
  ) {
    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\bil (?:est|etait|sera|serait)(?: vraiment)?(?: un)?\b'),
      RegExp(r'\belle (?:est|etait|sera|serait)(?: vraiment)?(?: une)?\b'),
      RegExp(r'\bils (?:sont|etaient|seront|seraient)(?: vraiment)?(?: des)?\b'),
      RegExp(r'\belles (?:sont|etaient|seront|seraient)(?: vraiment)?(?: des)?\b'),
      RegExp(r'\bce (?:mec|gars|type|joueur|joueuse) (?:est|etait|sera|serait)\b'),
      RegExp(r'\bcette (?:meuf|fille|joueuse) (?:est|etait|sera|serait)\b'),
      RegExp(r'\bquel(?:le)? (?:con|conne|connard|connasse|debile|idiot|idiote|cretin|cretine|abruti|abrutie|salope|pute|batard|batarde|tocard|tocarde)\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _isExplicitlyTargetedAbusiveVerbUse(
    String normalized,
  ) {
    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\b(?:t|te|vous) niqu(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient)\b'),
      RegExp(r'\bniqu(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) (?:mere|meres|famille|darone|daronne)\b'),
      RegExp(r'\b(?:t|te|vous) encul(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient)\b'),
      RegExp(r'\b(?:va|vas|allez|aller|irai|iras|irez|iront) (?:te|vous) faire (?:enculer|niquer)\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _isContextSensitiveLexiconTerm(
    String normalizedTerm,
  ) {
    if (_containsAnyPhrase(
          normalizedTerm,
          _strongFullWordInsults,
        ) ||
        _containsAnyPhrase(
          normalizedTerm,
          _contextualFullWordInsults,
        ) ||
        _containsAnyPhrase(
          normalizedTerm,
          _contextualFullPhraseInsults,
        ) ||
        _containsAnyPhrase(
          normalizedTerm,
          _modernDirectedTerms,
        ) ||
        _containsAnyPhrase(
          normalizedTerm,
          _mildModernMockery,
        ) ||
        _containsAnyPhrase(
          normalizedTerm,
          _strongAbbreviations,
        )) {
      return true;
    }

    return RegExp(
      r'^(?:con(?:s|ne|nes)?|conn(?:ard|ards|asse|asses)|salopes?|putes?|encul[a-z]*|enfoir[a-z]*|batard[a-z]*|tocard[a-z]*|crevard[a-z]*|ordures?|merdeu[a-z]*|debiles?|idiot[a-z]*|cretin[a-z]*|abruti[a-z]*|minables?|niqu[a-z]*|ferm[a-z]* gueules?)$',
    ).hasMatch(
      normalizedTerm,
    );
  }

  static bool _shouldIgnoreContextualLexiconMatch(
    String normalized,
    String normalizedTerm,
  ) {
    if (!_isContextSensitiveLexiconTerm(
      normalizedTerm,
    )) {
      return false;
    }

    if (_looksLikeQuotedOrExplanatoryUse(
      normalized,
    )) {
      return true;
    }

    // Les verbes vulgaires peuvent être employés sans attaquer un joueur
    // (ex. "j'ai niqué le boss", "tu niques le boss"). Le lexique brut ne
    // doit les bloquer que lorsqu'ils sont explicitement dirigés contre
    // quelqu'un.
    if (RegExp(
          r'^(?:niqu|encul)[a-z]*$',
        ).hasMatch(
          normalizedTerm,
        ) &&
        !_isExplicitlyTargetedAbusiveVerbUse(
          normalized,
        )) {
      return true;
    }

    final bool directTarget =
        _looksDirectlyTargeted(
      normalized,
    );

    final bool insultingFrame =
        _looksLikeInsultFrame(
      normalized,
    );

    final bool humanTargetFrame =
        _looksLikeHumanTargetFrame(
      normalized,
    );

    final bool intensified =
        _containsAnyPhrase(
      normalized,
      const <String>{
        'sale',
        'gros',
        'grosse',
        'espece de',
        'pauvre',
        'putain de',
        'vieux',
        'vieille',
      },
    );

    if (directTarget ||
        insultingFrame ||
        humanTargetFrame ||
        intensified ||
        _isShortStandaloneAttack(
          normalized,
        )) {
      return false;
    }

    // Utilisation non dirigée : jeu, film, objet, citation, discussion
    // générale... Le lexique brut ne doit pas reprendre la main.
    return true;
  }

  static bool _looksDirectlyTargeted(
    String normalized,
  ) {
    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\btu\b'),
      RegExp(r'\btoi\b'),
      RegExp(r'\bvous\b'),
      RegExp(r'\bt es\b'),
      RegExp(r'\bton\b'),
      RegExp(r'\bta\b'),
      RegExp(r'\btes\b'),
      RegExp(r'\byou\b'),
      RegExp(r'\byou are\b'),
      RegExp(r'\byoure\b'),
      RegExp(r'\byour\b'),
      RegExp(r'\bu r\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _looksLikeInsultFrame(
    String normalized,
  ) {
    final List<RegExp> patterns =
        <RegExp>[
      RegExp(r'\bt es(?: vraiment)?(?: un| une)?\b'),
      RegExp(r'\btu es(?: vraiment)?(?: un| une)?\b'),
      RegExp(r'\btoi t es\b'),
      RegExp(r'\bvous etes(?: un| une)?\b'),
      RegExp(r'\byou are(?: a| an)?\b'),
      RegExp(r'\byoure(?: a| an)?\b'),
      RegExp(r'\bu r(?: a| an)?\b'),
      RegExp(r'\bferm(?:e|es|ez|ons|er|erai|eras|era|erons|erez|eront|erais|erait|erions|eriez|eraient|ais|ait|ions|iez|aient) (?:ta|ton|tes|votre|vos) gueules?\b'),
      RegExp(r'\bferme la\b'),
      RegExp(r'\b(?:degage|degagez)\b'),
    ];

    return patterns.any(
      (RegExp pattern) =>
          pattern.hasMatch(
        normalized,
      ),
    );
  }

  static bool _isShortStandaloneAttack(
    String normalized,
  ) {
    final List<String> tokens =
        normalized
            .split(
              RegExp(
                r'\s+',
              ),
            )
            .where(
              (String token) =>
                  token.isNotEmpty,
            )
            .toList();

    return tokens.length <= 2;
  }

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
