import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class OnlinePresenceService
    with WidgetsBindingObserver {
  OnlinePresenceService._();

  static final OnlinePresenceService instance =
      OnlinePresenceService._();

  final StreamController<int> _onlineCountController =
      StreamController<int>.broadcast();

  RealtimeChannel? _channel;

  bool _started = false;
  bool _tracked = false;

  int _currentCount = 0;

  int get currentCount =>
      _currentCount;

  Stream<int> get onlineCountStream =>
      _onlineCountController.stream;

  // ===========================================================================
  // DÉMARRAGE
  //
  // À appeler une seule fois lorsque le joueur arrive dans le Hall.
  // Le service reste actif pendant les écrans ouverts au-dessus du Hall :
  // Taverne, Communicateur XP, Compagnie, etc.
  // ===========================================================================

  Future<void> start() async {
    if (_started) {
      return;
    }

    final User? user =
        SupabaseService.currentUser;

    if (user == null) {
      return;
    }

    _started = true;

    WidgetsBinding.instance.addObserver(
      this,
    );

    final RealtimeChannel channel =
        SupabaseService.client.channel(
      'project_xp_global_presence',
    );

    _channel = channel;

    channel
        .onPresenceSync(
          (
            RealtimePresenceSyncPayload payload,
          ) {
            _refreshOnlineCount();
          },
        )
        .onPresenceJoin(
          (
            RealtimePresenceJoinPayload payload,
          ) {
            _refreshOnlineCount();
          },
        )
        .onPresenceLeave(
          (
            RealtimePresenceLeavePayload payload,
          ) {
            _refreshOnlineCount();
          },
        )
        .subscribe(
          (
            RealtimeSubscribeStatus status,
            Object? error,
          ) async {
            if (status ==
                RealtimeSubscribeStatus.subscribed) {
              await _trackCurrentUser();
              _refreshOnlineCount();
            }
          },
        );
  }

  // ===========================================================================
  // ARRÊT
  // ===========================================================================

  Future<void> stop() async {
    if (!_started) {
      return;
    }

    _started = false;

    WidgetsBinding.instance.removeObserver(
      this,
    );

    final RealtimeChannel? channel =
        _channel;

    _channel = null;

    if (channel != null) {
      try {
        await channel.untrack();
      } catch (_) {
        // Rien à faire.
      }

      try {
        await SupabaseService.client
            .removeChannel(
          channel,
        );
      } catch (_) {
        // Rien à faire.
      }
    }

    _tracked = false;

    _setOnlineCount(
      0,
    );
  }

  // ===========================================================================
  // CYCLE DE VIE DE L'APPLICATION
  //
  // L'utilisateur est considéré "en ligne" lorsque Project XP est réellement
  // au premier plan. Lorsqu'il met l'application en arrière-plan, sa présence
  // est retirée.
  // ===========================================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(
          _trackCurrentUser(),
        );
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(
          _untrackCurrentUser(),
        );
        break;
    }
  }

  // ===========================================================================
  // TRACK / UNTRACK
  // ===========================================================================

  Future<void> _trackCurrentUser() async {
    if (!_started ||
        _tracked) {
      return;
    }

    final RealtimeChannel? channel =
        _channel;

    final User? user =
        SupabaseService.currentUser;

    if (channel == null ||
        user == null) {
      return;
    }

    try {
      await channel.track(
        <String, dynamic>{
          'user_id': user.id,
          'online_at':
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
        },
      );

      _tracked = true;
    } catch (_) {
      _tracked = false;
    }
  }

  Future<void> _untrackCurrentUser() async {
    if (!_tracked) {
      return;
    }

    final RealtimeChannel? channel =
        _channel;

    if (channel == null) {
      _tracked = false;
      return;
    }

    try {
      await channel.untrack();
    } catch (_) {
      // La déconnexion du socket finira également par retirer la présence.
    }

    _tracked = false;
  }

  // ===========================================================================
  // COMPTAGE
  //
  // presenceState() représente les connexions présentes sur le channel.
  // On récupère user_id dans chaque payload et on déduplique les UUID.
  //
  // Résultat :
  // - même compte sur 2 appareils = 1 joueur
  // - 2 comptes différents = 2 joueurs
  // ===========================================================================

  void _refreshOnlineCount() {
    final RealtimeChannel? channel =
        _channel;

    if (channel == null) {
      _setOnlineCount(
        0,
      );

      return;
    }

    final Set<String> userIds =
        <String>{};

    final List<SinglePresenceState> states =
        channel.presenceState();

    for (final SinglePresenceState state
        in states) {
      for (final Presence presence
          in state.presences) {
        final String userId =
            presence.payload['user_id']
                    ?.toString()
                    .trim() ??
                '';

        if (userId.isNotEmpty) {
          userIds.add(
            userId,
          );
        }
      }
    }

    _setOnlineCount(
      userIds.length,
    );
  }

  void _setOnlineCount(
    int value,
  ) {
    if (_currentCount == value) {
      return;
    }

    _currentCount = value;

    if (!_onlineCountController.isClosed) {
      _onlineCountController.add(
        value,
      );
    }
  }
}
