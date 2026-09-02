import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/avatar_storage.dart';

import 'auth_screen.dart';
import 'avatar/avatar_choice_screen.dart';
import 'hall_screen.dart';

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
  static const Duration _nextScreenFadeDuration =
      Duration(
    milliseconds: 2000,
  );

  late final AnimationController _controller;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  bool _navigationStarted = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 8000,
      ),
    );

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

  Future<void> _startIntro() async {
    final Future<Widget> destinationFuture =
        _getDestination();

    await _controller.forward();

    if (!mounted) {
      return;
    }

    final Widget destination =
        await destinationFuture;

    if (!mounted) {
      return;
    }

    await _openNextScreen(
      destination,
    );
  }

  Future<Widget> _getDestination() async {
    final bool isLoggedIn =
        await AuthService.isLoggedIn();

    if (!isLoggedIn) {
      return const AuthScreen();
    }

    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty) {
      return const AuthScreen();
    }

    final bool hasAvatar =
        await AvatarStorage.hasAvatar(
      userId,
    );

    if (!hasAvatar) {
      return const AvatarChoiceScreen();
    }

    return const HallScreen();
  }

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
