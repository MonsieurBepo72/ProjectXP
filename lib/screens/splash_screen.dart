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
  // ===========================================================================
  // DURÉES VISUELLES
  //
  // Ces valeurs reprennent exactement le rythme de l'IntroSplashScreen actuel.
  //
  // Intro actuelle :
  // 100000 ms au total
  //
  // 20 % → apparition
  // 55 % → maintien
  // 25 % → disparition
  //
  // Donc :
  // 20 % de 100000 = 20000 ms
  // ===========================================================================

  static const Duration _splashDuration =
      Duration(
    milliseconds: 4000,
  );

  static const Duration _nextScreenFadeDuration =
      Duration(
    milliseconds: 2000,
  );

  // ===========================================================================
  // ANIMATIONS
  // ===========================================================================

  late final AnimationController _controller;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  bool _navigationStarted = false;

  // ===========================================================================
  // INITIALISATION
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _splashDuration,
    );

    // =========================================================================
    // FONDU
    //
    // EXACTEMENT LE MÊME RYTHME QUE L'INTRO :
    //
    // 20 % :
    // noir → Splash
    //
    // 55 % :
    // Splash complètement visible
    //
    // 25 % :
    // Splash → noir
    // =========================================================================

    _fadeAnimation = TweenSequence<double>(
      [
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).chain(
            CurveTween(
              curve: Curves.easeOut,
            ),
          ),
          weight: 20,
        ),

        TweenSequenceItem<double>(
          tween: ConstantTween<double>(
            1.0,
          ),
          weight: 55,
        ),

        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.0,
            end: 0.0,
          ).chain(
            CurveTween(
              curve: Curves.easeIn,
            ),
          ),
          weight: 25,
        ),
      ],
    ).animate(
      _controller,
    );

    // =========================================================================
    // LÉGER ZOOM
    //
    // Même principe que l'intro :
    //
    // 100 % → 104 %
    //
    // sur toute la durée.
    // =========================================================================

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _startSplash();
  }

  // ===========================================================================
  // DÉMARRAGE DU SPLASH
  // ===========================================================================

  Future<void> _startSplash() async {
    // On commence immédiatement à déterminer
    // où le joueur devra aller.
    //
    // La vérification se fait donc pendant
    // l'animation du Splash.
    final Future<Widget> destinationFuture =
        _getDestination();

    // On lance le cycle visuel complet :
    //
    // noir
    // → Splash
    // → maintien
    // → noir
    await _controller.forward();

    if (!mounted) {
      return;
    }

    // Normalement la destination sera déjà connue
    // depuis longtemps.
    //
    // Mais on attend quand même proprement le résultat
    // au cas où une opération prendrait exceptionnellement
    // plus de temps.
    final Widget destination =
        await destinationFuture;

    if (!mounted) {
      return;
    }

    await _openNextScreen(
      destination,
    );
  }

  // ===========================================================================
  // DÉTERMINER LA DESTINATION
  // ===========================================================================

  Future<Widget> _getDestination() async {
    // -------------------------------------------------------------------------
    // CONNEXION
    // -------------------------------------------------------------------------

    final bool isLoggedIn =
        await AuthService.isLoggedIn();

    if (!isLoggedIn) {
      return const AuthScreen();
    }

    // -------------------------------------------------------------------------
    // UTILISATEUR
    // -------------------------------------------------------------------------

    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty) {
      return const AuthScreen();
    }

    // -------------------------------------------------------------------------
    // AVATAR
    // -------------------------------------------------------------------------

    final bool hasAvatar =
        await AvatarStorage.hasAvatar(
      userId,
    );

    if (!hasAvatar) {
      return const AvatarChoiceScreen();
    }

    // -------------------------------------------------------------------------
    // HALL
    // -------------------------------------------------------------------------

    return const HallScreen();
  }

  // ===========================================================================
  // OUVERTURE DE L'ÉCRAN SUIVANT
  //
  // À ce moment précis :
  //
  // le Splash est déjà devenu complètement noir.
  //
  // L'écran suivant apparaît alors progressivement
  // depuis ce noir avec :
  //
  // durée = 20 % de la durée de l'intro
  //       = 20000 ms
  //
  // courbe = easeOut
  //
  // C'est donc la même sensation que :
  //
  // noir → Intro
  // =========================================================================

  Future<void> _openNextScreen(
    Widget destination,
  ) async {
    if (_navigationStarted) {
      return;
    }

    _navigationStarted = true;

    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration:
            _nextScreenFadeDuration,
        reverseTransitionDuration:
            _nextScreenFadeDuration,

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
          final Animation<double> fadeAnimation =
              CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );

          return FadeTransition(
            opacity: fadeAnimation,
            child: child,
          );
        },
      ),
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
      // Fond noir permanent.
      //
      // Lorsque le contenu du Splash devient transparent,
      // c'est donc naturellement le noir qui apparaît.
      backgroundColor: Colors.black,

      body: FadeTransition(
        opacity: _fadeAnimation,

        child: ScaleTransition(
          scale: _scaleAnimation,

          child: ColoredBox(
            color: const Color(
              0xff160e09,
            ),

            child: SafeArea(
              child: Stack(
                children: [
                  // ===========================================================
                  // HALO CENTRAL
                  // ===========================================================

                  Center(
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
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

                  // ===========================================================
                  // CONTENU PRINCIPAL
                  // ===========================================================

                  Center(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        // =====================================================
                        // LOGO PROJECT XP
                        // =====================================================

                        Image.asset(
                          'assets/icon/app_icon.png',
                          width: 250,
                          fit: BoxFit.contain,
                          filterQuality:
                              FilterQuality.high,

                          errorBuilder: (
                            context,
                            error,
                            stackTrace,
                          ) {
                            return const Text(
                              'PROJECT XP',
                              textAlign:
                                  TextAlign.center,
                              style: TextStyle(
                                color: Color(
                                  0xffffc857,
                                ),
                                fontSize: 42,
                                fontWeight:
                                    FontWeight.bold,
                                letterSpacing: 4,
                              ),
                            );
                          },
                        ),

                        const SizedBox(
                          height: 22,
                        ),

                        // =====================================================
                        // SOUS-TITRE
                        // =====================================================

                        const Text(
                          'TON AVENTURE COMMENCE ICI',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight:
                                FontWeight.w600,
                            letterSpacing: 2.2,
                          ),
                        ),

                        const SizedBox(
                          height: 32,
                        ),

                        // =====================================================
                        // CHARGEMENT
                        // =====================================================

                        const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(
                              0xffffc857,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ===========================================================
                  // SIGNATURE BASSE
                  // ===========================================================

                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Text(
                      'PROJECT XP',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                        fontWeight:
                            FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // NETTOYAGE
  // ===========================================================================

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}