import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_library_entry.dart';
import 'auth_service.dart';
import 'game_library_service.dart';
import 'gaming_accounts_service.dart';
import 'supabase_service.dart';

class SteamSyncException implements Exception {
  final String message;

  const SteamSyncException(this.message);

  @override
  String toString() => message;
}

class SteamLibrarySyncResult {
  final String steamId;
  final int detected;
  final int added;
  final int updated;
  final Set<String> activityChangedAppIds;
  final String? warning;

  const SteamLibrarySyncResult({
    required this.steamId,
    required this.detected,
    required this.added,
    required this.updated,
    required this.activityChangedAppIds,
    required this.warning,
  });
}

class SteamAchievementSyncIssue {
  final String gameId;
  final String title;
  final String appId;
  final String message;

  const SteamAchievementSyncIssue({
    required this.gameId,
    required this.title,
    required this.appId,
    required this.message,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gameId': gameId,
      'title': title,
      'appId': appId,
      'message': message,
    };
  }

  factory SteamAchievementSyncIssue.fromJson(Map<String, dynamic> json) {
    return SteamAchievementSyncIssue(
      gameId: json['gameId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      appId: json['appId']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

class SteamAllAchievementSyncResult {
  final int linkedGames;
  final int checkedGames;
  final int skippedFreshGames;
  final int gamesWithoutAchievements;
  final int unavailableGames;
  final int newlyUnlocked;
  final int totalAchievementsKnown;
  final List<SteamAchievementSyncIssue> issues;

  const SteamAllAchievementSyncResult({
    required this.linkedGames,
    required this.checkedGames,
    required this.skippedFreshGames,
    required this.gamesWithoutAchievements,
    required this.unavailableGames,
    required this.newlyUnlocked,
    required this.totalAchievementsKnown,
    required this.issues,
  });
}

class SteamFullSyncResult {
  final SteamLibrarySyncResult library;
  final SteamAllAchievementSyncResult achievements;

  const SteamFullSyncResult({
    required this.library,
    required this.achievements,
  });
}

enum SteamSyncPhase { idle, library, achievements, completed, failed }

enum SteamSyncGameOutcome { success, failed }

class SteamSyncUiState {
  final SteamSyncPhase phase;
  final String label;
  final int current;
  final int total;
  final String? message;
  final List<SteamSyncGameOutcome> outcomes;
  final List<SteamAchievementSyncIssue> issues;

  const SteamSyncUiState({
    required this.phase,
    required this.label,
    this.current = 0,
    this.total = 0,
    this.message,
    this.outcomes = const <SteamSyncGameOutcome>[],
    this.issues = const <SteamAchievementSyncIssue>[],
  });

  const SteamSyncUiState.idle()
    : phase = SteamSyncPhase.idle,
      label = '',
      current = 0,
      total = 0,
      message = null,
      outcomes = const <SteamSyncGameOutcome>[],
      issues = const <SteamAchievementSyncIssue>[];

  bool get running =>
      phase == SteamSyncPhase.library || phase == SteamSyncPhase.achievements;
}

class SteamAchievementSyncResult {
  final GameAchievementSummary summary;
  final List<GameAchievementDetail> achievements;
  final int newlyUnlocked;
  final GameLibraryEntry updatedEntry;
  final List<GameAchievementDetail> newlyUnlockedDetails;
  final bool firstDetailedSync;

  const SteamAchievementSyncResult({
    required this.summary,
    required this.achievements,
    required this.newlyUnlocked,
    required this.updatedEntry,
    required this.newlyUnlockedDetails,
    required this.firstDetailedSync,
  });
}

class SteamSyncService {
  SteamSyncService._();

  static Future<SteamFullSyncResult>? _activeSync;
  static bool _retryingIssues = false;
  static String? _cachedOfficialSteamId;

  static final ValueNotifier<SteamSyncUiState> syncState =
      ValueNotifier<SteamSyncUiState>(const SteamSyncUiState.idle());

  static bool get backgroundSyncRunning =>
      _activeSync != null || _retryingIssues;
  static const String _steamRefPrefix = 'project_xp_steam_reference_';
  static const String _steamIdPrefix = 'project_xp_steam_id_';
  static const String _steamIssuesPrefix = 'project_xp_steam_sync_issues_';
  static const String _steamIssueRetryPrefix =
      'project_xp_steam_sync_issue_retries_';
  static const int maxIssueRetryAttempts = 3;
  static const Duration _achievementRequestTimeout = Duration(seconds: 25);
  static const int _achievementSyncConcurrency = 2;

  static Future<String?> _currentUserId() {
    return AuthService.getCurrentUserId();
  }

  static Future<String?> _issuesStorageKey() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.trim().isEmpty) {
      return null;
    }
    return '$_steamIssuesPrefix${userId.trim()}';
  }

  static Future<String?> _issueRetryStorageKey() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.trim().isEmpty) {
      return null;
    }
    return '$_steamIssueRetryPrefix${userId.trim()}';
  }

  static Future<int> loadIssueRetryAttempts() async {
    final String? key = await _issueRetryStorageKey();
    if (key == null) {
      return 0;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(key) ?? 0)
        .clamp(0, maxIssueRetryAttempts)
        .toInt();
  }

  static Future<void> _saveIssueRetryAttempts(int attempts) async {
    final String? key = await _issueRetryStorageKey();
    if (key == null) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int safeAttempts = attempts
        .clamp(0, maxIssueRetryAttempts)
        .toInt();
    if (safeAttempts <= 0) {
      await prefs.remove(key);
      return;
    }
    await prefs.setInt(key, safeAttempts);
  }

