import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_library_entry.dart';
import 'game_library_service.dart';
import 'supabase_service.dart';

typedef PlayStationSyncProgress =
    void Function(int completed, int total, String title, bool success);

class PlayStationSyncException implements Exception {
  final String message;

  const PlayStationSyncException(this.message);

  @override
  String toString() => message;
}

class PlayStationSyncResult {
  final int added;
  final int updated;
  final int unchanged;
  final int total;
  final int detailFailures;

  const PlayStationSyncResult({
    required this.added,
    required this.updated,
    required this.unchanged,
    required this.total,
    this.detailFailures = 0,
  });
}

class PlayStationSyncSnapshot {
  final List<Map<String, dynamic>> games;

  const PlayStationSyncSnapshot({required this.games});

  int get total => games.length;
}

class _PlayStationTrophySetRequest {
  final int gameIndex;
  final String clientKey;
  final String npCommunicationId;
  final String npServiceName;
  final String title;

  const _PlayStationTrophySetRequest({
    required this.gameIndex,
    required this.clientKey,
    required this.npCommunicationId,
    required this.npServiceName,
    required this.title,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clientKey': clientKey,
    'npCommunicationId': npCommunicationId,
    'npServiceName': npServiceName,
    'title': title,
  };
}

class PlayStationSyncService {
  PlayStationSyncService._();

  static const String _ownedPlatformMarkerPrefix =
      'projectxp:owned-playstation:';

  static const Duration _detailStaleAfter = Duration(days: 7);
  static const int _detailBatchSize = 12;
  static const int _maxDetailGamesPerSync = 36;

  static Future<PlayStationSyncResult> syncEverything({
    PlayStationSyncProgress? onProgress,
  }) async {
    final PlayStationSyncSnapshot snapshot = await fetchDetailedSnapshot(
      onProgress: onProgress,
    );
    return mergeSnapshot(snapshot);
  }

  static Future<PlayStationSyncSnapshot> fetchSnapshot() async {
    final FunctionResponse response;

    try {
      response = await SupabaseService.client.functions.invoke(
        'playstation-sync',
        body: const <String, dynamic>{'action': 'sync'},
      );
    } on FunctionException catch (error) {
      throw PlayStationSyncException(_friendlyFunctionError(error.details));
    } catch (error) {
      throw PlayStationSyncException(_friendlyFunctionError(error.toString()));
    }

    final dynamic raw = response.data;
    if (raw is! Map) {
      throw const PlayStationSyncException(
        'PlayStation a renvoyé une réponse invalide.',
      );
    }

    final Map<String, dynamic> data = Map<String, dynamic>.from(raw);
    if (data['ok'] != true) {
      throw PlayStationSyncException(
        data['error']?.toString() ??
            'La synchronisation PlayStation a échoué.',
      );
    }

    final dynamic gamesRaw = data['games'];
    final List<Map<String, dynamic>> games = gamesRaw is List
        ? gamesRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : <Map<String, dynamic>>[];

    return PlayStationSyncSnapshot(
      games: List<Map<String, dynamic>>.unmodifiable(games),
    );
  }

