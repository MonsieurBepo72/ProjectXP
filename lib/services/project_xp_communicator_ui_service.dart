import 'dart:async';

import 'package:flutter/material.dart';

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
      alertVisibilityRevision.value++;
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
      alertVisibilityRevision.value++;
    }
  }

  static void markNavigationReady() {
    if (_navigationReady) {
      return;
    }

    _navigationReady = true;
    alertVisibilityRevision.value++;

    if (!_navigationReadyCompleter.isCompleted) {
      _navigationReadyCompleter.complete();
    }
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
