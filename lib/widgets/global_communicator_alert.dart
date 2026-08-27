import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/phone_home_screen.dart';
import '../screens/private_chat_screen.dart';
import '../services/app_notification_service.dart';
import '../services/friend_alias_service.dart';
import '../services/friend_service.dart';
import '../services/private_message_service.dart';
import '../services/project_xp_communicator_ui_service.dart';
import '../services/project_xp_startup_service.dart';

class GlobalCommunicatorAlert extends StatefulWidget {
  const GlobalCommunicatorAlert({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<GlobalCommunicatorAlert> createState() =>
      _GlobalCommunicatorAlertState();
}

class _GlobalCommunicatorAlertState
    extends State<GlobalCommunicatorAlert>
    with SingleTickerProviderStateMixin {
  StreamSubscription<ProjectXpInAppNotification>?
      _inAppSubscription;

  StreamSubscription<ProjectXpNotificationTap>?
      _tapSubscription;

  StreamSubscription<int>?
      _unreadPrivateMessageSubscription;

  StreamSubscription<int>?
      _friendRequestCountSubscription;

  late final AnimationController _shakeController;

  ProjectXpInAppNotification? _visibleNotification;

  int _unreadPrivateMessageCount = 0;
  int _incomingFriendRequestCount = 0;
  int _otherPendingCount = 0;

  DateTime? _lastShakeAt;

  int get _persistentUnreadCount {
    final int total =
        _unreadPrivateMessageCount +
            _incomingFriendRequestCount +
            _otherPendingCount;

    return total.clamp(0, 999).toInt();
  }

  @override
  void initState() {
    super.initState();

    _shakeController =
        AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1450,
      ),
    );

    ProjectXpCommunicatorUiService
        .alertVisibilityRevision
        .addListener(
      _handleSuppressionChange,
    );

    _inAppSubscription =
        AppNotificationService
            .instance
            .inAppNotifications
            .listen(
      _handleInAppNotification,
    );

    _tapSubscription =
        AppNotificationService
            .instance
            .notificationTaps
            .listen(
      _handleNotificationTap,
    );

    ProjectXpStartupService
        .instance
        .socialReadyRevision
        .addListener(
      _handleSocialReady,
    );

    if (ProjectXpStartupService
        .instance
        .socialReady) {
      unawaited(
        _bindSocialStreams(),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted) {
          return;
        }

        final AppNotificationService service =
            AppNotificationService.instance;

        service.markNotificationTapUiReady();

        final List<ProjectXpNotificationTap>
            pending =
            service.takePendingNotificationTaps();

        for (final ProjectXpNotificationTap event
            in pending) {
          unawaited(
            _handleNotificationTap(
              event,
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    ProjectXpCommunicatorUiService
        .alertVisibilityRevision
        .removeListener(
      _handleSuppressionChange,
    );

    ProjectXpStartupService
        .instance
        .socialReadyRevision
        .removeListener(
      _handleSocialReady,
    );

    _inAppSubscription?.cancel();
    _tapSubscription?.cancel();
    _unreadPrivateMessageSubscription?.cancel();
    _friendRequestCountSubscription?.cancel();

    _shakeController.dispose();

    super.dispose();
  }

  void _handleSocialReady() {
    if (!mounted ||
        !ProjectXpStartupService
            .instance
            .socialReady) {
      return;
    }

    unawaited(
      _bindSocialStreams(),
    );
  }

  Future<void> _bindSocialStreams() async {
    await _unreadPrivateMessageSubscription?.cancel();
    await _friendRequestCountSubscription?.cancel();

    if (!mounted) {
      return;
    }

    _unreadPrivateMessageSubscription =
        PrivateMessageService
            .unreadCountStream()
            .listen(
      _handleUnreadPrivateMessageCount,
      onError: (
        Object error,
      ) {
        debugPrint(
          'Compteur global messages non lus indisponible : $error',
        );
      },
    );

    _friendRequestCountSubscription =
        FriendService
            .incomingRequestCountStream()
            .listen(
      _handleIncomingFriendRequestCount,
      onError: (
        Object error,
      ) {
        debugPrint(
          'Compteur global demandes d’amis indisponible : $error',
        );
      },
    );
  }

  void _handleSuppressionChange() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _handleUnreadPrivateMessageCount(
    int count,
  ) {
    if (!mounted) {
      return;
    }

    final int cleanCount =
        count < 0 ? 0 : count;

    final bool increased =
        cleanCount >
            _unreadPrivateMessageCount;

    setState(() {
      _unreadPrivateMessageCount =
          cleanCount;

      if (cleanCount == 0 &&
          _isPrivateMessageNotification(
            _visibleNotification,
          )) {
        _visibleNotification = null;
      }
    });

    if (increased) {
      _triggerShake();
    }
  }

  void _handleIncomingFriendRequestCount(
    int count,
  ) {
    if (!mounted) {
      return;
    }

    final int cleanCount =
        count < 0 ? 0 : count;

    final bool increased =
        cleanCount >
            _incomingFriendRequestCount;

    setState(() {
      _incomingFriendRequestCount =
          cleanCount;

      if (cleanCount == 0 &&
          _isFriendRequestNotification(
            _visibleNotification,
          )) {
        _visibleNotification = null;
      }
    });

    if (increased) {
      _triggerShake();
    }
  }

  void _handleInAppNotification(
    ProjectXpInAppNotification notification,
  ) {
    final bool privateMessage =
        _isPrivateMessageNotification(
      notification,
    );

    final bool friendRequest =
        _isFriendRequestNotification(
      notification,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _visibleNotification =
          notification;

      if (!privateMessage &&
          !friendRequest) {
        _otherPendingCount =
            (_otherPendingCount + 1)
                .clamp(
                  0,
                  99,
                )
                .toInt();
      }
    });

    _triggerShake();
  }

  void _triggerShake() {
    if (ProjectXpCommunicatorUiService
        .isGlobalCommunicatorAlertSuppressed) {
      return;
    }

    final DateTime now =
        DateTime.now();

    final DateTime? last =
        _lastShakeAt;

    if (last != null &&
        now.difference(last) <
            const Duration(
              milliseconds: 500,
            )) {
      return;
    }

    _lastShakeAt = now;

    _shakeController.forward(
      from: 0,
    );
  }

  bool _isPrivateMessageNotification(
    ProjectXpInAppNotification?
        notification,
  ) {
    if (notification == null) {
      return false;
    }

    final String payload =
        notification.payload?.trim() ?? '';

    final String type =
        notification.data['type']
                ?.toString()
                .trim() ??
            '';

    return payload.startsWith(
          'private_message:',
        ) ||
        type == 'private_message';
  }

  bool _isFriendRequestNotification(
    ProjectXpInAppNotification?
        notification,
  ) {
    if (notification == null) {
      return false;
    }

    final String payload =
        notification.payload
                ?.toLowerCase()
                .trim() ??
            '';

    final String type =
        notification.data['type']
                ?.toString()
                .toLowerCase()
                .trim() ??
            '';

    return payload.contains(
          'friend',
        ) ||
        type.contains(
          'friend',
        );
  }

  void _clearGenericPendingNotifications() {
    if (!mounted ||
        _otherPendingCount == 0) {
      return;
    }

    setState(() {
      _otherPendingCount = 0;
    });
  }

  Future<void> _handleNotificationTap(
    ProjectXpNotificationTap event,
  ) async {
    await _openPayload(
      payload: event.payload,
      data: event.data,
      coldStart: event.coldStart,
    );
  }

  Future<void> _openVisibleNotification() async {
    if (_unreadPrivateMessageCount > 0) {
      final bool opened =
          await _openLatestUnreadPrivateConversation();

      if (opened) {
        return;
      }
    }

    if (_incomingFriendRequestCount > 0) {
      await _openCommunicator();
      return;
    }

    final ProjectXpInAppNotification?
        notification =
        _visibleNotification;

    if (notification == null) {
      await _openCommunicator();
      return;
    }

    if (!_isPrivateMessageNotification(
          notification,
        ) &&
        !_isFriendRequestNotification(
          notification,
        )) {
      _clearGenericPendingNotifications();
    }

    await _openPayload(
      payload: notification.payload,
      data: notification.data,
      coldStart: false,
    );
  }

  Future<bool>
      _openLatestUnreadPrivateConversation() async {
    try {
      final List<Map<String, dynamic>> inbox =
          await PrivateMessageService
              .getInbox();

      for (final Map<String, dynamic>
          conversation in inbox) {
        final int unread =
            _asInt(
          conversation['unread_count'],
        );

        if (unread <= 0) {
          continue;
        }

        final String conversationId =
            conversation['conversation_id']
                    ?.toString()
                    .trim() ??
                '';

        if (conversationId.isEmpty) {
          continue;
        }

        await _openPrivateConversation(
          conversationId:
              conversationId,
          data:
              const <String, dynamic>{},
        );

        return true;
      }
    } catch (error) {
      debugPrint(
        'Ouverture du dernier message non lu impossible : $error',
      );
    }

    return false;
  }

  Future<void> _openPayload({
    required String? payload,
    required Map<String, dynamic> data,
    required bool coldStart,
  }) async {
    final bool ready =
        await ProjectXpCommunicatorUiService
            .waitUntilNavigationReady(
      // Un ancien téléphone peut mettre longtemps à traverser Firebase,
      // Supabase, l'intro et le chargement du Hall. Pendant un vrai cold
      // start, on conserve donc le clic sur la notification jusqu'à ce que
      // le Hall soit effectivement prêt.
      timeout: coldStart
          ? null
          : const Duration(
              seconds: 15,
            ),
    );

    if (!ready) {
      debugPrint(
        'Navigation notification : Hall non prêt.',
      );

      return;
    }

    if (coldStart) {
      // Laisse au Navigator le temps de terminer proprement l'arrivée au Hall
      // sur les appareils anciens avant d'empiler la conversation privée.
      await Future<void>.delayed(
        const Duration(
          milliseconds: 750,
        ),
      );
    }

    final String cleanPayload =
        payload?.trim() ?? '';

    if (cleanPayload.startsWith(
      'private_message:',
    )) {
      final String conversationId =
          cleanPayload
              .substring(
                'private_message:'.length,
              )
              .trim();

      if (conversationId.isEmpty) {
        return;
      }

      await _openPrivateConversation(
        conversationId:
            conversationId,
        data: data,
      );

      return;
    }

    await _openCommunicator();
  }

  Future<void> _openPrivateConversation({
    required String conversationId,
    required Map<String, dynamic> data,
  }) async {
    if (ProjectXpCommunicatorUiService
            .activeConversationId ==
        conversationId) {
      await _markConversationReadSafely(
        conversationId,
      );

      return;
    }

    final _ConversationTarget? target =
        await _resolveConversationTarget(
      conversationId:
          conversationId,
      data: data,
    );

    if (target == null) {
      await _openCommunicator();

      return;
    }

    await _markConversationReadSafely(
      conversationId,
    );

    final NavigatorState? navigator =
        projectXpNavigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    await _restoreNormalSystemBars();

    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: '/private-chat',
        ),
        builder: (
          BuildContext context,
        ) {
          return PrivateChatScreen(
            friendId:
                target.friendId,
            displayName:
                target.displayName,
            avatarUrl:
                target.avatarUrl,
            avatarData:
                target.avatarData,
            initialConversationId:
                conversationId,
          );
        },
      ),
    );

    if (ProjectXpCommunicatorUiService
        .communicatorSessionActive) {
      await SystemChrome
          .setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    }
  }

