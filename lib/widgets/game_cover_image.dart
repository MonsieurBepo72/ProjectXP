import 'package:flutter/material.dart';

import '../models/game_library_entry.dart';
import '../services/game_cover_repair_service.dart';

/// Affiche la meilleure jaquette connue d'un jeu.
///
/// V1.10.3a : si toutes les vraies covers Steam/catalogue échouent, Project XP
/// lance une recherche IGDB ciblée pour CE jeu uniquement. La nouvelle cover
/// apparaît dès qu'elle est trouvée et reste ensuite enregistrée dans la
/// Bibliothèque Cloud.
class GameCoverImage extends StatefulWidget {
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
  State<GameCoverImage> createState() =>
      _GameCoverImageState();
}

class _GameCoverImageState extends State<GameCoverImage> {
  bool _repairRequested = false;
  String? _repairedUrl;

  @override
  void didUpdateWidget(
    covariant GameCoverImage oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.game.id != widget.game.id) {
      _repairRequested = false;
      _repairedUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> candidates = <String>[
      if ((_repairedUrl?.trim().isNotEmpty ?? false))
        _repairedUrl!.trim(),
      ...widget.game.coverCandidates,
    ]
        .where((url) => !_isLowQualityCover(url))
        .toSet()
        .toList();

    return _candidate(
      candidates,
      0,
    );
  }

  bool _isLowQualityCover(String raw) {
    final String url = raw.toLowerCase();

    return url.contains('/public/images/apps/') ||
        url.contains(
          'steamcommunity/public/images/apps/',
        ) ||
        url.contains('img_icon_url') ||
        url.endsWith('/header.jpg');
  }

  Widget _candidate(
    List<String> candidates,
    int index,
  ) {
    if (index >= candidates.length) {
      _requestRepairOnce();
      return _fallback();
    }

    return Image.network(
      candidates[index],
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
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

  void _requestRepairOnce() {
    if (_repairRequested) {
      return;
    }

    _repairRequested = true;

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        final String? url =
            await GameCoverRepairService.requestRepair(
          widget.game,
        );

        if (!mounted ||
            url == null ||
            url.trim().isEmpty) {
          return;
        }

        setState(() {
          _repairedUrl = url.trim();
        });
      },
    );
  }

  Widget _fallback() {
    final String initial =
        widget.game.title.trim().isEmpty
            ? '?'
            : widget.game.title
                .trim()
                .substring(0, 1)
                .toUpperCase();

    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xff111315),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sports_esports,
            color: Colors.white24,
            size: widget.fallbackIconSize,
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
