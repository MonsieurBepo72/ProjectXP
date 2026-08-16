import 'package:flutter/material.dart';

class Bjorn extends StatelessWidget {
  final VoidCallback? onTap;

  const Bjorn({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Image.asset(
        'assets/images/bjorn/bjorn_idle.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}