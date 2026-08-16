import 'package:flutter/material.dart';

import '../services/profile_storage.dart';

class FindPlayersScreen extends StatefulWidget {
  const FindPlayersScreen({super.key});

  @override
  State<FindPlayersScreen> createState() => _FindPlayersScreenState();
}

class _FindPlayersScreenState extends State<FindPlayersScreen> {
  String? selectedGame;
  String? selectedPlatform;
  bool availableNowOnly = false;

  bool isLoadingProfile = true;

  List<String> profileGames = [];
  List<String> profilePlatforms = [];

  // ---------------------------------------------------------------------------
  // JOUEURS DE TEST
  // ---------------------------------------------------------------------------

  final List<_Player> allPlayers = const [
    _Player(
      name: 'ShadowWolf',
      level: 24,
      games: [
        'Minecraft',
        'Rocket League',
      ],
      platforms: [
        'PC',
      ],
      availableNow: true,
      crossPlayGames: [
        'Minecraft',
        'Rocket League',
      ],
      description: 'Toujours partant pour une session chill.',
      avatar: 'warrior',
    ),
    _Player(
      name: 'LunaGaming',
      level: 18,
      games: [
        'Fortnite',
        'Minecraft',
        'Valorant',
      ],
      platforms: [
        'PlayStation 5',
      ],
      availableNow: true,
      crossPlayGames: [
        'Fortnite',
        'Minecraft',
      ],
      description: 'Je cherche une équipe sympa et sans prise de tête.',
      avatar: 'mage',
    ),
    _Player(
      name: 'Thor974',
      level: 31,
      games: [
        'Rocket League',
        'EA Sports FC 26',
      ],
      platforms: [
        'PlayStation 5',
      ],
      availableNow: false,
      crossPlayGames: [
        'Rocket League',
        'EA Sports FC 26',
      ],
      description: 'Joueur régulier, plutôt compétitif.',
      avatar: 'knight',
    ),
    _Player(
      name: 'PixelKnight',
      level: 12,
      games: [
        'Minecraft',
        'Terraria',
      ],
      platforms: [
        'Nintendo Switch',
      ],
      availableNow: true,
      crossPlayGames: [
        'Minecraft',
      ],
      description: 'Construction, exploration et aventure.',
      avatar: 'archer',
    ),
    _Player(
      name: 'DarkPhoenix',
      level: 42,
      games: [
        'Call of Duty',
        'GTA V',
      ],
      platforms: [
        'Xbox Series X/S',
      ],
      availableNow: false,
      crossPlayGames: [
        'Call of Duty',
      ],
      description: 'Dispo pour du multi le soir.',
      avatar: 'rogue',
    ),
    _Player(
      name: 'Nova',
      level: 27,
      games: [
        'Fortnite',
        'Rocket League',
        'Minecraft',
      ],
      platforms: [
        'PC',
        'PlayStation 5',
      ],
      availableNow: true,
      crossPlayGames: [
        'Fortnite',
        'Rocket League',
        'Minecraft',
      ],
      description: 'Je joue surtout en équipe.',
      avatar: 'adventurer',
    ),
  ];

  // ---------------------------------------------------------------------------
  // INITIALISATION
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await ProfileStorage.loadProfile();

      final dynamic gamesData = profile['games'];
      final dynamic platformsData = profile['platforms'];

      final List<String> loadedGames = [];

      if (gamesData is List) {
        for (final game in gamesData) {
          final String gameName = game.toString().trim();

          if (gameName.isNotEmpty && !loadedGames.contains(gameName)) {
            loadedGames.add(gameName);
          }
        }
      }

      final List<String> loadedPlatforms = [];

      if (platformsData is List) {
        for (final platform in platformsData) {
          if (platform is Map) {
            final String platformName =
                platform['nom']?.toString().trim() ?? '';

            if (platformName.isNotEmpty &&
                !loadedPlatforms.contains(platformName)) {
              loadedPlatforms.add(platformName);
            }
          } else {
            final String platformName = platform.toString().trim();

            if (platformName.isNotEmpty &&
                !loadedPlatforms.contains(platformName)) {
              loadedPlatforms.add(platformName);
            }
          }
        }
      }

      if (!mounted) return;

