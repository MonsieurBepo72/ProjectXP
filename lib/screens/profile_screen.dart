import 'package:flutter/material.dart';

import 'package:project_xp/models/avatar_model.dart';
import 'package:project_xp/models/game_library_entry.dart';
import 'package:project_xp/screens/avatar/avatar_choice_screen.dart';
import 'package:project_xp/screens/avatar/avatar_edit_screen.dart';
import 'package:project_xp/screens/splash_screen.dart';
import 'package:project_xp/services/auth_service.dart';
import 'package:project_xp/services/avatar_storage.dart';
import 'package:project_xp/services/game_library_service.dart';
import 'package:project_xp/services/profile_storage.dart';
import 'package:project_xp/services/session_service.dart';
import 'package:project_xp/services/tavern_profile_service.dart';
import 'package:project_xp/widgets/avatar_renderer.dart';
import 'package:project_xp/widgets/brand_icon.dart';
import 'package:project_xp/widgets/game_cover_image.dart';

Brand _brandFromString(String value) {
  final String normalized = value.trim().toLowerCase();

  switch (normalized) {
    case 'apple':
    case 'ios':
    case 'iphone':
    case 'ipad':
      return Brand.apple;
    case 'discord':
      return Brand.discord;
    case 'google':
    case 'android':
      return Brand.google;
    case 'steam':
    case 'steam deck':
      return Brand.steam;
    case 'twitch':
      return Brand.twitch;
    case 'xbox':
    case 'xbox one':
    case 'xbox series x/s':
      return Brand.xbox;
    default:
      return Brand.google;
  }
}

class ProfileScreen extends StatefulWidget {
  final bool embedded;

