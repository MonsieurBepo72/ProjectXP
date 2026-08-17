import 'package:flutter/material.dart';

import 'package:project_xp/models/avatar_model.dart';
import 'package:project_xp/screens/avatar/avatar_choice_screen.dart';
import 'package:project_xp/screens/avatar/avatar_edit_screen.dart';
import 'package:project_xp/screens/splash_screen.dart';
import 'package:project_xp/services/auth_service.dart';
import 'package:project_xp/services/avatar_storage.dart';
import 'package:project_xp/services/profile_storage.dart';
import 'package:project_xp/services/session_service.dart';
import 'package:project_xp/widgets/avatar_renderer.dart';
import 'package:project_xp/widgets/brand_icon.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
  });

  @override
  State<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState
    extends State<ProfileScreen> {
  bool _profileLoaded = false;
  AvatarModel? _avatar;

  String pseudo = 'Mon aventurier';

  String description =
      "Je cherche des compagnons pour partir à l'aventure !";

  final List<String> jeux = [
    'Minecraft',
    'Fortnite',
    'Rocket League',
  ];

  final List<Map<String, String>>
      toutesLesPlateformes = [
    {
      'nom': 'PC',
      'logo': 'pc',
    },
    {
      'nom': 'PlayStation 5',
      'logo': 'playstation',
    },
    {
      'nom': 'PlayStation 4',
      'logo': 'playstation',
    },
    {
      'nom': 'Xbox Series X/S',
      'logo': 'xbox',
    },
    {
      'nom': 'Xbox One',
      'logo': 'xbox',
    },
    {
      'nom': 'Nintendo Switch',
      'logo': 'nintendo',
    },
    {
      'nom': 'Nintendo Switch 2',
      'logo': 'nintendo',
    },
    {
      'nom': 'Android',
      'logo': 'android',
    },
    {
      'nom': 'iPhone / iPad',
      'logo': 'apple',
    },
    {
      'nom': 'Steam Deck',
      'logo': 'steamdeck',
    },
  ];

  final List<Map<String, String>> plateformes = [
    {
      'nom': 'PC',
      'logo': 'pc',
    },
    {
      'nom': 'PlayStation 5',
      'logo': 'playstation',
    },
  ];

  final Map<String, List<String>> disponibilites = {
    'Lundi': [
      '20h -> 23h',
    ],
    'Mardi': [
      '20h -> 23h',
    ],
    'Mercredi': [],
    'Jeudi': [
      '20h -> 23h',
    ],
    'Vendredi': [
      '21h -> 00h',
    ],
    'Samedi': [],
    'Dimanche': [],
  };

  final List<Map<String, String>> reseaux = [
    {
      'nom': 'Discord',
      'pseudo': 'MonDiscord',
      'visibilite': 'Prive',
    },
    {
      'nom': 'PlayStation',
      'pseudo': 'MonPSN',
      'visibilite': 'Visible',
    },
    {
      'nom': 'Steam',
      'pseudo': 'MonSteam',
      'visibilite': 'Visible',
    },
  ];

  static const List<String> _jours = [
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
      final Map<String, dynamic> data =
          await ProfileStorage.loadProfile();

      final String? userId =
          await AuthService.getCurrentUserId();

      AvatarModel? savedAvatar;

      if (userId != null) {
        savedAvatar =
            await AvatarStorage.loadAvatar(userId);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        pseudo =
            data['pseudo'] as String? ??
                'Mon aventurier';

        description =
            data['description'] as String? ??
                "Je cherche des compagnons pour partir à l'aventure !";

        jeux
          ..clear()
          ..addAll(
            List<String>.from(
              data['games'] as List? ?? [],
            ),
          );

        plateformes
          ..clear()
          ..addAll(
            (data['platforms'] as List? ?? [])
                .map<Map<String, String>>(
              (item) =>
                  Map<String, String>.from(
                item as Map,
              ),
            ),
          );

        disponibilites
          ..clear()
          ..addAll(
            _normalizeAvailability(
              data['availability'] as Map?,
            ),
          );

        reseaux
          ..clear()
          ..addAll(
            (data['networks'] as List? ?? [])
                .map<Map<String, String>>(
              (item) =>
                  Map<String, String>.from(
                item as Map,
              ),
            ),
          );

        _avatar = savedAvatar;
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
          content: Text(
            'Impossible de charger le profil.',
          ),
        ),
      );
    }
  }

  Map<String, List<String>>
      _normalizeAvailability(
    Map? raw,
  ) {
    final Map<String, List<String>> result = {
      for (final String day in _jours)
        day: <String>[],
    };

    if (raw == null) {
      return result;
    }

    for (final MapEntry<dynamic, dynamic> entry
        in raw.entries) {
      final String day =
          entry.key.toString();

      final dynamic value = entry.value;

      if (!result.containsKey(day) ||
          value is! List) {
        continue;
      }

      result[day] =
          List<String>.from(value);
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
    return ProfileStorage.saveProfile(
      pseudo:
          pseudoOverride ?? pseudo,
      description:
          descriptionOverride ??
              description,
      games: List<String>.from(jeux),
      platforms: plateformes
          .map(
            (item) =>
                Map<String, String>.from(
              item,
            ),
          )
          .toList(),
      availability:
          disponibilites.map(
        (key, value) => MapEntry(
          key,
          List<String>.from(value),
        ),
      ),
      networks: reseaux
          .map(
            (item) =>
                Map<String, String>.from(
              item,
            ),
          )
          .toList(),
    );
  }

  // ==========================================================================
  // AVATAR
  // ==========================================================================

  Future<void> _openAvatarEditor() async {
    final AvatarModel? currentAvatar =
        _avatar;

    if (currentAvatar == null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) =>
              const AvatarChoiceScreen(),
        ),
      );

      if (!mounted) {
        return;
      }

      final String? userId =
          await AuthService.getCurrentUserId();

      if (userId == null) {
        return;
      }

      final AvatarModel? newAvatar =
          await AvatarStorage.loadAvatar(
        userId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _avatar = newAvatar;
      });

      return;
    }

    final AvatarModel? result =
        await Navigator.push<AvatarModel>(
      context,
      MaterialPageRoute<AvatarModel>(
        builder: (context) =>
            AvatarEditScreen(
          initialAvatar:
              currentAvatar,
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    await AvatarStorage.saveAvatar(
      result,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _avatar = result;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Avatar modifié !',
        ),
      ),
    );
  }

  // ==========================================================================
  // DÉCONNEXION
  // ==========================================================================

  Future<void> _logout() async {
    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: const Text(
            'Déconnexion',
            style: TextStyle(
              color: Colors.amber,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: const Text(
            'Tu veux vraiment te déconnecter de Project XP ?',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'SE DÉCONNECTER',
                style: TextStyle(
                  color:
                      Colors.redAccent,
                  fontWeight:
                      FontWeight.bold,
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

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) =>
            const SplashScreen(),
      ),
      (route) => false,
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (!_profileLoaded) {
      return const Scaffold(
        backgroundColor:
            Color(0xff1b120d),
        body: Center(
          child:
              CircularProgressIndicator(
            color: Colors.amber,
          ),
        ),
      );
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
          'MON PROFIL',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 25,
          ),
          child: Column(
            children: [
              _buildAvatar(),

              const SizedBox(
                height: 18,
              ),

              Text(
                pseudo,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Colors.amber,
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              const Text(
                'Niveau 1 - Aventurier',
                style: TextStyle(
                  color:
                      Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  18,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xff2b1a12,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    15,
                  ),
                  border:
                      Border.all(
                    color:
                        Colors.amber,
                  ),
                ),
                child: Text(
                  description.isEmpty
                      ? 'Aucune description.'
                      : description,
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),

              const SizedBox(
                height: 25,
              ),

              _ProfileOption(
                icon: '🎮',
                title: 'MES JEUX',
                subtitle:
                    '${jeux.length} jeu${jeux.length > 1 ? 'x' : ''} sélectionné${jeux.length > 1 ? 's' : ''}',
                onTap:
                    _showGamesPopup,
              ),

              const SizedBox(
                height: 15,
              ),

              _ProfileOption(
                icon: '🕹️',
                title:
                    'MES PLATEFORMES',
                subtitle:
                    '${plateformes.length} plateforme${plateformes.length > 1 ? 's' : ''}',
                onTap:
                    _showPlatformsPopup,
              ),

              const SizedBox(
                height: 15,
              ),

              _ProfileOption(
                icon: '🕐',
                title:
                    'MES DISPONIBILITÉS',
                subtitle:
                    _getAvailabilitySubtitle(),
                onTap:
                    _showAvailabilityPopup,
              ),

              const SizedBox(
                height: 15,
              ),

              _ProfileOption(
                icon: '🔗',
                title:
                    'MES RÉSEAUX',
                subtitle:
                    _getNetworksSubtitle(),
                onTap:
                    _showNetworksPopup,
              ),

              const SizedBox(
                height: 30,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _showEditProfilePopup,
                  icon: const Icon(
                    Icons.edit,
                  ),
                  label: const Text(
                    'MODIFIER MON PROFIL',
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        Colors.amber,
                    side:
                        const BorderSide(
                      color:
                          Colors.amber,
                    ),
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _openAvatarEditor,
                  icon: const Icon(
                    Icons.face_retouching_natural,
                  ),
                  label: Text(
                    _avatar == null
                        ? 'CRÉER MON AVATAR'
                        : 'MODIFIER MON AVATAR',
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        Colors.amber,
                    side:
                        const BorderSide(
                      color:
                          Colors.amber,
                    ),
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 25,
              ),

              const Divider(
                color:
                    Colors.white12,
              ),

              const SizedBox(
                height: 18,
              ),

              SizedBox(
                width:
                    double.infinity,
                height: 52,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _logout,
                  icon: const Icon(
                    Icons.logout,
                  ),
                  label: const Text(
                    'SE DÉCONNECTER',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        Colors.redAccent,
                    side:
                        const BorderSide(
                      color:
                          Colors.redAccent,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              TextButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                icon:
                    const Icon(
                  Icons.home,
                ),
                label:
                    const Text(
                  'Retour au Compagnie',
                ),
                style:
                    TextButton.styleFrom(
                  foregroundColor:
                      Colors.white70,
                ),
              ),

              const SizedBox(
                height: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final AvatarModel? avatar =
        _avatar;

    if (avatar == null) {
      return Container(
        width: 120,
        height: 150,
        decoration: BoxDecoration(
          color:
              const Color(0xff2b1a12),
          borderRadius:
              BorderRadius.circular(
            20,
          ),
          border: Border.all(
            color: Colors.amber,
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.person,
          color: Colors.amber,
          size: 58,
        ),
      );
    }

    return AvatarRenderer(
      avatar: avatar,
      size: 120,
    );
  }

  // ==========================================================================
  // SOUS-TITRES
  // ==========================================================================

  String _getAvailabilitySubtitle() {
    int total = 0;

    for (final List<String> slots
        in disponibilites.values) {
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
          backgroundColor:
              const Color(0xff2b1a12),
          title: const Text(
            'MODIFIER MON PROFIL',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color: Colors.amber,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content:
              SingleChildScrollView(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue:
                      draftPseudo,
                  maxLength: 24,
                  onChanged: (value) {
                    draftPseudo = value;
                  },
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Pseudo',
                    helperText:
                        'Un pseudo ne peut appartenir qu’à un seul aventurier.',
                    helperMaxLines: 2,
                    labelStyle:
                        TextStyle(
                      color:
                          Colors.amber,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                TextFormField(
                  initialValue:
                      draftDescription,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 180,
                  onChanged: (value) {
                    draftDescription =
                        value;
                  },
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Description',
                    labelStyle:
                        TextStyle(
                      color:
                          Colors.amber,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(
                  dialogContext,
                ).unfocus();

                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(
                  color:
                      Colors.white70,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final String newPseudo =
                    draftPseudo.trim();

                final String newDescription =
                    draftDescription.trim();

                if (newPseudo.isEmpty) {
                  return;
                }

                final String? currentUserId =
                    await AuthService
                        .getCurrentUserId();

                final bool available =
                    await AuthService
                        .isUsernameAvailable(
                  newPseudo,
                  excludeUserId:
                      currentUserId,
                );

                if (!dialogContext
                    .mounted) {
                  return;
                }

                if (!available) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ce pseudo est déjà utilisé.',
                      ),
                    ),
                  );
                  return;
                }

                final bool saved =
                    await _saveProfile(
                  pseudoOverride:
                      newPseudo,
                  descriptionOverride:
                      newDescription,
                );

                if (!dialogContext
                    .mounted) {
                  return;
                }

                if (!saved) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Impossible d’utiliser ce pseudo.',
                      ),
                    ),
                  );
                  return;
                }

                if (!mounted) {
                  return;
                }

                setState(() {
                  pseudo = newPseudo;
                  description =
                      newDescription;
                });

                FocusScope.of(
                  dialogContext,
                ).unfocus();

                Navigator.pop(
                  dialogContext,
                );

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Profil sauvegardé !',
                    ),
                  ),
                );
              },
              child: const Text(
                'ENREGISTRER',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // JEUX
  // ==========================================================================

  void _showGamesPopup() {
    final Set<String> selectedGames =
        jeux.toSet();

    const List<String> allGames = [
      'Minecraft',
      'Fortnite',
      'Rocket League',
      'Call of Duty',
      'GTA V',
      'GTA VI',
      'Valorant',
      'League of Legends',
      'Overwatch 2',
      'Apex Legends',
      'Counter-Strike 2',
      'EA Sports FC 26',
      'FIFA',
      'The Sims 4',
      'Among Us',
      'Roblox',
      'Fall Guys',
      'Terraria',
      'Palworld',
      'Helldivers 2',
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setPopupState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(
                0xff2b1a12,
              ),
              title: const Text(
                'MES JEUX',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width:
                    double.maxFinite,
                height: 430,
                child:
                    ListView.separated(
                  itemCount:
                      allGames.length,
                  separatorBuilder:
                      (_, _) =>
                          const SizedBox(
                    height: 8,
                  ),
                  itemBuilder:
                      (context, index) {
                    final String game =
                        allGames[index];

                    final bool selected =
                        selectedGames
                            .contains(
                      game,
                    );

                    return InkWell(
                      borderRadius:
                          BorderRadius
                              .circular(
                        12,
                      ),
                      onTap: () {
                        setPopupState(
                          () {
                            if (selected) {
                              selectedGames
                                  .remove(
                                game,
                              );
                            } else {
                              selectedGames
                                  .add(
                                game,
                              );
                            }
                          },
                        );
                      },
                      child:
                          AnimatedContainer(
                        duration:
                            const Duration(
                          milliseconds:
                              150,
                        ),
                        padding:
                            const EdgeInsets
                                .all(
                          10,
                        ),
                        decoration:
                            BoxDecoration(
                          color: selected
                              ? const Color(
                                  0xff6B4226,
                                )
                              : const Color(
                                  0xff1b120d,
                                ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                          border:
                              Border.all(
                            color: selected
                                ? Colors
                                    .amber
                                : Colors
                                    .white24,
                            width:
                                selected
                                    ? 2
                                    : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(
                                child:
                                    BrandIcon(
                                  brand:
                                      game,
                                  size:
                                      24,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child: Text(
                                game,
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons
                                      .check_circle
                                  : Icons
                                      .radio_button_unchecked,
                              color: selected
                                  ? Colors
                                      .amber
                                  : Colors
                                      .white30,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedGames
                        .isEmpty) {
                      return;
                    }

                    setState(() {
                      jeux
                        ..clear()
                        ..addAll(
                          selectedGames,
                        );
                    });

                    await _saveProfile();

                    if (!dialogContext
                        .mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'VALIDER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
                      fontWeight:
                          FontWeight.bold,
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

  // ==========================================================================
  // PLATEFORMES
  // ==========================================================================

  void _showPlatformsPopup() {
    final Set<String>
        selectedPlatforms =
        plateformes
            .map(
              (item) =>
                  item['nom']!,
            )
            .toSet();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setPopupState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(
                0xff2b1a12,
              ),
              title: const Text(
                'MES PLATEFORMES',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width:
                    double.maxFinite,
                height: 430,
                child:
                    GridView.builder(
                  itemCount:
                      toutesLesPlateformes
                          .length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing:
                        10,
                    mainAxisSpacing: 10,
                    childAspectRatio:
                        1.55,
                  ),
                  itemBuilder:
                      (context, index) {
                    final Map<String,
                            String>
                        platform =
                        toutesLesPlateformes[
                            index];

                    final String name =
                        platform['nom']!;

                    final bool selected =
                        selectedPlatforms
                            .contains(
                      name,
                    );

                    return InkWell(
                      borderRadius:
                          BorderRadius
                              .circular(
                        12,
                      ),
                      onTap: () {
                        setPopupState(
                          () {
                            if (selected) {
                              selectedPlatforms
                                  .remove(
                                name,
                              );
                            } else {
                              selectedPlatforms
                                  .add(
                                name,
                              );
                            }
                          },
                        );
                      },
                      child:
                          AnimatedContainer(
                        duration:
                            const Duration(
                          milliseconds:
                              150,
                        ),
                        padding:
                            const EdgeInsets
                                .all(
                          8,
                        ),
                        decoration:
                            BoxDecoration(
                          color: selected
                              ? const Color(
                                  0xff6B4226,
                                )
                              : const Color(
                                  0xff1b120d,
                                ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                          border:
                              Border.all(
                            color: selected
                                ? Colors
                                    .amber
                                : Colors
                                    .white24,
                            width:
                                selected
                                    ? 2
                                    : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .center,
                          children: [
                            BrandIcon(
                              brand:
                                  name,
                              size: 24,
                            ),
                            const SizedBox(
                              height: 6,
                            ),
                            Text(
                              name,
                              maxLines: 2,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                              textAlign:
                                  TextAlign
                                      .center,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                                fontSize:
                                    11,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedPlatforms
                        .isEmpty) {
                      return;
                    }

                    setState(() {
                      plateformes
                        ..clear()
                        ..addAll(
                          toutesLesPlateformes
                              .where(
                            (platform) =>
                                selectedPlatforms
                                    .contains(
                              platform[
                                  'nom'],
                            ),
                          ),
                        );
                    });

                    await _saveProfile();

                    if (!dialogContext
                        .mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'VALIDER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
                      fontWeight:
                          FontWeight.bold,
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

  // ==========================================================================
  // DISPONIBILITÉS
  // ==========================================================================

  void _showAvailabilityPopup() {
    final Map<String, List<String>>
        workingCopy = {
      for (final String day in _jours)
        day: List<String>.from(
          disponibilites[day] ??
              <String>[],
        ),
    };

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setPopupState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(
                0xff2b1a12,
              ),
              title: const Text(
                'MES DISPONIBILITÉS',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width:
                    double.maxFinite,
                height: 520,
                child:
                    ListView(
                  children: _jours.map(
                    (day) {
                      final List<String>
                          slots =
                          workingCopy[
                                  day] ??
                              <String>[];

                      return _AvailabilityDay(
                        day: day,
                        slots: slots,
                        onAdd: () {
                          if (slots.length >=
                              3) {
                            return;
                          }

                          setPopupState(
                            () {
                              slots.add(
                                '20h -> 23h',
                              );
                            },
                          );
                        },
                        onRemove:
                            (index) {
                          setPopupState(
                            () {
                              slots.removeAt(
                                index,
                              );
                            },
                          );
                        },
                        onEditStart:
                            (index) async {
                          await _editAvailabilityTime(
                            context:
                                dialogContext,
                            workingCopy:
                                workingCopy,
                            day: day,
                            index: index,
                            editStart:
                                true,
                            setPopupState:
                                setPopupState,
                          );
                        },
                        onEditEnd:
                            (index) async {
                          await _editAvailabilityTime(
                            context:
                                dialogContext,
                            workingCopy:
                                workingCopy,
                            day: day,
                            index: index,
                            editStart:
                                false,
                            setPopupState:
                                setPopupState,
                          );
                        },
                      );
                    },
                  ).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      disponibilites
                        ..clear()
                        ..addAll(
                          workingCopy.map(
                            (
                              key,
                              value,
                            ) =>
                                MapEntry(
                              key,
                              List<String>.from(
                                value,
                              ),
                            ),
                          ),
                        );
                    });

                    await _saveProfile();

                    if (!dialogContext
                        .mounted) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'VALIDER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
                      fontWeight:
                          FontWeight.bold,
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
    required Map<String, List<String>>
        workingCopy,
    required String day,
    required int index,
    required bool editStart,
    required StateSetter setPopupState,
  }) async {
    final List<String> slots =
        workingCopy[day] ??
            <String>[];

    if (index < 0 ||
        index >= slots.length) {
      return;
    }

    final List<String> parts =
        slots[index].split('->');

    if (parts.length != 2) {
      return;
    }

    final String start =
        parts[0].trim();

    final String end =
        parts[1].trim();

    final TimeOfDay initial =
        _parseTime(
      editStart ? start : end,
    );

    final TimeOfDay? selected =
        await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (selected == null) {
      return;
    }

    final String newTime =
        _formatTime(selected);

    setPopupState(() {
      slots[index] = editStart
          ? '$newTime -> $end'
          : '$start -> $newTime';
    });
  }

  TimeOfDay _parseTime(
    String value,
  ) {
    final String cleaned =
        value
            .replaceAll('h', ':')
            .replaceAll('::', ':')
            .trim();

    final List<String> parts =
        cleaned.split(':');

    final int hour =
        int.tryParse(
              parts.first,
            ) ??
            20;

    final int minute =
        parts.length > 1
            ? int.tryParse(
                  parts[1],
                ) ??
                0
            : 0;

    return TimeOfDay(
      hour: hour.clamp(0, 23),
      minute:
          minute.clamp(0, 59),
    );
  }

  String _formatTime(
    TimeOfDay time,
  ) {
    if (time.minute == 0) {
      return '${time.hour}h';
    }

    final String hour =
        time.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String minute =
        time.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

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
          builder: (
            context,
            setPopupState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(
                0xff2b1a12,
              ),
              title: const Text(
                'MES RÉSEAUX',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width:
                    double.maxFinite,
                child: reseaux.isEmpty
                    ? const Padding(
                        padding:
                            EdgeInsets.all(
                          20,
                        ),
                        child: Text(
                          'Aucun réseau configuré.',
                          textAlign:
                              TextAlign.center,
                          style:
                              TextStyle(
                            color:
                                Colors.white70,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap:
                            true,
                        itemCount:
                            reseaux.length,
                        separatorBuilder:
                            (_, _) =>
                                const SizedBox(
                          height: 8,
                        ),
                        itemBuilder:
                            (context,
                                index) {
                          final Map<String,
                                  String>
                              network =
                              reseaux[
                                  index];

                          return _NetworkCard(
                            name:
                                network[
                                    'nom']!,
                            username:
                                network[
                                    'pseudo']!,
                            visibility:
                                network[
                                    'visibilite']!,
                            onEdit:
                                () async {
                              await _showEditNetworkPopup(
                                index,
                              );

                              setPopupState(
                                () {},
                              );
                            },
                            onDelete:
                                () async {
                              final bool?
                                  confirmed =
                                  await showDialog<
                                      bool>(
                                context:
                                    dialogContext,
                                builder:
                                    (confirmContext) {
                                  return AlertDialog(
                                    backgroundColor:
                                        const Color(
                                      0xff2b1a12,
                                    ),
                                    title:
                                        const Text(
                                      'Supprimer le réseau ?',
                                      style:
                                          TextStyle(
                                        color:
                                            Colors.amber,
                                      ),
                                    ),
                                    content:
                                        Text(
                                      'Supprimer ${network['nom']} de ton profil ?',
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors.white70,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () {
                                          Navigator.pop(
                                            confirmContext,
                                            false,
                                          );
                                        },
                                        child:
                                            const Text(
                                          'ANNULER',
                                        ),
                                      ),
                                      TextButton(
                                        onPressed:
                                            () {
                                          Navigator.pop(
                                            confirmContext,
                                            true,
                                          );
                                        },
                                        child:
                                            const Text(
                                          'SUPPRIMER',
                                          style:
                                              TextStyle(
                                            color:
                                                Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (confirmed !=
                                  true) {
                                return;
                              }

                              setState(() {
                                reseaux
                                    .removeAt(
                                  index,
                                );
                              });

                              await _saveProfile();

                              setPopupState(
                                () {},
                              );
                            },
                            onToggleVisibility:
                                () async {
                              setState(() {
                                network[
                                    'visibilite'] = network[
                                            'visibilite'] ==
                                        'Visible'
                                    ? 'Prive'
                                    : 'Visible';
                              });

                              await _saveProfile();

                              setPopupState(
                                () {},
                              );
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    await _showAddNetworkPopup();

                    setPopupState(
                      () {},
                    );
                  },
                  icon: const Icon(
                    Icons.add,
                    color:
                        Colors.amber,
                  ),
                  label: const Text(
                    'AJOUTER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'FERMER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
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

  Future<void> _showAddNetworkPopup() async {
    String selectedNetwork =
        'Discord';

    String draftUsername = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setPopupState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(
                0xff2b1a12,
              ),
              title: const Text(
                'AJOUTER UN RÉSEAU',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  DropdownButtonFormField<
                      String>(
                    initialValue:
                        selectedNetwork,
                    dropdownColor:
                        const Color(
                      0xff2b1a12,
                    ),
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Réseau',
                      labelStyle:
                          TextStyle(
                        color:
                            Colors.amber,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value:
                            'Discord',
                        child:
                            Text(
                          'Discord',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                            'PlayStation',
                        child:
                            Text(
                          'PlayStation',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Xbox',
                        child:
                            Text(
                          'Xbox',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Steam',
                        child:
                            Text(
                          'Steam',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                            'Nintendo',
                        child:
                            Text(
                          'Nintendo',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                            'Epic Games',
                        child:
                            Text(
                          'Epic Games',
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setPopupState(
                        () {
                          selectedNetwork =
                              value;
                        },
                      );
                    },
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  TextFormField(
                    initialValue:
                        draftUsername,
                    onChanged: (value) {
                      draftUsername =
                          value;
                    },
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                    ),
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Pseudo / identifiant',
                      labelStyle:
                          TextStyle(
                        color:
                            Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(
                      dialogContext,
                    ).unfocus();

                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final String username =
                        draftUsername.trim();

                    if (username.isEmpty) {
                      return;
                    }

                    final bool exists =
                        reseaux.any(
                      (item) =>
                          item['nom'] ==
                          selectedNetwork,
                    );

                    if (exists) {
                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            '$selectedNetwork est déjà configuré.',
                          ),
                        ),
                      );
                      return;
                    }

                    setState(() {
                      reseaux.add({
                        'nom':
                            selectedNetwork,
                        'pseudo':
                            username,
                        'visibilite':
                            'Prive',
                      });
                    });

                    await _saveProfile();

                    if (!dialogContext
                        .mounted) {
                      return;
                    }

                    FocusScope.of(
                      dialogContext,
                    ).unfocus();

                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'AJOUTER',
                    style:
                        TextStyle(
                      color:
                          Colors.amber,
                      fontWeight:
                          FontWeight.bold,
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

  Future<void> _showEditNetworkPopup(
    int index,
  ) async {
    if (index < 0 ||
        index >= reseaux.length) {
      return;
    }

    final Map<String, String> network =
        reseaux[index];

    String draftUsername =
        network['pseudo'] ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: Text(
            'MODIFIER ${network['nom']}',
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
          content: TextFormField(
            initialValue:
                draftUsername,
            autofocus: true,
            onChanged: (value) {
              draftUsername = value;
            },
            style:
                const TextStyle(
              color: Colors.white,
            ),
            decoration:
                const InputDecoration(
              labelText:
                  'Pseudo / identifiant',
              labelStyle:
                  TextStyle(
                color:
                    Colors.amber,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(
                  dialogContext,
                ).unfocus();

                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(
                  color:
                      Colors.white70,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final String username =
                    draftUsername.trim();

                if (username.isEmpty) {
                  return;
                }

                setState(() {
                  network['pseudo'] =
                      username;
                });

                await _saveProfile();

                if (!dialogContext
                    .mounted) {
                  return;
                }

                FocusScope.of(
                  dialogContext,
                ).unfocus();

                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'ENREGISTRER',
                style: TextStyle(
                  color:
                      Colors.amber,
                  fontWeight:
                      FontWeight.bold,
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
// OPTION DE PROFIL
// =============================================================================

class _ProfileOption
    extends StatelessWidget {
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
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color:
            const Color(
          0xff6B4226,
        ),
        borderRadius:
            BorderRadius.circular(
          15,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(
            15,
          ),
          child: Container(
            padding:
                const EdgeInsets.all(
              17,
            ),
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              border: Border.all(
                color:
                    Colors.amber,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Text(
                  icon,
                  style:
                      const TextStyle(
                    fontSize: 30,
                  ),
                ),
                const SizedBox(
                  width: 15,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        title,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize: 17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        subtitle,
                        style:
                            const TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.amber,
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
// DISPONIBILITÉS
// =============================================================================

class _AvailabilityDay
    extends StatelessWidget {
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
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      padding:
          const EdgeInsets.all(
        10,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff1b120d,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color:
              Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day,
                  style:
                      const TextStyle(
                    color:
                        Colors.amber,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    slots.length >= 3
                        ? null
                        : onAdd,
                icon:
                    const Icon(
                  Icons.add_circle_outline,
                ),
                color:
                    Colors.amber,
                tooltip:
                    'Ajouter un créneau',
              ),
            ],
          ),
          if (slots.isEmpty)
            const Padding(
              padding:
                  EdgeInsets.only(
                bottom: 8,
              ),
              child: Text(
                'Aucun créneau',
                style:
                    TextStyle(
                  color:
                      Colors.white38,
                ),
              ),
            ),
          ...List<Widget>.generate(
            slots.length,
            (index) =>
                _AvailabilitySlot(
              value:
                  slots[index],
              onEditStart: () =>
                  onEditStart(
                index,
              ),
              onEditEnd: () =>
                  onEditEnd(
                index,
              ),
              onRemove: () =>
                  onRemove(
                index,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilitySlot
    extends StatelessWidget {
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
  Widget build(
    BuildContext context,
  ) {
    final List<String> parts =
        value.split('->');

    final String start =
        parts.isNotEmpty
            ? parts[0].trim()
            : '--';

    final String end =
        parts.length > 1
            ? parts[1].trim()
            : '--';

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 8,
      ),
      padding:
          const EdgeInsets.all(
        8,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color:
              Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TimeButton(
              label: 'Début',
              value: start,
              onTap:
                  onEditStart,
            ),
          ),
          const Padding(
            padding:
                EdgeInsets.symmetric(
              horizontal: 5,
            ),
            child: Text(
              '→',
              style:
                  TextStyle(
                color:
                    Colors.white54,
              ),
            ),
          ),
          Expanded(
            child: _TimeButton(
              label: 'Fin',
              value: end,
              onTap:
                  onEditEnd,
            ),
          ),
          IconButton(
            onPressed:
                onRemove,
            icon: const Icon(
              Icons.delete_outline,
              color:
                  Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton
    extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(
        8,
      ),
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        decoration:
            BoxDecoration(
          color:
              const Color(
            0xff1b120d,
          ),
          borderRadius:
              BorderRadius.circular(
            8,
          ),
          border: Border.all(
            color:
                Colors.white12,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.white38,
                fontSize: 10,
              ),
            ),
            const SizedBox(
              height: 2,
            ),
            Text(
              value,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RÉSEAU
// =============================================================================

class _NetworkCard
    extends StatelessWidget {
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
  Widget build(
    BuildContext context,
  ) {
    final bool isVisible =
        visibility == 'Visible';

    return Container(
      padding:
          const EdgeInsets.all(
        10,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff1b120d,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color:
              Colors.white12,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child:
                  BrandIcon(
                brand: name,
                size: 24,
              ),
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  name,
                  style:
                      const TextStyle(
                    color:
                        Colors.amber,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                Text(
                  username,
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                onToggleVisibility,
            tooltip: isVisible
                ? 'Rendre privé'
                : 'Rendre visible',
            icon: Icon(
              isVisible
                  ? Icons.visibility
                  : Icons.visibility_off,
              color: isVisible
                  ? Colors.amber
                  : Colors.white38,
            ),
          ),
          PopupMenuButton<String>(
            color:
                const Color(
              0xff2b1a12,
            ),
            iconColor:
                Colors.white70,
            onSelected:
                (value) {
              if (value ==
                  'edit') {
                onEdit();
              }

              if (value ==
                  'delete') {
                onDelete();
              }
            },
            itemBuilder:
                (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  'Modifier',
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Supprimer',
                  style:
                      TextStyle(
                    color:
                        Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
