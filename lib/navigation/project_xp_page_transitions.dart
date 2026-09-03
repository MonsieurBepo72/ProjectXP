import 'package:flutter/material.dart';

class ProjectXpPageTransitionsBuilder extends PageTransitionsBuilder {
  const ProjectXpPageTransitionsBuilder();

  // Le fondu noir reste une signature de Project XP, mais une navigation
  // courante ne doit jamais donner l'impression que l'application charge.
  static const Duration _duration = Duration(milliseconds: 420);

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> blackOpacity =
        TweenSequence<double>(<TweenSequenceItem<double>>[
          TweenSequenceItem<double>(
            tween: Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 28,
          ),
          TweenSequenceItem<double>(
            tween: ConstantTween<double>(1.0),
            weight: 72,
          ),
        ]).animate(animation);

    final Animation<double> pageOpacity =
        TweenSequence<double>(<TweenSequenceItem<double>>[
          TweenSequenceItem<double>(
            tween: ConstantTween<double>(0.0),
            weight: 28,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 72,
          ),
        ]).animate(animation);

    final Animation<double> scaleAnimation = Tween<double>(
      begin: 0.992,
      end: 1.0,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FadeTransition(
          opacity: blackOpacity,
          child: const ColoredBox(color: Colors.black),
        ),
        FadeTransition(
          opacity: pageOpacity,
          child: ScaleTransition(scale: scaleAnimation, child: child),
        ),
      ],
    );
  }
}
