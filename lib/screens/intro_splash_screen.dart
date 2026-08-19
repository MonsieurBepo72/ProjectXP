import 'package:flutter/material.dart';

import 'splash_screen.dart';

class IntroSplashScreen extends StatefulWidget {
  const IntroSplashScreen({
    super.key,
  });

  @override
  State<IntroSplashScreen> createState() =>
      _IntroSplashScreenState();
}

class _IntroSplashScreenState
    extends State<IntroSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // =========================================================================
    // ANIMATION GÉNÉRALE DE L'INTRO
    // =========================================================================

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 8000,
      ),
    );

    // =========================================================================
    // FONDU
    //
    // Invisible
    // → apparition
    // → maintien
    // → disparition vers le noir
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
    // LÉGER ZOOM CINÉMATIQUE
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

    _startIntro();
  }

  // ===========================================================================
  // DÉMARRAGE
  // ===========================================================================

  Future<void> _startIntro() async {
    await _controller.forward();

    if (!mounted) {
      return;
    }

    // L'intro est déjà complètement fondue vers le noir.
    // On ouvre donc le Splash sans animation supplémentaire.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (
          context,
          animation,
          secondaryAnimation,
        ) {
          return const SplashScreen();
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                child: Image.asset(
                  'assets/images/project_xp_intro.png',
                  width: double.infinity,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return const Text(
                      'PROJECT XP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    );
                  },
                ),
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