  Future<void> _markConversationReadSafely(
    String conversationId,
  ) async {
    try {
      await PrivateMessageService
          .markConversationRead(
        conversationId,
      );
    } catch (error) {
      debugPrint(
        'Marquage de lecture depuis notification impossible : $error',
      );
    }
  }

  Future<_ConversationTarget?>
      _resolveConversationTarget({
    required String conversationId,
    required Map<String, dynamic> data,
  }) async {
    Map<String, dynamic>? matchingConversation;

    for (int attempt = 0;
        attempt < 4;
        attempt++) {
      try {
        final List<Map<String, dynamic>> inbox =
            await PrivateMessageService
                .getInbox();

        for (final Map<String, dynamic>
            conversation in inbox) {
          final String id =
              conversation[
                          'conversation_id']
                      ?.toString()
                      .trim() ??
                  '';

          if (id == conversationId) {
            matchingConversation =
                conversation;
            break;
          }
        }
      } catch (error) {
        debugPrint(
          'Recherche conversation depuis notification impossible : $error',
        );
      }

      if (matchingConversation != null) {
        break;
      }

      if (attempt < 3) {
        await Future<void>.delayed(
          const Duration(
            milliseconds: 220,
          ),
        );
      }
    }

    final Map<String, dynamic>? profile =
        _asMap(
      matchingConversation?[
          'friend_profile'],
    );

    String friendId =
        matchingConversation?[
                    'friend_id']
                ?.toString()
                .trim() ??
            '';

    if (friendId.isEmpty) {
      friendId =
          data['sender_id']
                  ?.toString()
                  .trim() ??
              '';
    }

    if (friendId.isEmpty) {
      return null;
    }

    String publicName =
        profile?['display_name']
                ?.toString()
                .trim() ??
            '';

    if (publicName.isEmpty) {
      publicName =
          data['sender_name']
                  ?.toString()
                  .trim() ??
              '';
    }

    if (publicName.isEmpty) {
      publicName = 'Aventurier';
    }

    String? alias;

    try {
      final Map<String, String> aliases =
          await FriendAliasService
              .getAliases();

      alias =
          aliases[friendId];
    } catch (_) {
      alias = null;
    }

    final String displayName =
        FriendAliasService
            .resolveDisplayName(
      publicDisplayName:
          publicName,
      alias:
          alias,
    );

    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic>? avatarData =
        _asMap(
      profile?['avatar_data'],
    );

    return _ConversationTarget(
      friendId: friendId,
      displayName: displayName,
      avatarUrl:
          avatarUrl.isEmpty
              ? null
              : avatarUrl,
      avatarData: avatarData,
    );
  }

