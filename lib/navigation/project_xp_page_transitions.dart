import 'package:flutter/material.dart';

class ProjectXpPageTransitionsBuilder extends PageTransitionsBuilder {
  const ProjectXpPageTransitionsBuilder();

  // Transition générale entre tous les écrans de Project XP.
  //
  // Avant : 15000 ms
  // Maintenant : 650 ms
  //
  // On conserve le fondu noir + apparition progressive de la nouvelle page,
  // mais avec une durée adaptée à une utilisation normale de l'application.
  static const Duration _duration = Duration(
    milliseconds: 1800,
  );

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
        TweenSequence<double>(
      [
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).chain(
            CurveTween(
              curve: Curves.easeIn,
            ),
          ),
          weight: 25,
        ),
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(
            1.0,
          ),
          weight: 75,
        ),
      ],
    ).animate(
      animation,
    );

    final Animation<double> pageOpacity =
        TweenSequence<double>(
      [
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(
            0.0,
          ),
          weight: 55,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).chain(
            CurveTween(
              curve: Curves.easeOut,
            ),
          ),
          weight: 45,
        ),
      ],
    ).animate(
      animation,
    );

    final Animation<double> scaleAnimation =
        Tween<double>(
      begin: 0.985,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: blackOpacity,
          child: const ColoredBox(
            color: Colors.black,
          ),
        ),
        FadeTransition(
          opacity: pageOpacity,
          child: ScaleTransition(
            scale: scaleAnimation,
            child: child,
          ),
        ),
      ],
    );
  }
}