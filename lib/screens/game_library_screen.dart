import 'package:flutter/material.dart';

import '../models/game_library_entry.dart';
import '../services/game_catalog_service.dart';
import '../services/game_library_service.dart';
import '../services/steam_sync_service.dart';
import '../widgets/game_cover_image.dart';
import 'gaming_accounts_screen.dart';

enum _LibrarySort {
  recent,
  titleAZ,
  titleZA,
  progressHigh,
  progressLow,
  playtimeHigh,
  playtimeLow,
}

extension _LibrarySortX on _LibrarySort {
  String get label {
    switch (this) {
      case _LibrarySort.recent:
        return 'Activité récente';
      case _LibrarySort.titleAZ:
        return 'Nom A → Z';
      case _LibrarySort.titleZA:
        return 'Nom Z → A';
      case _LibrarySort.progressHigh:
        return 'Progression ↓';
      case _LibrarySort.progressLow:
        return 'Progression ↑';
      case _LibrarySort.playtimeHigh:
        return 'Temps de jeu ↓';
      case _LibrarySort.playtimeLow:
        return 'Temps de jeu ↑';
    }
  }
}

enum _AchievementFilter {
  all,
  unlocked,
  locked,
}

extension _AchievementFilterX on _AchievementFilter {
  String get label {
    switch (this) {
      case _AchievementFilter.all:
        return 'TOUS';
      case _AchievementFilter.unlocked:
        return 'OBTENUS';
      case _AchievementFilter.locked:
        return 'À OBTENIR';
    }
  }
}

class GameLibraryScreen extends StatefulWidget {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() =>
      _GameLibraryScreenState();
}

class _GameLibraryScreenState extends State<GameLibraryScreen> {
  bool _loading = true;
  bool _steamBusy = false;
  String? _steamProgressLabel;
  SteamSyncPhase? _lastSteamSyncPhase;
  bool _catalogBusy = false;
  List<GameLibraryEntry> _games = <GameLibraryEntry>[];
  GameStatus? _statusFilter;
  bool _favoriteOnly = false;
  _LibrarySort _sort = _LibrarySort.recent;
  final TextEditingController _searchController =
      TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    SteamSyncService.syncState.addListener(
      _handleSteamSyncState,
    );