  /// Prépare un snapshot PlayStation complet sans écrire dans la bibliothèque.
  ///
  /// L'index global PSN est récupéré une fois. Ensuite seuls les catalogues de
  /// trophées manquants, modifiés ou anciens sont demandés par petits lots.
  /// Chaque jeu compte comme une unité de progression, même s'il est déjà à
  /// jour. Cela permet à la barre globale d'afficher réellement toute la
  /// bibliothèque PlayStation au lieu de seulement quelques requêtes Steam.
  static Future<PlayStationSyncSnapshot> fetchDetailedSnapshot({
    PlayStationSyncProgress? onProgress,
  }) async {
    final PlayStationSyncSnapshot base = await fetchSnapshot();
    final List<Map<String, dynamic>> games = base.games
        .map((game) => Map<String, dynamic>.from(game))
        .toList();

    if (games.isEmpty) {
      return PlayStationSyncSnapshot(games: games);
    }

    final List<GameLibraryEntry> library =
        await GameLibraryService.loadCurrentLibraryConsolidated();
    final DateTime now = DateTime.now();

    final List<_PlayStationTrophySetRequest> pending =
        <_PlayStationTrophySetRequest>[];
    final Map<int, int> remainingByGame = <int, int>{};
    final Map<int, List<Map<String, dynamic>>> detailsByGame =
        <int, List<Map<String, dynamic>>>{};
    final Map<int, bool> failedByGame = <int, bool>{};
    final Map<int, List<Map<String, dynamic>>> existingDetailsByGame =
        <int, List<Map<String, dynamic>>>{};

    int completed = 0;
    int detailGamesScheduled = 0;

    void report(int gameIndex, {required bool success}) {
      completed += 1;
      final String title = games[gameIndex]['title']?.toString().trim() ?? '';
      onProgress?.call(
        completed,
        games.length,
        title.isEmpty ? 'Jeu PlayStation' : title,
        success,
      );
    }

    for (int gameIndex = 0; gameIndex < games.length; gameIndex += 1) {
      final Map<String, dynamic> raw = games[gameIndex];
      final String title = raw['title']?.toString().trim() ?? '';
      final String externalId = raw['externalId']?.toString().trim() ?? '';

      final int existingIndex = _findExistingGameIndex(
        library,
        title: title,
        externalId: externalId,
      );
      final GamePlatformProfile? currentProfile = existingIndex < 0
          ? null
          : library[existingIndex].platformProfile(GamePlatform.playstation);

      if (currentProfile != null) {
        existingDetailsByGame[gameIndex] = currentProfile.achievementDetails
            .map((detail) => detail.toJson())
            .toList(growable: false);
      }

      final List<Map<String, dynamic>> trophySets = _readMapList(
        raw['trophySets'],
      );
      final int incomingTotal = _incomingTrophyTotal(raw);

      // Même logique que Steam : lorsqu'aucun catalogue de trophées n'est
      // associé au jeu par PSN, Project XP considère le catalogue comme connu
      // et vide. L'interface peut alors afficher « Aucun trophée » au lieu de
      // laisser éternellement « Progression non synchronisée ».
      //
      // Si un ancien profil possède déjà des trophées, on les conserve : une
      // réponse PSN momentanément incomplète ne doit jamais effacer des données
      // officielles déjà récupérées.
      if (trophySets.isEmpty && incomingTotal <= 0) {
        if (currentProfile != null && currentProfile.hasAchievementData) {
          raw['achievementCatalogInitialized'] =
              currentProfile.achievementCatalogInitialized;
          raw['achievementDetails'] = currentProfile.achievementDetails
              .map((detail) => detail.toJson())
              .toList(growable: false);
        } else {
          raw['achievementCatalogInitialized'] = true;
          raw['achievementDetails'] = <Map<String, dynamic>>[];
        }
        report(gameIndex, success: true);
        continue;
      }

      final DateTime? lastDetailSync = currentProfile?.achievementsLastSyncedAt;
      final bool detailsStale = lastDetailSync == null ||
          now.difference(lastDetailSync.toLocal()) > _detailStaleAfter;
      final bool missingCatalog = currentProfile == null ||
          !currentProfile.achievementCatalogInitialized ||
          (incomingTotal > 0 && currentProfile.achievementDetails.isEmpty);
      final bool summaryChanged = currentProfile == null ||
          _summaryChanged(currentProfile, raw);

      final bool needsDetails = trophySets.isNotEmpty &&
          (missingCatalog || summaryChanged || detailsStale);

      if (needsDetails &&
          detailGamesScheduled >= _maxDetailGamesPerSync) {
        if (currentProfile != null) {
          // Le détail existant reste visible, mais le catalogue est marqué
          // incomplet afin que le jeu soit repris dès la prochaine SYNCHRO.
          // Sinon la mise à jour du résumé ci-dessous pourrait le faire
          // paraître frais pendant plusieurs jours alors que ses trophées
          // détaillés n'ont pas encore été rafraîchis.
          raw['achievementCatalogInitialized'] = false;
          raw['achievementDetails'] = currentProfile.achievementDetails
              .map((detail) => detail.toJson())
              .toList(growable: false);
        }
        raw['detailSyncDeferred'] = true;
        report(gameIndex, success: true);
        continue;
      }

      if (!needsDetails) {
        if (currentProfile != null) {
          raw['achievementCatalogInitialized'] =
              currentProfile.achievementCatalogInitialized;
          raw['achievementDetails'] = currentProfile.achievementDetails
              .map((detail) => detail.toJson())
              .toList(growable: false);
        }
        report(gameIndex, success: true);
        continue;
      }

      final List<_PlayStationTrophySetRequest> requests =
          <_PlayStationTrophySetRequest>[];
      for (int setIndex = 0; setIndex < trophySets.length; setIndex += 1) {
        final Map<String, dynamic> set = trophySets[setIndex];
        final String npCommunicationId =
            set['npCommunicationId']?.toString().trim() ?? '';
        if (npCommunicationId.isEmpty) {
          continue;
        }
        final String rawService =
            set['npServiceName']?.toString().trim() ?? '';
        final String npServiceName =
            rawService == 'trophy' ? 'trophy' : 'trophy2';
        requests.add(
          _PlayStationTrophySetRequest(
            gameIndex: gameIndex,
            clientKey: '$gameIndex:$setIndex:$npCommunicationId',
            npCommunicationId: npCommunicationId,
            npServiceName: npServiceName,
            title: set['title']?.toString().trim().isNotEmpty == true
                ? set['title'].toString().trim()
                : title,
          ),
        );
      }

      if (requests.isEmpty) {
        if (currentProfile != null) {
          raw['achievementCatalogInitialized'] =
              currentProfile.achievementCatalogInitialized;
          raw['achievementDetails'] = currentProfile.achievementDetails
              .map((detail) => detail.toJson())
              .toList(growable: false);
        }
        report(gameIndex, success: true);
        continue;
      }

      detailGamesScheduled += 1;
      remainingByGame[gameIndex] = requests.length;
      detailsByGame[gameIndex] = <Map<String, dynamic>>[];
      failedByGame[gameIndex] = false;
      pending.addAll(requests);
    }

    for (int start = 0; start < pending.length; start += _detailBatchSize) {
      final int end =
          (start + _detailBatchSize).clamp(0, pending.length).toInt();
      final List<_PlayStationTrophySetRequest> batch = pending.sublist(
        start,
        end,
      );

      Map<String, Map<String, dynamic>> results =
          <String, Map<String, dynamic>>{};
      bool batchFailed = false;

      try {
        results = await _fetchTrophyDetailBatch(batch);
      } on PlayStationSyncException {
        batchFailed = true;
      } catch (_) {
        batchFailed = true;
      }

      for (final _PlayStationTrophySetRequest request in batch) {
        final Map<String, dynamic>? result = results[request.clientKey];
        final bool success = !batchFailed && result?['ok'] == true;

        if (success && result != null) {
          detailsByGame[request.gameIndex]!.addAll(
            _readMapList(result['achievementDetails']),
          );
        } else {
          failedByGame[request.gameIndex] = true;
        }

        final int remaining = (remainingByGame[request.gameIndex] ?? 1) - 1;
        remainingByGame[request.gameIndex] = remaining;

        if (remaining == 0) {
          final bool gameFailed = failedByGame[request.gameIndex] == true;
          final List<Map<String, dynamic>> downloaded =
              detailsByGame[request.gameIndex] ?? <Map<String, dynamic>>[];
          final List<Map<String, dynamic>> existing =
              existingDetailsByGame[request.gameIndex] ??
                  <Map<String, dynamic>>[];

          games[request.gameIndex]['achievementDetails'] =
              gameFailed ? existing : downloaded;
          games[request.gameIndex]['achievementCatalogInitialized'] =
              !gameFailed;
          games[request.gameIndex]['detailSyncAttempted'] = true;
          games[request.gameIndex]['detailSyncFailed'] = gameFailed;
          report(request.gameIndex, success: !gameFailed);
        }
      }
    }

    return PlayStationSyncSnapshot(
      games: List<Map<String, dynamic>>.unmodifiable(games),
    );
  }