  static Future<List<SteamAchievementSyncIssue>> loadSavedIssues() async {
    final String? key = await _issuesStorageKey();
    if (key == null) {
      return const <SteamAchievementSyncIssue>[];
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString(key)?.trim() ?? '';
    if (raw.isEmpty) {
      return const <SteamAchievementSyncIssue>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <SteamAchievementSyncIssue>[];
      }

      final List<SteamAchievementSyncIssue> issues =
          <SteamAchievementSyncIssue>[];
      for (final dynamic item in decoded) {
        if (item is Map) {
          issues.add(
            SteamAchievementSyncIssue.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
      return List<SteamAchievementSyncIssue>.unmodifiable(issues);
    } catch (_) {
      return const <SteamAchievementSyncIssue>[];
    }
  }

  static Future<void> _saveIssues(
    List<SteamAchievementSyncIssue> issues,
  ) async {
    final String? key = await _issuesStorageKey();
    if (key == null) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (issues.isEmpty) {
      await prefs.remove(key);
      return;
    }

    await prefs.setString(
      key,
      jsonEncode(issues.map((issue) => issue.toJson()).toList()),
    );
  }

  static Future<String?> getSavedReference() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_steamRefPrefix$userId');
  }

  static Future<void> _saveIdentity({
    required String reference,
    required String steamId,
  }) async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait<bool>([
      prefs.setString('$_steamRefPrefix$userId', reference.trim()),
      prefs.setString('$_steamIdPrefix$userId', steamId),
    ]);
  }

  static Future<String?> getSavedSteamId() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_steamIdPrefix$userId');
  }

  static Future<String?> getLegacySavedSteamId() {
    return getSavedSteamId();
  }

  static Future<String?> _officialSteamId() async {
    final String cached = _cachedOfficialSteamId?.trim() ?? '';
    if (cached.isNotEmpty) {
      return cached;
    }

    final GamingAccountLink? official = await GamingAccountsService.account(
      GamingPlatformProvider.steam,
    );
    final String officialId = official?.providerUserId.trim() ?? '';

    if (officialId.isNotEmpty) {
      _cachedOfficialSteamId = officialId;
      return officialId;
    }
    return null;
  }

  static Future<String?> getLinkedSteamId() async {
    final String officialId = (await _officialSteamId() ?? '').trim();
    if (officialId.isNotEmpty) {
      return officialId;
    }

    final String legacy = (await getSavedSteamId() ?? '').trim();
    return legacy.isEmpty ? null : legacy;
  }

  static Future<String?> getSyncReference() async {
    final String officialId = (await _officialSteamId() ?? '').trim();
    if (officialId.isNotEmpty) {
      return officialId;
    }

    final String savedId = (await getSavedSteamId() ?? '').trim();
    if (savedId.isNotEmpty) {
      return savedId;
    }

    final String legacyReference = (await getSavedReference() ?? '').trim();
    return legacyReference.isEmpty ? null : legacyReference;
  }

  static Future<bool> hasSyncIdentity() async {
    return (await getSyncReference())?.trim().isNotEmpty == true;
  }

  static Future<void> clearSavedIdentity() async {
    _cachedOfficialSteamId = null;
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait<bool>([
      prefs.remove('$_steamRefPrefix$userId'),
      prefs.remove('$_steamIdPrefix$userId'),
      prefs.remove('$_steamIssuesPrefix$userId'),
      prefs.remove('$_steamIssueRetryPrefix$userId'),
    ]);
  }

  static Future<SteamLibrarySyncResult> syncLibraryForLinkedAccount() async {
    final String reference = (await getSyncReference() ?? '').trim();

    if (reference.isEmpty) {
      throw const SteamSyncException(
        'Lie d’abord ton compte Steam depuis COMPTES.',
      );
    }

    return syncLibrary(reference);
  }

  /// Synchronisation non bloquante lancée au démarrage de Project XP.
  ///
  /// La bibliothèque Steam et les succès de TOUS les jeux liés sont rafraîchis
  /// à chaque lancement. Le Hall n'attend jamais cette opération : elle reste
  /// en arrière-plan. L'ancien plafond artificiel de 8 jeux est supprimé.
  static Future<void> syncAtStartup() async {
    final String reference = (await getSyncReference() ?? '').trim();

    if (reference.isEmpty) {
      return;
    }

    try {
      await syncEverything(
        force: false,
        staleAfter: const Duration(hours: 12),
      );
    } on SteamSyncException catch (error) {
      debugPrint('Sync Steam démarrage ignorée : ${error.message}');
    } catch (error) {
      debugPrint('Sync Steam démarrage ignorée : $error');
    }
  }

  static Future<SteamFullSyncResult> syncEverything({
    bool force = false,
    int? maxGames,
    Duration staleAfter = const Duration(hours: 24),
  }) {
    final Future<SteamFullSyncResult>? active = _activeSync;

    if (active != null) {
      return active;
    }

    final Future<SteamFullSyncResult> future = _runFullSync(
      force: force,
      maxGames: maxGames,
      staleAfter: staleAfter,
    );

    _activeSync = future;
    return future;
  }

