import 'package:flutter/material.dart';

import '../models/game_library_entry.dart';

/// Affiche la meilleure jaquette connue d'un jeu et tente automatiquement
/// plusieurs sources de secours lorsqu'une image distante manque.
///
/// Les mini-icônes de plateforme ne sont volontairement plus utilisées comme
/// jaquette : leur agrandissement donnait un rendu très pixelisé. Quand aucun
/// vrai artwork n'est disponible, Project XP préfère un placeholder propre.
class GameCoverImage extends StatelessWidget {
  final GameLibraryEntry game;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double fallbackIconSize;

  const GameCoverImage({
    super.key,
    required this.game,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallbackIconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> candidates = game.coverCandidates
        .where((url) => !_isLowQualityCover(url))
        .toList();

    return _candidate(
      candidates,
      0,
    );
  }

  bool _isLowQualityCover(String raw) {
    final String url = raw.toLowerCase();
    return url.contains('/public/images/apps/') ||
        url.contains('steamcommunity/public/images/apps/') ||
        url.contains('img_icon_url') ||
        url.endsWith('/header.jpg');
  }

  Widget _candidate(
    List<String> candidates,
    int index,
  ) {
    if (index >= candidates.length) {
      return _fallback();
    }

    return Image.network(
      candidates[index],
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
      errorBuilder: (
        context,
        error,
        stackTrace,
      ) {
        return _candidate(
          candidates,
          index + 1,
        );
      },
    );
  }

  Widget _fallback() {
    final String initial = game.title.trim().isEmpty
        ? '?'
        : game.title.trim().substring(0, 1).toUpperCase();

    return Container(
      width: width,
      height: height,
      color: const Color(0xff111315),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sports_esports,
            color: Colors.white24,
            size: fallbackIconSize,
          ),
          const SizedBox(height: 5),
          Text(
            initial,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