  static Future<Map<String, Map<String, dynamic>>> _fetchTrophyDetailBatch(
    List<_PlayStationTrophySetRequest> requests,
  ) async {
    final FunctionResponse response;

    try {
      response = await SupabaseService.client.functions.invoke(
        'playstation-sync',
        body: <String, dynamic>{
          'action': 'details',
          'trophySets': requests.map((request) => request.toJson()).toList(),
        },
      );
    } on FunctionException catch (error) {
      throw PlayStationSyncException(_friendlyFunctionError(error.details));
    } catch (error) {
      throw PlayStationSyncException(_friendlyFunctionError(error.toString()));
    }

    final dynamic raw = response.data;
    if (raw is! Map) {
      throw const PlayStationSyncException(
        'PlayStation a renvoyé des trophées invalides.',
      );
    }

    final Map<String, dynamic> data = Map<String, dynamic>.from(raw);
    if (data['ok'] != true) {
      throw PlayStationSyncException(
        data['error']?.toString() ??
            'Le détail des trophées PlayStation n’a pas pu être récupéré.',
      );
    }

    final Map<String, Map<String, dynamic>> result =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> item in _readMapList(data['results'])) {
      final String key = item['clientKey']?.toString() ?? '';
      if (key.isNotEmpty) {
        result[key] = item;
      }
    }
    return result;
  }

  static Future<PlayStationSyncResult> mergeSnapshot(
    PlayStationSyncSnapshot snapshot, {
    PlayStationSyncProgress? onProgress,
  }) async {
    return _mergeGames(snapshot.games, onProgress: onProgress);
  }