  static Future<SteamFullSyncResult> _runFullSync({
    required bool force,
    required int? maxGames,
    required Duration staleAfter,
  }) async {
    final String reference = (await getSyncReference() ?? '').trim();

    if (reference.isEmpty) {
      throw const SteamSyncException(
        'Lie d’abord ton compte Steam depuis COMPTES.',
      );
    }

    if (force) {
      await _saveIssueRetryAttempts(0);
    }

    syncState.value = const SteamSyncUiState(
      phase: SteamSyncPhase.library,
      label: 'SYNCHRO • Bibliothèque…',
    );

    try {
      final SteamLibrarySyncResult libraryResult = await syncLibrary(reference);

      final List<GameLibraryEntry> library =
          await GameLibraryService.loadCurrentLibraryConsolidated();

      syncState.value = const SteamSyncUiState(
        phase: SteamSyncPhase.achievements,
        label: 'SYNCHRO • Succès…',
      );

      final SteamAllAchievementSyncResult achievementResult =
          await syncAllAchievements(
            library: library,
            activityChangedAppIds: libraryResult.activityChangedAppIds,
            force: force,
            staleAfter: staleAfter,
            maxGames: maxGames,
            onProgress: (
              int completed,
              int total,
              String title,
              List<SteamSyncGameOutcome> outcomes,
            ) {
              syncState.value = SteamSyncUiState(
                phase: SteamSyncPhase.achievements,
                label: total <= 0
                    ? 'Succès Steam à jour'
                    : 'SYNCHRO • $completed/$total • $title',
                current: completed,
                total: total,
                outcomes: outcomes,
              );
            },
          );

      final List<String> details = <String>[
        '${libraryResult.detected} jeux',
        '${achievementResult.checkedGames} jeux vérifiés',
        if (achievementResult.totalAchievementsKnown > 0)
          '${achievementResult.totalAchievementsKnown} succès connus',
        if (achievementResult.gamesWithoutAchievements > 0)
          '${achievementResult.gamesWithoutAchievements} sans succès',
        if (achievementResult.unavailableGames > 0)
          '${achievementResult.unavailableGames} à revoir',
        if (achievementResult.newlyUnlocked > 0)
          '${achievementResult.newlyUnlocked} nouveaux succès',
      ];

      String message = 'Synchronisation terminée • ${details.join(' • ')}.';

      if (achievementResult.issues.isNotEmpty) {
        final String issueTitles = achievementResult.issues
            .take(5)
            .map((issue) => issue.title.trim())
            .where((title) => title.isNotEmpty)
            .join(', ');

        if (issueTitles.isNotEmpty) {
          message += ' À revoir : $issueTitles';

          final int remaining = achievementResult.issues.length - 5;
          if (remaining > 0) {
            message += ' (+$remaining)';
          }

          message += '.';
        }
      }

      if (libraryResult.warning?.trim().isNotEmpty == true) {
        message += ' ${libraryResult.warning!.trim()}';
      }

      await _saveIssues(achievementResult.issues);
      if (achievementResult.issues.isEmpty) {
        await _saveIssueRetryAttempts(0);
      }

      final SteamSyncUiState progressState = syncState.value;

      syncState.value = SteamSyncUiState(
        phase: SteamSyncPhase.completed,
        label: 'Synchronisation terminée',
        current: progressState.current,
        total: progressState.total,
        message: message,
        outcomes: progressState.outcomes,
        issues: achievementResult.issues,
      );

      return SteamFullSyncResult(
        library: libraryResult,
        achievements: achievementResult,
      );
    } on SteamSyncException catch (error) {
      final SteamSyncUiState progressState = syncState.value;

      syncState.value = SteamSyncUiState(
        phase: SteamSyncPhase.failed,
        label: 'Synchronisation échouée',
        current: progressState.current,
        total: progressState.total,
        message: 'Synchronisation échouée • ${error.message}',
        outcomes: progressState.outcomes,
        issues: progressState.issues,
      );
      rethrow;
    } catch (error) {
      final SteamSyncException wrapped = SteamSyncException(
        _friendlyFunctionError(error.toString()),
      );
      final SteamSyncUiState progressState = syncState.value;

      syncState.value = SteamSyncUiState(
        phase: SteamSyncPhase.failed,
        label: 'Synchronisation échouée',
        current: progressState.current,
        total: progressState.total,
        message: 'Synchronisation échouée • ${wrapped.message}',
        outcomes: progressState.outcomes,
        issues: progressState.issues,
      );

      throw wrapped;
    } finally {
      _activeSync = null;
    }
  }