      setState(() {
        profileGames = loadedGames;
        profilePlatforms = loadedPlatforms;
        isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        profileGames = [];
        profilePlatforms = [];
        isLoadingProfile = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // FILTRES
  // ---------------------------------------------------------------------------

  List<String> get availableFilterGames => profileGames;

  List<String> get availableFilterPlatforms => profilePlatforms;

  List<_Player> get filteredPlayers {
    return allPlayers.where((player) {
      if (selectedGame != null &&
          !player.games.contains(selectedGame)) {
        return false;
      }

      if (selectedPlatform != null &&
          !player.platforms.contains(selectedPlatform)) {
        return false;
      }

      if (availableNowOnly && !player.availableNow) {
        return false;
      }

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (isLoadingProfile) {
      return _buildLoadingScreen();
    }

    final players = filteredPlayers;

    return Scaffold(
      backgroundColor: const Color(0xff1b120d),
      appBar: AppBar(
        backgroundColor: const Color(0xff5c3317),
        foregroundColor: Colors.amber,
        centerTitle: true,
        title: const Text(
          'TROUVER DES JOUEURS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showFilters,
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtres',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: players.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        25,
                      ),
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];

                        return _PlayerCard(
                          player: player,
                          profileGames: profileGames,
                          profilePlatforms: profilePlatforms,
                          onTap: () {
                            _showPlayerDetails(player);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ÉCRAN DE CHARGEMENT
  // ---------------------------------------------------------------------------

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xff1b120d),
      appBar: AppBar(
        backgroundColor: const Color(0xff5c3317),
        foregroundColor: Colors.amber,
        centerTitle: true,
        title: const Text(
          'TROUVER DES JOUEURS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const Center(
        child: CircularProgressIndicator(
          color: Colors.amber,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    final List<String> activeFilters = [];

    if (selectedGame != null) {
      activeFilters.add(selectedGame!);
    }

    if (selectedPlatform != null) {
      activeFilters.add(selectedPlatform!);
    }

    if (availableNowOnly) {
      activeFilters.add('Disponible maintenant');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        20,
        16,
        10,
      ),
      child: Column(
        children: [
          const Text(
            'Trouve tes compagnons',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.amber,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${filteredPlayers.length} joueur(s) trouvé(s)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          if (activeFilters.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              alignment: WrapAlignment.center,
              children: activeFilters.map((filter) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff6B4226),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.amber,
                    ),
                  ),
                  child: Text(
                    filter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AUCUN RÉSULTAT
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              color: Colors.amber,
              size: 55,
            ),
            const SizedBox(height: 15),
            const Text(
              'Aucun joueur trouvé',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Essaie de modifier tes filtres.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _resetFilters,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber,
                side: const BorderSide(
                  color: Colors.amber,
                ),
              ),
              child: const Text(
                'RÉINITIALISER LES FILTRES',
              ),
            ),
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
    });
  }

  // ---------------------------------------------------------------------------
  // FILTRES
  // ---------------------------------------------------------------------------

  void _showFilters() {
    String? tempGame = selectedGame;
    String? tempPlatform = selectedPlatform;
    bool tempAvailableNow = availableNowOnly;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff2b1a12),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  25,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Center(
                        child: Text(
                          'FILTRES',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // JEU
                      const Text(
                        'JEU',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String?>(
                        initialValue: tempGame,
                        dropdownColor: const Color(0xff2b1a12),
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xff1b120d),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Tous mes jeux',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                          ...availableFilterGames.map(
                            (game) {
                              return DropdownMenuItem<String?>(
                                value: game,
                                child: Text(game),
                              );
                            },
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() {
                            tempGame = value;
                          });
                        },
                      ),

                      if (availableFilterGames.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          "Aucun jeu n'est encore renseigné dans ton profil.",
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // PLATEFORME
                      const Text(
                        'PLATEFORME',
                        style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String?>(
                        initialValue: tempPlatform,
                        dropdownColor: const Color(0xff2b1a12),
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xff1b120d),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Toutes mes plateformes',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                          ...availableFilterPlatforms.map(
                            (platform) {
                              return DropdownMenuItem<String?>(
                                value: platform,
                                child: Text(platform),
                              );
                            },
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() {
                            tempPlatform = value;
                          });
                        },
                      ),

                      if (availableFilterPlatforms.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          "Aucune plateforme n'est encore renseignée dans ton profil.",
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // DISPONIBILITÉ
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Disponible maintenant',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Afficher uniquement les joueurs disponibles.',
                          style: TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                        value: tempAvailableNow,
                        activeThumbColor: Colors.amber,
                        activeTrackColor: const Color(0xff6B4226),
                        onChanged: (value) {
                          setModalState(() {
                            tempAvailableNow = value;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      // BOUTONS
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempGame = null;
                                  tempPlatform = null;
                                  tempAvailableNow = false;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(
                                  color: Colors.white30,
                                ),
                              ),
                              child: const Text(
                                'RÉINITIALISER',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedGame = tempGame;
                                  selectedPlatform = tempPlatform;
                                  availableNowOnly =
                                      tempAvailableNow;
                                });

                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                              ),
                              child: const Text(
                                'APPLIQUER',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
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

  // ---------------------------------------------------------------------------
  // DÉTAILS JOUEUR
  // ---------------------------------------------------------------------------

  void _showPlayerDetails(_Player player) {
    final int compatibility = _calculateCompatibility(player);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: Text(
            player.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                _PlayerAvatar(
                  type: player.avatar,
                  size: 110,
                ),
                const SizedBox(height: 12),
                _AnimatedHeart(
                  percentage: compatibility,
                  size: 90,
                ),
                const SizedBox(height: 10),
                Text(
                  '$compatibility% de compatibilité',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _compatibilityMessage(compatibility),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  player.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                _detailLine(
                  Icons.games,
                  'Jeux',
                  player.games.join(', '),
                ),

                const SizedBox(height: 10),

                _detailLine(
                  Icons.sports_esports,
                  'Plateformes',
                  player.platforms.join(', '),
                ),

                const SizedBox(height: 10),

                _crossPlayLine(player),

                const SizedBox(height: 10),

                _detailLine(
                  player.availableNow
                      ? Icons.circle
                      : Icons.circle_outlined,
                  'Disponibilité',
                  player.availableNow
                      ? 'Disponible maintenant'
                      : 'Pas disponible maintenant',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'FERMER',
                style: TextStyle(
                  color: Colors.amber,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Demande envoyée à ${player.name}.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('INVITER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailLine(
    IconData icon,
    String title,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.amber,
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title : ',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _crossPlayLine(_Player player) {
    final List<String> compatibleGames = player.crossPlayGames;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          compatibleGames.isNotEmpty
              ? Icons.link
              : Icons.link_off,
          color: compatibleGames.isNotEmpty
              ? Colors.greenAccent
              : Colors.redAccent,
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compatibleGames.isNotEmpty
                    ? 'Cross-play compatible'
                    : 'Pas de cross-play',
                style: TextStyle(
                  color: compatibleGames.isNotEmpty
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (compatibleGames.isNotEmpty)
                Text(
                  compatibleGames.join(', '),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COMPATIBILITÉ
  // ---------------------------------------------------------------------------

  int _calculateCompatibility(_Player player) {
    int score = 0;

    final int commonGames = player.games
        .where(
          (game) => profileGames.contains(game),
        )
        .length;

    if (profileGames.isNotEmpty) {
      final double gameRatio =
          commonGames / profileGames.length;

      score += (gameRatio * 40).round();
    }

    final int commonPlatforms = player.platforms
        .where(
          (platform) => profilePlatforms.contains(platform),
        )
        .length;

    if (profilePlatforms.isNotEmpty) {
      final double platformRatio =
          commonPlatforms / profilePlatforms.length;

      score += (platformRatio * 25).round();
    }

    final bool hasCrossPlay = player.crossPlayGames.any(
      (game) => profileGames.contains(game),
    );

    if (hasCrossPlay) {
      score += 20;
    }

    if (player.availableNow) {
      score += 15;
    }

    return score.clamp(0, 100);
  }

  String _compatibilityMessage(int percentage) {
    if (percentage >= 90) {
      return 'Vous êtes faits pour jouer ensemble !';
    }

    if (percentage >= 75) {
      return 'Une très belle équipe pourrait se former !';
    }

    if (percentage >= 50) {
      return 'Vous avez plusieurs points communs !';
    }

    if (percentage >= 25) {
      return 'Il y a peut-être une belle aventure à tenter !';
    }

    return 'Vous avez encore quelques points à découvrir.';
  }
}

// =============================================================================
// CARTE JOUEUR
// =============================================================================

class _PlayerCard extends StatelessWidget {
  final _Player player;
  final List<String> profileGames;
  final List<String> profilePlatforms;
  final VoidCallback onTap;

  const _PlayerCard({
    required this.player,
    required this.profileGames,
    required this.profilePlatforms,
    required this.onTap,
  });

  int _compatibilityForCard() {
    int score = 0;

    final int commonGames = player.games
        .where(
          (game) => profileGames.contains(game),
        )
        .length;

    if (profileGames.isNotEmpty) {
      score +=
          ((commonGames / profileGames.length) * 40).round();
    }

    final int commonPlatforms = player.platforms
        .where(
          (platform) => profilePlatforms.contains(platform),
        )
        .length;

    if (profilePlatforms.isNotEmpty) {
      score +=
          ((commonPlatforms / profilePlatforms.length) * 25)
              .round();
    }

    final bool hasCrossPlay = player.crossPlayGames.any(
      (game) => profileGames.contains(game),
    );

    if (hasCrossPlay) {
      score += 20;
    }

    if (player.availableNow) {
      score += 15;
    }

    return score.clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final int compatibility = _compatibilityForCard();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xff2b1a12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              14,
              8,
              14,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 58,
                      child: Column(
                        children: [
                          _AnimatedHeart(
                            percentage: compatibility,
                            size: 45,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$compatibility%',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            player.name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Niv. ${player.level}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: player.availableNow
                                      ? Colors.greenAccent
                                      : Colors.white30,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  player.availableNow
                                      ? 'Disponible maintenant'
                                      : 'Pas disponible maintenant',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: player.availableNow
                                        ? Colors.greenAccent
                                        : Colors.white54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 4),

                    SizedBox(
                      width: 92,
                      height: 105,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _PlayerAvatar(
                          type: player.avatar,
                          size: 92,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: player.games.map(
                      (game) {
                        return _Tag(
                          icon: Icons.games,
                          text: game,
                        );
                      },
                    ).toList(),
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.sports_esports,
                      color: Colors.amber,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        player.platforms.join('  |  '),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 9),

                Row(
                  children: [
                    Icon(
                      player.crossPlayGames.isNotEmpty
                          ? Icons.link
                          : Icons.link_off,
                      color: player.crossPlayGames.isNotEmpty
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        player.crossPlayGames.isNotEmpty
                            ? 'Cross-play compatible'
                            : 'Pas de cross-play',
                        style: TextStyle(
                          color: player.crossPlayGames.isNotEmpty
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.amber,
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
// CŒUR DE COMPATIBILITÉ
// =============================================================================

class _AnimatedHeart extends StatefulWidget {
  final int percentage;
  final double size;

  const _AnimatedHeart({
    required this.percentage,
    required this.size,
  });

  @override
  State<_AnimatedHeart> createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<_AnimatedHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fillAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1400,
      ),
    );

    _fillAnimation = Tween<double>(
      begin: 0,
      end: widget.percentage / 100,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 1,
      end: 1.12,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.85,
          1,
          curve: Curves.elasticOut,
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _HeartPainter(
                fill: _fillAnimation.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeartPainter extends CustomPainter {
  final double fill;

  _HeartPainter({
    required this.fill,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final Path path = Path();

    final double w = size.width;
    final double h = size.height;

    path.moveTo(w * 0.5, h * 0.9);

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

    final Paint outlinePaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(
      path,
      outlinePaint,
    );

    canvas.save();

    canvas.clipPath(path);

    final double fillHeight = h * fill;

    final Paint fillPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

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
    return oldDelegate.fill != fill;
  }
}

// =============================================================================
// AVATAR TEMPORAIRE
// =============================================================================

class _PlayerAvatar extends StatelessWidget {
  final String type;
  final double size;

  const _PlayerAvatar({
    required this.type,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;

    switch (type) {
      case 'mage':
        icon = Icons.auto_awesome;
        break;

      case 'knight':
        icon = Icons.shield;
        break;

      case 'archer':
        icon = Icons.architecture;
        break;

      case 'rogue':
        icon = Icons.visibility_off;
        break;

      case 'adventurer':
        icon = Icons.explore;
        break;

      case 'warrior':
      default:
        icon = Icons.person;
        break;
    }

    return SizedBox(
      width: size,
      height: size * 1.15,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            width: size * 0.55,
            height: size * 0.12,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          Container(
            width: size * 0.68,
            height: size * 0.85,
            decoration: BoxDecoration(
              color: const Color(0xff6B4226),
              borderRadius: BorderRadius.circular(
                size * 0.28,
              ),
              border: Border.all(
                color: Colors.amber,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  decoration: BoxDecoration(
                    color: const Color(0xffd69b72),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black45,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: size * 0.22,
                  ),
                ),
                Container(
                  width: size * 0.38,
                  height: size * 0.27,
                  decoration: BoxDecoration(
                    color: const Color(0xff3b2416),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAG JEU
// =============================================================================

class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Tag({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff6B4226),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.amber,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODÈLE JOUEUR
// =============================================================================

class _Player {
  final String name;
  final int level;
  final List<String> games;
  final List<String> platforms;
  final bool availableNow;
  final List<String> crossPlayGames;
  final String description;
  final String avatar;

  const _Player({
    required this.name,
    required this.level,
    required this.games,
    required this.platforms,
    required this.availableNow,
    required this.crossPlayGames,
    required this.description,
    required this.avatar,
  });
}