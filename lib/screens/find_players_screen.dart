import 'dart:async';

import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../models/team_model.dart';
import '../services/auth_service.dart';
import '../services/compagnie_invitation_storage.dart';
import '../services/compagnie_player_service.dart';
import '../services/friend_service.dart';
import '../services/online_presence_service.dart';
import '../services/profile_storage.dart';
import '../services/team_storage.dart';
import '../widgets/avatar_renderer.dart';

class FindPlayersScreen extends StatefulWidget {
  const FindPlayersScreen({super.key});

  @override
  State<FindPlayersScreen> createState() =>
      _FindPlayersScreenState();
}

class _FindPlayersScreenState
    extends State<FindPlayersScreen> {
  String? selectedGame;
  String? selectedPlatform;
  bool availableNowOnly = false;
  bool showFriends = false;

  bool _loading = true;
  String? _errorMessage;

  List<String> profileGames = <String>[];
  List<String> profilePlatforms = <String>[];

  List<_Player> _players = <_Player>[];
  Set<String> _onlineUserIds = <String>{};
  Set<String> _friendUserIds = <String>{};

  StreamSubscription<Set<String>>? _presenceSubscription;

  @override
  void initState() {
    super.initState();

    _onlineUserIds =
        OnlinePresenceService.instance.currentOnlineUserIds;

    _presenceSubscription =
        OnlinePresenceService.instance.onlineUserIdsStream.listen(
      (Set<String> userIds) {
        if (!mounted) {
          return;
        }

        setState(() {
          _onlineUserIds =
              Set<String>.from(userIds);
        });
      },
    );

    _loadData();
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData({
    bool showLoader = true,
  }) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      await OnlinePresenceService.instance.start();

      final Map<String, dynamic> profile =
          await ProfileStorage.loadProfile();

      final List<Map<String, dynamic>> rows =
          await CompagniePlayerService.loadPublicPlayers();

      final List<Map<String, dynamic>> friendships =
          await FriendService.getFriends();

      final Set<String> friendUserIds = friendships
          .map(
            (Map<String, dynamic> friendship) =>
                friendship['friend_id']?.toString().trim() ?? '',
          )
          .where(
            (String id) => id.isNotEmpty,
          )
          .toSet();

      final List<_Player> players = rows
          .map(
            (Map<String, dynamic> row) =>
                _Player.fromPublicProfile(row),
          )
          .where(
            (_Player player) =>
                player.id.isNotEmpty,
          )
          .toList();

      final List<String> loadedGames =
          _readStringList(
        profile['games'],
      );

      final List<String> loadedPlatforms =
          _readPlatformNames(
        profile['platforms'],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        profileGames = loadedGames;
        profilePlatforms = loadedPlatforms;
        _players = players;
        _friendUserIds = friendUserIds;
        _onlineUserIds =
            OnlinePresenceService.instance.currentOnlineUserIds;
        _loading = false;
        _errorMessage = null;

        if (selectedGame != null &&
            !profileGames.contains(selectedGame)) {
          selectedGame = null;
        }

        if (selectedPlatform != null &&
            !profilePlatforms.contains(selectedPlatform)) {
          selectedPlatform = null;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'Impossible de charger les joueurs pour le moment.';
      });
    }
  }

  List<String> get availableFilterGames =>
      profileGames;

  List<String> get availableFilterPlatforms =>
      profilePlatforms;

  List<_Player> get filteredPlayers {
    final List<_Player> result =
        _players.where(
      (_Player player) {
        if (selectedGame != null &&
            !player.games.contains(selectedGame)) {
          return false;
        }

        if (selectedPlatform != null &&
            !player.platforms.contains(selectedPlatform)) {
          return false;
        }

        if (availableNowOnly &&
            !_isOnline(player)) {
          return false;
        }

        if (!showFriends &&
            _friendUserIds.contains(player.id)) {
          return false;
        }

        return true;
      },
    ).toList();

    result.sort(
      (
        _Player a,
        _Player b,
      ) {
        final bool aOnline = _isOnline(a);
        final bool bOnline = _isOnline(b);

        if (aOnline != bOnline) {
          return aOnline ? -1 : 1;
        }

        final int? aCompatibility =
            _calculateCompatibility(a);

        final int? bCompatibility =
            _calculateCompatibility(b);

        if (aCompatibility != null ||
            bCompatibility != null) {
          final int comparison =
              (bCompatibility ?? -1).compareTo(
            aCompatibility ?? -1,
          );

          if (comparison != 0) {
            return comparison;
          }
        }

        return a.name
            .toLowerCase()
            .compareTo(
              b.name.toLowerCase(),
            );
      },
    );

    return result;
  }

  bool _isOnline(
    _Player player,
  ) {
    return _onlineUserIds.contains(
      player.id,
    );
  }

  int? _calculateCompatibility(
    _Player player,
  ) {
    int earned = 0;
    int possible = 0;

    if (profileGames.isNotEmpty) {
      possible += 70;

      final int commonGames =
          player.games
              .where(
                (String game) =>
                    profileGames.contains(game),
              )
              .length;

      final double ratio =
          commonGames / profileGames.length;

      earned +=
          (ratio.clamp(0.0, 1.0) * 70).round();
    }

    if (profilePlatforms.isNotEmpty) {
      possible += 30;

      final int commonPlatforms =
          player.platforms
              .where(
                (String platform) =>
                    profilePlatforms.contains(platform),
              )
              .length;

      final double ratio =
          commonPlatforms / profilePlatforms.length;

      earned +=
          (ratio.clamp(0.0, 1.0) * 30).round();
    }

    if (possible == 0) {
      return null;
    }

    final int result =
        ((earned / possible) * 100).round();

    if (result < 0) {
      return 0;
    }

    if (result > 100) {
      return 100;
    }

    return result;
  }

  List<String> _commonGames(
    _Player player,
  ) {
    return player.games
        .where(
          (String game) =>
              profileGames.contains(game),
        )
        .toList();
  }

  List<String> _commonPlatforms(
    _Player player,
  ) {
    return player.platforms
        .where(
          (String platform) =>
              profilePlatforms.contains(platform),
        )
        .toList();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      backgroundColor:
          const Color(0xff1b120d),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff5c3317),
        foregroundColor:
            Colors.amber,
        centerTitle: true,
        title: const Text(
          'TROUVER DES JOUEURS',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body:
          SafeArea(
        child:
            _errorMessage != null
                ? _buildErrorState()
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final List<_Player> players =
        filteredPlayers;

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child:
              RefreshIndicator(
            color:
                Colors.amber,
            onRefresh:
                () => _loadData(
              showLoader:
                  false,
            ),
            child:
                players.isEmpty
                    ? ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height:
                                MediaQuery.sizeOf(context).height *
                                    0.16,
                          ),
                          _buildEmptyState(),
                        ],
                      )
                    : ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          25,
                        ),
                        itemCount:
                            players.length,
                        itemBuilder:
                            (
                          BuildContext context,
                          int index,
                        ) {
                          final _Player player =
                              players[index];

                          return _PlayerCard(
                            player:
                                player,
                            compatibility:
                                _calculateCompatibility(
                              player,
                            ),
                            online:
                                _isOnline(
                              player,
                            ),
                            commonGames:
                                _commonGames(
                              player,
                            ),
                            commonPlatforms:
                                _commonPlatforms(
                              player,
                            ),
                            onTap:
                                () {
                              _showPlayerDetails(
                                player,
                              );
                            },
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor:
          const Color(0xff1b120d),
      appBar:
          AppBar(
        backgroundColor:
            const Color(0xff5c3317),
        foregroundColor:
            Colors.amber,
        centerTitle:
            true,
        title:
            const Text(
          'TROUVER DES JOUEURS',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body:
          const Center(
        child:
            CircularProgressIndicator(
          color:
              Colors.amber,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          28,
        ),
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color:
                  Colors.amber,
              size:
                  52,
            ),
            const SizedBox(
              height:
                  14,
            ),
            Text(
              _errorMessage!,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize:
                    18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height:
                  18,
            ),
            ElevatedButton.icon(
              onPressed:
                  _loadData,
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.amber,
                foregroundColor:
                    Colors.black,
              ),
              icon:
                  const Icon(
                Icons.refresh_rounded,
              ),
              label:
                  const Text(
                'RÉESSAYER',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final List<String> activeFilters =
        <String>[];

    if (selectedGame != null) {
      activeFilters.add(
        selectedGame!,
      );
    }

    if (selectedPlatform != null) {
      activeFilters.add(
        selectedPlatform!,
      );
    }

    if (availableNowOnly) {
      activeFilters.add(
        'En ligne maintenant',
      );
    }

    if (showFriends) {
      activeFilters.add(
        'Amis affichés',
      );
    }

    final List<_Player> visiblePlayers =
        filteredPlayers;

    final int onlineCount =
        visiblePlayers
            .where(_isOnline)
            .length;

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        20,
        16,
        10,
      ),
      child:
          Column(
        children: [
          const Text(
            'Trouve tes compagnons',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Colors.amber,
              fontSize:
                  25,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height:
                6,
          ),
          SizedBox(
            width:
                double.infinity,
            height:
                44,
            child:
                Stack(
              alignment:
                  Alignment.center,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal:
                        52,
                  ),
                  child:
                      Text(
                    '${visiblePlayers.length} joueur(s) trouvé(s) • '
                    '$onlineCount en ligne',
                    textAlign:
                        TextAlign.center,
                    maxLines:
                        1,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      color:
                          Colors.white70,
                      fontSize:
                          14,
                    ),
                  ),
                ),
                Positioned(
                  right:
                      0,
                  child:
                      Tooltip(
                    message:
                        'Filtres',
                    child:
                        Material(
                      color:
                          Colors.transparent,
                      child:
                          InkWell(
                        onTap:
                            _showFilters,
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                        child:
                            Container(
                          width:
                              44,
                          height:
                              44,
                          alignment:
                              Alignment.center,
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(0xff2b1a12),
                            borderRadius:
                                BorderRadius.circular(
                              12,
                            ),
                            border:
                                Border.all(
                              color:
                                  Colors.amber,
                              width:
                                  1.25,
                            ),
                          ),
                          child:
                              const Icon(
                            Icons.tune_rounded,
                            color:
                                Colors.amber,
                            size:
                                23,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (activeFilters.isNotEmpty) ...[
            const SizedBox(
              height:
                  12,
            ),
            Wrap(
              spacing:
                  7,
              runSpacing:
                  7,
              alignment:
                  WrapAlignment.center,
              children:
                  activeFilters.map(
                (
                  String filter,
                ) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal:
                          10,
                      vertical:
                          6,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(0xff6B4226),
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                      border:
                          Border.all(
                        color:
                            Colors.amber,
                      ),
                    ),
                    child:
                        Text(
                      filter,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize:
                            12,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  );
                },
              ).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          30,
        ),
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_search_rounded,
              color:
                  Colors.amber,
              size:
                  55,
            ),
            const SizedBox(
              height:
                  15,
            ),
            Text(
              _players.isEmpty
                  ? 'Aucun autre joueur public'
                  : 'Aucun joueur trouvé',
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize:
                    21,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height:
                  8,
            ),
            Text(
              _players.isEmpty
                  ? 'Les profils apparaîtront ici dès qu’ils seront synchronisés.'
                  : 'Essaie de modifier tes filtres.',
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white70,
              ),
            ),
            if (_players.isNotEmpty) ...[
              const SizedBox(
                height:
                    20,
              ),
              OutlinedButton(
                onPressed:
                    _resetFilters,
                style:
                    OutlinedButton.styleFrom(
                  foregroundColor:
                      Colors.amber,
                  side:
                      const BorderSide(
                    color:
                        Colors.amber,
                  ),
                ),
                child:
                    const Text(
                  'RÉINITIALISER LES FILTRES',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      selectedGame = null;
      selectedPlatform = null;
      availableNowOnly = false;
      showFriends = false;
    });
  }

  void _showFilters() {
    String? tempGame =
        selectedGame;

    String? tempPlatform =
        selectedPlatform;

    bool tempAvailableNow =
        availableNowOnly;

    bool tempShowFriends =
        showFriends;

    showModalBottomSheet<void>(
      context:
          context,
      backgroundColor:
          const Color(0xff2b1a12),
      isScrollControlled:
          true,
      builder:
          (
        BuildContext context,
      ) {
        return StatefulBuilder(
          builder:
              (
            BuildContext context,
            StateSetter setModalState,
          ) {
            return SafeArea(
              child:
                  Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  25,
                ),
                child:
                    SingleChildScrollView(
                  child:
                      Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Center(
                        child:
                            Container(
                          width:
                              45,
                          height:
                              5,
                          decoration:
                              BoxDecoration(
                            color:
                                Colors.white30,
                            borderRadius:
                                BorderRadius.circular(
                              10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        height:
                            20,
                      ),
                      const Center(
                        child:
                            Text(
                          'FILTRES',
                          style:
                              TextStyle(
                            color:
                                Colors.amber,
                            fontSize:
                                22,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height:
                            25,
                      ),
                      const Text(
                        'JEU',
                        style:
                            TextStyle(
                          color:
                              Colors.amber,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height:
                            8,
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue:
                            tempGame,
                        dropdownColor:
                            const Color(0xff2b1a12),
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            InputDecoration(
                          filled:
                              true,
                          fillColor:
                              const Color(0xff1b120d),
                          border:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                              12,
                            ),
                          ),
                        ),
                        items:
                            <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            value:
                                null,
                            child:
                                Text(
                              'Tous mes jeux',
                              style:
                                  TextStyle(
                                color:
                                    Colors.white,
                              ),
                            ),
                          ),
                          ...availableFilterGames.map(
                            (
                              String game,
                            ) {
                              return DropdownMenuItem<String?>(
                                value:
                                    game,
                                child:
                                    Text(
                                  game,
                                ),
                              );
                            },
                          ),
                        ],
                        onChanged:
                            (
                          String? value,
                        ) {
                          setModalState(
                            () {
                              tempGame =
                                  value;
                            },
                          );
                        },
                      ),
                      if (availableFilterGames.isEmpty) ...[
                        const SizedBox(
                          height:
                              8,
                        ),
                        const Text(
                          "Aucun jeu n'est encore renseigné dans ton profil.",
                          style:
                              TextStyle(
                            color:
                                Colors.white54,
                            fontSize:
                                12,
                          ),
                        ),
                      ],
                      const SizedBox(
                        height:
                            20,
                      ),
                      const Text(
                        'PLATEFORME',
                        style:
                            TextStyle(
                          color:
                              Colors.amber,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height:
                            8,
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue:
                            tempPlatform,
                        dropdownColor:
                            const Color(0xff2b1a12),
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            InputDecoration(
                          filled:
                              true,
                          fillColor:
                              const Color(0xff1b120d),
                          border:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                              12,
                            ),
                          ),
                        ),
                        items:
                            <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            value:
                                null,
                            child:
                                Text(
                              'Toutes mes plateformes',
                              style:
                                  TextStyle(
                                color:
                                    Colors.white,
                              ),
                            ),
                          ),
                          ...availableFilterPlatforms.map(
                            (
                              String platform,
                            ) {
                              return DropdownMenuItem<String?>(
                                value:
                                    platform,
                                child:
                                    Text(
                                  platform,
                                ),
                              );
                            },
                          ),
                        ],
                        onChanged:
                            (
                          String? value,
                        ) {
                          setModalState(
                            () {
                              tempPlatform =
                                  value;
                            },
                          );
                        },
                      ),
                      if (availableFilterPlatforms.isEmpty) ...[
                        const SizedBox(
                          height:
                              8,
                        ),
                        const Text(
                          "Aucune plateforme n'est encore renseignée dans ton profil.",
                          style:
                              TextStyle(
                            color:
                                Colors.white54,
                            fontSize:
                                12,
                          ),
                        ),
                      ],
                      const SizedBox(
                        height:
                            20,
                      ),
                      SwitchListTile(
                        contentPadding:
                            EdgeInsets.zero,
                        title:
                            const Text(
                          'En ligne maintenant',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        subtitle:
                            const Text(
                          'Afficher uniquement les joueurs réellement connectés à Project XP.',
                          style:
                              TextStyle(
                            color:
                                Colors.white70,
                          ),
                        ),
                        value:
                            tempAvailableNow,
                        activeThumbColor:
                            Colors.amber,
                        activeTrackColor:
                            const Color(0xff6B4226),
                        onChanged:
                            (
                          bool value,
                        ) {
                          setModalState(
                            () {
                              tempAvailableNow =
                                  value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height:
                            4,
                      ),
                      SwitchListTile(
                        contentPadding:
                            EdgeInsets.zero,
                        title:
                            const Text(
                          'Afficher les amis',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        subtitle:
                            const Text(
                          'Inclure les joueurs déjà présents dans ta liste d’amis.',
                          style:
                              TextStyle(
                            color:
                                Colors.white70,
                          ),
                        ),
                        value:
                            tempShowFriends,
                        activeThumbColor:
                            Colors.amber,
                        activeTrackColor:
                            const Color(0xff6B4226),
                        onChanged:
                            (
                          bool value,
                        ) {
                          setModalState(
                            () {
                              tempShowFriends =
                                  value;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        height:
                            20,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child:
                                OutlinedButton(
                              onPressed:
                                  () {
                                setModalState(
                                  () {
                                    tempGame =
                                        null;
                                    tempPlatform =
                                        null;
                                    tempAvailableNow =
                                        false;
                                    tempShowFriends =
                                        false;
                                  },
                                );
                              },
                              style:
                                  OutlinedButton.styleFrom(
                                foregroundColor:
                                    Colors.white70,
                                side:
                                    const BorderSide(
                                  color:
                                      Colors.white30,
                                ),
                              ),
                              child:
                                  const Text(
                                'RÉINITIALISER',
                              ),
                            ),
                          ),
                          const SizedBox(
                            width:
                                12,
                          ),
                          Expanded(
                            child:
                                ElevatedButton(
                              onPressed:
                                  () {
                                setState(
                                  () {
                                    selectedGame =
                                        tempGame;
                                    selectedPlatform =
                                        tempPlatform;
                                    availableNowOnly =
                                        tempAvailableNow;
                                    showFriends =
                                        tempShowFriends;
                                  },
                                );

                                Navigator.pop(
                                  context,
                                );
                              },
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.amber,
                                foregroundColor:
                                    Colors.black,
                              ),
                              child:
                                  const Text(
                                'APPLIQUER',
                                style:
                                    TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
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
          },
        );
      },
    );
  }


  Future<void> _invitePlayerToTeam(
    _Player player,
  ) async {
    final String currentUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    if (currentUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible d’identifier ton compte pour le moment.',
            ),
          ),
        );
      }
      return;
    }

    final List<TeamModel> teams =
        await TeamStorage.loadTeamsForCurrentUser();

    final List<TeamModel> manageableTeams =
        teams
            .where(
              (TeamModel team) =>
                  team.canManageTeam(currentUserId),
            )
            .toList()
          ..sort(
            (TeamModel a, TeamModel b) =>
                a.name.toLowerCase().compareTo(
                      b.name.toLowerCase(),
                    ),
          );

    if (!mounted) {
      return;
    }

    if (manageableTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu n’es Chef ou Admin d’aucune équipe pour le moment.',
          ),
        ),
      );
      return;
    }

    final Map<String, bool> pendingByTeam =
        <String, bool>{};

    for (final TeamModel team in manageableTeams) {
      pendingByTeam[team.id] =
          await CompagnieInvitationStorage
              .hasPendingInvitation(
        teamId: team.id,
        inviteeId: player.id,
      );
    }

    if (!mounted) {
      return;
    }

    final TeamModel? selectedTeam =
        await showModalBottomSheet<TeamModel>(
      context: context,
      backgroundColor:
          const Color(0xff2b1a12),
      shape:
          const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              14,
              16,
              22,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'INVITER ${player.name.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Choisis l’équipe qui doit envoyer l’invitation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 15),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.sizeOf(sheetContext)
                                .height *
                            0.52,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: manageableTeams.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (
                      BuildContext context,
                      int index,
                    ) {
                      final TeamModel team =
                          manageableTeams[index];

                      final bool pending =
                          pendingByTeam[team.id] ?? false;

                      final bool alreadyMember =
                          team.memberIds.contains(
                        player.id,
                      );

                      final bool full =
                          team.memberIds.length >=
                              team.maxMembers;

                      final bool enabled =
                          !alreadyMember &&
                          !pending &&
                          !full;

                      return Material(
                        color: const Color(0xff1b120d),
                        borderRadius:
                            BorderRadius.circular(14),
                        child: InkWell(
                          onTap: enabled
                              ? () {
                                  Navigator.pop(
                                    sheetContext,
                                    team,
                                  );
                                }
                              : null,
                          borderRadius:
                              BorderRadius.circular(14),
                          child: Container(
                            padding:
                                const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(14),
                              border: Border.all(
                                color: enabled
                                    ? Colors.amber
                                        .withValues(alpha: 0.55)
                                    : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_rounded,
                                  color: Colors.amber,
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        team.name,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: enabled
                                              ? Colors.white
                                              : Colors.white54,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        alreadyMember
                                            ? 'Déjà membre de cette équipe'
                                            : pending
                                                ? 'Invitation déjà en attente'
                                                : full
                                                    ? 'Équipe complète'
                                                    : '${team.memberIds.length}/${team.maxMembers} membres',
                                        style: TextStyle(
                                          color: alreadyMember ||
                                                  pending ||
                                                  full
                                              ? Colors.amber
                                              : Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  alreadyMember
                                      ? Icons.check_circle_rounded
                                      : pending
                                          ? Icons.hourglass_top_rounded
                                          : full
                                              ? Icons.lock_rounded
                                              : Icons.chevron_right_rounded,
                                  color: alreadyMember
                                      ? Colors.greenAccent
                                      : enabled
                                          ? Colors.amber
                                          : Colors.white30,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedTeam == null ||
        !mounted) {
      return;
    }

    final Map<String, dynamic> profile =
        await ProfileStorage.loadProfile();

    final String inviterName =
        profile['pseudo']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? profile['pseudo'].toString().trim()
            : 'Joueur';

    final CompagnieInvitationCreateResult result =
        await CompagnieInvitationStorage
            .createInvitation(
      team: selectedTeam,
      inviterId: currentUserId,
      inviterName: inviterName,
      inviteeId: player.id,
      inviteeName: player.name,
    );

    if (!mounted) {
      return;
    }

    final String message;

    switch (result) {
      case CompagnieInvitationCreateResult.success:
        message =
            'Invitation envoyée à ${player.name} pour ${selectedTeam.name}.';
        break;
      case CompagnieInvitationCreateResult.alreadyPending:
        message =
            'Une invitation est déjà en attente pour ${player.name}.';
        break;
      case CompagnieInvitationCreateResult.alreadyMember:
        message =
            '${player.name} fait déjà partie de cette équipe.';
        break;
      case CompagnieInvitationCreateResult.teamFull:
        message = 'Cette équipe est complète.';
        break;
      case CompagnieInvitationCreateResult.notAllowed:
        message =
            'Tu n’as plus les droits pour inviter dans cette équipe.';
        break;
      case CompagnieInvitationCreateResult.invalid:
        message =
            'Impossible d’envoyer l’invitation. Vérifie la connexion et la configuration Supabase.';
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<_PlayerInviteSummary> _loadPlayerInviteSummary(
    _Player player,
  ) async {
    final String currentUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    if (currentUserId.isEmpty) {
      return const _PlayerInviteSummary(
        canInvite: false,
        label: 'INVITATION INDISPONIBLE',
      );
    }

    final List<TeamModel> teams =
        await TeamStorage.loadTeamsForCurrentUser();

    final List<TeamModel> managedTeams =
        teams
            .where(
              (TeamModel team) =>
                  team.canManageTeam(currentUserId),
            )
            .toList();

    if (managedTeams.isEmpty) {
      return const _PlayerInviteSummary(
        canInvite: false,
        label: 'AUCUNE ÉQUIPE À GÉRER',
      );
    }

    bool allAlreadyMember = true;
    bool hasPending = false;

    for (final TeamModel team in managedTeams) {
      if (team.memberIds.contains(player.id)) {
        continue;
      }

      allAlreadyMember = false;

      if (team.memberIds.length >= team.maxMembers) {
        continue;
      }

      final bool pending =
          await CompagnieInvitationStorage
              .hasPendingInvitation(
        teamId: team.id,
        inviteeId: player.id,
      );

      if (pending) {
        hasPending = true;
        continue;
      }

      return const _PlayerInviteSummary(
        canInvite: true,
        label: 'INVITER DANS UNE ÉQUIPE',
      );
    }

    if (allAlreadyMember) {
      return const _PlayerInviteSummary(
        canInvite: false,
        label: 'DÉJÀ MEMBRE DE TON ÉQUIPE',
      );
    }

    if (hasPending) {
      return const _PlayerInviteSummary(
        canInvite: false,
        label: 'INVITATION DÉJÀ EN ATTENTE',
      );
    }

    return const _PlayerInviteSummary(
      canInvite: false,
      label: 'AUCUNE INVITATION POSSIBLE',
    );
  }

  Future<void> _showPlayerDetails(
    _Player player,
  ) async {
    FriendRelationshipState relationship =
        await FriendService.getRelationshipState(
      player.id,
    );

    if (!mounted) {
      return;
    }

    final _PlayerInviteSummary inviteSummary =
        await _loadPlayerInviteSummary(
      player,
    );

    if (!mounted) {
      return;
    }

    final int? compatibility =
        _calculateCompatibility(
      player,
    );

    final List<String> commonGames =
        _commonGames(
      player,
    );

    final List<String> commonPlatforms =
        _commonPlatforms(
      player,
    );

    await showDialog<void>(
      context:
          context,
      builder:
          (
        BuildContext dialogContext,
      ) {
        return StatefulBuilder(
          builder:
              (
            BuildContext context,
            StateSetter setDialogState,
          ) {
            final bool canSendFriendRequest =
                relationship ==
                    FriendRelationshipState.none;

            return AlertDialog(
              backgroundColor:
                  const Color(0xff2b1a12),
              title:
                  Text(
                player.name,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content:
                  SingleChildScrollView(
                child:
                    Column(
                  children: [
                    _PlayerAvatar(
                      player:
                          player,
                      size:
                          104,
                    ),
                    const SizedBox(
                      height:
                          12,
                    ),
                    _CompatibilityBadge(
                      percentage:
                          compatibility,
                      size:
                          82,
                    ),
                    const SizedBox(
                      height:
                          8,
                    ),
                    Text(
                      compatibility == null
                          ? 'Compatibilité à calculer'
                          : '$compatibility% de compatibilité',
                      style:
                          const TextStyle(
                        color:
                            Colors.amber,
                        fontSize:
                            19,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    if (compatibility == null) ...[
                      const SizedBox(
                        height:
                            5,
                      ),
                      const Text(
                        'Complète tes jeux et plateformes pour obtenir un score utile.',
                        textAlign:
                            TextAlign.center,
                        style:
                            TextStyle(
                          color:
                              Colors.white54,
                          fontSize:
                              12,
                        ),
                      ),
                    ],
                    const SizedBox(
                      height:
                          12,
                    ),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Container(
                          width:
                              9,
                          height:
                              9,
                          decoration:
                              BoxDecoration(
                            color:
                                _isOnline(player)
                                    ? Colors.greenAccent
                                    : Colors.white30,
                            shape:
                                BoxShape.circle,
                          ),
                        ),
                        const SizedBox(
                          width:
                              7,
                        ),
                        Text(
                          _isOnline(player)
                              ? 'En ligne maintenant'
                              : 'Hors ligne',
                          style:
                              TextStyle(
                            color:
                                _isOnline(player)
                                    ? Colors.greenAccent
                                    : Colors.white54,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height:
                          18,
                    ),
                    Text(
                      player.description.isEmpty
                          ? 'Aucune description.'
                          : player.description,
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                      ),
                    ),
                    const SizedBox(
                      height:
                          20,
                    ),
                    _detailLine(
                      Icons.games_rounded,
                      'Jeux',
                      player.games.isEmpty
                          ? 'Non renseignés'
                          : player.games.join(', '),
                    ),
                    const SizedBox(
                      height:
                          10,
                    ),
                    _detailLine(
                      Icons.devices_rounded,
                      'Plateformes',
                      player.platforms.isEmpty
                          ? 'Non renseignées'
                          : player.platforms.join(', '),
                    ),
                    const SizedBox(
                      height:
                          10,
                    ),
                    _detailLine(
                      Icons.favorite_rounded,
                      'Jeux en commun',
                      commonGames.isEmpty
                          ? 'Aucun'
                          : commonGames.join(', '),
                    ),
                    const SizedBox(
                      height:
                          10,
                    ),
                    _detailLine(
                      Icons.link_rounded,
                      'Plateformes communes',
                      commonPlatforms.isEmpty
                          ? 'Aucune'
                          : commonPlatforms.join(', '),
                    ),
                    if (player.availabilityText.isNotEmpty) ...[
                      const SizedBox(
                        height:
                            10,
                      ),
                      _detailLine(
                        Icons.schedule_rounded,
                        'Disponibilités',
                        player.availabilityText,
                      ),
                    ],
                    if (player.networks.isNotEmpty) ...[
                      const SizedBox(
                        height:
                            10,
                      ),
                      _detailLine(
                        Icons.alternate_email_rounded,
                        'Réseaux',
                        player.networks.join('\n'),
                      ),
                    ],
                    const SizedBox(
                      height:
                          20,
                    ),
                    SizedBox(
                      width:
                          double.infinity,
                      child:
                          OutlinedButton.icon(
                        onPressed:
                            inviteSummary.canInvite
                                ? () {
                                    _invitePlayerToTeam(
                                      player,
                                    );
                                  }
                                : null,
                        icon:
                            Icon(
                          inviteSummary.canInvite
                              ? Icons.group_add_rounded
                              : Icons.lock_rounded,
                        ),
                        label:
                            Text(
                          inviteSummary.label,
                          textAlign:
                              TextAlign.center,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        style:
                            OutlinedButton.styleFrom(
                          foregroundColor:
                              Colors.amber,
                          side:
                              const BorderSide(
                            color:
                                Colors.amber,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                      const Text(
                    'FERMER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed:
                      canSendFriendRequest
                          ? () async {
                              final FriendRequestSendResult result =
                                  await FriendService.sendFriendRequest(
                                player.id,
                              );

                              if (!mounted) {
                                return;
                              }

                              final String message;

                              switch (result) {
                                case FriendRequestSendResult.sent:
                                  message =
                                      'Demande d’ami envoyée à ${player.name}.';
                                  break;
                                case FriendRequestSendResult.alreadyPending:
                                  message =
                                      'Une demande est déjà en attente.';
                                  break;
                                case FriendRequestSendResult.incomingPending:
                                  message =
                                      '${player.name} t’a déjà envoyé une demande.';
                                  break;
                                case FriendRequestSendResult.alreadyFriends:
                                  message =
                                      'Vous êtes déjà amis.';
                                  break;
                                case FriendRequestSendResult.invalidUser:
                                case FriendRequestSendResult.error:
                                  message =
                                      'Impossible d’envoyer la demande.';
                                  break;
                              }

                              relationship =
                                  await FriendService.getRelationshipState(
                                player.id,
                              );

                              if (dialogContext.mounted) {
                                setDialogState(
                                  () {},
                                );
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(this.context)
                                    .showSnackBar(
                                  SnackBar(
                                    content:
                                        Text(
                                      message,
                                    ),
                                  ),
                                );
                              }
                            }
                          : null,
                  icon:
                      Icon(
                    _relationshipIcon(
                      relationship,
                    ),
                  ),
                  label:
                      Text(
                    _relationshipLabel(
                      relationship,
                    ),
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.amber,
                    foregroundColor:
                        Colors.black,
                    disabledBackgroundColor:
                        Colors.white12,
                    disabledForegroundColor:
                        Colors.white54,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _relationshipIcon(
    FriendRelationshipState relationship,
  ) {
    switch (relationship) {
      case FriendRelationshipState.none:
        return Icons.person_add_alt_1_rounded;
      case FriendRelationshipState.outgoingPending:
        return Icons.hourglass_top_rounded;
      case FriendRelationshipState.incomingPending:
        return Icons.mark_email_unread_rounded;
      case FriendRelationshipState.friends:
        return Icons.people_alt_rounded;
      case FriendRelationshipState.self:
        return Icons.person_rounded;
    }
  }

  String _relationshipLabel(
    FriendRelationshipState relationship,
  ) {
    switch (relationship) {
      case FriendRelationshipState.none:
        return 'AJOUTER EN AMI';
      case FriendRelationshipState.outgoingPending:
        return 'DEMANDE ENVOYÉE';
      case FriendRelationshipState.incomingPending:
        return 'DEMANDE REÇUE';
      case FriendRelationshipState.friends:
        return 'DÉJÀ AMIS';
      case FriendRelationshipState.self:
        return 'TON PROFIL';
    }
  }

  Widget _detailLine(
    IconData icon,
    String title,
    String value,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color:
              Colors.amber,
          size:
              21,
        ),
        const SizedBox(
          width:
              10,
        ),
        Expanded(
          child:
              RichText(
            text:
                TextSpan(
              children: [
                TextSpan(
                  text:
                      '$title : ',
                  style:
                      const TextStyle(
                    color:
                        Colors.amber,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text:
                      value,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


}

// =============================================================================
// CARTE JOUEUR
// =============================================================================

class _PlayerCard
    extends StatelessWidget {
  final _Player player;
  final int? compatibility;
  final bool online;
  final List<String> commonGames;
  final List<String> commonPlatforms;
  final VoidCallback onTap;

  const _PlayerCard({
    required this.player,
    required this.compatibility,
    required this.online,
    required this.commonGames,
    required this.commonPlatforms,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom:
            14,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(0xff2b1a12),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              const Color(0xffffc857),
          width:
              1.25,
        ),
      ),
      child:
          Material(
        color:
            Colors.transparent,
        child:
            InkWell(
          onTap:
              onTap,
          borderRadius:
              BorderRadius.circular(
            16,
          ),
          child:
              Padding(
            padding:
                const EdgeInsets.fromLTRB(
              12,
              13,
              8,
              13,
            ),
            child:
                Column(
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width:
                          58,
                      child:
                          Column(
                        children: [
                          _CompatibilityBadge(
                            percentage:
                                compatibility,
                            size:
                                45,
                          ),
                          const SizedBox(
                            height:
                                2,
                          ),
                          Text(
                            compatibility == null
                                ? '--'
                                : '$compatibility%',
                            style:
                                const TextStyle(
                              color:
                                  Colors.amber,
                              fontSize:
                                  11,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width:
                          8,
                    ),
                    Expanded(
                      child:
                          Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Text(
                            player.name,
                            textAlign:
                                TextAlign.center,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontSize:
                                  19,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height:
                                7,
                          ),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Container(
                                width:
                                    8,
                                height:
                                    8,
                                decoration:
                                    BoxDecoration(
                                  color:
                                      online
                                          ? Colors.greenAccent
                                          : Colors.white30,
                                  shape:
                                      BoxShape.circle,
                                ),
                              ),
                              const SizedBox(
                                width:
                                    5,
                              ),
                              Flexible(
                                child:
                                    Text(
                                  online
                                      ? 'En ligne'
                                      : 'Hors ligne',
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style:
                                      TextStyle(
                                    color:
                                        online
                                            ? Colors.greenAccent
                                            : Colors.white54,
                                    fontSize:
                                        11,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (commonGames.isNotEmpty) ...[
                            const SizedBox(
                              height:
                                  6,
                            ),
                            Text(
                              commonGames.length == 1
                                  ? '1 jeu en commun'
                                  : '${commonGames.length} jeux en commun',
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white70,
                                fontSize:
                                    11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(
                      width:
                          4,
                    ),
                    SizedBox(
                      width:
                          84,
                      height:
                          110,
                      child:
                          Align(
                        alignment:
                            Alignment.bottomCenter,
                        child:
                            _PlayerAvatar(
                          player:
                              player,
                          size:
                              74,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height:
                      9,
                ),
                Align(
                  alignment:
                      Alignment.centerLeft,
                  child:
                      Wrap(
                    spacing:
                        6,
                    runSpacing:
                        6,
                    children:
                        player.games
                            .take(
                              4,
                            )
                            .map(
                              (
                                String game,
                              ) =>
                                  _Tag(
                                icon:
                                    Icons.games_rounded,
                                text:
                                    game,
                              ),
                            )
                            .toList(),
                  ),
                ),
                if (player.games.isNotEmpty)
                  const SizedBox(
                    height:
                        8,
                  ),
                Row(
                  children: [
                    const Icon(
                      Icons.devices_rounded,
                      color:
                          Colors.amber,
                      size:
                          17,
                    ),
                    const SizedBox(
                      width:
                          6,
                    ),
                    Expanded(
                      child:
                          Text(
                        player.platforms.isEmpty
                            ? 'Plateformes non renseignées'
                            : player.platforms.join('  |  '),
                        style:
                            const TextStyle(
                          color:
                              Colors.white70,
                          fontSize:
                              12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height:
                      9,
                ),
                Row(
                  children: [
                    Icon(
                      commonPlatforms.isNotEmpty
                          ? Icons.link_rounded
                          : commonGames.isNotEmpty
                              ? Icons.compare_arrows_rounded
                              : Icons.link_off_rounded,
                      color:
                          commonPlatforms.isNotEmpty
                              ? Colors.greenAccent
                              : commonGames.isNotEmpty
                                  ? Colors.amber
                                  : Colors.white38,
                      size:
                          17,
                    ),
                    const SizedBox(
                      width:
                          6,
                    ),
                    Expanded(
                      child:
                          Text(
                        commonPlatforms.isNotEmpty
                            ? 'Plateforme commune : ${commonPlatforms.first}'
                            : commonGames.isNotEmpty
                                ? 'Jeu commun, plateformes différentes'
                                : 'Aucun jeu commun',
                        style:
                            TextStyle(
                          color:
                              commonPlatforms.isNotEmpty
                                  ? Colors.greenAccent
                                  : commonGames.isNotEmpty
                                      ? Colors.amber
                                      : Colors.white38,
                          fontSize:
                              12,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color:
                          Colors.amber,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// COMPATIBILITÉ
// =============================================================================

class _CompatibilityBadge
    extends StatelessWidget {
  final int? percentage;
  final double size;

  const _CompatibilityBadge({
    required this.percentage,
    required this.size,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final int? value =
        percentage;

    if (value == null) {
      return SizedBox(
        width:
            size,
        height:
            size,
        child:
            CustomPaint(
          painter:
              _HeartPainter(
            fill:
                0,
          ),
          child:
              const Center(
            child:
                Icon(
              Icons.question_mark_rounded,
              color:
                  Colors.amber,
              size:
                  17,
            ),
          ),
        ),
      );
    }

    return _AnimatedHeart(
      percentage:
          value,
      size:
          size,
    );
  }
}

class _AnimatedHeart
    extends StatefulWidget {
  final int percentage;
  final double size;

  const _AnimatedHeart({
    required this.percentage,
    required this.size,
  });

  @override
  State<_AnimatedHeart> createState() =>
      _AnimatedHeartState();
}

class _AnimatedHeartState
    extends State<_AnimatedHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fillAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync:
          this,
      duration:
          const Duration(
        milliseconds:
            1100,
      ),
    );

    _fillAnimation =
        Tween<double>(
      begin:
          0,
      end:
          widget.percentage / 100,
    ).animate(
      CurvedAnimation(
        parent:
            _controller,
        curve:
            Curves.easeOutCubic,
      ),
    );

    _scaleAnimation =
        Tween<double>(
      begin:
          1,
      end:
          1.08,
    ).animate(
      CurvedAnimation(
        parent:
            _controller,
        curve:
            const Interval(
          0.85,
          1,
          curve:
              Curves.elasticOut,
        ),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AnimatedBuilder(
      animation:
          _controller,
      builder:
          (
        BuildContext context,
        Widget? child,
      ) {
        return Transform.scale(
          scale:
              _scaleAnimation.value,
          child:
              SizedBox(
            width:
                widget.size,
            height:
                widget.size,
            child:
                CustomPaint(
              painter:
                  _HeartPainter(
                fill:
                    _fillAnimation.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeartPainter
    extends CustomPainter {
  final double fill;

  _HeartPainter({
    required this.fill,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final Path path =
        Path();

    final double w =
        size.width;

    final double h =
        size.height;

    path.moveTo(
      w * 0.5,
      h * 0.9,
    );

    path.cubicTo(
      w * 0.35,
      h * 0.72,
      w * 0.08,
      h * 0.56,
      w * 0.08,
      h * 0.3,
    );

    path.cubicTo(
      w * 0.08,
      h * 0.08,
      w * 0.38,
      h * 0.02,
      w * 0.5,
      h * 0.2,
    );

    path.cubicTo(
      w * 0.62,
      h * 0.02,
      w * 0.92,
      h * 0.08,
      w * 0.92,
      h * 0.3,
    );

    path.cubicTo(
      w * 0.92,
      h * 0.56,
      w * 0.65,
      h * 0.72,
      w * 0.5,
      h * 0.9,
    );

    path.close();

    final Paint outlinePaint =
        Paint()
          ..color =
              Colors.amber
          ..style =
              PaintingStyle.stroke
          ..strokeWidth =
              3;

    canvas.drawPath(
      path,
      outlinePaint,
    );

    canvas.save();

    canvas.clipPath(
      path,
    );

    final double safeFill =
        fill.clamp(
          0.0,
          1.0,
        ).toDouble();

    final double fillHeight =
        h * safeFill;

    final Paint fillPaint =
        Paint()
          ..color =
              Colors.redAccent
          ..style =
              PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(
        0,
        h - fillHeight,
        w,
        fillHeight,
      ),
      fillPaint,
    );

    canvas.restore();

    canvas.drawPath(
      path,
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _HeartPainter oldDelegate,
  ) {
    return oldDelegate.fill !=
        fill;
  }
}

// =============================================================================
// AVATAR PUBLIC
// =============================================================================

class _PlayerAvatar
    extends StatelessWidget {
  final _Player player;
  final double size;

  const _PlayerAvatar({
    required this.player,
    required this.size,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final String imageUrl =
        player.avatarUrl.trim();

    if (imageUrl.isNotEmpty) {
      return Container(
        width:
            size,
        height:
            size * 1.25,
        decoration:
            BoxDecoration(
          color:
              const Color(0xff160e09),
          borderRadius:
              BorderRadius.circular(
            14,
          ),
          border:
              Border.all(
            color:
                Colors.amber,
          ),
        ),
        clipBehavior:
            Clip.antiAlias,
        child:
            Image.network(
          imageUrl,
          fit:
              BoxFit.cover,
          errorBuilder:
              (
            BuildContext context,
            Object error,
            StackTrace? stackTrace,
          ) {
            return _fallback();
          },
        ),
      );
    }

    final AvatarModel? avatar =
        player.avatar;

    if (avatar != null) {
      return SizedBox(
        width:
            size,
        height:
            size * 1.25,
        child:
            FittedBox(
          fit:
              BoxFit.contain,
          child:
              AvatarRenderer(
            avatar:
                avatar,
            size:
                size,
            showFrame:
                false,
            compactHeadCrop:
                true,
          ),
        ),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    final String initial =
        player.name.trim().isEmpty
            ? '?'
            : player.name
                .trim()
                .substring(
                  0,
                  1,
                )
                .toUpperCase();

    return Container(
      width:
          size,
      height:
          size,
      alignment:
          Alignment.center,
      decoration:
          BoxDecoration(
        color:
            const Color(0xff6B4226),
        shape:
            BoxShape.circle,
        border:
            Border.all(
          color:
              Colors.amber,
          width:
              2,
        ),
      ),
      child:
          Text(
        initial,
        style:
            TextStyle(
          color:
              Colors.white,
          fontSize:
              size * 0.35,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }
}

// =============================================================================
// TAG
// =============================================================================

class _Tag
    extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Tag({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal:
            8,
        vertical:
            5,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(0xff6B4226),
        borderRadius:
            BorderRadius.circular(
          10,
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                Colors.amber,
            size:
                14,
          ),
          const SizedBox(
            width:
                4,
          ),
          Text(
            text,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontSize:
                  11,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODÈLE D'ÉCRAN
// =============================================================================

class _Player {
  final String id;
  final String name;
  final List<String> games;
  final List<String> platforms;
  final String description;
  final List<String> networks;
  final Map<String, List<String>> availability;
  final String avatarUrl;
  final AvatarModel? avatar;

  const _Player({
    required this.id,
    required this.name,
    required this.games,
    required this.platforms,
    required this.description,
    required this.networks,
    required this.availability,
    required this.avatarUrl,
    required this.avatar,
  });

  factory _Player.fromPublicProfile(
    Map<String, dynamic> source,
  ) {
    final String id =
        source['id']?.toString().trim() ?? '';

    final String name =
        source['display_name']?.toString().trim() ?? '';

    final Map<String, dynamic> publicData =
        _readMap(
          source['public_profile_data'],
        ) ??
        <String, dynamic>{};

    final List<String> games =
        _readStringList(
      publicData['games'],
    );

    final List<String> platforms =
        _readPlatformNames(
      publicData['platforms'],
    );

    final List<String> networks =
        _readNetworks(
      publicData['networks'],
    );

    final Map<String, List<String>> availability =
        _readAvailability(
      publicData['availability'],
    );

    final Map<String, dynamic>? avatarData =
        _readMap(
      source['avatar_data'],
    );

    return _Player(
      id:
          id,
      name:
          name.isEmpty
              ? 'Aventurier'
              : name,
      games:
          games,
      platforms:
          platforms,
      description:
          publicData['description']
                  ?.toString()
                  .trim() ??
              '',
      networks:
          networks,
      availability:
          availability,
      avatarUrl:
          source['avatar_url']
                  ?.toString()
                  .trim() ??
              '',
      avatar:
          _avatarFromData(
        id,
        avatarData,
      ),
    );
  }

  String get availabilityText {
    final List<String> lines =
        <String>[];

    for (final MapEntry<String, List<String>> entry
        in availability.entries) {
      if (entry.value.isEmpty) {
        continue;
      }

      lines.add(
        '${entry.key} : ${entry.value.join(', ')}',
      );
    }

    return lines.join('\n');
  }
}

// =============================================================================
// LECTURE DES DONNÉES PUBLIQUES
// =============================================================================

Map<String, dynamic>? _readMap(
  dynamic value,
) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return Map<String, dynamic>.from(
      value,
    );
  }

  return null;
}

class _PlayerInviteSummary {
  const _PlayerInviteSummary({
    required this.canInvite,
    required this.label,
  });

  final bool canInvite;
  final String label;
}

List<String> _readStringList(
  dynamic value,
) {
  if (value is! List) {
    return <String>[];
  }

  final List<String> result =
      <String>[];

  for (final dynamic item
      in value) {
    final String text =
        item.toString().trim();

    if (text.isNotEmpty &&
        !result.contains(text)) {
      result.add(
        text,
      );
    }
  }

  return result;
}

List<String> _readPlatformNames(
  dynamic value,
) {
  if (value is! List) {
    return <String>[];
  }

  final List<String> result =
      <String>[];

  for (final dynamic item
      in value) {
    final String text;

    if (item is Map) {
      text =
          item['nom']
                  ?.toString()
                  .trim() ??
              '';
    } else {
      text =
          item.toString().trim();
    }

    if (text.isNotEmpty &&
        !result.contains(text)) {
      result.add(
        text,
      );
    }
  }

  return result;
}

List<String> _readNetworks(
  dynamic value,
) {
  if (value is! List) {
    return <String>[];
  }

  final List<String> result =
      <String>[];

  for (final dynamic item
      in value) {
    if (item is! Map) {
      continue;
    }

    final String name =
        item['nom']
                ?.toString()
                .trim() ??
            '';

    final String username =
        item['pseudo']
                ?.toString()
                .trim() ??
            '';

    if (name.isEmpty) {
      continue;
    }

    result.add(
      username.isEmpty
          ? name
          : '$name : $username',
    );
  }

  return result;
}

Map<String, List<String>> _readAvailability(
  dynamic value,
) {
  if (value is! Map) {
    return <String, List<String>>{};
  }

  final Map<String, List<String>> result =
      <String, List<String>>{};

  for (final MapEntry<dynamic, dynamic> entry
      in value.entries) {
    result[
        entry.key.toString()] =
        _readStringList(
      entry.value,
    );
  }

  return result;
}

AvatarModel? _avatarFromData(
  String userId,
  Map<String, dynamic>? avatarData,
) {
  if (avatarData == null) {
    return null;
  }

  final String creationMode =
      avatarData['creationMode']
              ?.toString()
              .trim() ??
          '';

  if (creationMode != 'manual') {
    return null;
  }

  final DateTime now =
      DateTime.now();

  try {
    return AvatarModel.fromJson(
      <String, dynamic>{
        'userId':
            userId.isEmpty
                ? 'compagnie-player'
                : userId,
        'creationMode':
            'manual',
        'skin':
            avatarData['skin'],
        'hair':
            avatarData['hair'],
        'beard':
            avatarData['beard'],
        'outfit':
            avatarData['outfit'],
        'accessory':
            avatarData['accessory'],
        'glasses':
            avatarData['glasses'],
        'createdAt':
            now.toIso8601String(),
        'updatedAt':
            now.toIso8601String(),
      },
    );
  } catch (_) {
    return null;
  }
}
