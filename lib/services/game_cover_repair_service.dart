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

  // V3 : retente les anciennes covers manquantes avec plusieurs variantes
  // de recherche IGDB, sans dépendre de la synchro des succès Steam.
  static const String _failurePrefix =
      'project_xp_cover_repair_failure_v3_';

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

    final List<String> queries = <String>[game.title.trim()];
    final String simplified = _editionAgnosticTitle(
      _canonicalTitle(game.title),
    );
    if (simplified.length >= 2 &&
        simplified.toLowerCase() != game.title.trim().toLowerCase()) {
      queries.add(simplified);
    }

    final Map<String, GameCatalogResult> resultById =
        <String, GameCatalogResult>{};

    for (final String query in queries) {
      final List<GameCatalogResult> results =
          await GameCatalogService.searchGames(query);
      for (final GameCatalogResult result in results) {
        resultById[result.id] = result;
      }

      final bool alreadyHasSafeCandidate = resultById.values.any(
        (result) =>
            (result.coverUrl?.trim().isNotEmpty ?? false) &&
            _titleMatchScore(game.title, result.title) >= 80,
      );
      if (alreadyHasSafeCandidate) {
        break;
      }
    }

    // On accepte les variantes sûres de type Deluxe / Definitive /
    // Remastered / GOTY, tout en gardant un seuil strict pour éviter les
    // mauvaises jaquettes.
    final List<GameCatalogResult> candidates = resultById.values
        .where(
          (result) =>
              (result.coverUrl?.trim().isNotEmpty ?? false) &&
              _titleMatchScore(game.title, result.title) >= 80,
        )
        .toList();

    if (candidates.isEmpty) {
      await _rememberFailure(game.id);
      return null;
    }

    candidates.sort(
      (a, b) => _score(b, game).compareTo(
        _score(a, game),
      ),
    );

    final GameCatalogResult best = candidates.first;
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
      'Cover IGDB réparée automatiquement : ${game.title} '
      '→ ${best.title}',
    );

    return cover;
  }

  static int _score(
    GameCatalogResult result,
    GameLibraryEntry game,
  ) {
    // Le titre reste le critère dominant. Le score de titre est multiplié
    // pour éviter qu'une année ou une plateforme ne fasse gagner un faux match.
    int score = _titleMatchScore(
      game.title,
      result.title,
    ) * 10;

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

  static int _titleMatchScore(
    String expected,
    String candidate,
  ) {
    final String a = _canonicalTitle(expected);
    final String b = _canonicalTitle(candidate);

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    if (a == b) {
      return 100;
    }

    final String editionA = _editionAgnosticTitle(a);
    final String editionB = _editionAgnosticTitle(b);

    if (editionA.isNotEmpty &&
        editionA == editionB) {
      return 96;
    }

    final Set<String> aTokens =
        _meaningfulTokens(editionA);
    final Set<String> bTokens =
        _meaningfulTokens(editionB);

    if (aTokens.isEmpty || bTokens.isEmpty) {
      return 0;
    }

    final Set<String> intersection =
        aTokens.intersection(bTokens);
    final Set<String> union =
        aTokens.union(bTokens);

    final double overlap =
        intersection.length / union.length;

    // 80 % ou plus : le résultat IGDB est suffisamment proche pour une
    // réparation automatique. En dessous, on préfère laisser la cover vide
    // plutôt que d'associer le mauvais jeu.
    if (overlap >= 0.90) {
      return 92;
    }
    if (overlap >= 0.80) {
      return 86;
    }

    return (overlap * 100).round();
  }

  static String _editionAgnosticTitle(String raw) {
    String value = raw
        .replaceAll(
          RegExp(r'\bgame of the year\b'),
          ' ',
        );

    const Set<String> editionNoise = <String>{
      'edition',
      'deluxe',
      'ultimate',
      'complete',
      'definitive',
      'remastered',
      'remaster',
      'enhanced',
      'anniversary',
      'collection',
      'bundle',
      'digital',
      'standard',
      'goty',
    };

    value = value
        .split(' ')
        .where(
          (token) =>
              token.isNotEmpty &&
              !editionNoise.contains(token),
        )
        .join(' ');

    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Set<String> _meaningfulTokens(
    String raw,
  ) {
    return raw
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toSet();
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
