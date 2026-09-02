import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_audio_service.dart';
import 'app_notification_service.dart';
import 'auth_service.dart';
import 'cloud_data_sync_service.dart';
import 'gaming_accounts_service.dart';
import 'computer_settings_service.dart';
import 'local_account_repair_service.dart';
import 'push_device_token_service.dart';
import 'supabase_service.dart';
import 'steam_sync_service.dart';
import 'tavern_profile_service.dart';

class ProjectXpStartupService {
  ProjectXpStartupService._();

  static final ProjectXpStartupService instance =
      ProjectXpStartupService._();

  static const Duration _hallNetworkBudget =
      Duration(
    milliseconds: 2200,
  );

  Future<void>? _startFuture;

  final Completer<void> _localReadyCompleter =
      Completer<void>();

  final Completer<void> _hallReadyCompleter =
      Completer<void>();

  final ValueNotifier<int> socialReadyRevision =
      ValueNotifier<int>(0);

  bool _socialReady = false;

  bool get socialReady => _socialReady;

  Future<void> get localReady =>
      _localReadyCompleter.future;

  Future<void> get hallReady =>
      _hallReadyCompleter.future;

  Future<void> start() {
    return _startFuture ??= _startInternal();
  }

  Future<void> _startInternal() async {
    final Future<void> authFuture =
        _safeStep(
      'Compte local',
      AuthService.initialize,
    );

    final Future<void> settingsFuture =
        _safeStep(
      'Réglages',
      ComputerSettingsService.initialize,
    );

    final Future<void> audioFuture =
        _safeStep(
      'Audio',
      AppAudioService.instance.initialize,
    );

    final Future<bool> firstSocialAttempt =
        _tryInitializeSocialSession();

    // Les liens de retour navigateur (Steam aujourd'hui, autres plateformes
    // demain) sont préparés très tôt, sans retarder l'affichage du Hall.
    unawaited(
      _safeStep(
        'Liens comptes gaming',
        GamingAccountsService.initialize,
      ),
    );

    final Future<void> notificationFuture =
        settingsFuture.then(
      (_) => _safeStep(
        'Notifications',
        AppNotificationService.instance.initialize,
      ),
    );

    await Future.wait<void>(
      <Future<void>>[
        authFuture,
        settingsFuture,
      ],
    );

    if (!_localReadyCompleter.isCompleted) {
      _localReadyCompleter.complete();
    }

    await Future.any<void>(
      <Future<void>>[
        firstSocialAttempt.then((_) {}),
        Future<void>.delayed(
          _hallNetworkBudget,
        ),
      ],
    );

    if (!_hallReadyCompleter.isCompleted) {
      _hallReadyCompleter.complete();
    }

    unawaited(
      _finishDeferredStartup(
        authFuture: authFuture,
        audioFuture: audioFuture,
        notificationFuture: notificationFuture,
        firstSocialAttempt: firstSocialAttempt,
      ),
    );
  }

  Future<void> _finishDeferredStartup({
    required Future<void> authFuture,
    required Future<void> audioFuture,
    required Future<void> notificationFuture,
    required Future<bool> firstSocialAttempt,
  }) async {
    await authFuture;

    unawaited(
      _safeStep(
        'Réparation compte local',
        LocalAccountRepairService.runOnce,
      ),
    );

    unawaited(audioFuture);
    unawaited(notificationFuture);

    bool socialReady =
        await firstSocialAttempt;

    if (!socialReady) {
      const List<Duration> retryDelays =
          <Duration>[
        Duration(seconds: 3),
        Duration(seconds: 8),
        Duration(seconds: 18),
      ];

      for (final Duration delay
          in retryDelays) {
        await Future<void>.delayed(delay);

        socialReady =
            await _tryInitializeSocialSession();

        if (socialReady) {
          break;
        }
      }
    }

    if (!socialReady) {
      return;
    }

    // V1.10 : si le compte Supabase est permanent, on restaure / migre les
    // données personnelles en arrière-plan AVANT de republier le profil social.
    await _safeStep(
      'Données Cloud Project XP',
      CloudDataSyncService.syncCurrentAccount,
    );

    // La synchronisation gaming démarre en arrière-plan une fois la
    // Bibliothèque Cloud restaurée. Elle ne fait jamais attendre le Hall.
    unawaited(
      _safeStep(
        'Synchronisation gaming',
        SteamSyncService.syncAtStartup,
      ),
    );

    await notificationFuture;
    await _refreshPushTokenRegistration();

    await _safeStep(
      'Profil public',
      _syncTavernProfile,
    );
  }

  Future<bool> _tryInitializeSocialSession() async {
    if (_socialReady) {
      return true;
    }

    try {
      final user =
          await SupabaseService.ensureAnonymousSession();

      final bool ready =
          user != null ||
              SupabaseService.currentUser != null;

      if (ready) {
        _markSocialReady();
      }

      return ready;
    } catch (error) {
      debugPrint(
        'Démarrage Supabase différé : $error',
      );

      return false;
    }
  }

  void _markSocialReady() {
    if (_socialReady) {
      return;
    }

    _socialReady = true;
    socialReadyRevision.value =
        socialReadyRevision.value + 1;
  }

  Future<void> _refreshPushTokenRegistration() async {
    try {
      final String? token =
          await AppNotificationService
              .instance
              .getFcmToken();

      final String cleanToken =
          token?.trim() ?? '';

      if (cleanToken.isEmpty) {
        return;
      }

      await PushDeviceTokenService.saveToken(
        token: cleanToken,
      );
    } catch (error) {
      debugPrint(
        'Réenregistrement push différé impossible : $error',
      );
    }
  }

  Future<void> _syncTavernProfile() async {
    final bool profileSynced =
        await TavernProfileService.syncCurrentProfile();

    debugPrint(
      'Profil Taverne synchronisé : $profileSynced',
    );
  }

  Future<void> _safeStep(
    String name,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint(
        '$name : initialisation non bloquante échouée : $error',
      );
    }
  }
}
