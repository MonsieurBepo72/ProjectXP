import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_audio_service.dart';
import '../services/auth_service.dart';
import '../services/compagnie_request_notification_sync.dart';
import '../services/friend_service.dart';
import '../services/notification_center_service.dart';
import '../services/private_message_service.dart';
import '../services/online_presence_service.dart';
import '../services/project_xp_communicator_ui_service.dart';
import 'computer_screen.dart';
import 'phone_home_screen.dart';
import 'compagnie_screen.dart';
import 'tavern_screen.dart';

class HallScreen extends StatefulWidget {
  const HallScreen({
    super.key,
  });

  @override
  State<HallScreen> createState() => _HallScreenState();
}

class _HallScreenState extends State<HallScreen>
    with WidgetsBindingObserver, RouteAware {
  // ===========================================================================
  // REPÈRE LOGIQUE DU HALL
  //
  // Toute la scène est construite dans un repère fixe 941 × 1672.
  //
  // Le FittedBox applique ensuite automatiquement une échelle uniforme
  // en fonction du téléphone.
  // ===========================================================================

  static const double hallWidth = 941;
  static const double hallHeight = 1672;

  // ===========================================================================
  // DIMENSIONS NATIVES DES EXTENSIONS
  //
  // hall_extension_top.png    = 1570 × 1001
  // hall_extension_bottom.png = 1570 × 1001
  //
  // Leur ratio est toujours conservé.
  // ===========================================================================

  static const double extensionNativeWidth = 1570;
  static const double extensionNativeHeight = 1001;

  // ===========================================================================
  // EXTENSION HAUTE - FIGÉE
  // ===========================================================================

  static const double _topExtensionX = -184.5;
  static const double _topExtensionY = -261;
  static const double _topExtensionSize = 1350;

  double get _topExtensionHeight {
    return _topExtensionSize *
        (extensionNativeHeight / extensionNativeWidth);
  }

  // ===========================================================================
  // EXTENSION BASSE - FIGÉE
  //
  // Valeurs conservées pour le moment.
  // On pourra revenir uniquement sur cet élément plus tard.
  // ===========================================================================

  static const double _bottomExtensionX = -75.5;
  static const double _bottomExtensionY = 1397;
  static const double _bottomExtensionSize = 1018;

  double get _bottomExtensionHeight {
    return _bottomExtensionSize *
        (extensionNativeHeight / extensionNativeWidth);
  }

  // ===========================================================================
  // COMPTOIR / PC - FIGÉ
  //
  // hall_foreground_pc_counter.png = 1024 × 1024
  // ===========================================================================

  static const double _pcCounterX = 277;
  static const double _pcCounterY = 1170;
  static const double _pcCounterSize = 382;

  // Mets true uniquement pour afficher les zones tactiles en rouge.
  static const bool debugTouchZones = false;

  // ===========================================================================
  // AMBIANCE DYNAMIQUE DU HALL
  // ===========================================================================

  DateTime _hallClock = DateTime.now();
  Timer? _hallClockTimer;

  static const String _dayHallAsset =
      'assets/images/hall/hall_background_day.png';

  static const String _nightHallAsset =
      'assets/images/hall/hall_background_night.png';

  // ===========================================================================
  // BJORN
  // ===========================================================================

  String bjornMessage =
      'Bienvenue aventurier.\n'
      'Que puis-je faire pour toi ?';

  int _dialogueVersion = 0;

  // ===========================================================================
  // NOTIFICATIONS / TÉLÉPHONE
  // ===========================================================================

  int _notificationCenterUnreadCount = 0;
  int _unreadPrivateMessageCount = 0;
  int _incomingFriendRequestCount = 0;

  StreamSubscription<int>?
      _privateMessageUnreadSubscription;

  StreamSubscription<int>?
      _friendRequestCountSubscription;

  StreamSubscription<int>?
      _notificationCenterCountSubscription;

  int get _unreadNotificationCount {
    return _notificationCenterUnreadCount +
        _unreadPrivateMessageCount +
        _incomingFriendRequestCount;
  }

  String get _unreadNotificationLabel {
    if (_unreadNotificationCount > 99) {
      return '99+';
    }

    return _unreadNotificationCount.toString();
  }

  final Object _globalCommunicatorAlertToken =
      Object();

  PageRoute<dynamic>? _hallRoute;

  bool _hallAlertSuppressed = false;

  void _suppressGlobalCommunicatorAlert() {
    if (_hallAlertSuppressed) {
      return;
    }

    _hallAlertSuppressed = true;

    ProjectXpCommunicatorUiService
        .suppressGlobalCommunicatorAlert(
      _globalCommunicatorAlertToken,
    );
  }

  void _releaseGlobalCommunicatorAlert() {
    if (!_hallAlertSuppressed) {
      return;
    }

    _hallAlertSuppressed = false;

    ProjectXpCommunicatorUiService
        .releaseGlobalCommunicatorAlert(
      _globalCommunicatorAlertToken,
    );
  }

  // ===========================================================================
  // INITIALISATION
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    unawaited(
      OnlinePresenceService.instance.start(),
    );

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        _refreshCompagniePhone();
        _startPhoneRealtimeCounters();
      },
    );

    _hallClockTimer = Timer.periodic(
      const Duration(
        seconds: 30,
      ),
      (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _hallClock = DateTime.now();
        });
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final ModalRoute<dynamic>? modalRoute =
        ModalRoute.of(
      context,
    );

    if (modalRoute is! PageRoute<dynamic>) {
      return;
    }

    if (_hallRoute != modalRoute) {
      if (_hallRoute != null) {
        projectXpRouteObserver.unsubscribe(
          this,
        );
      }

      _hallRoute = modalRoute;

      projectXpRouteObserver.subscribe(
        this,
        modalRoute,
      );
    }

    if (modalRoute.isCurrent) {
      _suppressGlobalCommunicatorAlert();

      ProjectXpCommunicatorUiService
          .markNavigationReady();
    }
  }

  @override
  void didPush() {
    _suppressGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .markNavigationReady();
  }

  @override
  void didPopNext() {
    _suppressGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .markNavigationReady();
  }

  @override
  void didPushNext() {
    _releaseGlobalCommunicatorAlert();
  }

  @override
  void didPop() {
    _releaseGlobalCommunicatorAlert();
  }

  @override
  void dispose() {
    projectXpRouteObserver.unsubscribe(
      this,
    );

    _releaseGlobalCommunicatorAlert();

    WidgetsBinding.instance.removeObserver(this);
    _hallClockTimer?.cancel();

    _privateMessageUnreadSubscription?.cancel();
    _friendRequestCountSubscription?.cancel();
    _notificationCenterCountSubscription?.cancel();

    unawaited(
      OnlinePresenceService.instance.stop(),
    );

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state != AppLifecycleState.resumed || !mounted) {
      return;
    }

    setState(() {
      _hallClock = DateTime.now();
    });

    unawaited(
      _refreshCompagniePhone(),
    );
  }

  // ===========================================================================
  // COMPTEURS REALTIME DU COMMUNICATEUR
  // ===========================================================================

  void _startPhoneRealtimeCounters() {
    _privateMessageUnreadSubscription?.cancel();
    _friendRequestCountSubscription?.cancel();
    _notificationCenterCountSubscription?.cancel();

    _privateMessageUnreadSubscription =
        PrivateMessageService
            .unreadCountStream()
            .listen(
      (
        int count,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _unreadPrivateMessageCount =
              count < 0 ? 0 : count;
        });
      },
      onError: (
        Object error,
      ) {
        debugPrint(
          'Compteur messages privés du Hall indisponible : $error',
        );
      },
    );

    _friendRequestCountSubscription =
        FriendService
            .incomingRequestCountStream()
            .listen(
      (
        int count,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _incomingFriendRequestCount =
              count < 0 ? 0 : count;
        });
      },
      onError: (
        Object error,
      ) {
        debugPrint(
          'Compteur demandes d’amis du Hall indisponible : $error',
        );
      },
    );

    _notificationCenterCountSubscription =
        NotificationCenterService
            .unreadCountStream()
            .listen(
      (
        int count,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _notificationCenterUnreadCount =
              count < 0 ? 0 : count;
        });
      },
      onError: (
        Object error,
      ) {
        debugPrint(
          'Compteur Notifications du Hall indisponible : $error',
        );
      },
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: const Color(
        0xff160e09,
      ),
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ===================================================================
          // FOND DE SÉCURITÉ
          // ===================================================================

          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xff100a07),
                  Color(0xff21150e),
                  Color(0xff100a07),
                ],
              ),
            ),
          ),

          // ===================================================================
          // SCÈNE PRINCIPALE 941 × 1672
          //
          // Toute la scène utilise le même repère.
          //
          // Le FittedBox applique ensuite automatiquement une échelle uniforme
          // adaptée à la taille disponible.
          // ===================================================================

          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              child: SizedBox(
                width: hallWidth,
                height: hallHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // =========================================================
                    // EXTENSION HAUTE
                    //
                    // X = -184.5
                    // Y = -261
                    // S = 1350
                    //
                    // Ratio original 1570 × 1001 conservé.
                    // =========================================================

                    Positioned(
                      left: _topExtensionX,
                      top: _topExtensionY,
                      width: _topExtensionSize,
                      height: _topExtensionHeight,
                      child: IgnorePointer(
                        child: Image.asset(
                          'assets/images/hall_extension_top.png',
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),

                    // =========================================================
                    // EXTENSION BASSE
                    //
                    // X = -75.5
                    // Y = 1397
                    // S = 1018
                    //
                    // Ratio original 1570 × 1001 conservé.
                    // =========================================================

                    Positioned(
                      left: _bottomExtensionX,
                      top: _bottomExtensionY,
                      width: _bottomExtensionSize,
                      height: _bottomExtensionHeight,
                      child: IgnorePointer(
                        child: Image.asset(
                          'assets/images/hall_extension_bottom.png',
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),

                    // =========================================================
                    // HALL + BAIE VITRÉE + JOUR / NUIT
                    // =========================================================

                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          end: _nightOpacity(
                            _hallClock,
                          ),
                        ),
                        duration: const Duration(
                          seconds: 4,
                        ),
                        curve: Curves.easeInOutCubic,
                        builder: (
                          context,
                          nightBlend,
                          child,
                        ) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              // =================================================
                              // BACKGROUND JOUR
                              // =================================================

                              Image.asset(
                                _dayHallAsset,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.high,
                              ),

                              // =================================================
                              // BACKGROUND NUIT
                              //
                              // Visible uniquement dans les carreaux de la baie.
                              // =================================================

                              Opacity(
                                opacity: nightBlend,
                                child: ClipPath(
                                  clipper:
                                      const _HallWindowGlassClipper(),
                                  child: Image.asset(
                                    _nightHallAsset,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),

                              // =================================================
                              // SOLEIL / LUNE
                              // =================================================

                              IgnorePointer(
                                child: ClipPath(
                                  clipper:
                                      const _HallWindowSkyGlassClipper(),
                                  child: _HallCelestialAssetsLayer(
                                    time: _hallClock,
                                  ),
                                ),
                              ),

                              // =================================================
                              // OVERLAY DE LA FENÊTRE
                              // =================================================

                              IgnorePointer(
                                child: Image.asset(
                                  'assets/images/hall/'
                                  'hall_window_overlay.png',
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // =========================================================
                    // BJORN
                    // =========================================================

                    Positioned(
                      left: 105,
                      top: 930,
                      width: 650,
                      child: GestureDetector(
                        onTap: () {
                          _setBjornMessage(
                            'Bienvenue aventurier.\n'
                            'Je suis Bjorn, gardien de cette taverne.',
                          );
                        },
                        child: Image.asset(
                          'assets/images/bjorn/bjorn_idle.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),

                    // =========================================================
                    // COMPTOIR / PC
                    //
                    // X = 277
                    // Y = 1170
                    // S = 382
                    // =========================================================

                    Positioned(
                      left: _pcCounterX,
                      top: _pcCounterY,
                      width: _pcCounterSize,
                      height: _pcCounterSize,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openComputer,
                        child: Image.asset(
                          'assets/images/hall_foreground_pc_counter.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),

                    // =========================================================
                    // LUMIÈRE DYNAMIQUE
                    // =========================================================

                    Positioned.fill(
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            end: _nightOpacity(
                              _hallClock,
                            ),
                          ),
                          duration: const Duration(
                            seconds: 4,
                          ),
                          curve: Curves.easeInOutCubic,
                          builder: (
                            context,
                            nightBlend,
                            child,
                          ) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                end: _goldenHourOpacity(
                                  _hallClock,
                                ),
                              ),
                              duration: const Duration(
                                seconds: 4,
                              ),
                              curve: Curves.easeInOutCubic,
                              builder: (
                                context,
                                goldenBlend,
                                child,
                              ) {
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ColoredBox(
                                        color: const Color(
                                          0xff173b69,
                                        ).withValues(
                                          alpha: 0.20 * nightBlend,
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: ColoredBox(
                                        color: const Color(
                                          0xffff9b52,
                                        ).withValues(
                                          alpha: 0.09 * goldenBlend,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // =========================================================
                    // PORTAIL MODE COMPAGNIE
                    // =========================================================

                    Positioned(
                      left: 82,
                      top: 590,
                      width: 225,
                      height: 405,
                      child: _TouchZone(
                        debug: debugTouchZones,
                        label: 'Mode Compagnie',
                        onTap: _openCompagnie,
                      ),
                    ),

                    // =========================================================
                    // PORTAIL VERROUILLÉ
                    // =========================================================

                    Positioned(
                      right: 72,
                      top: 590,
                      width: 225,
                      height: 405,
                      child: _TouchZone(
                        debug: debugTouchZones,
                        label: 'Portail verrouillé',
                        onTap: () {
                          _setBjornMessage(
                            'Hmm... Ce portail reste scellé.\n'
                            'Même moi, j’ignore encore ce qui se cache derrière.',
                          );
                        },
                      ),
                    ),

                    // =========================================================
                    // LIVRE / MODE TAVERNE
                    // =========================================================

                    Positioned(
                      left: 610,
                      top: 1220,
                      width: 170,
                      height: 195,
                      child: _TouchZone(
                        debug: debugTouchZones,
                        label: 'Mode Taverne',
                        onTap: _openTavern,
                      ),
                    ),

                    // =========================================================
                    // TÉLÉPHONE / COMMUNICATEUR XP
                    // =========================================================

                    Positioned(
                      left: 805,
                      top: 1220,
                      width: 100,
                      height: 185,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: _TouchZone(
                              debug: debugTouchZones,
                              label: 'Communicateur XP',
                              onTap: _openPhone,
                            ),
                          ),

                          if (_unreadNotificationCount > 0)
                            Positioned(
                              right: -5,
                              top: -8,
                              child: IgnorePointer(
                                child: TweenAnimationBuilder<double>(
                                  key: ValueKey<int>(
                                    _unreadNotificationCount,
                                  ),
                                  tween: Tween<double>(
                                    begin: 0.72,
                                    end: 1,
                                  ),
                                  duration: const Duration(
                                    milliseconds: 420,
                                  ),
                                  curve: Curves.elasticOut,
                                  builder: (
                                    BuildContext context,
                                    double scale,
                                    Widget? child,
                                  ) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 31,
                                      minHeight: 31,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.redAccent.withValues(
                                            alpha: 0.48,
                                          ),
                                          blurRadius: 14,
                                          spreadRadius: 2,
                                        ),
                                        const BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 7,
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _unreadNotificationLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // =========================================================
                    // DIALOGUE BJORN
                    // =========================================================

                    Positioned(
                      left: 65,
                      right: 65,
                      bottom: 35,
                      child: _buildBjornDialogue(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CYCLE JOUR / NUIT
  // ===========================================================================

  double _minutesOfDay(
    DateTime time,
  ) {
    return (time.hour * 60) +
        time.minute +
        (time.second / 60);
  }

  double _nightOpacity(
    DateTime time,
  ) {
    final double minutes = _minutesOfDay(
      time,
    );

    const double dawnStart = 5.5 * 60;
    const double dawnEnd = 7.5 * 60;

    const double duskStart = 18 * 60;
    const double duskEnd = 20.5 * 60;

    if (minutes < dawnStart || minutes >= duskEnd) {
      return 1;
    }

    if (minutes >= dawnStart && minutes < dawnEnd) {
      return 1 -
          ((minutes - dawnStart) /
              (dawnEnd - dawnStart));
    }

    if (minutes >= duskStart && minutes < duskEnd) {
      return (minutes - duskStart) /
          (duskEnd - duskStart);
    }

    return 0;
  }

  double _goldenHourOpacity(
    DateTime time,
  ) {
    final double minutes = _minutesOfDay(
      time,
    );

    const double morningStart = 6 * 60;
    const double morningPeak = 7 * 60;
    const double morningEnd = 8 * 60;

    const double eveningStart = 17 * 60;
    const double eveningPeak = 18.5 * 60;
    const double eveningEnd = 20 * 60;

    double triangular(
      double start,
      double peak,
      double end,
    ) {
      if (minutes <= start || minutes >= end) {
        return 0;
      }

      if (minutes <= peak) {
        return (minutes - start) /
            (peak - start);
      }

      return 1 -
          ((minutes - peak) /
              (end - peak));
    }

    final double morning = triangular(
      morningStart,
      morningPeak,
      morningEnd,
    );

    final double evening = triangular(
      eveningStart,
      eveningPeak,
      eveningEnd,
    );

    return morning > evening
        ? morning
        : evening;
  }

  // ===========================================================================
  // OUVRIR COMPAGNIE
  // ===========================================================================

  Future<void> _openCompagnie() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const CompagnieScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshCompagniePhone();
  }

  // ===========================================================================
  // OUVRIR LE TERMINAL
  // ===========================================================================

  Future<void> _openComputer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const ComputerScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshCompagniePhone();
  }

  // ===========================================================================
  // MODE TAVERNE
  // ===========================================================================

  Future<void> _openTavern() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const TavernScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshCompagniePhone();
  }

  // ===========================================================================
  // MESSAGE BJORN
  // ===========================================================================

  void _setBjornMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      bjornMessage = message;
      _dialogueVersion++;
    });
  }

  // ===========================================================================
  // DIALOGUE BJORN
  // ===========================================================================

  Widget _buildBjornDialogue() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xff1b110b,
        ).withValues(
          alpha: 0.90,
        ),
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: const Color(
            0xffffc857,
          ),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 14,
            offset: Offset(
              0,
              6,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_fire_department,
                color: Color(
                  0xffffc857,
                ),
                size: 18,
              ),
              SizedBox(
                width: 7,
              ),
              Text(
                'BJORN',
                style: TextStyle(
                  color: Color(
                    0xffffc857,
                  ),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 6,
          ),

          AnimatedSwitcher(
            duration: const Duration(
              milliseconds: 300,
            ),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (
              Widget child,
              Animation<double> animation,
            ) {
              final Animation<Offset> slide =
                  Tween<Offset>(
                begin: const Offset(
                  0,
                  0.10,
                ),
                end: Offset.zero,
              ).animate(
                animation,
              );

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: slide,
                  child: child,
                ),
              );
            },
            child: Text(
              bjornMessage,
              key: ValueKey(
                '$bjornMessage-$_dialogueVersion',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SYNCHRONISATION DU TÉLÉPHONE
  // ===========================================================================

  Future<void> _refreshCompagniePhone() async {
    try {
      final String? userId =
          await AuthService.getCurrentUserId();

      if (userId == null || userId.trim().isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _notificationCenterUnreadCount = 0;
        });

        return;
      }

      await CompagnieRequestNotificationSync
          .syncForCurrentUser();

      final int notificationCount =
          await NotificationCenterService
              .unreadCount();

      if (!mounted) {
        return;
      }

      setState(() {
        _notificationCenterUnreadCount =
            notificationCount < 0
                ? 0
                : notificationCount;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _notificationCenterUnreadCount = 0;
      });
    }
  }

  // ===========================================================================
  // COMMUNICATEUR XP
  //
  // Le téléphone reste toujours accessible, même lorsque les notifications
  // sont désactivées dans le Terminal. Ce réglage ne doit pas bloquer l'accès
  // aux Messages, Amis, Demandes et autres applications du téléphone.
  // ===========================================================================

  Future<void> _openPhone() async {
    AppAudioService.instance.notificationFeedback();

    if (_unreadNotificationCount > 0) {
      _setBjornMessage(
        'Ton Communicateur XP a de nouvelles activités.',
      );
    } else {
      _setBjornMessage(
        'Ton Communicateur XP est prêt.',
      );
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const PhoneHomeScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshCompagniePhone();
  }
}

// =============================================================================
// MONTANTS / TRACERIES DE LA BAIE
// =============================================================================

class _HallWindowForegroundClipper
    extends CustomClipper<Path> {
  const _HallWindowForegroundClipper();

  static const double _referenceWidth = 941;
  static const double _referenceHeight = 1672;

  void _addSegment(
    Path path,
    Offset a,
    Offset b,
    double width,
  ) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;

    final double length = math.sqrt(
      (dx * dx) + (dy * dy),
    );

    if (length <= 0.001) {
      return;
    }

    final double half = width / 2;

    final double px =
        (-dy / length) * half;

    final double py =
        (dx / length) * half;

    path.addPolygon(
      [
        Offset(
          a.dx + px,
          a.dy + py,
        ),
        Offset(
          b.dx + px,
          b.dy + py,
        ),
        Offset(
          b.dx - px,
          b.dy - py,
        ),
        Offset(
          a.dx - px,
          a.dy - py,
        ),
      ],
      true,
    );
  }

  void _addQuadratic(
    Path path,
    Offset start,
    Offset control,
    Offset end,
    double width,
  ) {
    Offset previous = start;

    const int steps = 14;

    for (int i = 1; i <= steps; i++) {
      final double t = i / steps;
      final double mt = 1 - t;

      final Offset current = Offset(
        (mt * mt * start.dx) +
            (2 * mt * t * control.dx) +
            (t * t * end.dx),
        (mt * mt * start.dy) +
            (2 * mt * t * control.dy) +
            (t * t * end.dy),
      );

      _addSegment(
        path,
        previous,
        current,
        width,
      );

      previous = current;
    }
  }

  @override
  Path getClip(
    Size size,
  ) {
    final double sx =
        size.width / _referenceWidth;

    final double sy =
        size.height / _referenceHeight;

    Offset s(
      double x,
      double y,
    ) {
      return Offset(
        x * sx,
        y * sy,
      );
    }

    Rect r(
      double left,
      double top,
      double right,
      double bottom,
    ) {
      return Rect.fromLTRB(
        left * sx,
        top * sy,
        right * sx,
        bottom * sy,
      );
    }

    final double stroke =
        12 * ((sx + sy) / 2);

    final Path path = Path();

    // Grille principale.
    path.addRect(
      r(404, 316, 417, 662),
    );

    path.addRect(
      r(484, 309, 497, 662),
    );

    path.addRect(
      r(561, 316, 574, 662),
    );

    path.addRect(
      r(334, 316, 608, 329),
    );

    path.addRect(
      r(334, 438, 608, 451),
    );

    path.addRect(
      r(334, 578, 608, 591),
    );

    // Montant central.
    path.addRect(
      r(484, 233, 497, 321),
    );

    // Grandes ogives internes.
    _addQuadratic(
      path,
      s(411, 322),
      s(409, 276),
      s(447, 248),
      stroke,
    );

    _addQuadratic(
      path,
      s(568, 322),
      s(571, 276),
      s(535, 248),
      stroke,
    );

    // Branches en Y.
    _addQuadratic(
      path,
      s(490, 306),
      s(474, 276),
      s(447, 248),
      stroke,
    );

    _addQuadratic(
      path,
      s(490, 306),
      s(507, 276),
      s(535, 248),
      stroke,
    );

    // Petites ogives supérieures.
    _addQuadratic(
      path,
      s(447, 249),
      s(457, 230),
      s(470, 232),
      stroke,
    );

    _addQuadratic(
      path,
      s(470, 232),
      s(482, 234),
      s(490, 252),
      stroke,
    );

    _addQuadratic(
      path,
      s(490, 252),
      s(500, 234),
      s(512, 232),
      stroke,
    );

    _addQuadratic(
      path,
      s(512, 232),
      s(525, 230),
      s(535, 249),
      stroke,
    );

    // Traceries latérales.
    _addQuadratic(
      path,
      s(411, 288),
      s(392, 255),
      s(370, 258),
      stroke,
    );

    _addQuadratic(
      path,
      s(568, 288),
      s(588, 255),
      s(606, 259),
      stroke,
    );

    return path;
  }

  @override
  bool shouldReclip(
    covariant _HallWindowForegroundClipper oldClipper,
  ) {
    return false;
  }
}

// =============================================================================
// CARREAUX DE VERRE
// =============================================================================

class _HallWindowGlassClipper
    extends CustomClipper<Path> {
  const _HallWindowGlassClipper();

  @override
  Path getClip(
    Size size,
  ) {
    final Path window =
        const _HallWindowClipper().getClip(
      size,
    );

    final Path mullions =
        const _HallWindowForegroundClipper()
            .getClip(
      size,
    );

    return Path.combine(
      PathOperation.difference,
      window,
      mullions,
    );
  }

  @override
  bool shouldReclip(
    covariant _HallWindowGlassClipper oldClipper,
  ) {
    return false;
  }
}

// =============================================================================
// CIEL VISIBLE DANS LA BAIE
// =============================================================================

class _HallWindowSkyGlassClipper
    extends CustomClipper<Path> {
  const _HallWindowSkyGlassClipper();

  @override
  Path getClip(
    Size size,
  ) {
    final double sx =
        size.width / 941;

    final double sy =
        size.height / 1672;

    final Path sky = Path()
      ..moveTo(
        310 * sx,
        190 * sy,
      )
      ..lineTo(
        635 * sx,
        190 * sy,
      )
      ..lineTo(
        635 * sx,
        515 * sy,
      )
      ..lineTo(
        606 * sx,
        494 * sy,
      )
      ..lineTo(
        585 * sx,
        483 * sy,
      )
      ..lineTo(
        563 * sx,
        505 * sy,
      )
      ..lineTo(
        545 * sx,
        519 * sy,
      )
      ..lineTo(
        528 * sx,
        527 * sy,
      )
      ..lineTo(
        505 * sx,
        520 * sy,
      )
      ..lineTo(
        486 * sx,
        519 * sy,
      )
      ..lineTo(
        469 * sx,
        521 * sy,
      )
      ..lineTo(
        460 * sx,
        495 * sy,
      )
      ..lineTo(
        454 * sx,
        485 * sy,
      )
      ..lineTo(
        448 * sx,
        468 * sy,
      )
      ..lineTo(
        443 * sx,
        491 * sy,
      )
      ..lineTo(
        437 * sx,
        476 * sy,
      )
      ..lineTo(
        432 * sx,
        448 * sy,
      )
      ..lineTo(
        426 * sx,
        489 * sy,
      )
      ..lineTo(
        421 * sx,
        474 * sy,
      )
      ..lineTo(
        416 * sx,
        493 * sy,
      )
      ..lineTo(
        409 * sx,
        505 * sy,
      )
      ..lineTo(
        397 * sx,
        514 * sy,
      )
      ..lineTo(
        382 * sx,
        505 * sy,
      )
      ..lineTo(
        365 * sx,
        493 * sy,
      )
      ..lineTo(
        345 * sx,
        505 * sy,
      )
      ..lineTo(
        310 * sx,
        520 * sy,
      )
      ..close();

    final Path glass =
        const _HallWindowGlassClipper()
            .getClip(
      size,
    );

    return Path.combine(
      PathOperation.intersect,
      glass,
      sky,
    );
  }

  @override
  bool shouldReclip(
    covariant _HallWindowSkyGlassClipper oldClipper,
  ) {
    return false;
  }
}

// =============================================================================
// SOLEIL / LUNE
// =============================================================================

class _HallCelestialAssetsLayer
    extends StatelessWidget {
  final DateTime time;

  const _HallCelestialAssetsLayer({
    required this.time,
  });

  static const double _referenceWidth = 941;
  static const double _referenceHeight = 1672;

  double get _minutes =>
      (time.hour * 60) +
      time.minute +
      (time.second / 60);

  double? _sunProgress() {
    const double start = 6 * 60;
    const double end = 18.75 * 60;

    if (_minutes < start || _minutes > end) {
      return null;
    }

    return ((_minutes - start) /
            (end - start))
        .clamp(
      0.0,
      1.0,
    );
  }

  double? _moonProgress() {
    const double start = 19 * 60;

    const double endNextDay =
        (24 * 60) +
            (7 * 60);

    double value = _minutes;

    if (value < 7 * 60) {
      value += 24 * 60;
    }

    if (value < start || value > endNextDay) {
      return null;
    }

    return ((value - start) /
            (endNextDay - start))
        .clamp(
      0.0,
      1.0,
    );
  }

  double _sunOpacity() {
    const double fadeInStart = 5.75 * 60;
    const double fullStart = 6.5 * 60;

    const double fullEnd = 18 * 60;
    const double fadeOutEnd = 18.75 * 60;

    final double value = _minutes;

    if (value <= fadeInStart ||
        value >= fadeOutEnd) {
      return 0;
    }

    if (value < fullStart) {
      return ((value - fadeInStart) /
              (fullStart - fadeInStart))
          .clamp(
        0.0,
        1.0,
      );
    }

    if (value <= fullEnd) {
      return 1;
    }

    return (1 -
            ((value - fullEnd) /
                (fadeOutEnd - fullEnd)))
        .clamp(
      0.0,
      1.0,
    );
  }

  double _moonOpacity() {
    const double fadeInStart = 19 * 60;
    const double fullStart = 20 * 60;

    const double fullEnd =
        (24 * 60) +
            (6 * 60);

    const double fadeOutEnd =
        (24 * 60) +
            (7 * 60);

    double value = _minutes;

    if (value < 19 * 60) {
      value += 24 * 60;
    }

    if (value <= fadeInStart ||
        value >= fadeOutEnd) {
      return 0;
    }

    if (value < fullStart) {
      return ((value - fadeInStart) /
              (fullStart - fadeInStart))
          .clamp(
        0.0,
        1.0,
      );
    }

    if (value <= fullEnd) {
      return 1;
    }

    return (1 -
            ((value - fullEnd) /
                (fadeOutEnd - fullEnd)))
        .clamp(
      0.0,
      1.0,
    );
  }

  double _quadratic(
    double start,
    double control,
    double end,
    double t,
  ) {
    final double mt = 1 - t;

    return (mt * mt * start) +
        (2 * mt * t * control) +
        (t * t * end);
  }

  Offset _sunPosition(
    double t,
  ) {
    return Offset(
      _quadratic(
        350,
        470,
        590,
        t,
      ),
      _quadratic(
        435,
        275,
        430,
        t,
      ),
    );
  }

  Offset _moonPosition(
    double t,
  ) {
    return Offset(
      _quadratic(
        590,
        485,
        355,
        t,
      ),
      _quadratic(
        430,
        270,
        425,
        t,
      ),
    );
  }

  Widget _celestial({
    required String asset,
    required Offset center,
    required double size,
    required double opacity,
  }) {
    return Positioned(
      left: center.dx - (size / 2),
      top: center.dy - (size / 2),
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final double? sunProgress =
        _sunProgress();

    final double? moonProgress =
        _moonProgress();

    return SizedBox(
      width: _referenceWidth,
      height: _referenceHeight,
      child: Stack(
        children: [
          if (sunProgress != null &&
              _sunOpacity() > 0.001)
            _celestial(
              asset: 'assets/images/hall/sun.png',
              center: _sunPosition(
                sunProgress,
              ),
              size: 82,
              opacity: _sunOpacity(),
            ),

          if (moonProgress != null &&
              _moonOpacity() > 0.001)
            _celestial(
              asset: 'assets/images/hall/moon.png',
              center: _moonPosition(
                moonProgress,
              ),
              size: 70,
              opacity: _moonOpacity(),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// FORME GLOBALE DE LA BAIE
// =============================================================================

class _HallWindowClipper
    extends CustomClipper<Path> {
  const _HallWindowClipper();

  @override
  Path getClip(
    Size size,
  ) {
    final double sx =
        size.width / 941;

    final double sy =
        size.height / 1672;

    final Path path = Path();

    path.moveTo(
      326 * sx,
      659 * sy,
    );

    path.lineTo(
      326 * sx,
      376 * sy,
    );

    path.cubicTo(
      326 * sx,
      274 * sy,
      384 * sx,
      211 * sy,
      470.5 * sx,
      211 * sy,
    );

    path.cubicTo(
      557 * sx,
      211 * sy,
      615 * sx,
      274 * sy,
      615 * sx,
      376 * sy,
    );

    path.lineTo(
      615 * sx,
      659 * sy,
    );

    path.close();

    return path;
  }

  @override
  bool shouldReclip(
    covariant _HallWindowClipper oldClipper,
  ) {
    return false;
  }
}

// =============================================================================
// ZONE TACTILE INVISIBLE
// =============================================================================

class _TouchZone extends StatelessWidget {
  final bool debug;
  final String label;
  final VoidCallback onTap;

  const _TouchZone({
    required this.debug,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: debug
              ? BoxDecoration(
                  color: Colors.red.withValues(
                    alpha: 0.25,
                  ),
                  border: Border.all(
                    color: Colors.red,
                    width: 3,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}