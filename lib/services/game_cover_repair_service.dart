import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_library_entry.dart';
import 'game_catalog_service.dart';
import 'game_library_service.dart';

/// Répare uniquement les jaquettes qui ont réellement échoué à l'affichage.
///
/// On ne lance donc pas 100+ recherches IGDB sur toute la bibliothèque.
/// GameCoverImage appelle ce service seulement après l'échec de toutes les
/// vraies covers connues. Les recherches sont sérialisées et les échecs ont
/// un cooldown pour garder Project XP léger en réseau.
class GameCoverRepairService {
  GameCoverRepairService._();

  static const String _failurePrefix =
      'project_xp_cover_repair_failure_v1_';

  static const Duration _failureCooldown =
      Duration(hours: 12);

  static final Map<String, Future<String?>> _inFlight =
      <String, Future<String?>>{};

  static Future<void> _queueTail = Future<void>.value();

  static Future<String?> requestRepair(
    GameLibraryEntry game,
  ) {
    final String id = game.id.trim();

    if (id.isEmpty || game.title.trim().isEmpty) {
      return Future<String?>.value(null);
    }

    final Future<String?>? existing = _inFlight[id];

    if (existing != null) {
      return existing;
    }

    final Future<String?> job = _queueTail.then<String?>(
      (_) => _repairSafely(game),
    );

    _queueTail = job.then<void>((_) {});
    _inFlight[id] = job;

    job.whenComplete(
      () {
        _inFlight.remove(id);
      },
    );

    return job;
  }

  static Future<String?> _repairSafely(
    GameLibraryEntry game,
  ) async {
    try {
      return await _repair(game);
    } catch (error) {
      debugPrint(
        'Réparation cover impossible pour ${game.title} : $error',
      );
      await _rememberFailure(game.id);
      return null;
    }
  }

  static Future<String?> _repair(
    GameLibraryEntry game,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String failureKey =
        '$_failurePrefix${game.id}';

    final int lastFailureMs =
        prefs.getInt(failureKey) ?? 0;

    if (lastFailureMs > 0) {
      final DateTime lastFailure =
          DateTime.fromMillisecondsSinceEpoch(
        lastFailureMs,
      );

      if (DateTime.now().difference(lastFailure) <
          _failureCooldown) {
        return null;
      }
    }

    final List<GameCatalogResult> results =
        await GameCatalogService.searchGames(
      game.title,
    );

    final String target =
        _canonicalTitle(game.title);

    final List<GameCatalogResult> exact = results
        .where(
          (result) =>
              _canonicalTitle(result.title) == target &&
              (result.coverUrl?.trim().isNotEmpty ?? false),
        )
        .toList();

    if (exact.isEmpty) {
      await _rememberFailure(game.id);
      return null;
    }

    exact.sort(
      (a, b) => _score(b, game).compareTo(
        _score(a, game),
      ),
    );

    final GameCatalogResult best = exact.first;
    final String cover =
        best.coverUrl?.trim() ?? '';

    if (cover.isEmpty) {
      await _rememberFailure(game.id);
      return null;
    }

    await GameLibraryService.enrichFromCatalog(
      entry: game,
      catalogId: best.id,
      title: best.title,
      coverUrl: best.coverUrl,
      summary: best.summary,
      releaseYear: best.releaseYear,
      genres: best.genres,
      catalogPlatforms: best.platforms,
    );

    await prefs.remove(failureKey);

    debugPrint(
      'Cover IGDB réparée automatiquement : ${game.title}',
    );

    return cover;
  }

  static int _score(
    GameCatalogResult result,
    GameLibraryEntry game,
  ) {
    int score = 10;

    final int? expectedYear = game.releaseYear;
    final int? resultYear = result.releaseYear;

    if (expectedYear != null && resultYear != null) {
      final int delta =
          (expectedYear - resultYear).abs();

      if (delta == 0) {
        score += 5;
      } else if (delta <= 1) {
        score += 3;
      } else if (delta >= 3) {
        score -= 4;
      }
    }

    final bool pcLike = result.platforms.any(
      (platform) {
        final String value =
            platform.toLowerCase();

        return value.contains('windows') ||
            value == 'pc' ||
            value.contains('linux') ||
            value.contains('mac');
      },
    );

    if (pcLike) {
      score += 2;
    }

    return score;
  }

  static String _canonicalTitle(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('™', '')
        .replaceAll('®', '')
        .replaceAll(
          RegExp(r'[^a-z0-9à-ÿ]+'),
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();
  }

  static Future<void> _rememberFailure(
    String gameId,
  ) async {
    final String id = gameId.trim();

    if (id.isEmpty) {
      return;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      '$_failurePrefix$id',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
