import 'package:flutter/material.dart';

class TavernBook extends StatelessWidget {
  final VoidCallback? onTap;

  const TavernBook({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,

      child: Container(
        width: 80,
        height: 55,

        decoration: BoxDecoration(
          color: const Color(0xff5c3317),

          borderRadius: BorderRadius.circular(8),

          border: Border.all(
            color: Colors.amber,
            width: 3,
          ),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),

        child: const Center(
          child: Text(
            "📖",
            style: TextStyle(
              fontSize: 35,
            ),
          ),
        ),
      ),
    );
  }
}