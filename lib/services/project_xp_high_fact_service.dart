import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_library_entry.dart';
import 'game_library_service.dart';
import 'project_xp_message_send_result.dart';
import 'supabase_service.dart';
import 'tavern_service.dart';

class ProjectXpHighFactService {
  ProjectXpHighFactService._();

  static bool _publishing = false;
  static bool _publishAgain = false;

  static Future<void> publishNewHighFacts() async {
    if (_publishing) {
      _publishAgain = true;
      return;
    }

    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    _publishing = true;

    try {
      final List<GameLibraryEntry> library =
          await GameLibraryService.loadCurrentLibraryConsolidated();
      final List<_ProjectXpHighFact> currentFacts = _currentFacts(library);
      if (currentFacts.isEmpty) {
        return;
      }

      final Map<String, dynamic>? channel = await _highFactsChannel();
      final String channelId = channel?['id']?.toString().trim() ?? '';
      if (channelId.isEmpty) {
        return;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String preferenceKey = 'project_xp_tavern_high_facts_${user.id}';
      final Set<String> locallyPublished =
          (prefs.getStringList(preferenceKey) ?? const <String>[]).toSet();

      final Set<String> existingTitles = await _existingHighFactTitles(
        channelId: channelId,
        authorId: user.id,
      );

      final List<_ProjectXpHighFact> missing = currentFacts.where((fact) {
        return !locallyPublished.contains(fact.key) &&
            !existingTitles.contains(fact.title.toLowerCase());
      }).toList(growable: false);

      if (missing.isEmpty) {
        return;
      }

      final String content = <String>[
        '🏆 HAUTS FAITS PROJECT XP',
        ...missing.map(
          (fact) => '• ${fact.emoji} ${fact.title} — ${fact.detail}',
        ),
      ].join('\n');

      final ProjectXpMessageSendResult result = await TavernService.sendMessage(
        channelId: channelId,
        content: content,
      );

      if (!result.sent) {
        return;
      }

      locallyPublished.addAll(missing.map((fact) => fact.key));
      await prefs.setStringList(
        preferenceKey,
        locallyPublished.toList()..sort(),
      );
    } catch (_) {
      // Une publication sociale ne doit jamais bloquer la bibliothèque,
      // la synchronisation ou le démarrage de Project XP.
    } finally {
      _publishing = false;
      if (_publishAgain) {
        _publishAgain = false;
        unawaited(publishNewHighFacts());
      }
    }
  }

  static Future<Map<String, dynamic>?> _highFactsChannel() async {
    try {
      final List<Map<String, dynamic>> channels =
          await TavernService.getChannels();
      for (final Map<String, dynamic> channel in channels) {
        final String slug = channel['slug']?.toString().toLowerCase().trim() ?? '';
        final String name =
            channel['name']?.toString().toLowerCase().trim() ?? '';
        if (slug == 'hauts_faits' ||
            slug == 'hauts-faits' ||
            (slug.contains('haut') && slug.contains('fait')) ||
            (name.contains('haut') && name.contains('fait'))) {
          return channel;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<Set<String>> _existingHighFactTitles({
    required String channelId,
    required String authorId,
  }) async {
    try {
      final List<dynamic> rows = await SupabaseService.client
          .from('tavern_messages')
          .select('content')
          .eq('channel_id', channelId)
          .eq('author_id', authorId)
          .order('created_at', ascending: false)
          .limit(200);

      final Set<String> result = <String>{};
      for (final dynamic raw in rows) {
        if (raw is! Map) {
          continue;
        }
        final String content = raw['content']?.toString().toLowerCase() ?? '';
        for (final String title in _allTierTitles) {
          if (content.contains('${title.toLowerCase()} —')) {
            result.add(title.toLowerCase());
          }
        }
      }
      return result;
    } catch (_) {
      return <String>{};
    }
  }

  static List<_ProjectXpHighFact> _currentFacts(
    List<GameLibraryEntry> library,
  ) {
    final int completedGames =
        library.where((game) => game.status == GameStatus.completed).length;
    final int hundredPercentGames = library
        .where((game) => _displayCompletion(game) == 100)
        .length;
    final int playedGames =
        library.where((game) => game.totalPlaytimeMinutes > 0).length;
    final int multiPlatformGames = library
        .where((game) => game.connectedPlatforms.toSet().length >= 2)
        .length;
    final int totalPlaytimeMinutes = library.fold<int>(
      0,
      (sum, game) => sum + game.totalPlaytimeMinutes,
    );

    int platinumTrophies = 0;
    int unlockedAchievements = 0;

    for (final GameLibraryEntry game in library) {
      for (final GamePlatformProfile profile in game.resolvedPlatformProfiles) {
        final GameAchievementSummary summary =
            profile.computedAchievementSummary;
        if (profile.platform == GamePlatform.playstation &&
            summary.unlocked <= 0) {
          unlockedAchievements +=
              summary.bronzeUnlocked +
              summary.silverUnlocked +
              summary.goldUnlocked +
              summary.platinumUnlocked;
        } else {
          unlockedAchievements += summary.unlocked;
        }

        if (profile.platform == GamePlatform.playstation) {
          platinumTrophies += summary.platinumUnlocked;
        }
      }
    }

    final int playedHours = (totalPlaytimeMinutes / 60).floor();
    final List<_ProjectXpHighFact> facts = <_ProjectXpHighFact>[];

    void addFact({
      required String category,
      required String emoji,
      required int value,
      required List<({int threshold, String title})> tiers,
      required String Function(int value) detail,
    }) {
      ({int threshold, String title})? current;
      for (final ({int threshold, String title}) tier in tiers) {
        if (value >= tier.threshold) {
          current = tier;
        } else {
          break;
        }
      }
      if (current == null) {
        return;
      }
      facts.add(
        _ProjectXpHighFact(
          key: '$category:${current.threshold}',
          emoji: emoji,
          title: current.title,
          detail: detail(value),
        ),
      );
    }

    addFact(
      category: 'completion',
      emoji: '🏆',
      value: hundredPercentGames,
      tiers: _completionTiers,
      detail: (value) =>
          '$value jeu${value > 1 ? 'x' : ''} à 100 %',
    );
    addFact(
      category: 'achievements',
      emoji: '🔥',
      value: unlockedAchievements,
      tiers: _achievementTiers,
      detail: (value) => '$value succès / trophées débloqués',
    );
    addFact(
      category: 'completed',
      emoji: '⚔️',
      value: completedGames,
      tiers: _completedTiers,
      detail: (value) =>
          '$value jeu${value > 1 ? 'x' : ''} terminé${value > 1 ? 's' : ''}',
    );
    addFact(
      category: 'playtime',
      emoji: '💎',
      value: playedHours,
      tiers: _playtimeTiers,
      detail: (value) => '$value h de jeu cumulées',
    );
    addFact(
      category: 'played',
      emoji: '🎮',
      value: playedGames,
      tiers: _playedGameTiers,
      detail: (value) => '$value jeux réellement lancés',
    );
    addFact(
      category: 'platinum',
      emoji: '👑',
      value: platinumTrophies,
      tiers: _platinumTiers,
      detail: (value) =>
          '$value platine${value > 1 ? 's' : ''} obtenu${value > 1 ? 's' : ''}',
    );
    addFact(
      category: 'multiplatform',
      emoji: '🌐',
      value: multiPlatformGames,
      tiers: _multiPlatformTiers,
      detail: (value) => '$value jeux liés sur plusieurs plateformes',
    );

    return facts;
  }

  static int? _displayCompletion(GameLibraryEntry game) {
    int best = -1;
    for (final GamePlatformProfile profile in game.resolvedPlatformProfiles) {
      final GameAchievementSummary summary = profile.computedAchievementSummary;
      final int? value = profile.platform == GamePlatform.playstation &&
              summary.scoreTotal == 100
          ? summary.scoreEarned.clamp(0, 100).toInt()
          : profile.completionPercent;
      if (value != null && value > best) {
        best = value;
      }
    }
    if (best >= 0) {
      return best;
    }
    return game.progressPercent > 0 ? game.progressPercent : null;
  }

  static const List<({int threshold, String title})> _completionTiers = [
    (threshold: 1, title: 'Premier 100 %'),
    (threshold: 5, title: 'Complétionniste'),
    (threshold: 10, title: 'Maître du 100 %'),
    (threshold: 25, title: 'Collection parfaite'),
    (threshold: 50, title: 'Légende du 100 %'),
    (threshold: 100, title: 'Cent mondes maîtrisés'),
    (threshold: 200, title: 'Archiviste parfait'),
    (threshold: 350, title: 'Mythe de la complétion'),
    (threshold: 500, title: 'Éternel complétionniste'),
  ];

  static const List<({int threshold, String title})> _achievementTiers = [
    (threshold: 1, title: 'Premier exploit'),
    (threshold: 100, title: 'Chasseur de succès'),
    (threshold: 500, title: 'Collectionneur'),
    (threshold: 1000, title: 'Mille exploits'),
    (threshold: 2500, title: 'Vétéran des trophées'),
    (threshold: 5000, title: 'Archiviste des exploits'),
    (threshold: 10000, title: 'Dix mille conquêtes'),
    (threshold: 20000, title: 'Maître des accomplissements'),
    (threshold: 50000, title: 'Légende éternelle des exploits'),
  ];

  static const List<({int threshold, String title})> _completedTiers = [
    (threshold: 1, title: 'Première aventure accomplie'),
    (threshold: 10, title: 'Aventurier aguerri'),
    (threshold: 25, title: 'Vétéran'),
    (threshold: 50, title: 'Conquérant'),
    (threshold: 100, title: 'Chroniqueur de mondes'),
    (threshold: 200, title: 'Grand conquérant'),
    (threshold: 350, title: 'Maître des bibliothèques'),
    (threshold: 500, title: 'Légende aux cinq cents aventures'),
    (threshold: 750, title: 'Voyageur des mille mondes'),
  ];

  static const List<({int threshold, String title})> _playtimeTiers = [
    (threshold: 1, title: 'Premières heures d’aventure'),
    (threshold: 100, title: 'Cent heures d’aventure'),
    (threshold: 500, title: 'Voyageur infatigable'),
    (threshold: 1000, title: 'Mille heures d’aventure'),
    (threshold: 2500, title: 'Gardien des mondes'),
    (threshold: 5000, title: 'Légende du temps'),
    (threshold: 10000, title: 'Dix mille heures de légende'),
    (threshold: 20000, title: 'Éternel aventurier'),
    (threshold: 50000, title: 'Hors du temps'),
  ];

  static const List<({int threshold, String title})> _playedGameTiers = [
    (threshold: 10, title: 'Explorateur'),
    (threshold: 50, title: 'Bibliothèque vivante'),
    (threshold: 100, title: 'Cent aventures vécues'),
    (threshold: 250, title: 'Grand explorateur'),
    (threshold: 500, title: 'Voyageur des mondes'),
    (threshold: 1000, title: 'Mille jeux parcourus'),
  ];

  static const List<({int threshold, String title})> _platinumTiers = [
    (threshold: 1, title: 'Premier platine'),
    (threshold: 5, title: 'Chasseur de platines'),
    (threshold: 10, title: 'Couronne d’argent'),
    (threshold: 25, title: 'Maître des platines'),
    (threshold: 50, title: 'Seigneur des trophées'),
    (threshold: 100, title: 'Cent couronnes'),
    (threshold: 250, title: 'Empereur des platines'),
    (threshold: 500, title: 'Mythe PlayStation'),
  ];

  static const List<({int threshold, String title})> _multiPlatformTiers = [
    (threshold: 1, title: 'Premier pont entre plateformes'),
    (threshold: 5, title: 'Joueur sans frontières'),
    (threshold: 10, title: 'Multiplateforme'),
    (threshold: 25, title: 'Voyageur interplateforme'),
    (threshold: 50, title: 'Maître des écosystèmes'),
    (threshold: 100, title: 'Légende sans frontières'),
  ];

  static const List<String> _allTierTitles = [
    ...[
      'Premier 100 %',
      'Complétionniste',
      'Maître du 100 %',
      'Collection parfaite',
      'Légende du 100 %',
      'Cent mondes maîtrisés',
      'Archiviste parfait',
      'Mythe de la complétion',
      'Éternel complétionniste',
    ],
    ...[
      'Premier exploit',
      'Chasseur de succès',
      'Collectionneur',
      'Mille exploits',
      'Vétéran des trophées',
      'Archiviste des exploits',
      'Dix mille conquêtes',
      'Maître des accomplissements',
      'Légende éternelle des exploits',
    ],
    ...[
      'Première aventure accomplie',
      'Aventurier aguerri',
      'Vétéran',
      'Conquérant',
      'Chroniqueur de mondes',
      'Grand conquérant',
      'Maître des bibliothèques',
      'Légende aux cinq cents aventures',
      'Voyageur des mille mondes',
    ],
    ...[
      'Premières heures d’aventure',
      'Cent heures d’aventure',
      'Voyageur infatigable',
      'Mille heures d’aventure',
      'Gardien des mondes',
      'Légende du temps',
      'Dix mille heures de légende',
      'Éternel aventurier',
      'Hors du temps',
    ],
    ...[
      'Explorateur',
      'Bibliothèque vivante',
      'Cent aventures vécues',
      'Grand explorateur',
      'Voyageur des mondes',
      'Mille jeux parcourus',
    ],
    ...[
      'Premier platine',
      'Chasseur de platines',
      'Couronne d’argent',
      'Maître des platines',
      'Seigneur des trophées',
      'Cent couronnes',
      'Empereur des platines',
      'Mythe PlayStation',
    ],
    ...[
      'Premier pont entre plateformes',
      'Joueur sans frontières',
      'Multiplateforme',
      'Voyageur interplateforme',
      'Maître des écosystèmes',
      'Légende sans frontières',
    ],
  ];
}

class _ProjectXpHighFact {
  final String key;
  final String emoji;
  final String title;
  final String detail;

  const _ProjectXpHighFact({
    required this.key,
    required this.emoji,
    required this.title,
    required this.detail,
  });
}
