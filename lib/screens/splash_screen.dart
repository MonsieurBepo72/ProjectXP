import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/avatar_storage.dart';

import 'auth_screen.dart';
import 'avatar/avatar_choice_screen.dart';
import 'hall_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
  });

  @override
  State<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState
    extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _fadeAnimation;

  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // ============================================================
    // ANIMATION DU LOGO
    // ============================================================

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1000,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _controller.forward();

    _startSplash();
  }

  // ==============================================================
  // DÉMARRAGE
  // ==============================================================

  Future<void> _startSplash() async {
    // On lance la vérification de session
    // pendant que le Splash est affiché.
    final Future<Widget> destinationFuture =
        _getDestination();

    // Durée minimum du Splash.
    final Future<void> minimumSplashTime =
        Future.delayed(
      const Duration(
        milliseconds: 2400,
      ),
    );

    final List<dynamic> results =
        await Future.wait([
      destinationFuture,
      minimumSplashTime,
    ]);

    if (!mounted) {
      return;
    }

    final Widget destination =
        results[0] as Widget;

    _openNextScreen(
      destination,
    );
  }

  // ==============================================================
  // CHOIX DE L'ÉCRAN SUIVANT
  // ==============================================================

  Future<Widget> _getDestination() async {
    final bool isLoggedIn =
        await AuthService.isLoggedIn();

    // ------------------------------------------------------------
    // PAS CONNECTÉ
    // ------------------------------------------------------------

    if (!isLoggedIn) {
      return const AuthScreen();
    }

    // ------------------------------------------------------------
    // CONNECTÉ
    // ------------------------------------------------------------

    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null) {
      return const AuthScreen();
    }

    // ------------------------------------------------------------
    // VÉRIFICATION AVATAR
    // ------------------------------------------------------------

    final bool hasAvatar =
        await AvatarStorage.hasAvatar(
      userId,
    );

    if (!hasAvatar) {
      return const AvatarChoiceScreen();
    }

    // ------------------------------------------------------------
    // TOUT EST OK
    // ------------------------------------------------------------

    return const HallScreen();
  }

  // ==============================================================
  // TRANSITION VERS L'ÉCRAN SUIVANT
  // ==============================================================

  void _openNextScreen(
    Widget destination,
  ) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration:
            const Duration(
          milliseconds: 450,
        ),

        pageBuilder: (
          context,
          animation,
          secondaryAnimation,
        ) {
          return destination;
        },

        transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
        ) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  // ==============================================================
  // BUILD
  // ==============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),

      body: SafeArea(
        child: Stack(
          children: [
            // =====================================================
            // LÉGER HALO CENTRAL
            // =====================================================

            Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(
                        0xffffc857,
                      ).withValues(
                        alpha: 0.08,
                      ),
                      blurRadius: 90,
                      spreadRadius: 25,
                    ),
                  ],
                ),
              ),
            ),

            // =====================================================
            // LOGO
            // =====================================================

            Center(
              child: FadeTransition(
                opacity:
                    _fadeAnimation,

                child: ScaleTransition(
                  scale:
                      _scaleAnimation,

                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,

                    children: [
                      // =============================================
                      // LOGO PROJECT XP
                      // =============================================

                      Image.asset(
                        'assets/images/logo_project_xp.png',

                        width: 250,

                        fit:
                            BoxFit.contain,

                        errorBuilder: (
                          context,
                          error,
                          stackTrace,
                        ) {
                          // Sécurité si le logo
                          // n'est pas encore au bon emplacement.
                          return const Text(
                            'PROJECT XP',
                            textAlign:
                                TextAlign.center,
                            style:
                                TextStyle(
                              color:
                                  Color(
                                0xffffc857,
                              ),
                              fontSize: 42,
                              fontWeight:
                                  FontWeight.bold,
                              letterSpacing:
                                  4,
                            ),
                          );
                        },
                      ),

                      const SizedBox(
                        height: 22,
                      ),

                      const Text(
                        'TON AVENTURE COMMENCE ICI',

                        textAlign:
                            TextAlign.center,

                        style: TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w600,
                          letterSpacing:
                              2.2,
                        ),
                      ),

                      const SizedBox(
                        height: 32,
                      ),

                      // =============================================
                      // PETIT CHARGEMENT
                      // =============================================

                      const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Color(
                            0xffffc857,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // =====================================================
            // VERSION / SIGNATURE
            // =====================================================

            const Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Text(
                'PROJECT XP',

                textAlign:
                    TextAlign.center,

                style: TextStyle(
                  color:
                      Colors.white24,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w600,
                  letterSpacing:
                      2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}