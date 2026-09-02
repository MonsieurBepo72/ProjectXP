import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_library_entry.dart';
import 'auth_service.dart';

class GameLibraryService {
  GameLibraryService._();

  static const String _libraryPrefix =
      'project_xp_game_library_v1_';
  static const String _activityPrefix =
      'project_xp_gaming_activity_v1_';
  static const int _maxActivityEvents = 100;

  static Future<String?> _currentUserId() {
    return AuthService.getCurrentUserId();
  }

  static String _libraryKey(String userId) =>
      '$_libraryPrefix$userId';

  static String _activityKey(String userId) =>
      '$_activityPrefix$userId';

  static Future<List<GameLibraryEntry>>
      loadCurrentLibrary() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return <GameLibraryEntry>[];
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_libraryKey(userId));

    if (raw == null || raw.isEmpty) {
      return <GameLibraryEntry>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <GameLibraryEntry>[];
      }

      final List<GameLibraryEntry> entries = decoded
          .whereType<Map>()
          .map(
            (item) => GameLibraryEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((entry) => entry.id.isNotEmpty)
          .toList();

      entries.sort(
        (a, b) => b.updatedAt.compareTo(a.updatedAt),
      );
      return entries;
    } catch (_) {
      return <GameLibraryEntry>[];
    }
  }

  static Future<void> saveCurrentLibrary(
    List<GameLibraryEntry> entries,
  ) async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    await prefs.setString(
      _libraryKey(userId),
      jsonEncode(
        entries.map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  static Future<GameLibraryEntry> addManualGame({
    required String title,
    required GamePlatform platform,
    required GameStatus status,
    String? catalogId,
    String? coverUrl,
    String? summary,
    int? releaseYear,
    List<String> genres = const <String>[],
    List<String> catalogPlatforms = const <String>[],
  }) async {
    final DateTime now = DateTime.now();
    final GameLibraryEntry entry = GameLibraryEntry(
      id: 'manual_${now.microsecondsSinceEpoch}',
      title: title.trim(),
      platform: platform,
      status: status,
      favorite: false,
      progressPercent:
          status == GameStatus.completed ? 100 : 0,
      source: GameSource.manual,
      externalId: null,
      catalogId: catalogId,
      coverUrl: coverUrl,
      summary: summary,
      releaseYear: releaseYear,
      genres: genres,
      catalogPlatforms: catalogPlatforms,
      playtimeMinutes: 0,
      achievements: const GameAchievementSummary(),
      addedAt: now,
      updatedAt: now,
    );

    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    entries.insert(0, entry);
    await saveCurrentLibrary(entries);

    // V1.8.1 : ajouter un jeu à sa Bibliothèque n'est plus un événement
    // du Fil d'Aventure. Le fil est réservé aux accomplissements.
    return entry;
  }

  static Future<GameLibraryEntry> enrichFromCatalog({
    required GameLibraryEntry entry,
    required String catalogId,
    required String title,
    required String? coverUrl,
    required String? summary,
    required int? releaseYear,
    required List<String> genres,
    required List<String> catalogPlatforms,
  }) async {
    final GameLibraryEntry enriched = entry.copyWith(
      title: title.trim().isEmpty ? entry.title : title.trim(),
      catalogId: catalogId,
      coverUrl: coverUrl,
      summary: summary,
      releaseYear: releaseYear,
      genres: genres,
      catalogPlatforms: catalogPlatforms,
      updatedAt: DateTime.now(),
    );

    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    final int index =
        entries.indexWhere((game) => game.id == entry.id);
    if (index == -1) {
      return enriched;
    }

    entries[index] = enriched;
    await saveCurrentLibrary(entries);
    return enriched;
  }

  static Future<void> updateGame(
    GameLibraryEntry updated,
  ) async {
    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    final int index =
        entries.indexWhere((entry) => entry.id == updated.id);
    if (index == -1) {
      return;
    }

    final GameLibraryEntry previous = entries[index];
    final GameLibraryEntry normalized = updated.copyWith(
      progressPercent: updated.status == GameStatus.completed
          ? 100
          : updated.progressPercent,
      updatedAt: DateTime.now(),
    );
    entries[index] = normalized;
    await saveCurrentLibrary(entries);

    if (previous.status != GameStatus.completed &&
        normalized.status == GameStatus.completed) {
      await addActivity(
        title: '${normalized.title} terminé',
        detail:
            '${normalized.platform.label} • Aventure accomplie',
      );
    } else if (previous.status == GameStatus.abandoned &&
        normalized.status == GameStatus.inProgress) {
      await addActivity(
        title: '${normalized.title} reprend son aventure',
        detail:
            '${normalized.platform.label} • Retour après abandon',
      );
    }

    final int previousAchievements =
        previous.achievements.unlocked +
            previous.achievements.bronzeUnlocked +
            previous.achievements.silverUnlocked +
            previous.achievements.goldUnlocked +
            previous.achievements.platinumUnlocked;
    final int currentAchievements =
        normalized.achievements.unlocked +
            normalized.achievements.bronzeUnlocked +
            normalized.achievements.silverUnlocked +
            normalized.achievements.goldUnlocked +
            normalized.achievements.platinumUnlocked;

    if (normalized.achievements.platinumUnlocked >
        previous.achievements.platinumUnlocked) {
      await addActivity(
        title: 'Platine obtenu sur ${normalized.title}',
        detail:
            '${normalized.platform.label} • Trophée ultime débloqué',
      );
    } else if (currentAchievements > previousAchievements) {
      await addActivity(
        title:
            'Nouveaux ${normalized.platform.achievementLabel.toLowerCase()} '
            'sur ${normalized.title}',
        detail: normalized.achievementProgressText,
      );
    }
  }

  static Future<void> removeGame(String id) async {
    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    entries.removeWhere((entry) => entry.id == id);
    await saveCurrentLibrary(entries);
  }

  static Future<({int added, int updated})> mergeSteamGames(
    List<GameLibraryEntry> imported,
  ) async {
    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    int added = 0;
    int updated = 0;

    for (final GameLibraryEntry incoming in imported) {
      final int index = entries.indexWhere(
        (entry) =>
            entry.source == GameSource.steam &&
            entry.externalId == incoming.externalId,
      );

      if (index == -1) {
        entries.add(incoming);
        added += 1;
        continue;
      }

      final GameLibraryEntry existing = entries[index];
      entries[index] = existing.copyWith(
        title: incoming.title,
        coverUrl: incoming.coverUrl,
        playtimeMinutes: incoming.playtimeMinutes,
        updatedAt: DateTime.now(),
      );
      updated += 1;
    }

    entries.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );
    await saveCurrentLibrary(entries);
    return (added: added, updated: updated);
  }

  static Future<List<GamingActivityEvent>>
      loadCurrentActivity() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return <GamingActivityEvent>[];
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_activityKey(userId));
    if (raw == null || raw.isEmpty) {
      return <GamingActivityEvent>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <GamingActivityEvent>[];
      }

      final List<GamingActivityEvent> decodedEvents = decoded
          .whereType<Map>()
          .map(
            (item) => GamingActivityEvent.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      // Migration V1.8.0 -> V1.8.1 : on retire aussi les anciens événements
      // "rejoint ta Bibliothèque" déjà créés localement.
      final List<GamingActivityEvent> events = decodedEvents
          .where(
            (event) => !event.title
                .toLowerCase()
                .contains('rejoint ta bibliothèque'),
          )
          .toList();

      events.sort(
        (a, b) => b.createdAt.compareTo(a.createdAt),
      );

      if (events.length != decodedEvents.length) {
        await prefs.setString(
          _activityKey(userId),
          jsonEncode(
            events.map((event) => event.toJson()).toList(),
          ),
        );
      }

      return events;
    } catch (_) {
      return <GamingActivityEvent>[];
    }
  }

  static Future<void> addActivity({
    required String title,
    required String detail,
  }) async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final List<GamingActivityEvent> events =
        await loadCurrentActivity();
    final DateTime now = DateTime.now();
    events.insert(
      0,
      GamingActivityEvent(
        id: 'activity_${now.microsecondsSinceEpoch}',
        title: title,
        detail: detail,
        createdAt: now,
      ),
    );

    final List<GamingActivityEvent> kept =
        events.take(_maxActivityEvents).toList();
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    await prefs.setString(
      _activityKey(userId),
      jsonEncode(
        kept.map((event) => event.toJson()).toList(),
      ),
    );
  }
}
