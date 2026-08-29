import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

final GlobalKey<NavigatorState> projectXpNavigatorKey =
    GlobalKey<NavigatorState>();

final RouteObserver<PageRoute<dynamic>>
    projectXpRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class ProjectXpCommunicatorUiService {
  ProjectXpCommunicatorUiService._();

  static final Set<Object> _alertSuppressionTokens =
      <Object>{};

  static final ValueNotifier<int> alertVisibilityRevision =
      ValueNotifier<int>(0);

  // V2.4.7 — évite de notifier GlobalCommunicatorAlert pendant
  // qu'un arbre de widgets est en cours de construction.
  //
  // Les tokens sont, eux, modifiés immédiatement : la source de vérité reste
  // donc toujours correcte. Seule la notification visuelle est éventuellement
  // repoussée à la fin de la frame courante.
  static bool _alertVisibilityNotificationScheduled =
      false;

  static bool _navigationReady = false;

  static final Completer<void> _navigationReadyCompleter =
      Completer<void>();

  static String? _activeConversationId;
  static bool _communicatorSessionActive = false;

  static bool get isGlobalCommunicatorAlertSuppressed =>
      _alertSuppressionTokens.isNotEmpty;

  static bool get isNavigationReady =>
      _navigationReady;

  static String? get activeConversationId =>
      _activeConversationId;

  static bool get communicatorSessionActive =>
      _communicatorSessionActive;

  static void suppressGlobalCommunicatorAlert(
    Object token,
  ) {
    final bool changed =
        _alertSuppressionTokens.add(
      token,
    );

    if (changed) {
      _notifyAlertVisibilityChangedSafely();
    }
  }

  static void releaseGlobalCommunicatorAlert(
    Object token,
  ) {
    final bool changed =
        _alertSuppressionTokens.remove(
      token,
    );

    if (changed) {
      _notifyAlertVisibilityChangedSafely();
    }
  }

  static void markNavigationReady() {
    if (_navigationReady) {
      return;
    }

    _navigationReady = true;
    _notifyAlertVisibilityChangedSafely();

    if (!_navigationReadyCompleter.isCompleted) {
      _navigationReadyCompleter.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // IMPORTANT :
  //
  // RouteObserver.subscribe() peut appeler didPush() immédiatement depuis
  // didChangeDependencies(), donc pendant le build du Hall.
  //
  // Avant ce correctif, suppressGlobalCommunicatorAlert() modifiait le
  // ValueNotifier sur-le-champ. GlobalCommunicatorAlert recevait alors la
  // notification et appelait setState() pendant que Flutter était encore en
  // train de construire l'arbre, provoquant :
  //
  //   setState() or markNeedsBuild() called during build
  //
  // On notifie immédiatement uniquement lorsque Flutter est dans une phase
  // sûre. Sinon, on regroupe les changements et on notifie après la frame.
  // ---------------------------------------------------------------------------
  static void _notifyAlertVisibilityChangedSafely() {
    final SchedulerBinding binding =
        SchedulerBinding.instance;

    final SchedulerPhase phase =
        binding.schedulerPhase;

    final bool canNotifyImmediately =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;

    if (canNotifyImmediately) {
      alertVisibilityRevision.value++;
      return;
    }

    if (_alertVisibilityNotificationScheduled) {
      return;
    }

    _alertVisibilityNotificationScheduled = true;

    binding.addPostFrameCallback(
      (_) {
        _alertVisibilityNotificationScheduled = false;
        alertVisibilityRevision.value++;
      },
    );
  }

  static Future<bool> waitUntilNavigationReady({
    Duration? timeout =
        const Duration(
      seconds: 10,
    ),
  }) async {
    if (_navigationReady) {
      return true;
    }

    // Lors d'un démarrage à froid, certains anciens téléphones peuvent
    // mettre bien plus de 10 secondes avant d'arriver réellement au Hall.
    //
    // timeout == null signifie donc :
    // attendre le Hall aussi longtemps que nécessaire, sans perdre le clic
    // sur la notification.
    if (timeout == null) {
      await _navigationReadyCompleter.future;
      return true;
    }

    try {
      await _navigationReadyCompleter.future.timeout(
        timeout,
      );
      return true;
    } on TimeoutException {
      return false;
    }
  }

  static void setCommunicatorSessionActive(
    bool active,
  ) {
    _communicatorSessionActive = active;
  }

  static void setActiveConversation(
    String? conversationId,
  ) {
    final String clean =
        conversationId?.trim() ?? '';

    _activeConversationId =
        clean.isEmpty
            ? null
            : clean;
  }

  static void clearActiveConversation(
    String conversationId,
  ) {
    final String clean =
        conversationId.trim();

    if (clean.isEmpty ||
        _activeConversationId != clean) {
      return;
    }

    _activeConversationId = null;
  }
}
