import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_library_entry.dart';
import 'game_library_service.dart';
import 'gaming_accounts_service.dart';
import 'playstation_sync_service.dart';
import 'project_xp_high_fact_service.dart';
import 'steam_sync_service.dart';

enum GamingSyncPhase { idle, syncing, completed }

enum GamingSyncItemOutcome { success, failed }

class GamingSyncUiState {
  final GamingSyncPhase phase;
  final String label;
  final int current;
  final int total;
  final int steamCurrent;
  final int steamTotal;
  final int playStationCurrent;
  final int playStationTotal;
  final bool steamRunning;
  final bool playStationRunning;
  final List<GamingSyncItemOutcome> outcomes;

  const GamingSyncUiState({
    required this.phase,
    required this.label,
    this.current = 0,
    this.total = 0,
    this.steamCurrent = 0,
    this.steamTotal = 0,
    this.playStationCurrent = 0,
    this.playStationTotal = 0,
    this.steamRunning = false,
    this.playStationRunning = false,
    this.outcomes = const <GamingSyncItemOutcome>[],
  });

  static const idle = GamingSyncUiState(
    phase: GamingSyncPhase.idle,
    label: '',
  );

  bool get running => phase == GamingSyncPhase.syncing;
}

class GamingSyncException implements Exception {
  final String message;

  const GamingSyncException(this.message);

  @override
  String toString() => message;
}

class GamingSyncResult {
  final bool steamAttempted;
  final bool playStationAttempted;
  final SteamFullSyncResult? steam;
  final PlayStationSyncResult? playStation;
  final String? steamError;
  final String? playStationError;

  const GamingSyncResult({
    required this.steamAttempted,
    required this.playStationAttempted,
    required this.steam,
    required this.playStation,
    required this.steamError,
    required this.playStationError,
  });

  bool get hasErrors => steamError != null ||
      playStationError != null ||
      (playStation?.detailFailures ?? 0) > 0;

  String get summary {
    final List<String> parts = <String>[];

    if (steamAttempted) {
      parts.add(steamError == null ? 'Steam à jour' : 'Steam en erreur');
    }

    if (playStationAttempted) {
      final PlayStationSyncResult? result = playStation;
      if (playStationError != null) {
        parts.add('PlayStation en erreur');
      } else if (result != null) {
        final List<String> psDetails = <String>[
          if (result.added > 0) '${result.added} ajoutés',
          if (result.updated > 0) '${result.updated} actualisés',
          if (result.unchanged > 0) '${result.unchanged} déjà à jour',
          if (result.detailFailures > 0)
            '${result.detailFailures} trophées à revoir',
        ];
        parts.add(
          psDetails.isEmpty
              ? 'PlayStation à jour'
              : 'PlayStation • ${psDetails.join(' • ')}',
        );
      }
    }

    if (parts.isEmpty) {
      return 'Aucune plateforme liée.';
    }

    return parts.join(' • ');
  }
}

class GamingSyncService {
  GamingSyncService._();

  static final ValueNotifier<GamingSyncUiState> syncState =
      ValueNotifier<GamingSyncUiState>(GamingSyncUiState.idle);

  static Future<GamingSyncResult>? _activeSync;

  static Future<GamingSyncResult> syncEverything({
    bool forceSteamAchievements = false,
    Duration steamStaleAfter = const Duration(hours: 12),
    bool skipFreshPlayStation = false,
  }) {
    final Future<GamingSyncResult>? active = _activeSync;
    if (active != null) {
      return active;
    }

    final Future<GamingSyncResult> task = _runSync(
      forceSteamAchievements: forceSteamAchievements,
      steamStaleAfter: steamStaleAfter,
      skipFreshPlayStation: skipFreshPlayStation,
    );

    _activeSync = task;
    return task.whenComplete(() {
      if (identical(_activeSync, task)) {
        _activeSync = null;
      }
    });
  }

  static Future<void> syncAtStartup() async {
    try {
      await syncEverything(
        forceSteamAchievements: false,
        steamStaleAfter: const Duration(hours: 12),
        skipFreshPlayStation: true,
      );
    } on GamingSyncException catch (error) {
      debugPrint('Sync gaming démarrage ignorée : ${error.message}');
    } catch (error) {
      debugPrint('Sync gaming démarrage ignorée : $error');
    }
  }