  static Future<PlayStationSyncResult> _mergeGames(
    List<Map<String, dynamic>> rawGames, {
    PlayStationSyncProgress? onProgress,
  }) async {
    final List<GameLibraryEntry> library =
        await GameLibraryService.loadCurrentLibraryConsolidated();
    final DateTime now = DateTime.now();

    int added = 0;
    int updated = 0;
    int unchanged = 0;
    int detailFailures = 0;

    for (int rawIndex = 0; rawIndex < rawGames.length; rawIndex += 1) {
      final Map<String, dynamic> raw = rawGames[rawIndex];
      final String title = raw['title']?.toString().trim() ?? '';

      void reportProgress({bool success = true}) {
        onProgress?.call(
          rawIndex + 1,
          rawGames.length,
          title.isEmpty ? 'Jeu PlayStation' : title,
          success,
        );
      }

      if (title.isEmpty) {
        reportProgress();
        continue;
      }

      final String externalId = raw['externalId']?.toString().trim() ?? '';
      final String coverUrl = raw['coverUrl']?.toString().trim() ?? '';
      final List<String> precisePlatforms = _readStringList(raw['platforms']);
      final int playtimeMinutes =
          int.tryParse(raw['playtimeMinutes']?.toString() ?? '') ?? 0;
      final int reportedProgress =
          int.tryParse(raw['progressPercent']?.toString() ?? '') ?? 0;
      final bool progressKnown = raw['progressKnown'] == true;
      final DateTime? lastPlayedAt = DateTime.tryParse(
        raw['lastPlayedAt']?.toString() ?? '',
      );

      final Map<String, dynamic> trophies = raw['trophies'] is Map
          ? Map<String, dynamic>.from(raw['trophies'] as Map)
          : <String, dynamic>{};

      int readCount(String key) =>
          int.tryParse(trophies[key]?.toString() ?? '') ?? 0;

      final GameAchievementSummary summary = GameAchievementSummary(
        unlocked: readCount('unlocked'),
        total: readCount('total'),
        bronzeUnlocked: readCount('bronzeUnlocked'),
        bronzeTotal: readCount('bronzeTotal'),
        silverUnlocked: readCount('silverUnlocked'),
        silverTotal: readCount('silverTotal'),
        goldUnlocked: readCount('goldUnlocked'),
        goldTotal: readCount('goldTotal'),
        platinumUnlocked: readCount('platinumUnlocked'),
        platinumTotal: readCount('platinumTotal'),
        // Le pourcentage officiel PSN est conservé séparément afin d'éviter
        // les écarts liés au poids différent des trophées Bronze/Argent/Or.
        scoreEarned: progressKnown
            ? reportedProgress.clamp(0, 100).toInt()
            : 0,
        scoreTotal: progressKnown ? 100 : 0,
      );

      int index = _findExistingGameIndex(
        library,
        title: title,
        externalId: externalId,
      );
      final GameLibraryEntry? existing = index < 0 ? null : library[index];
      final GamePlatformProfile? currentProfile =
          existing?.platformProfile(GamePlatform.playstation);

      final bool hasIncomingDetails = raw.containsKey('achievementDetails');
      final List<GameAchievementDetail> incomingDetails = hasIncomingDetails
          ? _readMapList(raw['achievementDetails'])
                .map(GameAchievementDetail.fromJson)
                .where((detail) => detail.id.trim().isNotEmpty)
                .toList(growable: false)
          : currentProfile?.achievementDetails ??
                const <GameAchievementDetail>[];
      final bool catalogInitialized = raw.containsKey(
        'achievementCatalogInitialized',
      )
          ? raw['achievementCatalogInitialized'] == true
          : currentProfile?.achievementCatalogInitialized ?? false;
      final bool detailFailed = raw['detailSyncFailed'] == true;
      if (detailFailed) {
        detailFailures += 1;
      }

      final GamePlatformProfile playStationProfile = GamePlatformProfile(
        platform: GamePlatform.playstation,
        // GameSource ne possède pas encore une valeur PlayStation dédiée.
        source: GameSource.manual,
        externalId: externalId.isEmpty ? null : externalId,
        playtimeMinutes: playtimeMinutes,
        achievements: summary,
        achievementDetails: incomingDetails,
        achievementCatalogInitialized: catalogInitialized,
        achievementsLastSyncedAt: now,
        lastPlayedAt: lastPlayedAt,
      );

      final GameStatus playStationAutomaticStatus = _automaticStatus(
        playtimeMinutes: playtimeMinutes,
        summary: summary,
        reportedProgress: reportedProgress,
      );
      final bool anotherPlatformCompleted = existing != null &&
          existing.resolvedPlatformProfiles.any(
            (profile) =>
                profile.platform != GamePlatform.playstation &&
                profile.completionPercent == 100,
          );
      final GameStatus automaticStatus = anotherPlatformCompleted
          ? GameStatus.completed
          : playStationAutomaticStatus;

      if (index < 0) {
        final String stableKey =
            externalId.isNotEmpty ? externalId : _canonicalTitle(title);

        library.add(
          GameLibraryEntry(
            id: 'psn_${_stableHash(stableKey)}',
            title: title,
            platform: GamePlatform.playstation,
            status: automaticStatus,
            statusAutomatic: true,
            favorite: false,
            progressPercent: reportedProgress.clamp(0, 100).toInt(),
            source: GameSource.manual,
            externalId: externalId.isEmpty ? null : externalId,
            coverUrl: coverUrl.isEmpty ? null : coverUrl,
            catalogPlatforms: _mergeOwnedPlatformMetadata(
              const <String>[],
              precisePlatforms,
            ),
            playtimeMinutes: playtimeMinutes,
            achievements: summary,
            achievementDetails: incomingDetails,
            achievementCatalogInitialized: catalogInitialized,
            achievementsLastSyncedAt: now,
            platformProfiles: <GamePlatformProfile>[playStationProfile],
            addedAt: now,
            updatedAt: lastPlayedAt ?? now,
          ),
        );
        added += 1;
        reportProgress(success: !detailFailed);
        continue;
      }

      final bool mayAutoClassify =
          existing!.statusAutomatic ||
          existing.status == GameStatus.unclassified ||
          automaticStatus == GameStatus.completed;
      final bool meaningfulChange = _hasMeaningfulChange(
        existing: existing,
        incomingProfile: playStationProfile,
        incomingCoverUrl: coverUrl,
        automaticStatus: automaticStatus,
        reportedProgress: reportedProgress,
      );

      GameLibraryEntry merged = existing
          .withPlatformProfile(playStationProfile)
          .copyWith(
            status: mayAutoClassify ? automaticStatus : existing.status,
            statusAutomatic: mayAutoClassify ? true : existing.statusAutomatic,
            coverUrl: (existing.coverUrl?.trim().isNotEmpty ?? false)
                ? existing.coverUrl
                : (coverUrl.isEmpty ? null : coverUrl),
            catalogPlatforms: _mergeOwnedPlatformMetadata(
              existing.catalogPlatforms,
              precisePlatforms,
            ),
            progressPercent: existing.platform == GamePlatform.playstation
                ? reportedProgress.clamp(0, 100).toInt()
                : existing.progressPercent,
            updatedAt: _latest(existing.updatedAt, lastPlayedAt),
          );

      if (existing.platform == GamePlatform.playstation) {
        merged = merged.copyWith(
          externalId: externalId.isEmpty ? existing.externalId : externalId,
          playtimeMinutes: playtimeMinutes,
          achievements: summary,
          achievementDetails: incomingDetails,
          achievementCatalogInitialized: catalogInitialized,
          achievementsLastSyncedAt: now,
        );
      }

      library[index] = merged;
      if (meaningfulChange) {
        updated += 1;
      } else {
        unchanged += 1;
      }

      reportProgress(success: !detailFailed);
    }

    _collapsePlayStationDuplicates(library);
    _collapseCrossPlatformDuplicates(library);
    library.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await GameLibraryService.saveCurrentLibrary(library);
    await GameLibraryService.loadCurrentLibraryConsolidated();

    return PlayStationSyncResult(
      added: added,
      updated: updated,
      unchanged: unchanged,
      total: rawGames.length,
      detailFailures: detailFailures,
    );
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) {
      return <String>[];
    }
    return raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static List<String> _mergeOwnedPlatformMetadata(
    List<String> existing,
    List<String> precisePlatforms,
  ) {
    final List<String> next = List<String>.from(existing);
    for (final String platform in precisePlatforms) {
      final String marker = '$_ownedPlatformMarkerPrefix$platform';
      if (!next.contains(marker)) {
        next.add(marker);
      }
    }
    return next;
  }