  const ProfileScreen({super.key, this.embedded = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _profileLoaded = false;
  AvatarModel? _avatar;

  String pseudo = '';
  String description = '';
  String chatColor = '#C56CFF';

  List<GameLibraryEntry> _library = <GameLibraryEntry>[];
  List<GamingActivityEvent> _recentActivity = <GamingActivityEvent>[];

  // Anciennes données du profil conservées pour compatibilité.
  // Elles ne sont plus affichées : la Bibliothèque et COMPTES sont désormais
  // les sources officielles pour les jeux et plateformes.
  final List<String> _legacyGames = <String>[];
  final List<Map<String, String>> _legacyPlatforms = <Map<String, String>>[];

  static const List<Map<String, String>> _chatColors = <Map<String, String>>[
    {'name': 'Violet arcanique', 'hex': '#C56CFF'},
    {'name': 'Or héroïque', 'hex': '#FFCF5E'},
    {'name': 'Vert rôdeur', 'hex': '#65CE72'},
    {'name': 'Bleu mana', 'hex': '#53A6FF'},
    {'name': 'Orange forge', 'hex': '#FF9B45'},
    {'name': 'Turquoise esprit', 'hex': '#66D5CA'},
    {'name': 'Rose mystique', 'hex': '#FF728D'},
    {'name': 'Rouge dragon', 'hex': '#E86666'},
  ];

  final Map<String, List<String>> disponibilites = <String, List<String>>{
    'Lundi': <String>[],
    'Mardi': <String>[],
    'Mercredi': <String>[],
    'Jeudi': <String>[],
    'Vendredi': <String>[],
    'Samedi': <String>[],
    'Dimanche': <String>[],
  };

  final List<Map<String, String>> reseaux = <Map<String, String>>[];

  static const List<String> _jours = <String>[
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  // ==========================================================================
  // CHARGEMENT
  // ==========================================================================

  Future<void> _loadEverything() async {
    try {
      Future<List<GameLibraryEntry>> loadLibrarySafe() async {
        try {
          return await GameLibraryService.loadCurrentLibraryConsolidated();
        } catch (_) {
          return <GameLibraryEntry>[];
        }
      }

      Future<List<GamingActivityEvent>> loadActivitySafe() async {
        try {
          return await GameLibraryService.loadCurrentActivity();
        } catch (_) {
          return <GamingActivityEvent>[];
        }
      }

      // Profil et identité démarrent ensemble. Dès que l'identifiant est connu,
      // avatar, Bibliothèque et Fil d'aventure se chargent en parallèle.
      final Future<Map<String, dynamic>> profileFuture =
          ProfileStorage.loadProfile();
      final Future<String?> userIdFuture = AuthService.getCurrentUserId();

      final Map<String, dynamic> data = await profileFuture;
      final String? userId = await userIdFuture;

      final List<Object?> loaded = await Future.wait<Object?>(<Future<Object?>>[
        userId == null
            ? Future<AvatarModel?>.value(null)
            : AvatarStorage.loadAvatar(userId),
        loadLibrarySafe(),
        loadActivitySafe(),
      ]);

      final AvatarModel? savedAvatar = loaded[0] as AvatarModel?;
      final List<GameLibraryEntry> library =
          loaded[1] as List<GameLibraryEntry>;
      final List<GamingActivityEvent> activity =
          loaded[2] as List<GamingActivityEvent>;

      if (!mounted) {
        return;
      }

      setState(() {
        pseudo = data['pseudo'] as String? ?? 'Mon aventurier';

        description =
            data['description'] as String? ??
            "Je cherche des compagnons pour partir à l'aventure !";

        chatColor = data['chatColor']?.toString() ?? '#C56CFF';

        _legacyGames
          ..clear()
          ..addAll(
            List<String>.from(data['games'] as List? ?? const <String>[]),
          );

        _legacyPlatforms
          ..clear()
          ..addAll(
            (data['platforms'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map<Map<String, String>>(
                  (item) => Map<String, String>.from(item),
                ),
          );

        disponibilites
          ..clear()
          ..addAll(_normalizeAvailability(data['availability'] as Map?));

        reseaux
          ..clear()
          ..addAll(
            (data['networks'] as List? ?? const <dynamic>[])
                .whereType<Map>()
                .map<Map<String, String>>(
                  (item) => Map<String, String>.from(item),
                ),
          );

        _avatar = savedAvatar;
        _library = library;
        _recentActivity = activity.take(3).toList();
        _profileLoaded = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _profileLoaded = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de charger complètement le profil.'),
        ),
      );
    }
  }

  Map<String, List<String>> _normalizeAvailability(Map? raw) {
    final Map<String, List<String>> result = <String, List<String>>{
      for (final String day in _jours) day: <String>[],
    };

    if (raw == null) {
      return result;
    }

    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final String day = entry.key.toString();
      final dynamic value = entry.value;

      if (!result.containsKey(day) || value is! List) {
        continue;
      }

      result[day] = List<String>.from(value);
    }

    return result;
  }

  // ==========================================================================
  // SAUVEGARDE
  // ==========================================================================

  Future<bool> _saveProfile({
    String? pseudoOverride,
    String? descriptionOverride,
  }) async {
    final bool saved = await ProfileStorage.saveProfile(
      pseudo: pseudoOverride ?? pseudo,
      description: descriptionOverride ?? description,
      games: List<String>.from(_legacyGames),
      platforms: _legacyPlatforms
          .map((item) => Map<String, String>.from(item))
          .toList(),
      availability: disponibilites.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
      networks: reseaux.map((item) => Map<String, String>.from(item)).toList(),
      chatColor: chatColor,
    );

    if (saved) {
      await TavernProfileService.syncCurrentProfile();
    }

    return saved;
  }

  // ==========================================================================
  // STATISTIQUES
  // ==========================================================================

  int get _completedGames =>
      _library.where((game) => game.status == GameStatus.completed).length;

  int get _hundredPercentGames =>
      _library.where((game) => game.bestCompletionPercent == 100).length;

  int get _totalPlaytimeMinutes =>
      _library.fold<int>(0, (sum, game) => sum + game.totalPlaytimeMinutes);

  int get _unlockedAchievements {
    int total = 0;

    for (final GameLibraryEntry game in _library) {
      for (final GamePlatformProfile profile in game.resolvedPlatformProfiles) {
        final GameAchievementSummary summary =
            profile.computedAchievementSummary;

        if (profile.platform == GamePlatform.playstation &&
            summary.unlocked <= 0) {
          total +=
              summary.bronzeUnlocked +
              summary.silverUnlocked +
              summary.goldUnlocked +
              summary.platinumUnlocked;
        } else {
          total += summary.unlocked;
        }
      }
    }

    return total;
  }

  String get _playtimeLabel {
    final double hours = _totalPlaytimeMinutes / 60;

    if (hours >= 100) {
      return '${hours.round()} h';
    }

    return '${hours.toStringAsFixed(1)} h';
  }

  List<_ProfileHighFact> get _highFacts {
    final List<_ProfileHighFact> result = <_ProfileHighFact>[];

    _ProfileHighFact? tier({
      required String emoji,
      required int value,
      required List<({int threshold, String title})> tiers,
      required String Function(int value) currentDetail,
      required String Function(int threshold) nextDetail,
    }) {
      if (value <= 0) {
        return null;
      }

      ({int threshold, String title})? current;
      ({int threshold, String title})? next;

      for (final ({int threshold, String title}) item in tiers) {
        if (value >= item.threshold) {
          current = item;
        } else {
          next = item;
          break;
        }
      }

      current ??= tiers.first;

      final double progress = next == null
          ? 1.0
          : (value / next.threshold).clamp(0.0, 1.0).toDouble();

      return _ProfileHighFact(
        emoji: emoji,
        title: current.title,
        detail: currentDetail(value),
        nextMilestone: next == null
            ? 'Palier ultime atteint'
            : nextDetail(next.threshold),
        progress: progress,
      );
    }

    final _ProfileHighFact? completion = tier(
      emoji: '🏆',
      value: _hundredPercentGames,
      tiers: const <({int threshold, String title})>[
        (threshold: 1, title: 'Premier 100 %'),
        (threshold: 5, title: 'Complétionniste'),
        (threshold: 10, title: 'Maître du 100 %'),
        (threshold: 25, title: 'Légende du 100 %'),
        (threshold: 50, title: 'Mythe du 100 %'),
      ],
      currentDetail: (value) =>
          '$value jeu${value > 1 ? 'x' : ''} complété${value > 1 ? 's' : ''} à 100 %',
      nextDetail: (threshold) => 'Prochain palier : $threshold jeux à 100 %',
    );

    final _ProfileHighFact? achievements = tier(
      emoji: '🔥',
      value: _unlockedAchievements,
      tiers: const <({int threshold, String title})>[
        (threshold: 1, title: 'Premiers succès'),
        (threshold: 100, title: 'Chasseur de succès'),
        (threshold: 500, title: '500e succès'),
        (threshold: 1000, title: '1000e succès'),
        (threshold: 2500, title: 'Collectionneur légendaire'),
        (threshold: 5000, title: 'Archiviste des exploits'),
      ],
      currentDetail: (value) => '$value succès débloqués',
      nextDetail: (threshold) => 'Prochain palier : $threshold succès',
    );

    final _ProfileHighFact? completed = tier(
      emoji: '⚔️',
      value: _completedGames,
      tiers: const <({int threshold, String title})>[
        (threshold: 1, title: 'Première aventure accomplie'),
        (threshold: 10, title: 'Aventurier aguerri'),
        (threshold: 25, title: 'Vétéran'),
        (threshold: 50, title: 'Conquérant'),
        (threshold: 100, title: 'Chroniqueur de mondes'),
      ],
      currentDetail: (value) =>
          '$value jeu${value > 1 ? 'x' : ''} terminé${value > 1 ? 's' : ''}',
      nextDetail: (threshold) => 'Prochain palier : $threshold jeux terminés',
    );

    final int playedHours = (_totalPlaytimeMinutes / 60).floor();
    final _ProfileHighFact? playtime = tier(
      emoji: '💎',
      value: playedHours,
      tiers: const <({int threshold, String title})>[
        (threshold: 1, title: 'Premières heures d’aventure'),
        (threshold: 100, title: 'Cent heures d’aventure'),
        (threshold: 500, title: 'Voyageur infatigable'),
        (threshold: 1000, title: 'Mille heures d’aventure'),
        (threshold: 2500, title: 'Gardien des mondes'),
        (threshold: 5000, title: 'Légende du temps'),
      ],
      currentDetail: (_) => '$_playtimeLabel cumulées sur tes plateformes',
      nextDetail: (threshold) => 'Prochain palier : $threshold h de jeu',
    );

    for (final _ProfileHighFact? fact in <_ProfileHighFact?>[
      completion,
      achievements,
      completed,
      playtime,
    ]) {
      if (fact != null) {
        result.add(fact);
      }
    }

    return result;
  }

  List<GameLibraryEntry> get _showcaseGames {
    final List<GameLibraryEntry> favorites = _library
        .where((game) => game.favorite)
        .toList();

    favorites.sort(
      (a, b) => b.totalPlaytimeMinutes.compareTo(a.totalPlaytimeMinutes),
    );

    return favorites.take(3).toList();
  }

  // ==========================================================================
  // COULEUR DU CHAT
  // ==========================================================================

  String _chatColorLabel() {
    for (final Map<String, String> option in _chatColors) {
      if (option['hex'] == chatColor) {
        return option['name'] ?? 'Couleur personnalisée';
      }
    }

    return 'Couleur personnalisée';
  }

  Color _chatColorValue(String hex) {
    final String clean = hex.replaceFirst('#', '');
    final int? parsed = int.tryParse('FF$clean', radix: 16);

    return Color(parsed ?? 0xffc56cff);
  }

  Future<void> _showChatColorPopup() async {
    String? selected = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff21150e),
          title: const Text(
            'Couleur du chat',
            style: TextStyle(color: Colors.amber),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _chatColors.map((Map<String, String> option) {
                    final String hex = option['hex'] ?? '#C56CFF';
                    final String name = option['name'] ?? '';
                    final bool active = hex == chatColor;
                    final Color color = _chatColorValue(hex);

                    return Tooltip(
                      message: name,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(dialogContext, hex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            border: Border.all(
                              color: active ? Colors.white : Colors.white24,
                              width: active ? 3 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.28),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: active
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, '__custom__'),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('COULEUR PERSONNALISÉE'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );

    if (selected == '__custom__' && mounted) {
      selected = await _showCustomChatColorPopup();
    }

    if (selected == null || selected == chatColor || !mounted) {
      return;
    }

    setState(() {
      chatColor = selected!;
    });

    final bool saved = await ProfileStorage.saveChatColor(chatColor);

    if (saved) {
      await TavernProfileService.syncCurrentProfile();
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1300),
        content: Text(
          saved
              ? 'Couleur du Comptoir mise à jour.'
              : 'Impossible d’enregistrer la couleur.',
        ),
      ),
    );
  }

  Future<String?> _showCustomChatColorPopup() async {
    final String clean = chatColor.replaceFirst('#', '');
    final int initial = int.tryParse(clean, radix: 16) ?? 0xC56CFF;

    double red = ((initial >> 16) & 0xff).toDouble();
    double green = ((initial >> 8) & 0xff).toDouble();
    double blue = (initial & 0xff).toDouble();

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setDialogState,
              ) {
                final int r = red.round().clamp(0, 255).toInt();
                final int g = green.round().clamp(0, 255).toInt();
                final int b = blue.round().clamp(0, 255).toInt();

                final Color preview = Color.fromARGB(255, r, g, b);

                final String hex =
                    ('#${r.toRadixString(16).padLeft(2, '0')}'
                            '${g.toRadixString(16).padLeft(2, '0')}'
                            '${b.toRadixString(16).padLeft(2, '0')}')
                        .toUpperCase();

                Widget slider({
                  required String label,
                  required double value,
                  required ValueChanged<double> onChanged,
                }) {
                  return Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: value,
                          min: 0,
                          max: 255,
                          divisions: 255,
                          onChanged: onChanged,
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          value.round().toString(),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                    ],
                  );
                }

                return AlertDialog(
                  backgroundColor: const Color(0xff21150e),
                  title: const Text(
                    'Couleur personnalisée',
                    style: TextStyle(color: Colors.amber),
                  ),
                  content: SingleChildScrollView(
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            width: double.infinity,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: preview,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.46),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                hex,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          slider(
                            label: 'R',
                            value: red,
                            onChanged: (double value) {
                              setDialogState(() => red = value);
                            },
                          ),
                          slider(
                            label: 'V',
                            value: green,
                            onChanged: (double value) {
                              setDialogState(() => green = value);
                            },
                          ),
                          slider(
                            label: 'B',
                            value: blue,
                            onChanged: (double value) {
                              setDialogState(() => blue = value);
                            },
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'La couleur choisie sera utilisée pour le pseudo, '
                            'l’avatar et le contour des messages.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, hex),
                      child: const Text('Appliquer'),
                    ),
                  ],
                );
              },
        );
      },
    );
  }

  // ==========================================================================
  // AVATAR
  // ==========================================================================

  Future<void> _openAvatarEditor() async {
    final AvatarModel? currentAvatar = _avatar;

    if (currentAvatar == null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => const AvatarChoiceScreen(),
        ),
      );

      if (!mounted) {
        return;
      }

      final String? userId = await AuthService.getCurrentUserId();

      if (userId == null) {
        return;
      }

      final AvatarModel? newAvatar = await AvatarStorage.loadAvatar(userId);

      if (!mounted) {
        return;
      }

      setState(() {
        _avatar = newAvatar;
      });

      return;
    }

    final AvatarModel? result = await Navigator.push<AvatarModel>(
      context,
      MaterialPageRoute<AvatarModel>(
        builder: (context) => AvatarEditScreen(initialAvatar: currentAvatar),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    await AvatarStorage.saveAvatar(result);

    if (!mounted) {
      return;
    }

    setState(() {
      _avatar = result;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Avatar modifié !')));
  }

  // ==========================================================================
  // DÉCONNEXION
  // ==========================================================================

  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: const Text(
            'Déconnexion',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Tu veux vraiment te déconnecter de Project XP ?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                'SE DÉCONNECTER',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await SessionService.logout();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (context) => const SplashScreen()),
      (route) => false,
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    if (!_profileLoaded) {
      final Widget loading = const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );

      if (widget.embedded) {
        return Container(color: const Color(0xff1b120d), child: loading);
      }

      return Scaffold(backgroundColor: const Color(0xff1b120d), body: loading);
    }

    final Widget content = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xff1b120d), Color(0xff120c08)],
        ),
      ),
      child: RefreshIndicator(
        color: Colors.amber,
        onRefresh: _loadEverything,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            _buildIdentityCard(),
            const SizedBox(height: 22),
            _buildSectionTitle(
              icon: Icons.insights_rounded,
              title: 'STATISTIQUES',
              subtitle: 'Ton parcours de joueur en un coup d’œil',
            ),
            const SizedBox(height: 10),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildSectionTitle(
              icon: Icons.emoji_events_rounded,
              title: 'HAUTS FAITS',
              subtitle:
                  'Tes titres d’aventurier et la route vers les prochains paliers',
            ),
            const SizedBox(height: 10),
            _buildHighFacts(),
            const SizedBox(height: 24),
            _buildSectionTitle(
              icon: Icons.star_rounded,
              title: 'VITRINE DU JOUEUR',
              subtitle: 'Tes favoris, choisis dans ta Bibliothèque',
            ),
            const SizedBox(height: 10),
            _buildShowcase(),
            const SizedBox(height: 24),
            _buildSectionTitle(
              icon: Icons.history_rounded,
              title: 'DERNIERS EXPLOITS',
              subtitle: 'Un aperçu de ton unique Fil d’aventure',
            ),
            const SizedBox(height: 10),
            _buildRecentExploits(),
            const SizedBox(height: 24),
            _buildProfileActions(),
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text(
                  'SE DÉCONNECTER',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xff1b120d),
      appBar: AppBar(
        backgroundColor: const Color(0xff5c3317),
        foregroundColor: Colors.amber,
        centerTitle: true,
        title: const Text(
          'MON PROFIL',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.7),
        ),
      ),
      body: content,
    );
  }

  Widget _buildProfileActions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff1a1c1f),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📜  TA FICHE D’AVENTURIER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Bio, avatar, disponibilités, couleur du chat et réseaux.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10.2,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _showProfileSettings,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffffc857),
              foregroundColor: const Color(0xff2b1a12),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            ),
            child: const Text(
              'PERSONNALISER',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xff1d1f22),
            Color(0xff17191c),
            Color(0xff111315),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xffffc857).withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0x55ffc857))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '◆  REGISTRE DE L’AVENTURIER  ◆',
                  style: TextStyle(
                    color: Color(0xffffc857),
                    fontSize: 9.4,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0x55ffc857))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildAvatar(),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NOM D’AVENTURIER',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pseudo,
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 25,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff202326),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.42),
                        ),
                      ),
                      child: const Text(
                        'AVENTURIER PROJECT XP',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9.7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.65,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Ta chronique, tes exploits, ta vitrine.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10.3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              color: const Color(0xff141618),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❝',
                  style: TextStyle(
                    color: Color(0xffffc857),
                    fontSize: 22,
                    height: 0.9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    description.isEmpty ? 'Aucune description.' : description,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.2,
                      height: 1.42,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0x33ffc857))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '◆',
                  style: TextStyle(color: Color(0x99ffc857), fontSize: 10),
                ),
              ),
              Expanded(child: Divider(color: Color(0x33ffc857))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final AvatarModel? avatar = _avatar;

    if (avatar == null) {
      return Container(
        width: 112,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xff1b120d),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.person, color: Colors.amber, size: 56),
      );
    }

    return AvatarRenderer(avatar: avatar, size: 112);
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xff202326),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: Colors.amber, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xff1a1c1f),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.24)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0x33ffc857))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'TABLEAU DE BORD',
                  style: TextStyle(
                    color: Color(0xaaffc857),
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0x33ffc857))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileStatCell(
                  emoji: '🎮',
                  value: '${_library.length}',
                  label: 'Jeux',
                ),
              ),
              const _ProfileStatDivider(),
              Expanded(
                child: _ProfileStatCell(
                  emoji: '🏆',
                  value: '$_unlockedAchievements',
                  label: 'Succès',
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1, color: Colors.white10),
          ),
          Row(
            children: [
              Expanded(
                child: _ProfileStatCell(
                  emoji: '✅',
                  value: '$_completedGames',
                  label: 'Terminés',
                ),
              ),
              const _ProfileStatDivider(),
              Expanded(
                child: _ProfileStatCell(
                  emoji: '⏱️',
                  value: _playtimeLabel,
                  label: 'Temps joué',
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1, color: Colors.white10),
          ),
          _ProfileStatCell(
            emoji: '💯',
            value: '$_hundredPercentGames',
            label: 'Jeu${_hundredPercentGames > 1 ? 'x' : ''} à 100 %',
            centered: true,
          ),
        ],
      ),
    );
  }

  Widget _buildHighFacts() {
    final List<_ProfileHighFact> facts = _highFacts;

    if (facts.isEmpty) {
      return const _EmptyProfileBlock(
        icon: Icons.lock_outline_rounded,
        title: 'Tes hauts faits sont encore à écrire',
        detail:
            'Termine une aventure, débloque des succès ou atteins ton premier 100 %.',
      );
    }

    return Column(
      children: List<Widget>.generate(facts.length, (int index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index + 1 < facts.length ? 10 : 0),
          child: _HighFactCard(fact: facts[index]),
        );
      }),
    );
  }

  Widget _buildShowcase() {
    final List<GameLibraryEntry> games = _showcaseGames;

    if (games.isEmpty) {
      return const _EmptyProfileBlock(
        icon: Icons.star_border_rounded,
        title: 'Ta vitrine est vide',
        detail:
            'Ajoute des jeux en favoris dans ta Bibliothèque pour les mettre en avant ici.',
      );
    }

    return SizedBox(
      height: 154,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return _ShowcaseGameCard(game: games[index]);
        },
      ),
    );
  }

  Widget _buildRecentExploits() {
    if (_recentActivity.isEmpty) {
      return const _EmptyProfileBlock(
        icon: Icons.history_toggle_off_rounded,
        title: 'Aucun exploit récent',
        detail:
            'Le Fil d’aventure se remplira avec tes vraies actions : jeux terminés, succès et accomplissements.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff1a1c1f),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: List<Widget>.generate(_recentActivity.length, (index) {
          final GamingActivityEvent event = _recentActivity[index];

          return Column(
            children: [
              _RecentExploitTile(
                event: event,
                dateLabel: _activityDateLabel(event.createdAt),
              ),
              if (index + 1 < _recentActivity.length)
                const Divider(height: 1, color: Colors.white10),
            ],
          );
        }),
      ),
    );
  }

  String _activityDateLabel(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime target = DateTime(date.year, date.month, date.day);

    final int days = today.difference(target).inDays;

    if (days == 0) {
      return 'Aujourd’hui';
    }

    if (days == 1) {
      return 'Hier';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}';
  }

  // ==========================================================================
  // SOUS-TITRES
  // ==========================================================================

  String _getAvailabilitySubtitle() {
    int total = 0;

    for (final List<String> slots in disponibilites.values) {
      total += slots.length;
    }

    if (total == 0) {
      return 'Aucune disponibilité configurée';
    }

    if (total == 1) {
      return '1 créneau configuré';
    }

    return '$total créneaux configurés';
  }

  String _getNetworksSubtitle() {
    if (reseaux.isEmpty) {
      return 'Aucun réseau configuré';
    }

    if (reseaux.length == 1) {
      return '1 réseau configuré';
    }

    return '${reseaux.length} réseaux configurés';
  }

  void _showProfileSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
            ),
            decoration: const BoxDecoration(
              color: Color(0xff1b120d),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(
                top: BorderSide(color: Color(0xffffc857), width: 1.2),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Text('📜', style: TextStyle(fontSize: 27)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CARNET D’AVENTURIER',
                              style: TextStyle(
                                color: Color(0xffffc857),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.9,
                              ),
                            ),
                            Text(
                              'Personnalise ta fiche sans mélanger profil, bibliothèque et comptes.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10.5,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ProfileOption(
                    icon: '✍️',
                    title: 'IDENTITÉ',
                    subtitle: 'Pseudo et description',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showEditProfilePopup();
                    },
                  ),
                  const SizedBox(height: 10),
                  _ProfileOption(
                    icon: '🧙',
                    title: 'AVATAR',
                    subtitle: _avatar == null
                        ? 'Créer ton aventurier'
                        : 'Modifier ton aventurier',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openAvatarEditor();
                    },
                  ),
                  const SizedBox(height: 10),
                  _ProfileOption(
                    icon: '🕐',
                    title: 'DISPONIBILITÉS',
                    subtitle: _getAvailabilitySubtitle(),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showAvailabilityPopup();
                    },
                  ),
                  const SizedBox(height: 10),
                  _ProfileOption(
                    icon: '🎨',
                    title: 'COULEUR DU CHAT',
                    subtitle: _chatColorLabel(),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showChatColorPopup();
                    },
                  ),
                  const SizedBox(height: 10),
                  _ProfileOption(
                    icon: '🔗',
                    title: 'RÉSEAUX',
                    subtitle: _getNetworksSubtitle(),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showNetworksPopup();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // MODIFIER PROFIL
  // ==========================================================================

  Future<void> _showEditProfilePopup() async {
    String draftPseudo = pseudo;
    String draftDescription = description;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: const Text(
            'MODIFIER MON PROFIL',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: draftPseudo,
                  maxLength: 24,
                  onChanged: (value) {
                    draftPseudo = value;
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Pseudo',
                    helperText:
                        'Un pseudo ne peut appartenir qu’à un seul aventurier.',
                    helperMaxLines: 2,
                    labelStyle: TextStyle(color: Colors.amber),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: draftDescription,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 180,
                  onChanged: (value) {
                    draftDescription = value;
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () async {
                final String newPseudo = draftPseudo.trim();
                final String newDescription = draftDescription.trim();

                if (newPseudo.isEmpty) {
                  return;
                }

                final String? currentUserId =
                    await AuthService.getCurrentUserId();

                final bool available = await AuthService.isUsernameAvailable(
                  newPseudo,
                  excludeUserId: currentUserId,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                if (!available) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Ce pseudo est déjà utilisé.'),
                    ),
                  );
                  return;
                }

                final bool saved = await _saveProfile(
                  pseudoOverride: newPseudo,
                  descriptionOverride: newDescription,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                if (!saved) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Impossible d’utiliser ce pseudo.'),
                    ),
                  );
                  return;
                }

                if (!mounted) {
                  return;
                }

                setState(() {
                  pseudo = newPseudo;
                  description = newDescription;
                });

                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profil sauvegardé !')),
                );
              },
              child: const Text(
                'ENREGISTRER',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // DISPONIBILITÉS
  // ==========================================================================

  void _showAvailabilityPopup() {
    final Map<String, List<String>> workingCopy = <String, List<String>>{
      for (final String day in _jours)
        day: List<String>.from(disponibilites[day] ?? <String>[]),
    };

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              backgroundColor: const Color(0xff2b1a12),
              title: const Text(
                'MES DISPONIBILITÉS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 520,
                child: ListView(
                  children: _jours.map((day) {
                    final List<String> slots = workingCopy[day] ?? <String>[];

                    return _AvailabilityDay(
                      day: day,
                      slots: slots,
                      onAdd: () {
                        if (slots.length >= 3) {
                          return;
                        }

                        setPopupState(() {
                          slots.add('20h -> 23h');
                        });
                      },
                      onRemove: (index) {
                        setPopupState(() {
                          slots.removeAt(index);
                        });
                      },
                      onEditStart: (index) async {
                        await _editAvailabilityTime(
                          context: dialogContext,
                          workingCopy: workingCopy,
                          day: day,
                          index: index,
                          editStart: true,
                          setPopupState: setPopupState,
                        );
                      },
                      onEditEnd: (index) async {
                        await _editAvailabilityTime(
                          context: dialogContext,
                          workingCopy: workingCopy,
                          day: day,
                          index: index,
                          editStart: false,
                          setPopupState: setPopupState,
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'ANNULER',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      disponibilites
                        ..clear()
                        ..addAll(
                          workingCopy.map(
                            (key, value) =>
                                MapEntry(key, List<String>.from(value)),
                          ),
                        );
                    });

                    await _saveProfile();

                    if (!dialogContext.mounted) {
                      return;
                    }

                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'VALIDER',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editAvailabilityTime({
    required BuildContext context,
    required Map<String, List<String>> workingCopy,
    required String day,
    required int index,
    required bool editStart,
    required StateSetter setPopupState,
  }) async {
    final List<String> slots = workingCopy[day] ?? <String>[];

    if (index < 0 || index >= slots.length) {
      return;
    }

    final List<String> parts = slots[index].split('->');

    if (parts.length != 2) {
      return;
    }

    final String start = parts[0].trim();
    final String end = parts[1].trim();

    final TimeOfDay initial = _parseTime(editStart ? start : end);

    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (selected == null) {
      return;
    }

    final String newTime = _formatTime(selected);

    setPopupState(() {
      slots[index] = editStart ? '$newTime -> $end' : '$start -> $newTime';
    });
  }

  TimeOfDay _parseTime(String value) {
    final String cleaned = value
        .replaceAll('h', ':')
        .replaceAll('::', ':')
        .trim();

    final List<String> parts = cleaned.split(':');

    final int hour = int.tryParse(parts.first) ?? 20;

    final int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _formatTime(TimeOfDay time) {
    if (time.minute == 0) {
      return '${time.hour}h';
    }

    final String hour = time.hour.toString().padLeft(2, '0');

    final String minute = time.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  // ==========================================================================
  // RÉSEAUX
  // ==========================================================================

  void _showNetworksPopup() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              backgroundColor: const Color(0xff2b1a12),
              title: const Text(
                'MES RÉSEAUX',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: reseaux.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Aucun réseau configuré.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: reseaux.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final Map<String, String> network = reseaux[index];

                          return _NetworkCard(
                            name: network['nom'] ?? 'Réseau',
                            username: network['pseudo'] ?? '',
                            visibility: network['visibilite'] ?? 'Prive',
                            onEdit: () async {
                              await _showEditNetworkPopup(index);
                              setPopupState(() {});
                            },
                            onDelete: () async {
                              final bool? confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmContext) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xff2b1a12),
                                    title: const Text(
                                      'Supprimer le réseau ?',
                                      style: TextStyle(color: Colors.amber),
                                    ),
                                    content: Text(
                                      'Supprimer ${network['nom']} de ton profil ?',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(confirmContext, false);
                                        },
                                        child: const Text('ANNULER'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(confirmContext, true);
                                        },
                                        child: const Text(
                                          'SUPPRIMER',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (confirmed != true) {
                                return;
                              }

                              setState(() {
                                reseaux.removeAt(index);
                              });

                              await _saveProfile();
                              setPopupState(() {});
                            },
                            onToggleVisibility: () async {
                              setState(() {
                                network['visibilite'] =
                                    network['visibilite'] == 'Visible'
                                    ? 'Prive'
                                    : 'Visible';
                              });

                              await _saveProfile();
                              setPopupState(() {});
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    await _showAddNetworkPopup();
                    setPopupState(() {});
                  },
                  icon: const Icon(Icons.add, color: Colors.amber),
                  label: const Text(
                    'AJOUTER',
                    style: TextStyle(color: Colors.amber),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'FERMER',
                    style: TextStyle(color: Colors.amber),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddNetworkPopup() async {
    String selectedNetwork = 'Discord';
    String draftUsername = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              backgroundColor: const Color(0xff2b1a12),
              title: const Text(
                'AJOUTER UN RÉSEAU',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedNetwork,
                    dropdownColor: const Color(0xff2b1a12),
                    decoration: const InputDecoration(
                      labelText: 'Réseau',
                      labelStyle: TextStyle(color: Colors.amber),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Discord',
                        child: Text('Discord'),
                      ),
                      DropdownMenuItem(
                        value: 'PlayStation',
                        child: Text('PlayStation'),
                      ),
                      DropdownMenuItem(value: 'Xbox', child: Text('Xbox')),
                      DropdownMenuItem(value: 'Steam', child: Text('Steam')),
                      DropdownMenuItem(
                        value: 'Nintendo',
                        child: Text('Nintendo'),
                      ),
                      DropdownMenuItem(
                        value: 'Epic Games',
                        child: Text('Epic Games'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setPopupState(() {
                        selectedNetwork = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: draftUsername,
                    onChanged: (value) {
                      draftUsername = value;
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Pseudo / identifiant',
                      labelStyle: TextStyle(color: Colors.amber),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(dialogContext).unfocus();

                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'ANNULER',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final String username = draftUsername.trim();

                    if (username.isEmpty) {
                      return;
                    }

                    final bool exists = reseaux.any(
                      (item) => item['nom'] == selectedNetwork,
                    );

                    if (exists) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('$selectedNetwork est déjà configuré.'),
                        ),
                      );
                      return;
                    }

                    setState(() {
                      reseaux.add(<String, String>{
                        'nom': selectedNetwork,
                        'pseudo': username,
                        'visibilite': 'Prive',
                      });
                    });

                    await _saveProfile();

                    if (!dialogContext.mounted) {
                      return;
                    }

                    FocusScope.of(dialogContext).unfocus();

                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'AJOUTER',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditNetworkPopup(int index) async {
    if (index < 0 || index >= reseaux.length) {
      return;
    }

    final Map<String, String> network = reseaux[index];

    String draftUsername = network['pseudo'] ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: Text(
            'MODIFIER ${network['nom']}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextFormField(
            initialValue: draftUsername,
            autofocus: true,
            onChanged: (value) {
              draftUsername = value;
            },
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Pseudo / identifiant',
              labelStyle: TextStyle(color: Colors.amber),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () async {
                final String username = draftUsername.trim();

                if (username.isEmpty) {
                  return;
                }

                setState(() {
                  network['pseudo'] = username;
                });

                await _saveProfile();

                if (!dialogContext.mounted) {
                  return;
                }

                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'ENREGISTRER',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// ÉLÉMENTS DU NOUVEAU PROFIL
// =============================================================================

class _ProfileStatCell extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final bool centered;

  const _ProfileStatCell({
    required this.emoji,
    required this.value,
    required this.label,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 23)),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ],
    );

    return centered ? Center(child: content) : content;
  }
}

class _ProfileStatDivider extends StatelessWidget {
  const _ProfileStatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white10,
    );
  }
}

class _ProfileHighFact {
  final String emoji;
  final String title;
  final String detail;
  final String nextMilestone;
  final double progress;

  const _ProfileHighFact({
    required this.emoji,
    required this.title,
    required this.detail,
    required this.nextMilestone,
    required this.progress,
  });
}

class _HighFactCard extends StatelessWidget {
  final _ProfileHighFact fact;

  const _HighFactCard({required this.fact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xff1d1f22), Color(0xff17191c)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 55,
            height: 55,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xff111315),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xffffc857).withValues(alpha: 0.68),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xffffc857).withValues(alpha: 0.08),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Text(fact.emoji, style: const TextStyle(fontSize: 27)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.8,
                    height: 1.18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  fact.detail,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10.7,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: fact.progress,
                    minHeight: 5,
                    backgroundColor: Colors.black26,
                    color: const Color(0xffffc857),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff111315).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.flag_rounded,
                        color: Color(0xffffc857),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fact.nextMilestone,
                          style: const TextStyle(
                            color: Color(0xffffc857),
                            fontSize: 9.8,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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

class _ShowcaseGameCard extends StatelessWidget {
  final GameLibraryEntry game;

  const _ShowcaseGameCard({required this.game});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xff1a1c1f),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.42)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GameCoverImage(
                    game: game,
                    width: 108,
                    height: 108,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xff111315).withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.65),
                        ),
                      ),
                      child: const Text(
                        '★',
                        style: TextStyle(
                          color: Color(0xffffc857),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
              child: Text(
                game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentExploitTile extends StatelessWidget {
  final GamingActivityEvent event;
  final String dateLabel;

  const _RecentExploitTile({required this.event, required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xff202326),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber.withValues(alpha: 0.28)),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.amber,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
                if (event.detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    event.detail.trim(),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProfileBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _EmptyProfileBlock({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff1a1c1f),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white30, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// OPTION DE PROFIL
// =============================================================================

class _ProfileOption extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: const Color(0xff6B4226),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.72),
                width: 1.3,
              ),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.amber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DISPONIBILITÉS
// =============================================================================

class _AvailabilityDay extends StatelessWidget {
  final String day;
  final List<String> slots;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onEditStart;
  final ValueChanged<int> onEditEnd;

  const _AvailabilityDay({
    required this.day,
    required this.slots,
    required this.onAdd,
    required this.onRemove,
    required this.onEditStart,
    required this.onEditEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff1b120d),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: slots.length >= 3 ? null : onAdd,
                icon: const Icon(Icons.add_circle_outline),
                color: Colors.amber,
                tooltip: 'Ajouter un créneau',
              ),
            ],
          ),
          if (slots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Aucun créneau',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ...List<Widget>.generate(
            slots.length,
            (index) => _AvailabilitySlot(
              value: slots[index],
              onEditStart: () => onEditStart(index),
              onEditEnd: () => onEditEnd(index),
              onRemove: () => onRemove(index),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilitySlot extends StatelessWidget {
  final String value;
  final VoidCallback onEditStart;
  final VoidCallback onEditEnd;
  final VoidCallback onRemove;

  const _AvailabilitySlot({
    required this.value,
    required this.onEditStart,
    required this.onEditEnd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> parts = value.split('->');

    final String start = parts.isNotEmpty ? parts[0].trim() : '--';

    final String end = parts.length > 1 ? parts[1].trim() : '--';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xff2b1a12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TimeButton(
              label: 'Début',
              value: start,
              onTap: onEditStart,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: Text('→', style: TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: _TimeButton(label: 'Fin', value: end, onTap: onEditEnd),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xff1b120d),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RÉSEAUX
// =============================================================================

class _NetworkCard extends StatelessWidget {
  final String name;
  final String username;
  final String visibility;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleVisibility;

  const _NetworkCard({
    required this.name,
    required this.username,
    required this.visibility,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    final bool isVisible = visibility == 'Visible';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff1b120d),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: BrandIcon(brand: _brandFromString(name), size: 24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleVisibility,
            tooltip: isVisible ? 'Rendre privé' : 'Rendre visible',
            icon: Icon(
              isVisible ? Icons.visibility : Icons.visibility_off,
              color: isVisible ? Colors.amber : Colors.white38,
            ),
          ),
          PopupMenuButton<String>(
            color: const Color(0xff2b1a12),
            iconColor: Colors.white70,
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              }

              if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Modifier')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