    _handleSteamSyncState();
    _load();
  }

  @override
  void dispose() {
    SteamSyncService.syncState.removeListener(
      _handleSteamSyncState,
    );

    _searchController.dispose();
    super.dispose();
  }

  void _handleSteamSyncState() {
    if (!mounted) {
      return;
    }

    final SteamSyncUiState state =
        SteamSyncService.syncState.value;

    final SteamSyncPhase? previous =
        _lastSteamSyncPhase;

    _lastSteamSyncPhase = state.phase;

    setState(() {
      _steamBusy = state.running;
      _steamProgressLabel =
          state.running ? state.label : null;
    });

    final bool justFinished =
        (state.phase == SteamSyncPhase.completed ||
            state.phase == SteamSyncPhase.failed) &&
        previous != state.phase;

    if (justFinished) {
      _load();
    }
  }

  Future<void> _load() async {
    final List<GameLibraryEntry> games =
        await GameLibraryService.loadCurrentLibraryConsolidated();
    if (!mounted) {
      return;
    }
    setState(() {
      _games = games;
      _loading = false;
    });
  }

  List<GameLibraryEntry> get _visibleGames {
    Iterable<GameLibraryEntry> filtered = _games;

    if (_favoriteOnly) {
      filtered = filtered.where((game) => game.favorite);
    } else if (_statusFilter != null) {
      filtered = filtered.where(
        (game) => game.status == _statusFilter,
      );
    }

    final String query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where(
        (game) =>
            game.title.toLowerCase().contains(query) ||
            game.platformSummaryText.toLowerCase().contains(query),
      );
    }

    final List<GameLibraryEntry> result =
        filtered.toList();

    switch (_sort) {
      case _LibrarySort.recent:
        result.sort(
          (a, b) => b.updatedAt.compareTo(a.updatedAt),
        );
        break;
      case _LibrarySort.titleAZ:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(
                b.title.toLowerCase(),
              ),
        );
        break;
      case _LibrarySort.titleZA:
        result.sort(
          (a, b) => b.title.toLowerCase().compareTo(
                a.title.toLowerCase(),
              ),
        );
        break;
      case _LibrarySort.progressHigh:
        result.sort(
          (a, b) => (b.bestCompletionPercent ?? -1)
              .compareTo(a.bestCompletionPercent ?? -1),
        );
        break;
      case _LibrarySort.progressLow:
        result.sort(
          (a, b) => (a.bestCompletionPercent ?? 101)
              .compareTo(b.bestCompletionPercent ?? 101),
        );
        break;
      case _LibrarySort.playtimeHigh:
        result.sort(
          (a, b) =>
              b.totalPlaytimeMinutes.compareTo(a.totalPlaytimeMinutes),
        );
        break;
      case _LibrarySort.playtimeLow:
        result.sort(
          (a, b) =>
              a.totalPlaytimeMinutes.compareTo(b.totalPlaytimeMinutes),
        );
        break;
    }

    return result;
  }

  Future<void> _toggleFavorite(
    GameLibraryEntry game,
  ) async {
    await GameLibraryService.toggleFavorite(game);
    await _load();
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

  Future<void> _syncAllSteam() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final bool hasIdentity =
        await SteamSyncService.hasSyncIdentity();

    if (!mounted) {
      return;
    }

    if (!hasIdentity) {
      _message(
        'Lie d’abord une plateforme depuis COMPTES.',
      );
      await _openAccounts();
      return;
    }

    try {
      // Le Future appartient désormais au service global :
      // quitter cet écran n'interrompt jamais la synchronisation.
      await SteamSyncService.syncEverything(
        force: true,
      );

      if (mounted) {
        await _load();
      }
    } on SteamSyncException catch (error) {
      if (mounted) {
        _message(error.message);
      }
    }
  }

  Future<void> _openAccounts() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const GamingAccountsScreen(),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _editGame(GameLibraryEntry game) async {
    final GameLibraryEntry currentGame = game;

    if (!mounted) {
      return;
    }

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
      builder: (sheetContext) =>
          _GameEditSheet(game: currentGame),
    );

    if (result == null || !mounted) {
      return;
    }

    if (result.delete) {
      final bool confirmed =
          await _confirmDelete(currentGame);
      if (!confirmed) {
        return;
      }
      await GameLibraryService.removeGame(currentGame.id);
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
                    steamProgressLabel: _steamProgressLabel,
                    onAccounts: _openAccounts,
                    onSteam: _syncAllSteam,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    autofocus: false,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Rechercher dans mes ${_games.length} jeux...',
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xffffc857),
                      ),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white38,
                              ),
                            ),
                      filled: true,
                      fillColor: const Color(0xff1a1d20),
                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(13),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(13),
                        borderSide: const BorderSide(
                          color: Colors.white10,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(13),
                        borderSide: const BorderSide(
                          color: Color(0xffffc857),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        ...GameStatus.values
                            .where(
                              (status) =>
                                  status != GameStatus.unclassified,
                            )
                            .map(
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.sort_rounded,
                        color: Colors.white38,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'TRI',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<_LibrarySort>(
                        initialValue: _sort,
                        tooltip: 'Trier la Bibliothèque',
                        color: const Color(0xff23262a),
                        onSelected: (value) {
                          setState(() {
                            _sort = value;
                          });
                        },
                        itemBuilder: (context) =>
                            _LibrarySort.values
                                .map(
                                  (value) =>
                                      PopupMenuItem<_LibrarySort>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        if (value == _sort)
                                          const Icon(
                                            Icons.check,
                                            color:
                                                Color(0xffffc857),
                                            size: 17,
                                          )
                                        else
                                          const SizedBox(width: 17),
                                        const SizedBox(width: 8),
                                        Text(value.label),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xff1a1d20),
                            borderRadius:
                                BorderRadius.circular(10),
                            border:
                                Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _sort.label,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.expand_more,
                                color: Colors.white38,
                                size: 17,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (games.isEmpty)
                    _EmptyLibrary(
                      filtered: _statusFilter != null ||
                          _favoriteOnly ||
                          _searchQuery.isNotEmpty,
                    )
                  else
                    ...games.map(
                      (game) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GameCard(
                          game: game,
                          busy: _steamBusy || _catalogBusy,
                          onTap: () => _editGame(game),
                          onFavorite: () =>
                              _toggleFavorite(game),
                          onEnrich:
                              !game.hasOfficialPlatformConnection &&
                                      (game.source == GameSource.manual ||
                                          !game.hasCatalogMetadata)
                                  ? () => _enrichGame(game)
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
  final String? steamProgressLabel;
  final VoidCallback onAccounts;
  final VoidCallback onSteam;

  const _LibraryHeader({
    required this.total,
    required this.inProgress,
    required this.backlog,
    required this.completed,
    required this.steamBusy,
    required this.steamProgressLabel,
    required this.onAccounts,
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
            child: FilledButton.icon(
              onPressed: steamBusy ? null : onAccounts,
              icon: const Icon(Icons.manage_accounts_rounded),
              label: const Text('COMPTES'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff2a3138),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
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
                    : 'SYNCHRONISER TOUT',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffb7d8ff),
                side: const BorderSide(
                  color: Color(0xff315c83),
                ),
              ),
            ),
          ),
          if (steamBusy &&
              steamProgressLabel != null &&
              steamProgressLabel!.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              steamProgressLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10.5,
              ),
            ),
          ],
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
  final VoidCallback onFavorite;
  final VoidCallback? onEnrich;

  const _GameCard({
    required this.game,
    required this.busy,
    required this.onTap,
    required this.onFavorite,
    required this.onEnrich,
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
                        IconButton(
                          tooltip: game.favorite
                              ? 'Retirer des favoris'
                              : 'Ajouter aux favoris',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                          onPressed: busy ? null : onFavorite,
                          icon: Icon(
                            game.favorite
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: game.favorite
                                ? const Color(0xffffc857)
                                : Colors.white30,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      crossAxisAlignment:
                          WrapCrossAlignment.center,
                      children: [
                        for (final GamePlatform platform
                            in game.connectedPlatforms)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff24202d),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(
                                  0xffb69bdc,
                                ).withValues(alpha: 0.28),
                              ),
                            ),
                            child: Text(
                              platform.label,
                              style: const TextStyle(
                                color: Color(0xffcbb3e8),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (game.status !=
                            GameStatus.unclassified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff18231c),
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: Text(
                              game.status.label,
                              style: const TextStyle(
                                color: Color(0xff8fd5a6),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (game.releaseYear != null ||
                        game.genres.isNotEmpty) ...[
                      const SizedBox(height: 4),
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
                    if (game.bestCompletionPercent != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value:
                                  game.bestCompletionPercent! /
                                      100,
                              minHeight: 4,
                              backgroundColor:
                                  Colors.white10,
                              color:
                                  const Color(0xffffc857),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '${game.bestCompletionPercent} %',
                            style: const TextStyle(
                              color: Color(0xffffc857),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        game.bestCompletionPercent == 100
                            ? '🏆 Complété sur ${game.bestCompletionProfile!.platform.label}'
                            : 'Meilleure complétion • ${game.bestCompletionProfile!.platform.label}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                        ),
                      ),
                    ] else
                      Text(
                        game.allAchievementCatalogsKnownEmpty
                            ? 'Aucun trophée/succès sur les plateformes synchronisées'
                            : 'Complétion non synchronisée',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10.5,
                        ),
                      ),
                    if (game.totalPlaytimeMinutes > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${(game.totalPlaytimeMinutes / 60).toStringAsFixed(1)} h détectées sur les plateformes liées',
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GameCoverImage(
        game: game,
        width: width,
        height: height,
        fit: BoxFit.cover,
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
                autofocus: false,
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
  late GameStatus _status;
  late bool _favorite;
  late List<GamePlatformProfile> _profiles;
  late GamePlatform _selectedPlatform;
  _AchievementFilter _achievementFilter =
      _AchievementFilter.all;
  final Set<GamePlatform> _manualEditorsExpanded =
      <GamePlatform>{};

  @override
  void initState() {
    super.initState();

    final GameLibraryEntry game = widget.game;

    _title = TextEditingController(text: game.title);
    _status = game.status;
    _favorite = game.favorite;
    _profiles = List<GamePlatformProfile>.from(
      game.resolvedPlatformProfiles,
    );

    final GamePlatformProfile? steam =
        game.platformProfile(GamePlatform.steam);

    _selectedPlatform =
        steam?.platform ??
        (_profiles.isNotEmpty
            ? _profiles.first.platform
            : game.platform);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  GamePlatformProfile? get _selectedProfile {
    for (final GamePlatformProfile profile in _profiles) {
      if (profile.platform == _selectedPlatform) {
        return profile;
      }
    }

    return null;
  }

  List<int> get _visibleAchievementIndexes {
    final GamePlatformProfile? profile =
        _selectedProfile;

    if (profile == null) {
      return const <int>[];
    }

    final List<GameAchievementDetail> details =
        profile.achievementDetails;

    return List<int>.generate(
      details.length,
      (index) => index,
    ).where(
      (index) {
        final bool unlocked =
            details[index].isUnlocked;

        switch (_achievementFilter) {
          case _AchievementFilter.all:
            return true;
          case _AchievementFilter.unlocked:
            return unlocked;
          case _AchievementFilter.locked:
            return !unlocked;
        }
      },
    ).toList();
  }

  void _replaceProfile(
    GamePlatformProfile profile,
  ) {
    final int index = _profiles.indexWhere(
      (item) => item.platform == profile.platform,
    );

    if (index == -1) {
      _profiles.add(profile);
    } else {
      _profiles[index] = profile;
    }
  }

  void _toggleAchievement(
    int index,
    bool unlocked,
  ) {
    final GamePlatformProfile? profile =
        _selectedProfile;

    if (profile == null ||
        index < 0 ||
        index >= profile.achievementDetails.length) {
      return;
    }

    final List<GameAchievementDetail> details =
        List<GameAchievementDetail>.from(
      profile.achievementDetails,
    );

    final GameAchievementDetail achievement =
        details[index];

    if (achievement.platformUnlocked) {
      return;
    }

    details[index] =
        achievement.withManualState(unlocked);

    final GamePlatformProfile next =
        profile.copyWith(
      achievementDetails: details,
      achievementCatalogInitialized:
          profile.achievementCatalogInitialized ||
              details.isNotEmpty,
    );

    _replaceProfile(
      next.copyWith(
        achievements:
            next.computedAchievementSummary,
      ),
    );
  }

  void _save() {
    final bool titleLocked =
        widget.game.hasOfficialPlatformConnection;
    final String title = titleLocked
        ? widget.game.title
        : _title.text.trim();

    if (title.isEmpty) {
      return;
    }

    final List<GamePlatformProfile> normalizedProfiles =
        _profiles
            .map(
              (profile) => profile.copyWith(
                achievements:
                    profile.computedAchievementSummary,
              ),
            )
            .toList();

    final GameLibraryEntry updated =
        widget.game.copyWith(
      title: title,
      status: _status,
      favorite: _favorite,
      platformProfiles: normalizedProfiles,
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
    final GamePlatformProfile? best =
        _bestProfile(_profiles);
    final GamePlatformProfile? selected =
        _selectedProfile;
    final List<int> visibleAchievementIndexes =
        _visibleAchievementIndexes;
    final int selectedUnlockedCount =
        selected?.achievementDetails
                .where(
                  (achievement) => achievement.isUnlocked,
                )
                .length ??
            0;
    final int selectedLockedCount =
        (selected?.achievementDetails.length ?? 0) -
            selectedUnlockedCount;

    return Padding(
      padding: EdgeInsets.only(
        bottom: viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            18,
            14,
            18,
            24,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _GameCover(
                    game: game,
                    width: 72,
                    height: 102,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FICHE DU JEU',
                          style: TextStyle(
                            color:
                                Color(0xffffc857),
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (game.releaseYear != null)
                          Text(
                            'Sortie : ${game.releaseYear}',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white54,
                            ),
                          ),
                        if (game.genres.isNotEmpty)
                          Text(
                            game.genres.join(' • '),
                            maxLines: 2,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  Color(0xffcbb3e8),
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
                  maxLines: 5,
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
                readOnly:
                    game.hasOfficialPlatformConnection,
                enableInteractiveSelection: true,
                style:
                    const TextStyle(
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  labelText: 'Nom du jeu',
                  suffixIcon:
                      game.hasOfficialPlatformConnection
                          ? const Icon(
                              Icons.lock_outline,
                              color: Colors.white38,
                              size: 19,
                            )
                          : null,
                  helperText:
                      game.hasOfficialPlatformConnection
                          ? 'Nom verrouillé : cette fiche est liée à une plateforme synchronisée.'
                          : null,
                  helperStyle:
                      const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GameStatus>(
                initialValue:
                    _status ==
                            GameStatus.unclassified
                        ? null
                        : _status,
                dropdownColor:
                    const Color(0xff23262a),
                decoration:
                    const InputDecoration(
                  labelText: 'État personnel',
                  hintText: 'Choisir un état',
                ),
                items: GameStatus.values
                    .where(
                      (status) =>
                          status !=
                          GameStatus.unclassified,
                    )
                    .map(
                      (status) =>
                          DropdownMenuItem<
                              GameStatus>(
                        value: status,
                        child:
                            Text(status.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _status = value;
                  });
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding:
                    EdgeInsets.zero,
                title: const Text(
                  'Favori',
                  style:
                      TextStyle(
                    color: Colors.white,
                  ),
                ),
                value: _favorite,
                activeThumbColor:
                    const Color(0xffffc857),
                onChanged: (value) {
                  setState(() {
                    _favorite = value;
                  });
                },
              ),
              const Divider(
                color: Colors.white12,
                height: 28,
              ),
              const Text(
                'COMPLÉTION',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Chaque plateforme garde sa propre progression. '
                'Project XP met en avant ta meilleure complétion et ne fait pas '
                'une moyenne qui pourrait diminuer un 100 % déjà obtenu.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (best != null &&
                  best.completionPercent != null)
                _BestCompletionCard(
                  profile: best,
                )
              else
                const _UnknownCompletionCard(),
              const SizedBox(height: 12),
              for (final GamePlatformProfile profile
                  in _profiles) ...[
                _PlatformProgressCard(
                  profile: profile,
                  selected:
                      profile.platform ==
                          _selectedPlatform,
                  onTap: () {
                    setState(() {
                      _selectedPlatform =
                          profile.platform;
                      _achievementFilter =
                          _AchievementFilter.all;
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (selected != null) ...[
                const Divider(
                  color: Colors.white12,
                  height: 28,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected
                                .achievementCatalogKnownEmpty
                            ? selected.platform.label
                                .toUpperCase()
                            : selected.platform ==
                                    GamePlatform
                                        .playstation
                                ? 'TROPHÉES PLAYSTATION'
                                : 'SUCCÈS ${selected.platform.label.toUpperCase()}',
                        style:
                            const TextStyle(
                          color:
                              Color(0xffb69bdc),
                          fontWeight:
                              FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (!selected
                            .achievementCatalogKnownEmpty &&
                        selected
                                .completionPercent !=
                            null)
                      Text(
                        '${selected.completionPercent} %',
                        style:
                            const TextStyle(
                          color:
                              Color(0xffffc857),
                          fontSize: 12,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                if (selected
                    .achievementCatalogKnownEmpty)
                  Text(
                    selected.platform ==
                            GamePlatform
                                .playstation
                        ? 'Ce jeu ne possède aucun trophée détecté sur PlayStation.'
                        : 'Ce jeu ne possède aucun succès détecté sur ${selected.platform.label}.',
                    style:
                        const TextStyle(
                      color:
                          Colors.white54,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  )
                else
                  Text(
                    selected.progressText,
                    style:
                        const TextStyle(
                      color:
                          Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                if (selected.platform ==
                    GamePlatform.steam) ...[
                  const SizedBox(height: 5),
                  Text(
                    selected
                            .achievementCatalogKnownEmpty
                        ? 'Steam a renvoyé un catalogue vide : Project XP n’affiche donc aucune fausse barre de progression.'
                        : selected
                                .achievementCatalogInitialized
                            ? 'La liste peut être cochée manuellement. Une prochaine synchro Steam confirmera les succès officiels sans effacer les coches manuelles.'
                            : 'Utilise l’icône de synchronisation Steam sur la carte du jeu pour récupérer la liste détaillée.',
                    style:
                        const TextStyle(
                      color:
                          Colors.white38,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (selected
                    .achievementCatalogKnownEmpty)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xff15181b,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        11,
                      ),
                      border:
                          Border.all(
                        color:
                            Colors.white10,
                      ),
                    ),
                    child:
                        Row(
                      children: [
                        const Icon(
                          Icons.block,
                          color:
                              Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(
                          width: 9,
                        ),
                        Expanded(
                          child:
                              Text(
                            selected.platform ==
                                    GamePlatform
                                        .playstation
                                ? 'Aucun trophée à suivre pour cette version.'
                                : 'Aucun succès à suivre pour cette version.',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white54,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (selected
                    .achievementDetails
                    .isNotEmpty) ...[
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children:
                        _AchievementFilter
                            .values
                            .map(
                      (filter) {
                        final int count =
                            switch (filter) {
                          _AchievementFilter
                                .all =>
                            selected
                                .achievementDetails
                                .length,
                          _AchievementFilter
                                .unlocked =>
                            selectedUnlockedCount,
                          _AchievementFilter
                                .locked =>
                            selectedLockedCount,
                        };

                        return ChoiceChip(
                          label: Text(
                            '${filter.label} ($count)',
                          ),
                          selected:
                              _achievementFilter ==
                                  filter,
                          onSelected:
                              (_) {
                            setState(() {
                              _achievementFilter =
                                  filter;
                            });
                          },
                          selectedColor:
                              const Color(
                            0xff3a2e19,
                          ),
                          backgroundColor:
                              const Color(
                            0xff15181b,
                          ),
                          side:
                              BorderSide(
                            color:
                                _achievementFilter ==
                                        filter
                                    ? const Color(
                                        0xffffc857,
                                      )
                                    : Colors
                                        .white12,
                          ),
                          labelStyle:
                              TextStyle(
                            color:
                                _achievementFilter ==
                                        filter
                                    ? const Color(
                                        0xffffc857,
                                      )
                                    : Colors
                                        .white54,
                            fontSize: 9.5,
                            fontWeight:
                                FontWeight.bold,
                          ),
                          visualDensity:
                              VisualDensity
                                  .compact,
                        );
                      },
                    ).toList(),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  if (visibleAchievementIndexes
                      .isEmpty)
                    Container(
                      width:
                          double.infinity,
                      padding:
                          const EdgeInsets
                              .all(
                        12,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xff15181b,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          10,
                        ),
                        border:
                            Border.all(
                          color:
                              Colors.white10,
                        ),
                      ),
                      child:
                          Text(
                        _achievementFilter ==
                                _AchievementFilter
                                    .unlocked
                            ? 'Aucun accomplissement obtenu dans ce filtre.'
                            : 'Aucun accomplissement restant dans ce filtre.',
                        style:
                            const TextStyle(
                          color:
                              Colors.white38,
                          fontSize: 10.5,
                        ),
                      ),
                    )
                  else
                    ...visibleAchievementIndexes
                        .map(
                      (index) {
                        final GameAchievementDetail
                            achievement =
                            selected
                                    .achievementDetails[
                                index];

                        final String sourceLabel =
                            achievement
                                    .platformUnlocked
                                ? 'Confirmé par ${selected.platform.label}'
                                : achievement
                                        .manuallyUnlocked
                                    ? 'Coché manuellement • en attente de confirmation'
                                    : 'Non obtenu';

                        final Widget icon =
                            achievement.iconUrl ==
                                        null ||
                                    achievement
                                        .iconUrl!
                                        .isEmpty
                                ? Icon(
                                    achievement
                                            .isUnlocked
                                        ? Icons
                                            .emoji_events
                                        : Icons
                                            .lock_outline,
                                    color: achievement
                                            .isUnlocked
                                        ? const Color(
                                            0xffffc857,
                                          )
                                        : Colors
                                            .white24,
                                    size: 26,
                                  )
                                : ClipRRect(
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      6,
                                    ),
                                    child:
                                        Image.network(
                                      achievement
                                          .iconUrl!,
                                      width: 34,
                                      height: 34,
                                      fit:
                                          BoxFit.cover,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) =>
                                          Icon(
                                        achievement
                                                .isUnlocked
                                            ? Icons
                                                .emoji_events
                                            : Icons
                                                .lock_outline,
                                        color: achievement
                                                .isUnlocked
                                            ? const Color(
                                                0xffffc857,
                                              )
                                            : Colors
                                                .white24,
                                      ),
                                    ),
                                  );

                        return Container(
                          margin:
                              const EdgeInsets
                                  .only(
                            bottom: 7,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xff111315,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              10,
                            ),
                            border:
                                Border.all(
                              color: achievement
                                      .isUnlocked
                                  ? const Color(
                                      0xffffc857,
                                    ).withValues(
                                      alpha: 0.22,
                                    )
                                  : Colors
                                      .white10,
                            ),
                          ),
                          child:
                              CheckboxListTile(
                            value: achievement
                                .isUnlocked,
                            secondary: icon,
                            contentPadding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            dense: true,
                            controlAffinity:
                                ListTileControlAffinity
                                    .trailing,
                            activeColor:
                                const Color(
                              0xffffc857,
                            ),
                            checkColor:
                                const Color(
                              0xff21150e,
                            ),
                            title: Text(
                              achievement.name,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                                fontSize: 12,
                                fontWeight:
                                    FontWeight
                                        .w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                if (achievement
                                    .description
                                    .isNotEmpty)
                                  Text(
                                    achievement
                                        .description,
                                    maxLines: 2,
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                    style:
                                        const TextStyle(
                                      color: Colors
                                          .white38,
                                      fontSize: 10,
                                      height: 1.25,
                                    ),
                                  ),
                                const SizedBox(
                                  height: 2,
                                ),
                                Text(
                                  sourceLabel,
                                  style:
                                      TextStyle(
                                    color: achievement
                                            .platformUnlocked
                                        ? const Color(
                                            0xff8fd5a6,
                                          )
                                        : achievement
                                                .manuallyUnlocked
                                            ? const Color(
                                                0xff8ebce9,
                                              )
                                            : Colors
                                                .white24,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                            onChanged: achievement
                                    .platformUnlocked
                                ? null
                                : (value) {
                                    setState(() {
                                      _toggleAchievement(
                                        index,
                                        value ==
                                            true,
                                      );
                                    });
                                  },
                          ),
                        );
                      },
                    )
                ] else if (selected
                    .hasAchievementData)
                  _ManualSummaryEditor(
                    key: ValueKey<String>(
                      'manual_${selected.platform.name}',
                    ),
                    profile: selected,
                    onChanged: (summary) {
                      setState(() {
                        _replaceProfile(
                          selected.copyWith(
                            achievements: summary,
                          ),
                        );
                      });
                    },
                  )
                else if (_manualEditorsExpanded
                    .contains(
                  selected.platform,
                ))
                  _ManualSummaryEditor(
                    key: ValueKey<String>(
                      'manual_${selected.platform.name}',
                    ),
                    profile: selected,
                    onChanged: (summary) {
                      setState(() {
                        _replaceProfile(
                          selected.copyWith(
                            achievements: summary,
                          ),
                        );
                      });
                    },
                  )
                else
                  Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets
                            .all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xff15181b,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        11,
                      ),
                      border:
                          Border.all(
                        color:
                            Colors.white10,
                      ),
                    ),
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          selected.platform ==
                                  GamePlatform
                                      .playstation
                              ? 'Aucun trophée renseigné pour cette version.'
                              : 'Aucun succès renseigné pour cette version.',
                          style:
                              const TextStyle(
                            color:
                                Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(
                          height: 9,
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _manualEditorsExpanded
                                  .add(
                                selected.platform,
                              );
                            });
                          },
                          icon:
                              const Icon(
                            Icons.edit_note,
                            size: 18,
                          ),
                          label:
                              const Text(
                            'RENSEIGNER MANUELLEMENT',
                          ),
                          style:
                              OutlinedButton
                                  .styleFrom(
                            foregroundColor:
                                const Color(
                              0xffcbb3e8,
                            ),
                            side:
                                const BorderSide(
                              color:
                                  Color(
                                0x55CBB3E8,
                              ),
                            ),
                            textStyle:
                                const TextStyle(
                              fontSize: 9.5,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child:
                        OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          const _GameEditResult
                              .delete(),
                        );
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                      ),
                      label:
                          const Text(
                        'RETIRER',
                      ),
                      style: OutlinedButton
                          .styleFrom(
                        foregroundColor:
                            Colors.redAccent,
                        side:
                            const BorderSide(
                          color:
                              Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child:
                        FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(
                        Icons.save_outlined,
                      ),
                      label: const Text(
                        'ENREGISTRER',
                      ),
                      style: FilledButton
                          .styleFrom(
                        backgroundColor:
                            const Color(
                          0xffffc857,
                        ),
                        foregroundColor:
                            const Color(
                          0xff21150e,
                        ),
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

  GamePlatformProfile? _bestProfile(
    List<GamePlatformProfile> profiles,
  ) {
    GamePlatformProfile? best;
    int bestValue = -1;

    for (final GamePlatformProfile profile
        in profiles) {
      final int? value =
          profile.completionPercent;

      if (value == null) {
        continue;
      }

      if (value > bestValue) {
        best = profile;
        bestValue = value;
      }
    }

    return best;
  }
}

class _BestCompletionCard extends StatelessWidget {
  final GamePlatformProfile profile;

  const _BestCompletionCard({
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final int value =
        profile.completionPercent ?? 0;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
            const Color(0xff201b12),
        borderRadius:
            BorderRadius.circular(13),
        border: Border.all(
          color:
              const Color(0xffffc857)
                  .withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            value == 100
                ? '🏆 100 % COMPLÉTÉ'
                : 'MEILLEURE COMPLÉTION',
            style: const TextStyle(
              color:
                  Color(0xffffc857),
              fontWeight:
                  FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: value / 100,
            minHeight: 7,
            backgroundColor:
                Colors.white10,
            color:
                const Color(0xffffc857),
          ),
          const SizedBox(height: 6),
          Text(
            '${profile.platform.label} • $value % • ${profile.progressText}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnknownCompletionCard
    extends StatelessWidget {
  const _UnknownCompletionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
            const Color(0xff15181b),
        borderRadius:
            BorderRadius.circular(13),
        border:
            Border.all(
          color: Colors.white10,
        ),
      ),
      child: const Text(
        'Aucune progression de trophées/succès connue pour le moment.',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _PlatformProgressCard
    extends StatelessWidget {
  final GamePlatformProfile profile;
  final bool selected;
  final VoidCallback onTap;

  const _PlatformProgressCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final int? value =
        profile.completionPercent;

    return Material(
      color: selected
          ? const Color(0xff24202d)
          : const Color(0xff15181b),
      borderRadius:
          BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(12),
        child: Container(
          padding:
              const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(
                      0xffb69bdc,
                    )
                  : Colors.white10,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    _platformIcon(
                      profile.platform,
                    ),
                    color: selected
                        ? const Color(
                            0xffcbb3e8,
                          )
                        : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profile
                          .platform.label,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize: 12,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    value == null
                        ? '—'
                        : '$value %',
                    style:
                        const TextStyle(
                      color: Color(
                        0xffffc857,
                      ),
                      fontSize: 11,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (value != null) ...[
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: value / 100,
                  minHeight: 5,
                  backgroundColor:
                      Colors.white10,
                  color:
                      const Color(
                    0xffffc857,
                  ),
                ),
                const SizedBox(height: 5),
              ] else
                const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.achievementCatalogKnownEmpty
                          ? profile.platform ==
                                  GamePlatform
                                      .playstation
                              ? 'Aucun trophée sur cette version'
                              : 'Aucun succès sur cette version'
                          : value == null
                              ? 'Complétion non renseignée'
                              : profile.progressText,
                      style:
                          const TextStyle(
                        color:
                            Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  if (profile
                          .playtimeMinutes >
                      0)
                    Text(
                      '${(profile.playtimeMinutes / 60).toStringAsFixed(1)} h',
                      style:
                          const TextStyle(
                        color:
                            Colors.white38,
                        fontSize: 9.5,
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

  static IconData _platformIcon(
    GamePlatform platform,
  ) {
    switch (platform) {
      case GamePlatform.steam:
        return Icons.computer_rounded;
      case GamePlatform.playstation:
        return Icons.sports_esports_rounded;
      case GamePlatform.xbox:
        return Icons.gamepad_rounded;
      case GamePlatform.epic:
        return Icons.window_rounded;
      case GamePlatform.nintendo:
        return Icons.videogame_asset_rounded;
      case GamePlatform.pc:
        return Icons.desktop_windows_rounded;
      case GamePlatform.other:
        return Icons.devices_other_rounded;
    }
  }
}

class _ManualSummaryEditor extends StatefulWidget {
  final GamePlatformProfile profile;
  final ValueChanged<GameAchievementSummary> onChanged;

  const _ManualSummaryEditor({
    super.key,
    required this.profile,
    required this.onChanged,
  });

  @override
  State<_ManualSummaryEditor> createState() =>
      _ManualSummaryEditorState();
}

class _ManualSummaryEditorState
    extends State<_ManualSummaryEditor> {
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

    final GameAchievementSummary a =
        widget.profile.computedAchievementSummary;

    _unlocked =
        TextEditingController(text: '${a.unlocked}');
    _total =
        TextEditingController(text: '${a.total}');
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
    for (final TextEditingController controller
        in <TextEditingController>[
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

  int _read(
    TextEditingController controller,
  ) {
    return int.tryParse(
          controller.text.trim(),
        ) ??
        0;
  }

  void _emit() {
    widget.onChanged(
      GameAchievementSummary(
        unlocked: _read(_unlocked),
        total: _read(_total),
        bronzeUnlocked:
            _read(_bronzeUnlocked),
        bronzeTotal:
            _read(_bronzeTotal),
        silverUnlocked:
            _read(_silverUnlocked),
        silverTotal:
            _read(_silverTotal),
        goldUnlocked:
            _read(_goldUnlocked),
        goldTotal:
            _read(_goldTotal),
        platinumUnlocked:
            _read(_platinumUnlocked),
        platinumTotal:
            _read(_platinumTotal),
        scoreEarned:
            _read(_scoreEarned),
        scoreTotal:
            _read(_scoreTotal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GamePlatform platform =
        widget.profile.platform;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Aucune liste détaillée synchronisée. Tu peux conserver une progression manuelle en attendant la connexion officielle de cette plateforme.',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 10.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        if (platform ==
            GamePlatform.playstation) ...[
          _ManualCountRow(
            label: 'Bronze',
            unlocked: _bronzeUnlocked,
            total: _bronzeTotal,
            onChanged: _emit,
          ),
          _ManualCountRow(
            label: 'Argent',
            unlocked: _silverUnlocked,
            total: _silverTotal,
            onChanged: _emit,
          ),
          _ManualCountRow(
            label: 'Or',
            unlocked: _goldUnlocked,
            total: _goldTotal,
            onChanged: _emit,
          ),
          _ManualCountRow(
            label: 'Platine',
            unlocked: _platinumUnlocked,
            total: _platinumTotal,
            onChanged: _emit,
          ),
        ] else ...[
          _ManualCountRow(
            label: 'Succès',
            unlocked: _unlocked,
            total: _total,
            onChanged: _emit,
          ),
          if (platform ==
              GamePlatform.xbox)
            _ManualCountRow(
              label: 'Gamerscore',
              unlocked: _scoreEarned,
              total: _scoreTotal,
              unlockedHint: 'G obtenus',
              totalHint: 'G total',
              onChanged: _emit,
            ),
        ],
      ],
    );
  }
}

class _ManualCountRow
    extends StatelessWidget {
  final String label;
  final TextEditingController unlocked;
  final TextEditingController total;
  final String unlockedHint;
  final String totalHint;
  final VoidCallback onChanged;

  const _ManualCountRow({
    required this.label,
    required this.unlocked,
    required this.total,
    this.unlockedHint = 'Obtenus',
    this.totalHint = 'Total',
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 9,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.white70,
                fontWeight:
                    FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: unlocked,
              keyboardType:
                  TextInputType.number,
              onChanged: (_) =>
                  onChanged(),
              style:
                  const TextStyle(
                color: Colors.white,
              ),
              decoration:
                  InputDecoration(
                labelText:
                    unlockedHint,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: total,
              keyboardType:
                  TextInputType.number,
              onChanged: (_) =>
                  onChanged(),
              style:
                  const TextStyle(
                color: Colors.white,
              ),
              decoration:
                  InputDecoration(
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

