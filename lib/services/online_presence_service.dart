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

  final StreamController<Set<String>> _onlineUserIdsController =
      StreamController<Set<String>>.broadcast();

  RealtimeChannel? _channel;

  bool _started = false;
  bool _tracked = false;

  Timer? _presenceRepairTimer;
  AppLifecycleState _lifecycleState =
      AppLifecycleState.resumed;

  int _currentCount = 0;
  Set<String> _currentUserIds = <String>{};

  int get currentCount =>
      _currentCount;

  Set<String> get currentOnlineUserIds =>
      Set<String>.unmodifiable(
        _currentUserIds,
      );

  Stream<int> get onlineCountStream =>
      _onlineCountController.stream;

  Stream<Set<String>> get onlineUserIdsStream =>
      _onlineUserIdsController.stream;

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
            _refreshOnlineState();
          },
        )
        .onPresenceJoin(
          (
            RealtimePresenceJoinPayload payload,
          ) {
            _refreshOnlineState();
          },
        )
        .onPresenceLeave(
          (
            RealtimePresenceLeavePayload payload,
          ) {
            _refreshOnlineState();
          },
        )
        .subscribe(
          (
            RealtimeSubscribeStatus status,
            Object? error,
          ) async {
            if (status ==
                RealtimeSubscribeStatus.subscribed) {
              // Après une reconnexion réseau, Supabase recrée la présence du
              // channel. Notre ancien booléen _tracked peut encore être true
              // alors que le serveur ne connaît plus cette présence. On force
              // donc un nouveau track à chaque (re)souscription.
              _tracked = false;
              await _trackCurrentUser();
              _refreshOnlineState();
            } else if (status ==
                    RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut ||
                status == RealtimeSubscribeStatus.closed) {
              _tracked = false;
            }
          },
        );

    _presenceRepairTimer?.cancel();
    _presenceRepairTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!_started ||
            _lifecycleState == AppLifecycleState.paused ||
            _lifecycleState == AppLifecycleState.hidden ||
            _lifecycleState == AppLifecycleState.detached) {
          return;
        }

        // Répare silencieusement la présence après une perte réseau ou une
        // reconnexion du socket. track() est idempotent pour notre connexion.
        unawaited(
          _trackCurrentUser(force: true),
        );
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
    _presenceRepairTimer?.cancel();
    _presenceRepairTimer = null;

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

    _setOnlineUserIds(
      <String>{},
    );

    _setOnlineCount(
      0,
    );
  }

  // ===========================================================================
  // CYCLE DE VIE DE L'APPLICATION
  // ===========================================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    _lifecycleState = state;

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(
          _trackCurrentUser(force: true),
        );
        break;

      // Sur Android, inactive peut arriver alors que l'app est encore visible
      // (perte de focus temporaire, panneau système, sélecteur d'image...).
      // On reste donc en ligne dans cet état.
      case AppLifecycleState.inactive:
        break;

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

  Future<void> _trackCurrentUser({
    bool force = false,
  }) async {
    if (!_started ||
        (_tracked && !force)) {
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
  // PRÉSENCE
  //
  // On conserve maintenant aussi les UUID en ligne, et pas seulement le
  // compteur. Compagnie peut ainsi afficher le vrai statut des joueurs.
  // ===========================================================================

  void _refreshOnlineState() {
    final RealtimeChannel? channel =
        _channel;

    if (channel == null) {
      _setOnlineUserIds(
        <String>{},
      );
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

    _setOnlineUserIds(
      userIds,
    );

    _setOnlineCount(
      userIds.length,
    );
  }

  void _setOnlineUserIds(
    Set<String> value,
  ) {
    final bool unchanged =
        _currentUserIds.length == value.length &&
            _currentUserIds.containsAll(value);

    if (unchanged) {
      return;
    }

    _currentUserIds =
        Set<String>.from(value);

    if (!_onlineUserIdsController.isClosed) {
      _onlineUserIdsController.add(
        Set<String>.unmodifiable(
          _currentUserIds,
        ),
      );
    }
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
