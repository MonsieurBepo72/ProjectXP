// [RECONSTRUIT - version corrigée, base à revérifier]
import 'package:flutter/material.dart';

class TavernBook extends StatelessWidget {
  const TavernBook({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Open tavern book',
      icon: const Icon(Icons.menu_book),
    );
  }
}
