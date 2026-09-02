import 'package:flutter/material.dart';

import '../models/game_library_entry.dart';
import '../services/game_catalog_service.dart';
import '../services/game_library_service.dart';
import '../services/steam_sync_service.dart';

class GameLibraryScreen extends StatefulWidget {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() =>
      _GameLibraryScreenState();
}

class _GameLibraryScreenState extends State<GameLibraryScreen> {
  bool _loading = true;
  bool _steamBusy = false;
  bool _catalogBusy = false;
  List<GameLibraryEntry> _games = <GameLibraryEntry>[];
  GameStatus? _statusFilter;
  bool _favoriteOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<GameLibraryEntry> games =
        await GameLibraryService.loadCurrentLibrary();
    if (!mounted) {
      return;
    }
    setState(() {
      _games = games;
      _loading = false;
    });
  }

  List<GameLibraryEntry> get _visibleGames {
    if (_favoriteOnly) {
      return _games.where((game) => game.favorite).toList();
    }

    final GameStatus? filter = _statusFilter;
    if (filter == null) {
      return _games;
    }
    return _games.where((game) => game.status == filter).toList();
  }

  Future<void> _addGame() async {
    final _NewGameInput? input = await showDialog<_NewGameInput>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _AddGameDialog(),
    );
    if (input == null || !mounted) {
      return;
    }

    final GameCatalogResult? catalog = input.catalog;

    await GameLibraryService.addManualGame(
      title: catalog?.title ?? input.title,
      platform: input.platform,
      status: input.status,
      catalogId: catalog?.id,
      coverUrl: catalog?.coverUrl,
      summary: catalog?.summary,
      releaseYear: catalog?.releaseYear,
      genres: catalog?.genres ?? const <String>[],
      catalogPlatforms:
          catalog?.platforms ?? const <String>[],
    );
    await _load();
  }

  Future<void> _enrichGame(GameLibraryEntry game) async {
    if (_catalogBusy) {
      return;
    }

    final GameCatalogResult? result =
        await showDialog<GameCatalogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CatalogPickerDialog(
        initialQuery: game.title,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _catalogBusy = true;
    });

    try {
      await GameLibraryService.enrichFromCatalog(
        entry: game,
        catalogId: result.id,
        title: result.title,
        coverUrl: result.coverUrl,
        summary: result.summary,
        releaseYear: result.releaseYear,
        genres: result.genres,
        catalogPlatforms: result.platforms,
      );
      await _load();
      if (mounted) {
        _message(
          'Jaquette et informations mises à jour pour ${result.title}.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _catalogBusy = false;
        });
      }
    }
  }

  Future<void> _connectSteam() async {
    if (_steamBusy) {
      return;
    }

    final String saved =
        await SteamSyncService.getSavedReference() ?? '';
    if (!mounted) {
      return;
    }

    final String? reference =
        await _askSteamReference(saved);
    if (reference == null || !mounted) {
      return;
    }

    setState(() {
      _steamBusy = true;
    });

    try {
      final SteamLibrarySyncResult result =
          await SteamSyncService.syncLibrary(reference);
      await _load();
      if (!mounted) {
        return;
      }
      final String baseMessage =
          'Steam synchronisé : ${result.detected} jeux détectés, '
          '${result.added} ajoutés, ${result.updated} mis à jour.';
      _message(
        result.warning == null || result.warning!.isEmpty
            ? baseMessage
            : '$baseMessage ${result.warning}',
      );
    } on SteamSyncException catch (error) {
      if (mounted) {
        _message(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _steamBusy = false;
        });
      }
    }
  }

  Future<String?> _askSteamReference(String initial) {
    final TextEditingController controller =
        TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff17191c),
          title: const Text(
            'CONNECTER STEAM',
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Entre ton SteamID64, ton URL de profil Steam '
                'ou ton identifiant personnalisé.',
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Profil Steam',
                  hintText: 'steamcommunity.com/id/...',
                  labelStyle: TextStyle(color: Colors.white60),
                  hintStyle: TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Color(0xffffc857)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'La bibliothèque Steam doit être visible '
                'publiquement pour que Steam la renvoie.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ANNULER'),
            ),
            TextButton(
              onPressed: () {
                final String value = controller.text.trim();
                if (value.isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text(
                'SYNCHRONISER',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _editGame(GameLibraryEntry game) async {
    final _GameEditResult? result =
        await showModalBottomSheet<_GameEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff17191c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) => _GameEditSheet(game: game),
    );

    if (result == null || !mounted) {
      return;
    }

    if (result.delete) {
      final bool confirmed = await _confirmDelete(game);
      if (!confirmed) {
        return;
      }
      await GameLibraryService.removeGame(game.id);
      await _load();
      return;
    }

    if (result.game != null) {
      await GameLibraryService.updateGame(result.game!);
      await _load();
    }
  }

  Future<bool> _confirmDelete(GameLibraryEntry game) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xff17191c),
        title: const Text(
          'RETIRER LE JEU',
          style: TextStyle(color: Color(0xffffc857)),
        ),
        content: Text(
          'Retirer ${game.title} de ta Bibliothèque ?\n\n'
          'Cela retire seulement sa fiche locale. '
          'Ton historique d’accomplissements reste conservé.',
          style: const TextStyle(
            color: Colors.white70,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('ANNULER'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text(
              'RETIRER',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _syncGameAchievements(
    GameLibraryEntry game,
  ) async {
    setState(() {
      _steamBusy = true;
    });
    try {
      final GameAchievementSummary summary =
          await SteamSyncService.syncAchievements(game);
      await _load();
      if (!mounted) {
        return;
      }
      _message(
        'Succès Steam synchronisés : '
        '${summary.unlocked} / ${summary.total}.',
      );
    } on SteamSyncException catch (error) {
      if (mounted) {
        _message(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _steamBusy = false;
        });
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<GameLibraryEntry> games = _visibleGames;
    final int inProgress = _games
        .where((game) => game.status == GameStatus.inProgress)
        .length;
    final int completed = _games
        .where((game) => game.status == GameStatus.completed)
        .length;
    final int backlog = _games
        .where((game) => game.status == GameStatus.backlog)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xff0e1012),
      appBar: AppBar(
        backgroundColor: const Color(0xff202326),
        foregroundColor: const Color(0xffffc857),
        title: const Text(
          'MA BIBLIOTHÈQUE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGame,
        backgroundColor: const Color(0xffffc857),
        foregroundColor: const Color(0xff1c140b),
        icon: const Icon(Icons.add),
        label: const Text(
          'AJOUTER',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xffffc857),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  14,
                  14,
                  14,
                  100,
                ),
                children: [
                  _LibraryHeader(
                    total: _games.length,
                    inProgress: inProgress,
                    backlog: backlog,
                    completed: completed,
                    steamBusy: _steamBusy,
                    onSteam: _connectSteam,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterChip(
                          label: 'TOUS',
                          selected: _statusFilter == null &&
                              !_favoriteOnly,
                          onTap: () {
                            setState(() {
                              _statusFilter = null;
                              _favoriteOnly = false;
                            });
                          },
                        ),
                        ...GameStatus.values.map(
                          (status) => _FilterChip(
                            label: status.label.toUpperCase(),
                            selected: _statusFilter == status &&
                                !_favoriteOnly,
                            onTap: () {
                              setState(() {
                                _statusFilter = status;
                                _favoriteOnly = false;
                              });
                            },
                          ),
                        ),
                        _FilterChip(
                          label: 'FAVORIS',
                          selected: _favoriteOnly,
                          onTap: () {
                            setState(() {
                              _favoriteOnly = true;
                              _statusFilter = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (games.isEmpty)
                    _EmptyLibrary(
                      filtered: _statusFilter != null ||
                          _favoriteOnly,
                    )
                  else
                    ...games.map(
                      (game) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GameCard(
                          game: game,
                          busy: _steamBusy || _catalogBusy,
                          onTap: () => _editGame(game),
                          onEnrich: game.source == GameSource.manual
                              ? () => _enrichGame(game)
                              : null,
                          onSyncAchievements:
                              game.source == GameSource.steam
                                  ? () =>
                                      _syncGameAchievements(game)
                                  : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  final int total;
  final int inProgress;
  final int backlog;
  final int completed;
  final bool steamBusy;
  final VoidCallback onSteam;

  const _LibraryHeader({
    required this.total,
    required this.inProgress,
    required this.backlog,
    required this.completed,
    required this.steamBusy,
    required this.onSteam,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xff1a1d20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                color: Color(0xffffc857),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total jeux',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$inProgress en cours • $backlog à jouer • '
                      '$completed terminés',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: steamBusy ? null : onSteam,
              icon: steamBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                steamBusy
                    ? 'SYNCHRONISATION...'
                    : 'CONNECTER / SYNCHRONISER STEAM',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffb7d8ff),
                side: const BorderSide(
                  color: Color(0xff315c83),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xffffc857),
        backgroundColor: const Color(0xff1a1d20),
        labelStyle: TextStyle(
          color: selected
              ? const Color(0xff21150e)
              : Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
        side: BorderSide(
          color: selected
              ? const Color(0xffffc857)
              : Colors.white10,
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final bool filtered;

  const _EmptyLibrary({required this.filtered});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xff17191c),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.sports_esports_outlined,
            color: Colors.white30,
            size: 50,
          ),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'Aucun jeu dans cette catégorie.'
                : 'Ta Bibliothèque est vide.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!filtered) ...[
            const SizedBox(height: 8),
            const Text(
              'Recherche un jeu pour récupérer sa jaquette '
              'ou connecte Steam pour importer ta collection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameLibraryEntry game;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onEnrich;
  final VoidCallback? onSyncAchievements;

  const _GameCard({
    required this.game,
    required this.busy,
    required this.onTap,
    required this.onEnrich,
    required this.onSyncAchievements,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff1a1d20),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GameCover(
                game: game,
                width: 70,
                height: 96,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            game.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (game.favorite)
                          const Icon(
                            Icons.star,
                            color: Color(0xffffc857),
                            size: 18,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${game.platform.label} • '
                      '${game.status.label}',
                      style: const TextStyle(
                        color: Color(0xffb69bdc),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (game.releaseYear != null ||
                        game.genres.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (game.releaseYear != null)
                            '${game.releaseYear}',
                          if (game.genres.isNotEmpty)
                            game.genres.take(2).join(' • '),
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    if (game.progressPercent > 0) ...[
                      LinearProgressIndicator(
                        value: game.progressPercent / 100,
                        minHeight: 4,
                        backgroundColor: Colors.white10,
                        color: const Color(0xffffc857),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(
                      game.achievementProgressText,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10.5,
                      ),
                    ),
                    if (game.playtimeMinutes > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${(game.playtimeMinutes / 60).toStringAsFixed(1)} h jouées',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEnrich != null)
                    IconButton(
                      tooltip: game.hasCatalogMetadata
                          ? 'Corriger la jaquette / les infos'
                          : 'Ajouter jaquette & infos',
                      onPressed: busy ? null : onEnrich,
                      icon: Icon(
                        game.hasCatalogMetadata
                            ? Icons.image_search_outlined
                            : Icons.auto_awesome_outlined,
                        color: const Color(0xffcbb3e8),
                        size: 20,
                      ),
                    ),
                  if (onSyncAchievements != null)
                    IconButton(
                      tooltip: 'Synchroniser les succès Steam',
                      onPressed:
                          busy ? null : onSyncAchievements,
                      icon: const Icon(
                        Icons.cloud_sync_outlined,
                        color: Color(0xff8ebce9),
                        size: 20,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCover extends StatelessWidget {
  final GameLibraryEntry game;
  final double width;
  final double height;

  const _GameCover({
    required this.game,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final String? url = game.coverUrl;
    final Widget fallback = Container(
      width: width,
      height: height,
      color: const Color(0xff111315),
      alignment: Alignment.center,
      child: const Icon(
        Icons.sports_esports,
        color: Colors.white30,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null || url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (
                context,
                error,
                stackTrace,
              ) =>
                  fallback,
            ),
    );
  }
}

class _NewGameInput {
  final String title;
  final GamePlatform platform;
  final GameStatus status;
  final GameCatalogResult? catalog;

  const _NewGameInput({
    required this.title,
    required this.platform,
    required this.status,
    required this.catalog,
  });
}

class _AddGameDialog extends StatefulWidget {
  const _AddGameDialog();

  @override
  State<_AddGameDialog> createState() =>
      _AddGameDialogState();
}

class _AddGameDialogState extends State<_AddGameDialog> {
  final TextEditingController _query = TextEditingController();
  GamePlatform _platform = GamePlatform.playstation;
  GameStatus _status = GameStatus.backlog;
  bool _searching = false;
  String? _error;
  List<GameCatalogResult> _results = <GameCatalogResult>[];
  GameCatalogResult? _selected;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String query = _query.text.trim();
    if (query.length < 2 || _searching) {
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _results = <GameCatalogResult>[];
      _selected = null;
    });

    try {
      final List<GameCatalogResult> results =
          await GameCatalogService.searchGames(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _error =
              'Aucun résultat. Tu peux quand même ajouter le jeu manuellement.';
        }
      });
    } on GameCatalogException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  void _finish({required bool manual}) {
    final String typed = _query.text.trim();
    final GameCatalogResult? selected =
        manual ? null : _selected;
    final String title = selected?.title ?? typed;

    if (title.isEmpty) {
      return;
    }

    Navigator.pop(
      context,
      _NewGameInput(
        title: title,
        platform: _platform,
        status: _status,
        catalog: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double height =
        MediaQuery.sizeOf(context).height * 0.86;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 18,
      ),
      backgroundColor: const Color(0xff17191c),
      child: SizedBox(
        width: double.maxFinite,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'AJOUTER UN JEU',
                      style: TextStyle(
                        color: Color(0xffffc857),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Rechercher un jeu',
                  hintText: 'Rocket League, Elden Ring...',
                  labelStyle:
                      const TextStyle(color: Colors.white60),
                  hintStyle:
                      const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white54,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Rechercher',
                    onPressed: _searching ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.arrow_forward),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xffffb4a9),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? _CatalogSearchHint(searching: _searching)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final GameCatalogResult result =
                            _results[index];
                        final bool selected =
                            _selected?.id == result.id;
                        return _CatalogResultTile(
                          result: result,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              _selected = result;
                            });
                          },
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: const BoxDecoration(
                color: Color(0xff111315),
                border: Border(
                  top: BorderSide(color: Colors.white10),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<GamePlatform>(
                          initialValue: _platform,
                          isExpanded: true,
                          dropdownColor: const Color(0xff23262a),
                          decoration: const InputDecoration(
                            labelText: 'Ta plateforme',
                            isDense: true,
                          ),
                          items: GamePlatform.values
                              .map(
                                (platform) =>
                                    DropdownMenuItem<GamePlatform>(
                                  value: platform,
                                  child: Text(platform.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _platform = value;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<GameStatus>(
                          initialValue: _status,
                          isExpanded: true,
                          dropdownColor: const Color(0xff23262a),
                          decoration: const InputDecoration(
                            labelText: 'État',
                            isDense: true,
                          ),
                          items: GameStatus.values
                              .where(
                                (status) =>
                                    status !=
                                    GameStatus.unclassified,
                              )
                              .map(
                                (status) =>
                                    DropdownMenuItem<GameStatus>(
                                  value: status,
                                  child: Text(status.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _status = value;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _finish(manual: true),
                          child: const Text('AJOUT MANUEL'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _selected == null
                              ? null
                              : () => _finish(manual: false),
                          icon: const Icon(Icons.add),
                          label: const Text('AJOUTER'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                const Color(0xffffc857),
                            foregroundColor:
                                const Color(0xff21150e),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogPickerDialog extends StatefulWidget {
  final String initialQuery;

  const _CatalogPickerDialog({
    required this.initialQuery,
  });

  @override
  State<_CatalogPickerDialog> createState() =>
      _CatalogPickerDialogState();
}

class _CatalogPickerDialogState extends State<_CatalogPickerDialog> {
  late final TextEditingController _query;
  bool _searching = false;
  String? _error;
  List<GameCatalogResult> _results = <GameCatalogResult>[];

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _search();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String query = _query.text.trim();
    if (query.length < 2 || _searching) {
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _results = <GameCatalogResult>[];
    });

    try {
      final List<GameCatalogResult> results =
          await GameCatalogService.searchGames(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _error = 'Aucun résultat trouvé.';
        }
      });
    } on GameCatalogException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 18,
      ),
      backgroundColor: const Color(0xff17191c),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'JAQUETTE & INFORMATIONS',
                      style: TextStyle(
                        color: Color(0xffffc857),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Rechercher',
                  suffixIcon: IconButton(
                    onPressed: _searching ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.search),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xffffb4a9),
                  ),
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _results.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final GameCatalogResult result =
                      _results[index];
                  return _CatalogResultTile(
                    result: result,
                    selected: false,
                    onTap: () => Navigator.pop(context, result),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSearchHint extends StatelessWidget {
  final bool searching;

  const _CatalogSearchHint({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.travel_explore
                  : Icons.image_search_outlined,
              color: Colors.white24,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              searching
                  ? 'Recherche dans le catalogue...'
                  : 'Recherche ton jeu pour récupérer '
                      'automatiquement sa jaquette et ses infos.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogResultTile extends StatelessWidget {
  final GameCatalogResult result;
  final bool selected;
  final VoidCallback onTap;

  const _CatalogResultTile({
    required this.result,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String? cover = result.coverUrl;

    return Material(
      color: selected
          ? const Color(0xff302716)
          : const Color(0xff202326),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? const Color(0xffffc857)
                  : Colors.white10,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: cover == null || cover.isEmpty
                    ? Container(
                        width: 58,
                        height: 82,
                        color: const Color(0xff111315),
                        child: const Icon(
                          Icons.sports_esports,
                          color: Colors.white24,
                        ),
                      )
                    : Image.network(
                        cover,
                        width: 58,
                        height: 82,
                        fit: BoxFit.cover,
                        errorBuilder: (
                          context,
                          error,
                          stackTrace,
                        ) =>
                            Container(
                          width: 58,
                          height: 82,
                          color: const Color(0xff111315),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white24,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (result.releaseYear != null)
                          '${result.releaseYear}',
                        if (result.genres.isNotEmpty)
                          result.genres.take(2).join(' • '),
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffcbb3e8),
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.platforms.isEmpty
                          ? 'Plateformes non renseignées'
                          : result.platforms.take(4).join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.check_circle,
                    color: Color(0xffffc857),
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameEditResult {
  final GameLibraryEntry? game;
  final bool delete;

  const _GameEditResult.save(this.game) : delete = false;
  const _GameEditResult.delete()
      : game = null,
        delete = true;
}

class _GameEditSheet extends StatefulWidget {
  final GameLibraryEntry game;

  const _GameEditSheet({required this.game});

  @override
  State<_GameEditSheet> createState() =>
      _GameEditSheetState();
}

class _GameEditSheetState extends State<_GameEditSheet> {
  late final TextEditingController _title;
  late GamePlatform _platform;
  late GameStatus _status;
  late bool _favorite;
  late double _progress;

  late final TextEditingController _unlocked;
  late final TextEditingController _total;
  late final TextEditingController _bronzeUnlocked;
  late final TextEditingController _bronzeTotal;
  late final TextEditingController _silverUnlocked;
  late final TextEditingController _silverTotal;
  late final TextEditingController _goldUnlocked;
  late final TextEditingController _goldTotal;
  late final TextEditingController _platinumUnlocked;
  late final TextEditingController _platinumTotal;
  late final TextEditingController _scoreEarned;
  late final TextEditingController _scoreTotal;

  @override
  void initState() {
    super.initState();
    final GameLibraryEntry game = widget.game;
    final GameAchievementSummary a = game.achievements;
    _title = TextEditingController(text: game.title);
    _platform = game.platform;
    _status = game.status;
    _favorite = game.favorite;
    _progress = game.progressPercent.toDouble();
    _unlocked = TextEditingController(text: '${a.unlocked}');
    _total = TextEditingController(text: '${a.total}');
    _bronzeUnlocked =
        TextEditingController(text: '${a.bronzeUnlocked}');
    _bronzeTotal =
        TextEditingController(text: '${a.bronzeTotal}');
    _silverUnlocked =
        TextEditingController(text: '${a.silverUnlocked}');
    _silverTotal =
        TextEditingController(text: '${a.silverTotal}');
    _goldUnlocked =
        TextEditingController(text: '${a.goldUnlocked}');
    _goldTotal =
        TextEditingController(text: '${a.goldTotal}');
    _platinumUnlocked =
        TextEditingController(text: '${a.platinumUnlocked}');
    _platinumTotal =
        TextEditingController(text: '${a.platinumTotal}');
    _scoreEarned =
        TextEditingController(text: '${a.scoreEarned}');
    _scoreTotal =
        TextEditingController(text: '${a.scoreTotal}');
  }

  @override
  void dispose() {
    for (final TextEditingController controller in [
      _title,
      _unlocked,
      _total,
      _bronzeUnlocked,
      _bronzeTotal,
      _silverUnlocked,
      _silverTotal,
      _goldUnlocked,
      _goldTotal,
      _platinumUnlocked,
      _platinumTotal,
      _scoreEarned,
      _scoreTotal,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _read(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
  }

  GameAchievementSummary _summary() {
    return GameAchievementSummary(
      unlocked: _read(_unlocked),
      total: _read(_total),
      bronzeUnlocked: _read(_bronzeUnlocked),
      bronzeTotal: _read(_bronzeTotal),
      silverUnlocked: _read(_silverUnlocked),
      silverTotal: _read(_silverTotal),
      goldUnlocked: _read(_goldUnlocked),
      goldTotal: _read(_goldTotal),
      platinumUnlocked: _read(_platinumUnlocked),
      platinumTotal: _read(_platinumTotal),
      scoreEarned: _read(_scoreEarned),
      scoreTotal: _read(_scoreTotal),
    );
  }

  void _save() {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    final GameLibraryEntry updated = widget.game.copyWith(
      title: title,
      platform: _platform,
      status: _status,
      favorite: _favorite,
      progressPercent: _progress.round(),
      achievements: _summary(),
    );
    Navigator.pop(
      context,
      _GameEditResult.save(updated),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets =
        MediaQuery.viewInsetsOf(context);
    final GameLibraryEntry game = widget.game;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GameCover(
                    game: game,
                    width: 72,
                    height: 102,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FICHE DU JEU',
                          style: TextStyle(
                            color: Color(0xffffc857),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (game.releaseYear != null)
                          Text(
                            'Sortie : ${game.releaseYear}',
                            style: const TextStyle(
                              color: Colors.white54,
                            ),
                          ),
                        if (game.genres.isNotEmpty)
                          Text(
                            game.genres.join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xffcbb3e8),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (game.summary != null &&
                  game.summary!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  game.summary!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                style: const TextStyle(color: Colors.white),
                decoration:
                    const InputDecoration(labelText: 'Nom du jeu'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GamePlatform>(
                initialValue: _platform,
                dropdownColor: const Color(0xff23262a),
                decoration:
                    const InputDecoration(labelText: 'Plateforme'),
                items: GamePlatform.values
                    .map(
                      (platform) =>
                          DropdownMenuItem<GamePlatform>(
                        value: platform,
                        child: Text(platform.label),
                      ),
                    )
                    .toList(),
                onChanged: widget.game.source == GameSource.steam
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _platform = value;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GameStatus>(
                initialValue: _status,
                dropdownColor: const Color(0xff23262a),
                decoration:
                    const InputDecoration(labelText: 'État'),
                items: GameStatus.values
                    .map(
                      (status) => DropdownMenuItem<GameStatus>(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _status = value;
                      if (value == GameStatus.completed) {
                        _progress = 100;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Favori',
                  style: TextStyle(color: Colors.white),
                ),
                value: _favorite,
                activeThumbColor: const Color(0xffffc857),
                onChanged: (value) {
                  setState(() {
                    _favorite = value;
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Progression personnelle : '
                '${_progress.round()} %',
                style: const TextStyle(color: Colors.white70),
              ),
              Slider(
                value: _progress,
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: const Color(0xffffc857),
                onChanged: _status == GameStatus.completed
                    ? null
                    : (value) {
                        setState(() {
                          _progress = value;
                        });
                      },
              ),
              const Divider(color: Colors.white12, height: 28),
              Text(
                _platform == GamePlatform.playstation
                    ? 'TROPHÉES PLAYSTATION'
                    : _platform == GamePlatform.xbox
                        ? 'SUCCÈS XBOX'
                        : 'SUCCÈS '
                            '${_platform.label.toUpperCase()}',
                style: const TextStyle(
                  color: Color(0xffb69bdc),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              if (_platform == GamePlatform.playstation) ...[
                _CountPair(
                  label: 'Bronze',
                  unlocked: _bronzeUnlocked,
                  total: _bronzeTotal,
                ),
                _CountPair(
                  label: 'Argent',
                  unlocked: _silverUnlocked,
                  total: _silverTotal,
                ),
                _CountPair(
                  label: 'Or',
                  unlocked: _goldUnlocked,
                  total: _goldTotal,
                ),
                _CountPair(
                  label: 'Platine',
                  unlocked: _platinumUnlocked,
                  total: _platinumTotal,
                ),
              ] else ...[
                _CountPair(
                  label: 'Succès',
                  unlocked: _unlocked,
                  total: _total,
                ),
                if (_platform == GamePlatform.xbox)
                  _CountPair(
                    label: 'Gamerscore',
                    unlocked: _scoreEarned,
                    total: _scoreTotal,
                    unlockedHint: 'G obtenus',
                    totalHint: 'G total',
                  ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          const _GameEditResult.delete(),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('RETIRER'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('ENREGISTRER'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            const Color(0xffffc857),
                        foregroundColor:
                            const Color(0xff21150e),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPair extends StatelessWidget {
  final String label;
  final TextEditingController unlocked;
  final TextEditingController total;
  final String unlockedHint;
  final String totalHint;

  const _CountPair({
    required this.label,
    required this.unlocked,
    required this.total,
    this.unlockedHint = 'Obtenus',
    this.totalHint = 'Total',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: unlocked,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: unlockedHint,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: total,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: totalHint,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
