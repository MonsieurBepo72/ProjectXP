import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_audio_service.dart';
import '../services/auth_service.dart';
import '../services/computer_settings_service.dart';
import '../services/compagnie_invitation_storage.dart';
import '../services/compagnie_request_notification_sync.dart';
import '../services/compagnie_request_storage.dart';
import 'computer_screen.dart';
import 'compagnie_phone_screen.dart';
import 'compagnie_screen.dart';

class HallScreen extends StatefulWidget {
  const HallScreen({super.key});

  @override
  State<HallScreen> createState() => _HallScreenState();
}

class _HallScreenState extends State<HallScreen>
    with WidgetsBindingObserver {
  // ===========================================================================
  // DIMENSIONS DE RÉFÉRENCE DU HALL
  // ===========================================================================

  static const double hallWidth = 941;
  static const double hallHeight = 1672;

  // Mets true uniquement pour afficher les zones tactiles en rouge.
  static const bool debugTouchZones = false;

  // ===========================================================================
  // AMBIANCE DYNAMIQUE DU HALL
  //
  // Le décor principal reste TOUJOURS hall_background_day.png.
  // La version nuit n'est visible que dans la baie vitrée.
  // Ainsi, aucun objet du Hall ne change de place.
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

  int _pendingCompagnieActivityCount = 0;

  int get _unreadNotificationCount {
    if (!ComputerSettingsService
        .current.notificationsEnabled) {
      return 0;
    }

    return _pendingCompagnieActivityCount;
  }

  // ===========================================================================
  // INITIALISATION
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

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
      },
    );

    _hallClockTimer = Timer.periodic(
      const Duration(minutes: 1),
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hallClockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state != AppLifecycleState.resumed ||
        !mounted) {
      return;
    }

    setState(() {
      _hallClock = DateTime.now();
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff160e09),
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double screenWidth = constraints.maxWidth;
          final double screenHeight = constraints.maxHeight;

          final double widthScale = screenWidth / hallWidth;
          final double heightScale = screenHeight / hallHeight;

          final double hallScale =
              widthScale < heightScale ? widthScale : heightScale;

          final double displayedHallWidth = hallWidth * hallScale;
          final double displayedHallHeight = hallHeight * hallScale;

          final double horizontalSpace =
              (screenWidth - displayedHallWidth) / 2;

          final double verticalSpace =
              (screenHeight - displayedHallHeight) / 2;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ===============================================================
              // FOND DE SÉCURITÉ
              // ===============================================================

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

              // ===============================================================
              // EXTENSION HAUTE
              // ===============================================================

              if (verticalSpace > 0)
                Positioned(
                  left: horizontalSpace,
                  top: 0,
                  width: displayedHallWidth,
                  height: verticalSpace + 18,
                  child: ClipRect(
                    child: Image.asset(
                      'assets/images/hall_extension_top.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),

              // ===============================================================
              // EXTENSION BASSE
              // ===============================================================

              if (verticalSpace > 0)
                Positioned(
                  left: horizontalSpace,
                  bottom: 0,
                  width: displayedHallWidth,
                  height: verticalSpace + 18,
                  child: ClipRect(
                    child: Image.asset(
                      'assets/images/hall_extension_bottom.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ),

              // ===============================================================
              // HALL PRINCIPAL
              // ===============================================================

              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: hallWidth,
                    height: hallHeight,
                    child: Stack(
                      children: [
                        // =====================================================
                        // BACKGROUND DU HALL
                        // =====================================================

                        Positioned.fill(
                          child: Image.asset(
                            _dayHallAsset,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                        ),

                        // =====================================================
                        // BAIE VITRÉE DYNAMIQUE
                        //
                        // On superpose uniquement l'extérieur nocturne.
                        // Le cadre, les portails, le comptoir et tous les objets
                        // restent ceux de l'image de jour.
                        // =====================================================

                        Positioned.fill(
                          child: IgnorePointer(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                end: _nightOpacity(_hallClock),
                              ),
                              duration: const Duration(
                                seconds: 4,
                              ),
                              curve: Curves.easeInOutCubic,
                              builder: (
                                context,
                                opacity,
                                child,
                              ) {
                                return Opacity(
                                  opacity: opacity,
                                  child: child,
                                );
                              },
                              child: ClipPath(
                                clipper: const _HallWindowClipper(),
                                child: Image.asset(
                                  _nightHallAsset,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ===========================================================
                        // BJORN
                        // ===========================================================

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

                        // ===========================================================
                        // ÉCRAN DU PC - PREMIER PLAN DEVANT BJORN
                        // ===========================================================

                        Positioned(
                          left: 295,
                          top: 1150,
                          width: 350,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openComputer,
                            child: Image.asset(
                              'assets/images/hall_foreground_pc_counter.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // =====================================================
                        // LUMIÈRE DYNAMIQUE DU HALL
                        // =====================================================

                        Positioned.fill(
                          child: IgnorePointer(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: const Color(0xff173b69)
                                        .withValues(
                                      alpha: 0.20 *
                                          _nightOpacity(_hallClock),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: const Color(0xffff9b52)
                                        .withValues(
                                      alpha: 0.09 *
                                          _goldenHourOpacity(
                                            _hallClock,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // =====================================================
                        // PORTAIL MODE COMPAGNIE
                        // =====================================================

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

                        // =====================================================
                        // PORTAIL ???
                        // =====================================================

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

                        // =====================================================
                        // LIVRE - MODE TAVERNE
                        // =====================================================

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

                        // =====================================================
                        // TÉLÉPHONE - NOTIFICATIONS
                        // =====================================================

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
                                  label: 'Notifications',
                                  onTap: _openNotifications,
                                ),
                              ),
                              if (_unreadNotificationCount > 0)
                                Positioned(
                                  right: -5,
                                  top: -8,
                                  child: IgnorePointer(
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
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 7,
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _unreadNotificationCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // =====================================================
                        // DIALOGUE DE BJORN
                        // =====================================================

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
          );
        },
      ),
    );
  }

  // ===========================================================================
  // CYCLE JOUR / NUIT
  // ===========================================================================

  double _minutesOfDay(DateTime time) {
    return (time.hour * 60) +
        time.minute +
        (time.second / 60);
  }

  double _nightOpacity(DateTime time) {
    final double minutes = _minutesOfDay(time);

    const double dawnStart = 5.5 * 60; // 05:30
    const double dawnEnd = 7.5 * 60; // 07:30
    const double duskStart = 18 * 60; // 18:00
    const double duskEnd = 20.5 * 60; // 20:30

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

  double _goldenHourOpacity(DateTime time) {
    final double minutes = _minutesOfDay(time);

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
        return (minutes - start) / (peak - start);
      }

      return 1 -
          ((minutes - peak) / (end - peak));
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

    return morning > evening ? morning : evening;
  }

  // ===========================================================================
  // OUVRIR LE MODE COMPAGNIE
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
  // OUVRIR LE TERMINAL XP
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
  // OUVRIR LA TAVERNE
  // ===========================================================================

  void _openTavern() {
    _setBjornMessage(
      'Ah, le registre de la Taverne...\n'
      'C’est ici que les aventuriers se retrouvent.',
    );
  }

  // ===========================================================================
  // MODIFIER LE MESSAGE DE BJORN
  // ===========================================================================

  void _setBjornMessage(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      bjornMessage = message;
      _dialogueVersion++;
    });
  }

  // ===========================================================================
  // DIALOGUE DE BJORN
  // ===========================================================================

  Widget _buildBjornDialogue() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff1b110b).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xffffc857),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 14,
            offset: Offset(0, 6),
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
                color: Color(0xffffc857),
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                'BJORN',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (
              Widget child,
              Animation<double> animation,
            ) {
              final Animation<Offset> slide = Tween<Offset>(
                begin: const Offset(0, 0.10),
                end: Offset.zero,
              ).animate(animation);

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
  // SYNCHRONISER LE TÉLÉPHONE
  // ===========================================================================

  Future<void> _refreshCompagniePhone() async {
    try {
      final String? userId =
          await AuthService.getCurrentUserId();

      if (userId == null ||
          userId.trim().isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _pendingCompagnieActivityCount = 0;
        });

        return;
      }

      // Déclenche, si besoin, la vraie notification Android pour
      // les nouvelles demandes reçues.
      await CompagnieRequestNotificationSync
          .syncForCurrentUser();

      final requests =
          await CompagnieRequestStorage
              .pendingIncomingForUser(
        userId.trim(),
      );

      final invitations =
          await CompagnieInvitationStorage
              .pendingIncomingForUser(
        userId.trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingCompagnieActivityCount =
            requests.length + invitations.length;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingCompagnieActivityCount = 0;
      });
    }
  }

  // ===========================================================================
  // OUVRIR LE TÉLÉPHONE
  // ===========================================================================

  Future<void> _openNotifications() async {
    if (!ComputerSettingsService
        .current.notificationsEnabled) {
      _setBjornMessage(
        'Ton Communicateur XP est silencieux.\n'
        'Les notifications sont désactivées dans le Terminal.',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications désactivées dans les paramètres.',
          ),
        ),
      );

      return;
    }

    AppAudioService.instance
        .notificationFeedback();

    if (_pendingCompagnieActivityCount > 0) {
      _setBjornMessage(
        'Ton Communicateur XP contient une nouvelle activité Compagnie.',
      );
    } else {
      _setBjornMessage(
        'Ton Communicateur XP est prêt.\n'
        'Aucune nouvelle demande ou invitation pour le moment.',
      );
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const CompagniePhoneScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshCompagniePhone();
  }

}

// =============================================================================
// MASQUE DE LA BAIE VITRÉE
//
// Coordonnées exprimées dans le repère historique du Hall : 941 x 1672.
// Le masque reste volontairement à l'intérieur du cadre de pierre afin que
// les petites différences entre les images jour/nuit ne puissent jamais
// déplacer visuellement le décor intérieur.
// =============================================================================

class _HallWindowClipper extends CustomClipper<Path> {
  const _HallWindowClipper();

  @override
  Path getClip(Size size) {
    final double sx = size.width / 941;
    final double sy = size.height / 1672;

    final Path path = Path();

    path.moveTo(326 * sx, 659 * sy);
    path.lineTo(326 * sx, 376 * sy);

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

    path.lineTo(615 * sx, 659 * sy);
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
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: debug
              ? BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.25),
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