  static Future<GamingSyncResult> _runSync({
    required bool forceSteamAchievements,
    required Duration steamStaleAfter,
    required bool skipFreshPlayStation,
  }) async {
    final bool hasSteam = await SteamSyncService.hasSyncIdentity();
    final GamingAccountLink? playStationAccount =
        await GamingAccountsService.account(GamingPlatformProvider.playstation);

    bool shouldSyncPlayStation = playStationAccount != null;
    if (shouldSyncPlayStation && skipFreshPlayStation) {
      final DateTime? lastSync = playStationAccount.updatedAt;
      if (lastSync != null &&
          DateTime.now().difference(lastSync.toLocal()) <
              const Duration(hours: 6)) {
        shouldSyncPlayStation = false;
      }
    }

    if (!hasSteam && !shouldSyncPlayStation) {
      syncState.value = const GamingSyncUiState(
        phase: GamingSyncPhase.completed,
        label: 'Aucune plateforme à synchroniser.',
      );

      if (playStationAccount == null && !hasSteam) {
        await _normalizeCompletedGames();
        unawaited(ProjectXpHighFactService.publishNewHighFacts());
        throw const GamingSyncException(
          'Lie d’abord Steam ou PlayStation depuis COMPTES.',
        );
      }

      await _normalizeCompletedGames();
      unawaited(ProjectXpHighFactService.publishNewHighFacts());
      return const GamingSyncResult(
        steamAttempted: false,
        playStationAttempted: false,
        steam: null,
        playStation: null,
        steamError: null,
        playStationError: null,
      );
    }

    SteamFullSyncResult? steamResult;
    PlayStationSyncResult? playStationResult;
    PlayStationSyncSnapshot? playStationSnapshot;
    String? steamError;
    String? playStationError;

    int steamCurrent = 0;
    int steamTotal = 0;
    int playStationCurrent = 0;
    int playStationTotal = 0;
    bool steamRunning = hasSteam;
    bool playStationRunning = shouldSyncPlayStation;
    bool playStationMerging = false;
    List<GamingSyncItemOutcome> steamOutcomes = <GamingSyncItemOutcome>[];
    final List<GamingSyncItemOutcome> playStationOutcomes =
        <GamingSyncItemOutcome>[];

    String buildLabel() {
      final List<String> parts = <String>[];

      if (hasSteam) {
        if (steamTotal > 0) {
          parts.add('Steam $steamCurrent/$steamTotal');
        } else if (steamRunning) {
          parts.add('Steam…');
        } else {
          parts.add(steamError == null ? 'Steam ✓' : 'Steam en erreur');
        }
      }

      if (shouldSyncPlayStation) {
        if (playStationTotal > 0) {
          parts.add('PlayStation $playStationCurrent/$playStationTotal');
        } else if (playStationRunning || playStationMerging) {
          parts.add('PlayStation…');
        } else {
          parts.add(
            playStationError == null ? 'PlayStation ✓' : 'PlayStation en erreur',
          );
        }
      }

      return parts.isEmpty
          ? 'SYNCHRO'
          : 'SYNCHRO • ${parts.join(' • ')}';
    }

    void publish() {
      syncState.value = GamingSyncUiState(
        phase: GamingSyncPhase.syncing,
        label: buildLabel(),
        current: steamCurrent + playStationCurrent,
        total: steamTotal + playStationTotal,
        steamCurrent: steamCurrent,
        steamTotal: steamTotal,
        playStationCurrent: playStationCurrent,
        playStationTotal: playStationTotal,
        steamRunning: steamRunning,
        playStationRunning: playStationRunning || playStationMerging,
        outcomes: List<GamingSyncItemOutcome>.unmodifiable(
          <GamingSyncItemOutcome>[
            ...steamOutcomes,
            ...playStationOutcomes,
          ],
        ),
      );
    }

    void handleSteamState() {
      final SteamSyncUiState state = SteamSyncService.syncState.value;
      steamRunning = state.running;
      steamCurrent = state.current;
      steamTotal = state.total;
      steamOutcomes = state.outcomes
          .map(
            (outcome) => outcome == SteamSyncGameOutcome.success
                ? GamingSyncItemOutcome.success
                : GamingSyncItemOutcome.failed,
          )
          .toList(growable: false);
      publish();
    }

    SteamSyncService.syncState.addListener(handleSteamState);
    publish();

    Future<void>? steamTask;
    if (hasSteam) {
      steamTask = () async {
        try {
          steamResult = await SteamSyncService.syncEverything(
            force: forceSteamAchievements,
            staleAfter: steamStaleAfter,
          );
        } on SteamSyncException catch (error) {
          steamError = error.message;
        } catch (_) {
          steamError = 'La synchronisation Steam a échoué.';
        } finally {
          steamRunning = false;
          publish();
        }
      }();
    }

    Future<void>? playStationTask;
    if (shouldSyncPlayStation) {
      playStationTask = () async {
        try {
          playStationSnapshot =
              await PlayStationSyncService.fetchDetailedSnapshot(
            onProgress: (completed, total, title, success) {
              playStationCurrent = completed;
              playStationTotal = total;
              playStationOutcomes.add(
                success
                    ? GamingSyncItemOutcome.success
                    : GamingSyncItemOutcome.failed,
              );
              publish();
            },
          );
          playStationTotal = playStationSnapshot?.total ?? playStationTotal;
        } on PlayStationSyncException catch (error) {
          playStationError = error.message;
        } catch (_) {
          playStationError = 'La synchronisation PlayStation a échoué.';
        } finally {
          playStationRunning = false;
          publish();
        }
      }();
    }

    try {
      if (steamTask != null) {
        await steamTask;
      }
      if (playStationTask != null) {
        await playStationTask;
      }

      final PlayStationSyncSnapshot? snapshot = playStationSnapshot;
      if (snapshot != null && playStationError == null) {
        playStationMerging = true;
        publish();
        try {
          // La récupération réseau PS s'est faite en parallèle de Steam.
          // L'écriture finale attend volontairement Steam afin d'éviter que
          // deux sauvegardes de bibliothèque se remplacent mutuellement.
          playStationResult = await PlayStationSyncService.mergeSnapshot(
            snapshot,
          );
        } on PlayStationSyncException catch (error) {
          playStationError = error.message;
        } catch (_) {
          playStationError = 'La finalisation PlayStation a échoué.';
        } finally {
          playStationMerging = false;
          publish();
        }
      }

      await _normalizeCompletedGames();
      unawaited(ProjectXpHighFactService.publishNewHighFacts());

      final GamingSyncResult result = GamingSyncResult(
        steamAttempted: hasSteam,
        playStationAttempted: shouldSyncPlayStation,
        steam: steamResult,
        playStation: playStationResult,
        steamError: steamError,
        playStationError: playStationError,
      );

      syncState.value = GamingSyncUiState(
        phase: GamingSyncPhase.completed,
        label: result.summary,
        current: steamCurrent + playStationCurrent,
        total: steamTotal + playStationTotal,
        steamCurrent: steamCurrent,
        steamTotal: steamTotal,
        playStationCurrent: playStationCurrent,
        playStationTotal: playStationTotal,
        outcomes: List<GamingSyncItemOutcome>.unmodifiable(
          <GamingSyncItemOutcome>[
            ...steamOutcomes,
            ...playStationOutcomes,
          ],
        ),
      );

      final bool allAttemptedFailed =
          (hasSteam || shouldSyncPlayStation) &&
          (!hasSteam || steamError != null) &&
          (!shouldSyncPlayStation || playStationError != null);

      if (allAttemptedFailed) {
        throw GamingSyncException(
          <String>[?steamError, ?playStationError].join(' • '),
        );
      }

      return result;
    } finally {
      SteamSyncService.syncState.removeListener(handleSteamState);
    }
  }

  static Future<void> _normalizeCompletedGames() async {
    try {
      final List<GameLibraryEntry> library =
          await GameLibraryService.loadCurrentLibraryConsolidated();
      bool changed = false;

      for (int index = 0; index < library.length; index += 1) {
        final GameLibraryEntry game = library[index];
        final bool officiallyCompleted = game.resolvedPlatformProfiles.any(
          (profile) {
            final GameAchievementSummary summary =
                profile.computedAchievementSummary;
            if (profile.platform == GamePlatform.playstation &&
                summary.scoreTotal == 100 &&
                summary.scoreEarned >= 100) {
              return true;
            }
            return profile.completionPercent == 100;
          },
        );

        if (!officiallyCompleted || game.status == GameStatus.completed) {
          continue;
        }

        library[index] = game.copyWith(
          status: GameStatus.completed,
          statusAutomatic: true,
        );
        changed = true;
      }

      if (changed) {
        await GameLibraryService.saveCurrentLibrary(library);
      }
    } catch (error) {
      debugPrint('Normalisation des jeux terminés ignorée : $error');
    }
  }
}