  Future<void> _openCommunicator() async {
    final NavigatorState? navigator =
        projectXpNavigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: '/communicator',
        ),
        builder: (
          BuildContext context,
        ) {
          return const PhoneHomeScreen();
        },
      ),
    );
  }

  Future<void> _restoreNormalSystemBars() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor:
            Colors.transparent,
        systemNavigationBarColor:
            Colors.transparent,
        statusBarIconBrightness:
            Brightness.light,
        systemNavigationBarIconBrightness:
            Brightness.light,
      ),
    );
  }

  int _asInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  Map<String, dynamic>? _asMap(
    dynamic value,
  ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return null;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable:
          ProjectXpCommunicatorUiService
              .alertVisibilityRevision,
      builder: (
        BuildContext context,
        int revision,
        Widget? child,
      ) {
        final bool showCommunicatorShelf =
            ProjectXpCommunicatorUiService
                    .isNavigationReady &&
                !ProjectXpCommunicatorUiService
                    .isGlobalCommunicatorAlertSuppressed;

        if (!showCommunicatorShelf) {
          return widget.child;
        }

        final double systemTop =
            MediaQuery.paddingOf(
          context,
        ).top;

        return Stack(
          children: [
            Positioned.fill(
              child: widget.child,
            ),

            // Le mini Communicateur est placé sur la même ligne verticale
            // que la flèche "Retour" d'une AppBar standard.
            //
            // Il ne crée donc plus une deuxième barre au-dessus de la page.
            Positioned(
              top: systemTop + 7,
              right: 8,
              child: SafeArea(
                top: false,
                bottom: false,
                left: false,
                right: true,
                child: _CommunicatorShelf(
                  animation:
                      _shakeController,
                  count:
                      _persistentUnreadCount,
                  hasPending:
                      _persistentUnreadCount > 0,
                  onTap:
                      _openVisibleNotification,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommunicatorShelf extends StatelessWidget {
  const _CommunicatorShelf({
    required this.animation,
    required this.count,
    required this.hasPending,
    required this.onTap,
  });

  final Animation<double> animation;
  final int count;
  final bool hasPending;
  final VoidCallback onTap;

  @override
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: 48,
      height: 42,
      child: Semantics(
            button: true,
            label: hasPending
                ? 'Ouvrir la nouvelle notification du Communicateur XP'
                : 'Ouvrir le Communicateur XP',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (
                      BuildContext context,
                      Widget? child,
                    ) {
                      final double progress =
                          animation.value;

                      // Effet "transmission / hack" :
                      // plusieurs petites salves numériques séparées par
                      // de très courts moments de stabilité. Le téléphone
                      // ne donne plus l'impression d'être secoué brutalement.
                      double burst({
                        required double start,
                        required double end,
                        required double cycles,
                      }) {
                        if (progress <= start ||
                            progress >= end) {
                          return 0;
                        }

                        final double local =
                            (progress - start) /
                                (end - start);

                        final double envelope =
                            math.sin(
                          local * math.pi,
                        );

                        return math.sin(
                              local *
                                  math.pi *
                                  cycles *
                                  2,
                            ) *
                            envelope;
                      }

                      final double firstBurst =
                          burst(
                        start: 0.03,
                        end: 0.23,
                        cycles: 3.5,
                      );

                      final double secondBurst =
                          burst(
                        start: 0.34,
                        end: 0.57,
                        cycles: 4.5,
                      );

                      final double finalBurst =
                          burst(
                        start: 0.68,
                        end: 0.86,
                        cycles: 3,
                      );

                      final double glitch =
                          (firstBurst * 0.70) +
                              secondBurst +
                              (finalBurst * 0.55);

                      final double dx =
                          glitch * 5.2;

                      final double dy =
                          math.sin(
                                progress *
                                    math.pi *
                                    26,
                              ) *
                              glitch.abs() *
                              0.8;

                      final double angle =
                          glitch * 0.055;

                      final double scale =
                          1 +
                              (glitch.abs() *
                                  0.028);

                      final double opacity =
                          (1 -
                                  (glitch.abs() *
                                      0.12))
                              .clamp(
                                0.82,
                                1.0,
                              );

                      return Opacity(
                        opacity: opacity,
                        child: Transform.translate(
                          offset: Offset(
                            dx,
                            dy,
                          ),
                          child: Transform.rotate(
                            angle: angle,
                            child: Transform.scale(
                              scale: scale,
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
                    child: _PermanentPhoneIcon(
                      count: count,
                      hasPending:
                          hasPending,
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

class _PermanentPhoneIcon extends StatelessWidget {
  const _PermanentPhoneIcon({
    required this.count,
    required this.hasPending,
  });

  final int count;
  final bool hasPending;

  @override
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: 42,
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.phone_android_rounded,
            size: 32,
            color: hasPending
                ? const Color(
                    0xffffd27a,
                  )
                : const Color(
                    0xffc69a55,
                  ),
            shadows: hasPending
                ? [
                    Shadow(
                      color: const Color(
                        0xffffc857,
                      ).withValues(
                        alpha: 0.38,
                      ),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),

          if (count > 0)
            Positioned(
              right: -3,
              top: -2,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius:
                      BorderRadius.circular(
                    99,
                  ),
                  border: Border.all(
                    color: const Color(
                      0xff21150e,
                    ),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  count > 99
                      ? '99+'
                      : count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight:
                        FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationTarget {
  const _ConversationTarget({
    required this.friendId,
    required this.displayName,
    required this.avatarUrl,
    required this.avatarData,
  });

  final String friendId;
  final String displayName;
  final String? avatarUrl;
  final Map<String, dynamic>? avatarData;
}