  /// Relance uniquement les jeux restés "à revoir" après la dernière
  /// synchronisation complète. Les jeux déjà validés ne sont pas rappelés.
  static Future<void> retryFailedAchievements() async {
    if (_activeSync != null || _retryingIssues) {
      return;
    }

    final List<SteamAchievementSyncIssue> previousIssues =
        syncState.value.issues.isNotEmpty
        ? List<SteamAchievementSyncIssue>.from(syncState.value.issues)
        : List<SteamAchievementSyncIssue>.from(await loadSavedIssues());

    if (previousIssues.isEmpty) {
      return;
    }

    final int previousAttempts = await loadIssueRetryAttempts();
    if (previousAttempts >= maxIssueRetryAttempts) {
      return;
    }
    final int currentAttempt = previousAttempts + 1;
    await _saveIssueRetryAttempts(currentAttempt);

    _retryingIssues = true;

    try {
      final List<GameLibraryEntry> library =
          await GameLibraryService.loadCurrentLibraryConsolidated();
      final List<SteamAchievementSyncIssue> remaining =
          <SteamAchievementSyncIssue>[];
      final List<SteamSyncGameOutcome> outcomes = <SteamSyncGameOutcome>[];

      for (int index = 0; index < previousIssues.length; index += 1) {
        final SteamAchievementSyncIssue issue = previousIssues[index];

        GameLibraryEntry? game;
        for (final GameLibraryEntry candidate in library) {
          final String candidateAppId = candidate
                  .platformProfile(GamePlatform.steam)
                  ?.externalId
                  ?.trim() ??
              '';

          if (candidate.id == issue.gameId ||
              (issue.appId.isNotEmpty && candidateAppId == issue.appId)) {
            game = candidate;
            break;
          }
        }

        syncState.value = SteamSyncUiState(
          phase: SteamSyncPhase.achievements,
          label:
              'Nouvel essai Steam • ${index + 1}/${previousIssues.length} • '
              '${issue.title}',
          current: index,
          total: previousIssues.length,
          outcomes: List<SteamSyncGameOutcome>.unmodifiable(outcomes),
          issues: List<SteamAchievementSyncIssue>.unmodifiable(previousIssues),
        );

        if (game == null) {
          remaining.add(
            SteamAchievementSyncIssue(
              gameId: issue.gameId,
              title: issue.title,
              appId: issue.appId,
              message: 'Le jeu n’est plus présent dans la Bibliothèque.',
            ),
          );
          outcomes.add(SteamSyncGameOutcome.failed);
        } else {
          try {
            await syncAchievements(game);
            outcomes.add(SteamSyncGameOutcome.success);
          } on SteamSyncException catch (error) {
            remaining.add(
              SteamAchievementSyncIssue(
                gameId: issue.gameId,
                title: issue.title,
                appId: issue.appId,
                message: error.message,
              ),
            );
            outcomes.add(SteamSyncGameOutcome.failed);
          } catch (error) {
            remaining.add(
              SteamAchievementSyncIssue(
                gameId: issue.gameId,
                title: issue.title,
                appId: issue.appId,
                message: _friendlyFunctionError(error),
              ),
            );
            outcomes.add(SteamSyncGameOutcome.failed);
          }
        }

        syncState.value = SteamSyncUiState(
          phase: SteamSyncPhase.achievements,
          label:
              'Nouvel essai Steam • ${index + 1}/${previousIssues.length} • '
              '${issue.title}',
          current: index + 1,
          total: previousIssues.length,
          outcomes: List<SteamSyncGameOutcome>.unmodifiable(outcomes),
          issues: List<SteamAchievementSyncIssue>.unmodifiable(remaining),
        );

        if (index + 1 < previousIssues.length) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }

      await _saveIssues(remaining);
      if (remaining.isEmpty) {
        await _saveIssueRetryAttempts(0);
      }

      syncState.value = SteamSyncUiState(
        phase: SteamSyncPhase.completed,
        label: remaining.isEmpty
            ? 'Jeux à revoir corrigés'
            : '${remaining.length} jeu${remaining.length > 1 ? 'x' : ''} '
                'encore à revoir',
        current: previousIssues.length,
        total: previousIssues.length,
        message: remaining.isEmpty
            ? 'Tous les jeux à revoir ont été resynchronisés.'
            : 'Certains jeux restent indisponibles côté Steam.',
        outcomes: List<SteamSyncGameOutcome>.unmodifiable(outcomes),
        issues: List<SteamAchievementSyncIssue>.unmodifiable(remaining),
      );
    } catch (error) {
      syncState.value = SteamSyncUiState(
        phase: SteamSyncPhase.failed,
        label: 'Nouvel essai Steam impossible',
        message: _friendlyFunctionError(error),
        issues: List<SteamAchievementSyncIssue>.unmodifiable(previousIssues),
      );
    } finally {
      _retryingIssues = false;
    }
  }

