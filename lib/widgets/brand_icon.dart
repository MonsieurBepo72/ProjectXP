import 'package:flutter/material.dart';

class BrandIcon extends StatelessWidget {
  final String? name;
  final String? brand;
  final double size;

  const BrandIcon({
    super.key,
    this.name,
    this.brand,
    this.size = 24,
  });

  String get _value => (name ?? brand ?? '').trim().toLowerCase();

  IconData? _materialIcon() {
    switch (_value) {
      // =========================
      // PLATEFORMES
      // =========================
      case 'pc':
      case 'windows':
        return Icons.computer;

      case 'playstation':
      case 'ps':
      case 'ps4':
      case 'ps5':
        return Icons.sports_esports;

      case 'xbox':
      case 'xbox one':
      case 'xbox series x/s':
        return Icons.sports_esports;

      case 'nintendo':
      case 'switch':
      case 'nintendo switch':
      case 'nintendo switch 2':
        return Icons.gamepad;

      case 'android':
        return Icons.android;

      case 'apple':
      case 'iphone':
      case 'ipad':
        return Icons.phone_iphone;

      case 'steamdeck':
      case 'steam deck':
        return Icons.sports_esports;

      // =========================
      // RÉSEAUX
      // =========================
      case 'discord':
        return Icons.forum;

      case 'steam':
        return Icons.sports_esports;

      case 'epic games':
      case 'epic':
        return Icons.flash_on;

      // =========================
      // JEUX
      // =========================
      case 'minecraft':
        return Icons.view_in_ar;

      case 'fortnite':
        return Icons.flash_on;

      case 'rocket league':
        return Icons.sports_soccer;

      case 'call of duty':
        return Icons.military_tech;

      case 'gta v':
      case 'gta vi':
        return Icons.directions_car;

      case 'valorant':
        return Icons.adjust;

      case 'league of legends':
        return Icons.auto_awesome;

      case 'overwatch 2':
        return Icons.shield;

      case 'apex legends':
        return Icons.change_history;

      case 'counter-strike 2':
        return Icons.gps_fixed;

      case 'ea sports fc 26':
      case 'fifa':
        return Icons.sports_soccer;

      case 'the sims 4':
        return Icons.people;

      case 'among us':
        return Icons.person;

      case 'roblox':
        return Icons.extension;

      case 'fall guys':
        return Icons.emoji_people;

      case 'terraria':
        return Icons.park;

      case 'palworld':
        return Icons.pets;

      case 'helldivers 2':
        return Icons.rocket_launch;

      default:
        return Icons.sports_esports;
    }
  }

  @override
  Widget build(BuildContext context) {
    final IconData icon = _materialIcon() ?? Icons.sports_esports;

    return Icon(
      icon,
      size: size,
      color: Colors.white,
    );
  }
}