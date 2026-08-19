// [RECONSTRUIT - version corrigée, base à revérifier]
import 'package:flutter/material.dart';

class Door extends StatelessWidget {
  const Door({super.key, required this.isOpen, this.onTap});

  final bool isOpen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // TODO: Verify whether AnimatedContainer is needed. Without an explicit
    // duration there is no animation; consider using a simple Container.
    final IconData doorIcon =
        isOpen ? Icons.door_front_door_outlined : Icons.door_front_door;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration.zero,
        color: isOpen ? Colors.transparent : Colors.brown.shade800,
        child: Icon(
          doorIcon,
          color: Colors.white,
        ),
      ),
    );
  }
}