  static Future<SteamLibrarySyncResult> syncLibrary(
    String steamReference,
  ) async {
    final String cleanReference = steamReference.trim();
    if (cleanReference.isEmpty) {
      throw const SteamSyncException(
        'Entre ton SteamID64, ton URL de profil Steam ou ton identifiant personnalisé.',
      );
    }

    await SupabaseService.ensureAnonymousSession();

    try {
      final FunctionResponse response = await SupabaseService.client.functions
          .invoke(
            'steam-sync',
            body: {'action': 'library', 'steamRef': cleanReference},
          );

      final dynamic raw = response.data;
      if (raw is! Map) {
        throw const SteamSyncException(
          'Réponse Steam invalide reçue par Project XP.',
        );
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(raw);
      if (data['ok'] != true) {
        throw SteamSyncException(
          data['error']?.toString() ?? 'La synchronisation Steam a échoué.',
        );
      }

      final String steamId = data['steamId']?.toString() ?? '';
      final dynamic gamesRaw = data['games'];
      if (steamId.isEmpty || gamesRaw is! List) {
        throw const SteamSyncException(
          'Steam n’a pas renvoyé de bibliothèque exploitable.',
        );
      }

      final DateTime now = DateTime.now();
      final List<GameLibraryEntry> previousLibrary =
          await GameLibraryService.loadCurrentLibraryConsolidated();
      final Map<String, GamePlatformProfile> previousSteamByAppId =
          <String, GamePlatformProfile>{};

      for (final GameLibraryEntry existing in previousLibrary) {
        final GamePlatformProfile? steam = existing.platformProfile(
          GamePlatform.steam,
        );
        final String appId = steam?.externalId?.trim() ?? '';
        if (appId.isNotEmpty) {
          previousSteamByAppId[appId] = steam!;
        }
      }

      final Set<String> activityChangedAppIds = <String>{};
      final List<GameLibraryEntry> imported = <GameLibraryEntry>[];

      for (final dynamic item in gamesRaw) {
        if (item is! Map) {
          continue;
        }
        final Map<String, dynamic> game = Map<String, dynamic>.from(item);
        final String appId = game['appid']?.toString() ?? '';
        final String title = game['name']?.toString().trim() ?? '';
        if (appId.isEmpty || title.isEmpty) {
          continue;
        }

        final int playtime = game['playtime_forever'] is int
            ? game['playtime_forever'] as int
            : int.tryParse(game['playtime_forever']?.toString() ?? '') ?? 0;

        final int lastPlayedSeconds = game['rtime_last_played'] is int
            ? game['rtime_last_played'] as int
            : int.tryParse(game['rtime_last_played']?.toString() ?? '') ?? 0;

        final DateTime? lastPlayedAt = lastPlayedSeconds > 0
            ? DateTime.fromMillisecondsSinceEpoch(lastPlayedSeconds * 1000)
            : null;

        final GamePlatformProfile steamProfile = GamePlatformProfile(
          platform: GamePlatform.steam,
          source: GameSource.steam,
          externalId: appId,
          playtimeMinutes: playtime,
          lastPlayedAt: lastPlayedAt,
        );

        final GamePlatformProfile? previous = previousSteamByAppId[appId];
        final bool playtimeChanged =
            previous == null || previous.playtimeMinutes != playtime;
        final bool lastPlayedChanged =
            previous == null ||
            previous.lastPlayedAt?.millisecondsSinceEpoch !=
                lastPlayedAt?.millisecondsSinceEpoch;

        if (playtimeChanged || lastPlayedChanged) {
          activityChangedAppIds.add(appId);
        }

        // On ne conserve que des assets suffisamment grands pour servir de
        // jaquette. Les minuscules icônes Steam ne sont plus utilisées :
        // agrandies en portrait, elles donnaient l'impression d'une cover
        // extrêmement pixelisée.
        final List<String> coverFallbackUrls = <String>[
          'https://shared.fastly.steamstatic.com/store_item_assets/'
              'steam/apps/$appId/library_600x900_2x.jpg',
          'https://shared.cloudflare.steamstatic.com/store_item_assets/'
              'steam/apps/$appId/library_600x900_2x.jpg',
          'https://steamcdn-a.akamaihd.net/steam/apps/'
              '$appId/library_600x900_2x.jpg',
          'https://cdn.akamai.steamstatic.com/steam/apps/'
              '$appId/library_600x900_2x.jpg',
          'https://shared.fastly.steamstatic.com/store_item_assets/'
              'steam/apps/$appId/library_600x900.jpg',
          'https://shared.cloudflare.steamstatic.com/store_item_assets/'
              'steam/apps/$appId/library_600x900.jpg',
          'https://steamcdn-a.akamaihd.net/steam/apps/'
              '$appId/library_600x900.jpg',
          'https://cdn.akamai.steamstatic.com/steam/apps/'
              '$appId/library_600x900.jpg',
        ];

        imported.add(
          GameLibraryEntry(
            id: 'steam_$appId',
            title: title,
            platform: GamePlatform.steam,
            status: playtime > 0 ? GameStatus.inProgress : GameStatus.backlog,
            statusAutomatic: true,
            favorite: false,
            progressPercent: 0,
            source: GameSource.steam,
            externalId: appId,
            coverUrl:
                'https://shared.fastly.steamstatic.com/'
                'store_item_assets/steam/apps/'
                '$appId/library_600x900_2x.jpg',
            coverFallbackUrls: coverFallbackUrls,
            playtimeMinutes: playtime,
            achievements: const GameAchievementSummary(),
            platformProfiles: <GamePlatformProfile>[steamProfile],
            addedAt: now,
            updatedAt: lastPlayedAt ?? now,
          ),
        );
      }

      final ({int added, int updated}) merge =
          await GameLibraryService.mergeSteamGames(imported);
      await _saveIdentity(reference: cleanReference, steamId: steamId);

      return SteamLibrarySyncResult(
        steamId: steamId,
        detected: imported.length,
        added: merge.added,
        updated: merge.updated,
        activityChangedAppIds: Set<String>.unmodifiable(activityChangedAppIds),
        warning: data['warning']?.toString(),
      );
    } on FunctionException catch (error) {
      throw SteamSyncException(_friendlyFunctionError(error.details));
    } on SteamSyncException {
      rethrow;
    } catch (error) {
      throw SteamSyncException(_friendlyFunctionError(error.toString()));
    }
  }

  static Future<SteamAchievementSyncResult> syncAchievements(
    GameLibraryEntry entry, {
    bool persist = true,
    bool announceNewUnlocks = true,
  }) async {
    final GamePlatformProfile? steamProfile = entry.platformProfile(
      GamePlatform.steam,
    );

    if (steamProfile == null ||
        steamProfile.externalId == null ||
        steamProfile.externalId!.isEmpty) {
      throw const SteamSyncException(
        'Ce jeu n’est pas encore lié à une version Steam.',
      );
    }

    final String? steamId = await getLinkedSteamId();
    if (steamId == null || steamId.isEmpty) {
      throw const SteamSyncException(
        'Synchronise d’abord ta bibliothèque Steam.',
      );
    }

    await SupabaseService.ensureAnonymousSession();

    try {
      final FunctionResponse response = await SupabaseService.client.functions
          .invoke(
            'steam-sync',
            body: {
              'action': 'achievements',
              'steamId': steamId,
              'appId': steamProfile.externalId,
            },
          )
          .timeout(_achievementRequestTimeout);

      final dynamic raw = response.data;
      if (raw is! Map) {
        throw const SteamSyncException('Réponse Steam invalide.');
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(raw);

      if (data['ok'] != true) {
        throw SteamSyncException(
          data['error']?.toString() ??
              'Impossible de synchroniser les succès Steam.',
        );
      }

      final dynamic rawAchievements = data['achievements'];

      final List<GameAchievementDetail> remote = <GameAchievementDetail>[];

      if (rawAchievements is List) {
        for (final dynamic item in rawAchievements) {
          if (item is! Map) {
            continue;
          }

          final Map<String, dynamic> row = Map<String, dynamic>.from(item);

          final String id = row['id']?.toString().trim() ?? '';

          if (id.isEmpty) {
            continue;
          }

          final String icon = row['iconUrl']?.toString().trim() ?? '';

          remote.add(
            GameAchievementDetail(
              id: id,
              name: row['name']?.toString().trim().isNotEmpty == true
                  ? row['name'].toString().trim()
                  : id,
              description: row['description']?.toString().trim() ?? '',
              iconUrl: icon.isEmpty ? null : icon,
              hidden: row['hidden'] == true,
              kind: GameAchievementKind.generic,
              platformUnlocked: row['platformUnlocked'] == true,
              manuallyUnlocked: false,
              platformUnlockedAt: DateTime.tryParse(
                row['platformUnlockedAt']?.toString() ?? '',
              ),
            ),
          );
        }
      }

      final Map<String, GameAchievementDetail> previousById =
          <String, GameAchievementDetail>{
            for (final GameAchievementDetail achievement
                in steamProfile.achievementDetails)
              achievement.id: achievement,
          };

      final List<GameAchievementDetail> newlyUnlockedDetails =
          <GameAchievementDetail>[];

      // Le catalogue renvoyé par Steam est la référence officielle pour le
      // statut automatique. Les anciennes entrées locales ne doivent pas
      // empêcher un vrai 100 % Steam de passer le jeu en Terminé.
      final int officialAchievementTotal = remote.length;
      final int officialUnlocked = remote
          .where((achievement) => achievement.platformUnlocked)
          .length;

      final List<GameAchievementDetail> merged = remote.map((
        GameAchievementDetail incoming,
      ) {
        final GameAchievementDetail? previous = previousById[incoming.id];

        final bool wasUnlocked = previous?.isUnlocked ?? false;

        // Une coche manuelle reste vraie tant que Steam ne l'a pas encore
        // confirmée. Dès que Steam confirme, la source devient officielle.
        final bool manualStillNeeded = incoming.platformUnlocked
            ? false
            : previous?.manuallyUnlocked ?? false;

        final GameAchievementDetail result = incoming.copyWith(
          manuallyUnlocked: manualStillNeeded,
          manuallyUnlockedAt: manualStillNeeded
              ? previous?.manuallyUnlockedAt
              : null,
          clearManuallyUnlockedAt: !manualStillNeeded,
        );

        if (!wasUnlocked && result.isUnlocked) {
          newlyUnlockedDetails.add(result);
        }

        return result;
      }).toList();

      // On conserve uniquement les accomplissements réellement ajoutés /
      // cochés manuellement qui ne font pas partie du catalogue Steam actuel.
      // Une ancienne entrée distante supprimée du schéma Steam ne doit plus
      // gonfler le dénominateur et transformer artificiellement un 100 % en
      // progression partielle.
      final Set<String> remoteIds = merged
          .map((achievement) => achievement.id)
          .toSet();

      for (final GameAchievementDetail previous
          in steamProfile.achievementDetails) {
        if (!remoteIds.contains(previous.id) && previous.manuallyUnlocked) {
          merged.add(
            previous.copyWith(
              platformUnlocked: false,
              clearPlatformUnlockedAt: true,
            ),
          );
        }
      }

      merged.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final GamePlatformProfile updatedSteam = steamProfile.copyWith(
        achievementDetails: merged,
        achievementCatalogInitialized: true,
        achievementsLastSyncedAt: DateTime.now(),
      );

      final GameAchievementSummary summary =
          updatedSteam.computedAchievementSummary;

      final bool firstDetailedSync =
          !steamProfile.achievementCatalogInitialized;

      GameLibraryEntry updated = entry.withPlatformProfile(
        updatedSteam.copyWith(achievements: summary),
      );

      // Compatibilité avec les anciennes fiches qui étaient elles-mêmes Steam.
      if (entry.platform == GamePlatform.steam) {
        updated = updated.copyWith(
          externalId: steamProfile.externalId,
          playtimeMinutes: updatedSteam.playtimeMinutes,
          achievements: summary,
          achievementDetails: merged,
          achievementCatalogInitialized: true,
          achievementsLastSyncedAt: DateTime.now(),
        );
      }

      // Steam redevient la référence dès qu'il possède une donnée
      // suffisamment fiable. Un choix manuel ne doit pas figer une information
      // objectivement contredite par la plateforme.
      //
      // - catalogue Steam connu et non vide : 0 % = Pas commencé si aucune
      //   activité, progression partielle = En cours, 100 % = Terminé ;
      // - jeu Steam réellement sans succès : Steam ne sait pas si l'histoire
      //   a été terminée, donc un Terminé / Abandonné manuel reste pertinent ;
      // - Pas commencé / En cours sont toujours corrigés par le temps de jeu
      //   et les succès réellement débloqués sur Steam.
      final int platformUnlocked = officialAchievementTotal > 0
          ? officialUnlocked
          : summary.unlocked;
      final int achievementTotal = officialAchievementTotal > 0
          ? officialAchievementTotal
          : summary.total;
      final bool hasKnownAchievementProgress = achievementTotal > 0;
      final bool hasStarted =
          updatedSteam.playtimeMinutes > 0 || platformUnlocked > 0;

      // Un jeu terminé sur une plateforme reste Terminé dans la bibliothèque
      // multi-plateforme. Une progression PlayStation / Xbox plus faible ne
      // doit pas rétrograder un Perfect Steam, et inversement.
      final bool anotherPlatformCompleted = entry.resolvedPlatformProfiles.any(
        (profile) =>
            profile.platform != GamePlatform.steam &&
            profile.completionPercent == 100,
      );

      GameStatus automaticStatus;
      if (anotherPlatformCompleted ||
          (hasKnownAchievementProgress && platformUnlocked >= achievementTotal)) {
        automaticStatus = GameStatus.completed;
      } else if (hasStarted) {
        automaticStatus = GameStatus.inProgress;
      } else {
        automaticStatus = GameStatus.backlog;
      }

      final bool preserveManualOutcome =
          !hasKnownAchievementProgress &&
          !entry.statusAutomatic &&
          (entry.status == GameStatus.completed ||
              entry.status == GameStatus.abandoned);

      final DateTime now = DateTime.now();
      DateTime recentAt = entry.updatedAt;

      // Une synchro technique ne change pas l'activité récente. En revanche,
      // un succès réellement nouveau peut avancer la date avec SON horodatage
      // Steam, jamais avec l'heure de la synchronisation.
      if (!firstDetailedSync && newlyUnlockedDetails.isNotEmpty) {
        DateTime? latestUnlockAt;
        for (final GameAchievementDetail achievement in newlyUnlockedDetails) {
          final DateTime? unlockedAt = achievement.platformUnlockedAt;
          if (unlockedAt != null &&
              (latestUnlockAt == null || unlockedAt.isAfter(latestUnlockAt))) {
            latestUnlockAt = unlockedAt;
          }
        }
        final DateTime rawMeaningfulDate = latestUnlockAt ?? DateTime.now();
        final DateTime meaningfulDate =
            rawMeaningfulDate.isAfter(now.add(const Duration(minutes: 10)))
            ? now
            : rawMeaningfulDate;
        if (meaningfulDate.isAfter(recentAt)) {
          recentAt = meaningfulDate;
        }
      }

      updated = updated.copyWith(
        status: preserveManualOutcome ? entry.status : automaticStatus,
        statusAutomatic: !preserveManualOutcome,
        updatedAt: recentAt,
      );

      if (persist) {
        await GameLibraryService.updateGame(
          updated,
          announceAchievementUnlocks: false,
          technicalUpdate: true,
        );
      }

      if (persist &&
          announceNewUnlocks &&
          !firstDetailedSync &&
          newlyUnlockedDetails.isNotEmpty) {
        await _announceNewAchievements(
          entry: entry,
          updatedSteam: updatedSteam,
          achievements: newlyUnlockedDetails,
        );
      }

      return SteamAchievementSyncResult(
        summary: summary,
        achievements: merged,
        newlyUnlocked: firstDetailedSync ? 0 : newlyUnlockedDetails.length,
        updatedEntry: updated,
        newlyUnlockedDetails: List<GameAchievementDetail>.unmodifiable(
          newlyUnlockedDetails,
        ),
        firstDetailedSync: firstDetailedSync,
      );
    } on TimeoutException {
      throw const SteamSyncException(
        'Steam n’a pas répondu à temps pour ce jeu. '
        'Tu peux le réessayer depuis JEUX À REVOIR.',
      );
    } on FunctionException catch (error) {
      throw SteamSyncException(_friendlyFunctionError(error.details));
    } on SteamSyncException {
      rethrow;
    } catch (error) {
      throw SteamSyncException(_friendlyFunctionError(error.toString()));
    }
  }

  static Future<void> _announceNewAchievements({
    required GameLibraryEntry entry,
    required GamePlatformProfile updatedSteam,
    required List<GameAchievementDetail> achievements,
  }) async {
    if (achievements.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<GameAchievementDetail> ordered =
        List<GameAchievementDetail>.from(achievements)..sort((a, b) {
          final DateTime aDate = a.platformUnlockedAt ?? now;
          final DateTime bDate = b.platformUnlockedAt ?? now;
          return bDate.compareTo(aDate);
        });

    DateTime safeDate(GameAchievementDetail achievement) {
      final DateTime? raw = achievement.platformUnlockedAt;
      if (raw == null || raw.isAfter(now.add(const Duration(minutes: 10)))) {
        return now;
      }
      return raw;
    }

    for (final GameAchievementDetail achievement in ordered.take(5)) {
      await GameLibraryService.addActivity(
        title: 'Succès « ${achievement.name} » obtenu',
        detail: '${entry.title} • Steam',
        createdAt: safeDate(achievement),
      );
    }

    if (ordered.length > 5) {
      DateTime groupDate = safeDate(ordered[5]);
      for (final GameAchievementDetail achievement in ordered.skip(5)) {
        final DateTime candidate = safeDate(achievement);
        if (candidate.isAfter(groupDate)) {
          groupDate = candidate;
        }
      }

      await GameLibraryService.addActivity(
        title: '${ordered.length - 5} autres succès sur ${entry.title}',
        detail: updatedSteam.progressText,
        createdAt: groupDate,
      );
    }
  }

  static Future<SteamAllAchievementSyncResult> syncAllAchievements({
    required List<GameLibraryEntry> library,
    required Set<String> activityChangedAppIds,
    bool force = false,
    Duration staleAfter = const Duration(hours: 24),
    int? maxGames,
    void Function(
      int completed,
      int total,
      String title,
      List<SteamSyncGameOutcome> outcomes,
    )? onProgress,
  }) async {
    final DateTime now = DateTime.now();
    final List<GameLibraryEntry> linked = library.where((game) {
      final GamePlatformProfile? steam = game.platformProfile(
        GamePlatform.steam,
      );
      return steam?.externalId?.trim().isNotEmpty == true;
    }).toList();

    final List<GameLibraryEntry> queue = <GameLibraryEntry>[];
    int skippedFresh = 0;

    for (final GameLibraryEntry game in linked) {
      final GamePlatformProfile steam = game.platformProfile(
        GamePlatform.steam,
      )!;
      final String appId = steam.externalId!.trim();
      final DateTime? lastSync = steam.achievementsLastSyncedAt;

      final bool detailedCatalogMissing =
          steam.computedAchievementSummary.total > 0 &&
          steam.achievementDetails.isEmpty;
      final bool neverSynced =
          !steam.achievementCatalogInitialized ||
          lastSync == null ||
          detailedCatalogMissing;
      final bool activityChanged = activityChangedAppIds.contains(appId);
      final bool stale =
          lastSync == null || now.difference(lastSync) >= staleAfter;

      if (force || neverSynced || activityChanged || stale) {
        queue.add(game);
      } else {
        skippedFresh += 1;
      }
    }

    queue.sort((a, b) {
      final String aId =
          a.platformProfile(GamePlatform.steam)?.externalId ?? '';
      final String bId =
          b.platformProfile(GamePlatform.steam)?.externalId ?? '';
      final bool aChanged = activityChangedAppIds.contains(aId);
      final bool bChanged = activityChangedAppIds.contains(bId);
      if (aChanged != bChanged) {
        return aChanged ? -1 : 1;
      }

      final DateTime? aPlayed = a
          .platformProfile(GamePlatform.steam)
          ?.lastPlayedAt;
      final DateTime? bPlayed = b
          .platformProfile(GamePlatform.steam)
          ?.lastPlayedAt;
      if (aPlayed == null && bPlayed == null) {
        return 0;
      }
      if (aPlayed == null) {
        return 1;
      }
      if (bPlayed == null) {
        return -1;
      }
      return bPlayed.compareTo(aPlayed);
    });

    if (maxGames != null && maxGames > 0 && queue.length > maxGames) {
      final int deferred = queue.length - maxGames;
      queue.removeRange(maxGames, queue.length);
      skippedFresh += deferred;
    }

    int checked = 0;
    int noAchievements = 0;
    int unavailable = 0;
    int newlyUnlocked = 0;
    int totalAchievementsKnown = 0;

    final List<SteamAchievementSyncIssue> issues =
        <SteamAchievementSyncIssue>[];
    final List<GameLibraryEntry> workingLibrary = List<GameLibraryEntry>.from(
      library,
    );
    final List<
      (GameLibraryEntry, GamePlatformProfile, List<GameAchievementDetail>)
    >
    announcements =
        <
          (GameLibraryEntry, GamePlatformProfile, List<GameAchievementDetail>)
        >[];
    final List<SteamSyncGameOutcome> outcomes = <SteamSyncGameOutcome>[];

    if (queue.isNotEmpty) {
      onProgress?.call(
        0,
        queue.length,
        queue.first.title,
        const <SteamSyncGameOutcome>[],
      );
    }

    int nextQueueIndex = 0;
    int completed = 0;

    Future<void> worker(int workerIndex) async {
      // Décalage léger au démarrage : deux workers suffisent pour garder une
      // synchro fluide sans envoyer trop d'appels simultanés vers Steam.
      if (workerIndex > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: 220 * workerIndex),
        );
      }

      while (true) {
        if (nextQueueIndex >= queue.length) {
          return;
        }

        final int index = nextQueueIndex;
        nextQueueIndex += 1;
        final GameLibraryEntry game = queue[index];

        try {
          final SteamAchievementSyncResult result = await syncAchievements(
            game,
            persist: false,
            announceNewUnlocks: false,
          );
          checked += 1;
          newlyUnlocked += result.newlyUnlocked;
          totalAchievementsKnown += result.summary.total;

          final int libraryIndex = workingLibrary.indexWhere(
            (item) => item.id == game.id,
          );
          if (libraryIndex != -1) {
            workingLibrary[libraryIndex] = result.updatedEntry;
          }

          if (!result.firstDetailedSync &&
              result.newlyUnlockedDetails.isNotEmpty) {
            final GamePlatformProfile? updatedSteam = result.updatedEntry
                .platformProfile(GamePlatform.steam);
            if (updatedSteam != null) {
              announcements.add((
                game,
                updatedSteam,
                result.newlyUnlockedDetails,
              ));
            }
          }

          if (result.summary.total <= 0 && result.achievements.isEmpty) {
            noAchievements += 1;
          }

          outcomes.add(SteamSyncGameOutcome.success);
        } on SteamSyncException catch (error) {
          // Une fiche indisponible / privée ne bloque jamais les autres.
          // Avec trois workers, un jeu lent ou en timeout ne fige plus toute
          // la file derrière lui.
          unavailable += 1;

          final String appId =
              game.platformProfile(GamePlatform.steam)?.externalId?.trim() ??
              '';

          issues.add(
            SteamAchievementSyncIssue(
              gameId: game.id,
              title: game.title,
              appId: appId,
              message: error.message,
            ),
          );
          outcomes.add(SteamSyncGameOutcome.failed);

          debugPrint(
            'Succès Steam indisponibles pour ${game.title} '
            '($appId) : ${error.message}',
          );
        }

        completed += 1;
        onProgress?.call(
          completed,
          queue.length,
          game.title,
          List<SteamSyncGameOutcome>.unmodifiable(outcomes),
        );

        // Respiration courte entre deux jeux d'un même worker. Le débit reste
        // volontairement borné même si la bibliothèque contient 100+ jeux.
        if (nextQueueIndex < queue.length) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
    }

    final int workerCount = queue.length < _achievementSyncConcurrency
        ? queue.length
        : _achievementSyncConcurrency;

    if (workerCount > 0) {
      await Future.wait<void>(
        List<Future<void>>.generate(
          workerCount,
          (index) => worker(index),
        ),
      );
    }

    // Une grosse bibliothèque ne doit pas déclencher 100+ remplacements Cloud
    // successifs. Toutes les fiches vérifiées sont persistées en une seule
    // sauvegarde de bibliothèque.
    if (checked > 0) {
      await GameLibraryService.saveCurrentLibrary(workingLibrary);
    }

    for (final announcement in announcements) {
      await _announceNewAchievements(
        entry: announcement.$1,
        updatedSteam: announcement.$2,
        achievements: announcement.$3,
      );
    }

    return SteamAllAchievementSyncResult(
      linkedGames: linked.length,
      checkedGames: checked,
      skippedFreshGames: skippedFresh,
      gamesWithoutAchievements: noAchievements,
      unavailableGames: unavailable,
      newlyUnlocked: newlyUnlocked,
      totalAchievementsKnown: totalAchievementsKnown,
      issues: List<SteamAchievementSyncIssue>.unmodifiable(issues),
    );
  }

  static String _friendlyFunctionError(dynamic raw) {
    if (raw is Map && raw['error'] != null) {
      return raw['error'].toString();
    }

    final String message = raw?.toString() ?? '';
    if (message.contains('404') || message.contains('Function not found')) {
      return 'La fonction Steam n’est pas encore déployée dans Supabase. Suis le README V1.8 pour l’activer.';
    }
    if (message.contains('STEAM_WEB_API_KEY')) {
      return 'La clé Steam n’est pas encore configurée côté serveur.';
    }
    if (message.trim().isEmpty) {
      return 'Impossible de contacter la synchronisation Steam.';
    }
    return 'Synchronisation Steam indisponible : $message';
  }
}
