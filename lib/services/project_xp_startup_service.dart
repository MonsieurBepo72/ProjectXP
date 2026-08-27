import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_audio_service.dart';
import 'app_notification_service.dart';
import 'auth_service.dart';
import 'computer_settings_service.dart';
import 'local_account_repair_service.dart';
import 'push_device_token_service.dart';
import 'supabase_service.dart';
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
      ValueNotifier<int>(
    0,
  );

  bool _socialReady = false;

  bool get socialReady =>
      _socialReady;

  Future<void> get localReady =>
      _localReadyCompleter.future;

  Future<void> get hallReady =>
      _hallReadyCompleter.future;

  // ===========================================================================
  // DÉMARRAGE GLOBAL
  //
  // Ce service est volontairement non bloquant :
  // l'UI Project XP peut déjà s'afficher pendant que les services travaillent.
  // ===========================================================================

  Future<void> start() {
    return _startFuture ??=
        _startInternal();
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

    // Notifications :
    // on les initialise tôt, mais sans empêcher l'écran de démarrage d'avancer.
    //
    // Firebase est déjà prêt avant runApp().
    final Future<void> notificationFuture =
        settingsFuture.then(
      (_) => _safeStep(
        'Notifications',
        AppNotificationService.instance.initialize,
      ),
    );

    // Les opérations purement locales doivent être prêtes avant que le Splash
    // décide entre Auth / Avatar / Hall.
    await Future.wait<void>(
      <Future<void>>[
        authFuture,
        settingsFuture,
      ],
    );

    if (!_localReadyCompleter.isCompleted) {
      _localReadyCompleter.complete();
    }

    // Le Hall n'attend jamais indéfiniment le réseau.
    //
    // Sur une bonne connexion, la session Supabase sera déjà prête.
    // Sur un réseau lent / absent, on donne seulement ~2,2 s au premier essai
    // puis on ouvre quand même Project XP en mode dégradé.
    await Future.any<void>(
      <Future<void>>[
        firstSocialAttempt.then(
          (_) {},
        ),
        Future<void>.delayed(
          _hallNetworkBudget,
        ),
      ],
    );

    if (!_hallReadyCompleter.isCompleted) {
      _hallReadyCompleter.complete();
    }

    // Tout ce qui suit continue en arrière-plan.
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
    // Anciennes migrations / réparations :
    // utiles, mais elles ne doivent plus retarder l'apparition de l'interface.
    await authFuture;

    unawaited(
      _safeStep(
        'Réparation compte local',
        LocalAccountRepairService.runOnce,
      ),
    );

    // L'audio et les notifications peuvent finir tranquillement.
    unawaited(
      audioFuture,
    );

    unawaited(
      notificationFuture,
    );

    bool socialReady =
        await firstSocialAttempt;

    if (!socialReady) {
      // Réessais espacés pour les connexions lentes / mobiles instables.
      const List<Duration> retryDelays =
          <Duration>[
        Duration(
          seconds: 3,
        ),
        Duration(
          seconds: 8,
        ),
        Duration(
          seconds: 18,
        ),
      ];

      for (final Duration delay
          in retryDelays) {
        await Future<void>.delayed(
          delay,
        );

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

    // Les notifications ont besoin de la session Supabase pour enregistrer
    // correctement le token de cette installation.
    await notificationFuture;

    await _refreshPushTokenRegistration();

    await _safeStep(
      'Profil public',
      _syncTavernProfile,
    );
  }

  // ===========================================================================
  // SESSION SOCIALE
  // ===========================================================================

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

  // ===========================================================================
  // PUSH
  // ===========================================================================

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

  // ===========================================================================
  // PROFIL
  // ===========================================================================

  Future<void> _syncTavernProfile() async {
    final bool profileSynced =
        await TavernProfileService.syncCurrentProfile();

    debugPrint(
      'Profil Taverne synchronisé : $profileSynced',
    );
  }

  // ===========================================================================
  // OUTIL DE SÉCURITÉ
  // ===========================================================================

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
