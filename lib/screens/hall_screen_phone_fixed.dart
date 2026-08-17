import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_audio_service.dart';
import '../services/auth_service.dart';
import '../services/computer_settings_service.dart';
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

class _HallScreenState extends State<HallScreen> {
  // ===========================================================================
  // DIMENSIONS DE RÃ‰FÃ‰RENCE DU HALL
  // ===========================================================================

  static const double hallWidth = 941;
  static const double hallHeight = 1672;

  // Mets true uniquement pour afficher les zones tactiles en rouge.
  static const bool debugTouchZones = false;

  // ===========================================================================
  // BJORN
  // ===========================================================================

  String bjornMessage =
      'Bienvenue aventurier.\n'
      'Que puis-je faire pour toi ?';

  int _dialogueVersion = 0;

  // ===========================================================================
  // NOTIFICATIONS / TÃ‰LÃ‰PHONE
  // ===========================================================================

  int _pendingCompagnieRequestCount = 0;

  int get _unreadNotificationCount {
    if (!ComputerSettingsService
        .current.notificationsEnabled) {
      return 0;
    }

    return _pendingCompagnieRequestCount;
  }

  // ===========================================================================
  // INITIALISATION
  // ===========================================================================

  @override
  void initState() {
    super.initState();

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
              // FOND DE SÃ‰CURITÃ‰
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
                            'assets/images/hall/hall_background_day.png',
                            fit: BoxFit.fill,
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
                        // Ã‰CRAN DU PC - PREMIER PLAN DEVANT BJORN
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
                            label: 'Portail verrouillÃ©',
                            onTap: () {
                              _setBjornMessage(
                                'Hmm... Ce portail reste scellÃ©.\n'
                                'MÃªme moi, jâ€™ignore encore ce qui se cache derriÃ¨re.',
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
                        // TÃ‰LÃ‰PHONE - NOTIFICATIONS
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
      'Câ€™est ici que les aventuriers se retrouvent.',
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
  // SYNCHRONISER LE TÃ‰LÃ‰PHONE
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
          _pendingCompagnieRequestCount = 0;
        });

        return;
      }

      // DÃ©clenche, si besoin, la vraie notification Android pour
      // les nouvelles demandes reÃ§ues.
      await CompagnieRequestNotificationSync
          .syncForCurrentUser();

      final requests =
          await CompagnieRequestStorage
              .pendingIncomingForUser(
        userId.trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingCompagnieRequestCount =
            requests.length;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingCompagnieRequestCount = 0;
      });
    }
  }

  // ===========================================================================
  // OUVRIR LE TÃ‰LÃ‰PHONE
  // ===========================================================================

  Future<void> _openNotifications() async {
    if (!ComputerSettingsService
        .current.notificationsEnabled) {
      _setBjornMessage(
        'Ton Communicateur XP est silencieux.\n'
        'Les notifications sont dÃ©sactivÃ©es dans le Terminal.',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications dÃ©sactivÃ©es dans les paramÃ¨tres.',
          ),
        ),
      );

      return;
    }

    AppAudioService.instance
        .notificationFeedback();

    if (_pendingCompagnieRequestCount > 0) {
      _setBjornMessage(
        'On dirait que quelquâ€™un cherche Ã  rejoindre ton Compagnie.',
      );
    } else {
      _setBjornMessage(
        'Ton Communicateur XP est prÃªt.\n'
        'Aucune nouvelle demande pour le moment.',
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