  static List<String> _mergeCatalogPlatformMetadata(
    List<String> a,
    List<String> b,
  ) {
    return <String>{...a, ...b}.toList(growable: false);
  }

  static List<Map<String, dynamic>> _readMapList(dynamic raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static int _incomingTrophyTotal(Map<String, dynamic> raw) {
    final Map<String, dynamic> trophies = raw['trophies'] is Map
        ? Map<String, dynamic>.from(raw['trophies'] as Map)
        : <String, dynamic>{};
    return int.tryParse(trophies['total']?.toString() ?? '') ?? 0;
  }

  static bool _summaryChanged(
    GamePlatformProfile current,
    Map<String, dynamic> raw,
  ) {
    final Map<String, dynamic> trophies = raw['trophies'] is Map
        ? Map<String, dynamic>.from(raw['trophies'] as Map)
        : <String, dynamic>{};
    int read(String key) => int.tryParse(trophies[key]?.toString() ?? '') ?? 0;
    final GameAchievementSummary before = current.computedAchievementSummary;
    return before.unlocked != read('unlocked') ||
        before.total != read('total') ||
        before.bronzeUnlocked != read('bronzeUnlocked') ||
        before.bronzeTotal != read('bronzeTotal') ||
        before.silverUnlocked != read('silverUnlocked') ||
        before.silverTotal != read('silverTotal') ||
        before.goldUnlocked != read('goldUnlocked') ||
        before.goldTotal != read('goldTotal') ||
        before.platinumUnlocked != read('platinumUnlocked') ||
        before.platinumTotal != read('platinumTotal');
  }

  static int _findExistingGameIndex(
    List<GameLibraryEntry> library, {
    required String title,
    required String externalId,
  }) {
    if (externalId.isNotEmpty) {
      final int byExternalId = library.indexWhere((entry) {
        final GamePlatformProfile? profile =
            entry.platformProfile(GamePlatform.playstation);
        return profile?.externalId == externalId;
      });
      if (byExternalId >= 0) {
        return byExternalId;
      }
    }
    return _findMatchingGameIndex(library, title);
  }

  static void _collapsePlayStationDuplicates(
    List<GameLibraryEntry> library,
  ) {
    bool mergedOne = true;

    while (mergedOne) {
      mergedOne = false;

      for (int first = 0; first < library.length; first += 1) {
        final GameLibraryEntry a = library[first];
        if (a.platformProfile(GamePlatform.playstation) == null) {
          continue;
        }

        final String key = _canonicalPlatformNeutralTitle(a.title);
        if (key.isEmpty) {
          continue;
        }

        for (int second = first + 1; second < library.length; second += 1) {
          final GameLibraryEntry b = library[second];
          if (b.platformProfile(GamePlatform.playstation) == null ||
              _canonicalPlatformNeutralTitle(b.title) != key) {
            continue;
          }

          final bool keepB = _entryMergeQuality(b) > _entryMergeQuality(a);
          final int keeperIndex = keepB ? second : first;
          final int duplicateIndex = keepB ? first : second;
          final GameLibraryEntry keeper = library[keeperIndex];
          final GameLibraryEntry duplicate = library[duplicateIndex];
          final GamePlatformProfile mergedPs = _mergePlayStationProfiles(
            keeper.platformProfile(GamePlatform.playstation)!,
            duplicate.platformProfile(GamePlatform.playstation)!,
          );

          GameLibraryEntry merged = keeper.withPlatformProfile(mergedPs);
          for (final GamePlatformProfile profile
              in duplicate.resolvedPlatformProfiles) {
            if (profile.platform == GamePlatform.playstation) {
              continue;
            }
            if (merged.platformProfile(profile.platform) == null) {
              merged = merged.withPlatformProfile(profile);
            }
          }

          final String preferredTitle = _preferredDuplicateTitle(
            keeper.title,
            duplicate.title,
          );
          final List<String> fallbackCovers = <String>{
            ...keeper.coverFallbackUrls,
            ...duplicate.coverFallbackUrls,
            if ((duplicate.coverUrl?.trim().isNotEmpty ?? false) &&
                duplicate.coverUrl != keeper.coverUrl)
              duplicate.coverUrl!.trim(),
          }.toList();

          final bool platformCompleted = merged.resolvedPlatformProfiles.any(
            (profile) => profile.completionPercent == 100,
          );
          final bool manualCompleted =
              (keeper.status == GameStatus.completed &&
                  !keeper.statusAutomatic) ||
              (duplicate.status == GameStatus.completed &&
                  !duplicate.statusAutomatic);
          final bool eitherCompleted = platformCompleted || manualCompleted ||
              keeper.status == GameStatus.completed ||
              duplicate.status == GameStatus.completed;

          merged = merged.copyWith(
            title: preferredTitle,
            favorite: keeper.favorite || duplicate.favorite,
            status: eitherCompleted ? GameStatus.completed : keeper.status,
            statusAutomatic: platformCompleted
                ? true
                : manualCompleted
                ? false
                : keeper.statusAutomatic && duplicate.statusAutomatic,
            coverUrl: (keeper.coverUrl?.trim().isNotEmpty ?? false)
                ? keeper.coverUrl
                : duplicate.coverUrl,
            coverFallbackUrls: fallbackCovers,
            catalogPlatforms: _mergeCatalogPlatformMetadata(
              keeper.catalogPlatforms,
              duplicate.catalogPlatforms,
            ),
            personalUpdatedAt: _latestNullable(
              keeper.personalUpdatedAt,
              duplicate.personalUpdatedAt,
            ),
            updatedAt: _latest(keeper.updatedAt, duplicate.updatedAt),
          );

          library[keeperIndex] = merged;
          library.removeAt(duplicateIndex);
          mergedOne = true;
          break;
        }

        if (mergedOne) {
          break;
        }
      }
    }
  }

  static int _entryMergeQuality(GameLibraryEntry entry) {
    final GamePlatformProfile? ps =
        entry.platformProfile(GamePlatform.playstation);
    final GameAchievementSummary summary =
        ps?.computedAchievementSummary ?? const GameAchievementSummary();
    final int titlePenalty = _looksLikeTrophyAlias(entry.title) ? 0 : 1000000;
    return entry.connectedPlatforms.length * 10000000 +
        titlePenalty +
        (ps?.achievementDetails.length ?? 0) * 10000 +
        summary.total * 100 +
        (ps?.playtimeMinutes ?? 0).clamp(0, 999999).toInt();
  }

  static bool _looksLikeTrophyAlias(String value) {
    return RegExp(
      r'\b(trophy\s*(?:set|list)|trophies|trophy)\b',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static String _preferredDuplicateTitle(String a, String b) {
    final bool aAlias = _looksLikeTrophyAlias(a);
    final bool bAlias = _looksLikeTrophyAlias(b);
    if (aAlias != bAlias) {
      return aAlias ? b : a;
    }
    return a.length <= b.length ? a : b;
  }

  static GamePlatformProfile _mergePlayStationProfiles(
    GamePlatformProfile a,
    GamePlatformProfile b,
  ) {
    final GameAchievementSummary aSummary = a.computedAchievementSummary;
    final GameAchievementSummary bSummary = b.computedAchievementSummary;

    int quality(GamePlatformProfile profile, GameAchievementSummary summary) {
      return profile.achievementDetails.length * 100000 +
          summary.total * 1000 +
          summary.unlocked * 10 +
          (profile.achievementCatalogInitialized ? 1 : 0);
    }

    final GamePlatformProfile preferred =
        quality(b, bSummary) > quality(a, aSummary) ? b : a;
    final GamePlatformProfile other = identical(preferred, a) ? b : a;
    final DateTime? latestSync = _latestNullable(
      a.achievementsLastSyncedAt,
      b.achievementsLastSyncedAt,
    );
    final DateTime? latestPlayed = _latestNullable(a.lastPlayedAt, b.lastPlayedAt);

    return preferred.copyWith(
      externalId: preferred.externalId?.trim().isNotEmpty == true
          ? preferred.externalId
          : other.externalId,
      playtimeMinutes: a.playtimeMinutes >= b.playtimeMinutes
          ? a.playtimeMinutes
          : b.playtimeMinutes,
      achievementCatalogInitialized:
          a.achievementCatalogInitialized || b.achievementCatalogInitialized,
      achievementsLastSyncedAt: latestSync,
      lastPlayedAt: latestPlayed,
    );
  }

  static void _collapseCrossPlatformDuplicates(List<GameLibraryEntry> library) {
    for (int index = library.length - 1; index >= 0; index -= 1) {
      final GameLibraryEntry playStationEntry = library[index];
      final GamePlatformProfile? playStationProfile =
          playStationEntry.platformProfile(GamePlatform.playstation);

      if (playStationProfile == null ||
          playStationEntry.connectedPlatforms.length != 1) {
        continue;
      }

      final String key = _canonicalPlatformNeutralTitle(playStationEntry.title);
      if (key.isEmpty) {
        continue;
      }

      final int targetIndex = library.indexWhere((candidate) {
        if (candidate.id == playStationEntry.id ||
            candidate.platformProfile(GamePlatform.playstation) != null) {
          return false;
        }
        return _canonicalPlatformNeutralTitle(candidate.title) == key;
      });

      if (targetIndex < 0) {
        continue;
      }

      final GameLibraryEntry keeper = library[targetIndex];
      final List<String> fallbackCovers = <String>{
        ...keeper.coverFallbackUrls,
        ...playStationEntry.coverFallbackUrls,
        if ((playStationEntry.coverUrl?.trim().isNotEmpty ?? false) &&
            playStationEntry.coverUrl != keeper.coverUrl)
          playStationEntry.coverUrl!.trim(),
      }.toList();

      library[targetIndex] = keeper
          .withPlatformProfile(playStationProfile)
          .copyWith(
            favorite: keeper.favorite || playStationEntry.favorite,
            coverUrl: (keeper.coverUrl?.trim().isNotEmpty ?? false)
                ? keeper.coverUrl
                : playStationEntry.coverUrl,
            coverFallbackUrls: fallbackCovers,
            catalogPlatforms: _mergeCatalogPlatformMetadata(
              keeper.catalogPlatforms,
              playStationEntry.catalogPlatforms,
            ),
            personalUpdatedAt: _latestNullable(
              keeper.personalUpdatedAt,
              playStationEntry.personalUpdatedAt,
            ),
            updatedAt: _latest(keeper.updatedAt, playStationEntry.updatedAt),
          );

      library.removeAt(index);
    }
  }

  static DateTime? _latestNullable(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static int _findMatchingGameIndex(
    List<GameLibraryEntry> library,
    String incomingTitle,
  ) {
    final String exactKey = _canonicalTitle(incomingTitle);
    final String platformNeutralKey = _canonicalPlatformNeutralTitle(
      incomingTitle,
    );

    int index = library.indexWhere(
      (entry) => _canonicalTitle(entry.title) == exactKey,
    );
    if (index >= 0) {
      return index;
    }

    if (platformNeutralKey.isEmpty) {
      return -1;
    }

    return library.indexWhere(
      (entry) =>
          _canonicalPlatformNeutralTitle(entry.title) == platformNeutralKey,
    );
  }

  static String _canonicalPlatformNeutralTitle(String value) {
    final String cleaned = value
        .toLowerCase()
        .replaceAll('™', '')
        .replaceAll('®', '')
        .replaceAll('©', '')
        .replaceAll(
          RegExp(
            r'\bfor\s+(?=(playstation\s*[45]|ps\s*[45])\b)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'\b(playstation\s*[45]|ps\s*[45])\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(trophy\s*(?:set|list)|trophies|trophy)\b',
            caseSensitive: false,
          ),
          ' ',
        );

    return cleaned.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static bool _hasMeaningfulChange({
    required GameLibraryEntry existing,
    required GamePlatformProfile incomingProfile,
    required String incomingCoverUrl,
    required GameStatus automaticStatus,
    required int reportedProgress,
  }) {
    final GamePlatformProfile? current =
        existing.platformProfile(GamePlatform.playstation);

    if (current == null) {
      return true;
    }

    final GameAchievementSummary before = current.computedAchievementSummary;
    final GameAchievementSummary after =
        incomingProfile.computedAchievementSummary;

    final bool sameSummary = before.unlocked == after.unlocked &&
        before.total == after.total &&
        before.bronzeUnlocked == after.bronzeUnlocked &&
        before.bronzeTotal == after.bronzeTotal &&
        before.silverUnlocked == after.silverUnlocked &&
        before.silverTotal == after.silverTotal &&
        before.goldUnlocked == after.goldUnlocked &&
        before.goldTotal == after.goldTotal &&
        before.platinumUnlocked == after.platinumUnlocked &&
        before.platinumTotal == after.platinumTotal &&
        before.scoreEarned == after.scoreEarned &&
        before.scoreTotal == after.scoreTotal;

    final bool sameDetails = _sameAchievementDetails(
      current.achievementDetails,
      incomingProfile.achievementDetails,
    );
    final bool coverWouldChange =
        (existing.coverUrl?.trim().isEmpty ?? true) &&
        incomingCoverUrl.trim().isNotEmpty;
    final bool statusWouldChange =
        (existing.statusAutomatic || existing.status == GameStatus.unclassified) &&
        existing.status != automaticStatus;
    final bool topLevelProgressWouldChange =
        existing.platform == GamePlatform.playstation &&
        existing.progressPercent != reportedProgress.clamp(0, 100).toInt();

    return current.externalId != incomingProfile.externalId ||
        current.playtimeMinutes != incomingProfile.playtimeMinutes ||
        current.lastPlayedAt != incomingProfile.lastPlayedAt ||
        current.achievementCatalogInitialized !=
            incomingProfile.achievementCatalogInitialized ||
        !sameSummary ||
        !sameDetails ||
        coverWouldChange ||
        statusWouldChange ||
        topLevelProgressWouldChange;
  }

  static bool _sameAchievementDetails(
    List<GameAchievementDetail> a,
    List<GameAchievementDetail> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    final Map<String, GameAchievementDetail> byId =
        <String, GameAchievementDetail>{
      for (final GameAchievementDetail detail in a) detail.id: detail,
    };
    for (final GameAchievementDetail detail in b) {
      final GameAchievementDetail? before = byId[detail.id];
      if (before == null ||
          before.platformUnlocked != detail.platformUnlocked ||
          before.platformUnlockedAt != detail.platformUnlockedAt ||
          before.name != detail.name ||
          before.groupName != detail.groupName) {
        return false;
      }
    }
    return true;
  }

  static GameStatus _automaticStatus({
    required int playtimeMinutes,
    required GameAchievementSummary summary,
    required int reportedProgress,
  }) {
    final int unlocked = summary.bronzeUnlocked +
        summary.silverUnlocked +
        summary.goldUnlocked +
        summary.platinumUnlocked;
    final int total = summary.bronzeTotal +
        summary.silverTotal +
        summary.goldTotal +
        summary.platinumTotal;

    if ((total > 0 && unlocked >= total) || reportedProgress >= 100) {
      return GameStatus.completed;
    }
    if (playtimeMinutes > 0 || unlocked > 0 || reportedProgress > 0) {
      return GameStatus.inProgress;
    }
    return GameStatus.backlog;
  }

  static DateTime _latest(DateTime current, DateTime? candidate) {
    if (candidate == null || !candidate.isAfter(current)) {
      return current;
    }
    return candidate;
  }

  static String _canonicalTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll('™', '')
        .replaceAll('®', '')
        .replaceAll('©', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static String _stableHash(String value) {
    int hash = 0x811c9dc5;
    for (final int unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _friendlyFunctionError(dynamic raw) {
    if (raw is Map && raw['error'] != null) {
      return raw['error'].toString();
    }

    final String message = raw?.toString() ?? '';
    if (message.contains('404') || message.contains('Function not found')) {
      return 'La synchronisation PlayStation n’est pas encore déployée côté Supabase.';
    }
    if (message.contains('401') || message.toLowerCase().contains('reconnect')) {
      return 'La session PlayStation a expiré. Reconnecte ton compte depuis COMPTES.';
    }
    if (message.trim().isEmpty) {
      return 'Synchronisation PlayStation indisponible.';
    }
    return 'Synchronisation PlayStation indisponible : $message';
  }
}
