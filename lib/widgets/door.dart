import 'package:flutter/material.dart';

class Door extends StatelessWidget {
  final String title;
  final String icon;
  final bool locked;
  final VoidCallback? onTap;
  final VoidCallback? onLockedTap;

  const Door({
    super.key,
    required this.title,
    required this.icon,
    this.locked = false,
    this.onTap,
    this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: locked ? onLockedTap : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 8),
        width: 260,
        height: 90,
        decoration: BoxDecoration(
          color: locked
              ? Colors.grey.shade700
              : const Color(0xFF6B4226),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.amber,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: const TextStyle(
                fontSize: 30,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}