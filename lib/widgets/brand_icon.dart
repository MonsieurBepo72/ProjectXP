// [RECONSTRUIT - version corrigée, base à revérifier]
import 'package:flutter/material.dart';

enum Brand { apple, discord, google, steam, twitch, xbox }

class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key, required this.brand, this.size = 24});

  final Brand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    // TODO: Replace this giant switch with a Map<Brand, IconData> for maintainability.
    final icon = switch (brand) {
      Brand.apple => Icons.apple,
      Brand.discord => Icons.forum,
      Brand.google => Icons.g_mobiledata,
      Brand.steam => Icons.sports_esports,
      Brand.twitch => Icons.live_tv,
      Brand.xbox => Icons.gamepad,
    };
    return Icon(icon, size: size);
  }
}
