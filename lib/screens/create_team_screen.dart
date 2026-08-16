import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/team_model.dart';
import '../services/auth_service.dart';
import '../services/profile_storage.dart';
import '../services/team_storage.dart';

class CreateTeamScreen extends StatefulWidget {
  final TeamModel? teamToEdit;

  const CreateTeamScreen({
    super.key,
    this.teamToEdit,
  });

  bool get isEditing =>
      teamToEdit != null;

  @override
  State<CreateTeamScreen> createState() =>
      _CreateTeamScreenState();
}

class _CreateTeamScreenState
    extends State<CreateTeamScreen> {
  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  final TextEditingController
      _nameController =
      TextEditingController();

  final TextEditingController
      _descriptionController =
      TextEditingController();

  final ImagePicker _picker =
      ImagePicker();

  String? _imagePath;

  int _maxMembers = 5;

  bool _recruitmentOpen = true;

  bool _isSaving = false;

  final List<String> _selectedGames =
      <String>[];

  final List<String>
      _selectedPlatforms =
      <String>[];

  final List<String> _availableGames = [
    'Minecraft',
    'Fortnite',
    'Rocket League',
    'Valorant',
    'Call of Duty',
    'GTA V',
    'EA Sports FC 26',
    'Terraria',
    'Apex Legends',
    'Overwatch 2',
  ];

  final List<String>
      _availablePlatforms = [
    'PC',
    'PlayStation 5',
    'PlayStation 4',
    'Xbox Series X/S',
    'Xbox One',
    'Nintendo Switch',
  ];

  @override
  void initState() {
    super.initState();

    final TeamModel? team =
        widget.teamToEdit;

    if (team != null) {
      _nameController.text =
          team.name;

      _descriptionController.text =
          team.description;

      _imagePath =
          team.imagePath;

      _maxMembers =
          team.maxMembers;

      _recruitmentOpen =
          team.recruitmentOpen;

      _selectedGames
        ..clear()
        ..addAll(team.games);

      _selectedPlatforms
        ..clear()
        ..addAll(team.platforms);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // IMAGE
  // ===========================================================================

  Future<void> _pickImage() async {
    try {
      final XFile? image =
          await _picker.pickImage(
        source:
            ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _imagePath = image.path;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Impossible de sélectionner cette image.',
      );
    }
  }

  // ===========================================================================
  // SAUVEGARDE
  // ===========================================================================

  Future<void> _saveTeam() async {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    if (_selectedGames.isEmpty) {
      _showMessage(
        'Sélectionne au moins un jeu.',
      );
      return;
    }

    if (_selectedPlatforms.isEmpty) {
      _showMessage(
        'Sélectionne au moins une plateforme.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final TeamModel? current =
          widget.teamToEdit;

      if (current == null) {
        await _createNewTeam();
      } else {
        await _updateExistingTeam(
          current,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showMessage(
        'Une erreur est survenue pendant la sauvegarde.',
      );
    }
  }

  Future<void> _createNewTeam() async {
    final Map<String, dynamic> profile =
        await ProfileStorage.loadProfile();

    final String? authUserId =
        await AuthService.getCurrentUserId();

    final String? authUsername =
        await AuthService.getCurrentUsername();

    final String ownerId =
        authUserId?.trim().isNotEmpty ==
                true
            ? authUserId!.trim()
            : profile['id']
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? profile['id']
                    .toString()
                    .trim()
                : 'local_player';

    final String ownerName =
        profile['pseudo']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? profile['pseudo']
                .toString()
                .trim()
            : authUsername
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? authUsername!.trim()
                : 'Joueur';

    final TeamModel team =
        TeamModel(
      id: DateTime.now()
          .microsecondsSinceEpoch
          .toString(),
      name:
          _nameController.text.trim(),
      description:
          _descriptionController.text
              .trim(),
      games:
          List<String>.from(
        _selectedGames,
      ),
      platforms:
          List<String>.from(
        _selectedPlatforms,
      ),
      maxMembers:
          _maxMembers,
      recruitmentOpen:
          _recruitmentOpen,

      // 👑 Le créateur est le Chef.
      ownerId: ownerId,
      ownerName: ownerName,

      // 🛡️ Aucun Admin à la création.
      // Le Chef pourra en nommer un ensuite.
      leaderId: null,
      leaderName: null,

      imagePath:
          _imagePath,

      memberIds: [
        ownerId,
      ],

      createdAt:
          DateTime.now(),
    );

    final bool success =
        await TeamStorage.addTeam(
      team,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      setState(() {
        _isSaving = false;
      });

      _showMessage(
        'Impossible de créer cette équipe.',
      );

      return;
    }

    Navigator.pop(
      context,
      team,
    );
  }

  Future<void> _updateExistingTeam(
    TeamModel current,
  ) async {
    final TeamModel updated =
        current.copyWith(
      name:
          _nameController.text.trim(),
      description:
          _descriptionController.text
              .trim(),
      games:
          List<String>.from(
        _selectedGames,
      ),
      platforms:
          List<String>.from(
        _selectedPlatforms,
      ),
      maxMembers:
          _maxMembers,
      recruitmentOpen:
          _recruitmentOpen,
      imagePath:
          _imagePath,
      clearImagePath:
          _imagePath == null,
    );

    final bool success =
        await TeamStorage.updateTeam(
      updated,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      setState(() {
        _isSaving = false;
      });

      _showMessage(
        'Impossible de modifier cette équipe.',
      );

      return;
    }

    Navigator.pop(
      context,
      updated,
    );
  }

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final bool isEditing =
        widget.isEditing;

    return Scaffold(
      backgroundColor:
          const Color(0xff1b120d),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff5c3317),
        foregroundColor:
            Colors.amber,
        centerTitle: true,
        title: Text(
          isEditing
              ? 'MODIFIER L’ÉQUIPE'
              : 'CRÉER UNE ÉQUIPE',
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key:
              _formKey,
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              20,
              18,
              30,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _buildImagePicker(),

                const SizedBox(
                  height: 25,
                ),

                _buildSectionTitle(
                  'NOM DE L’ÉQUIPE',
                ),

                const SizedBox(
                  height: 8,
                ),

                TextFormField(
                  controller:
                      _nameController,
                  maxLength: 30,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      _inputDecoration(
                    'Ex : Les Aventuriers',
                    Icons.groups,
                  ),
                  validator:
                      (value) {
                    if (value == null ||
                        value
                            .trim()
                            .isEmpty) {
                      return 'Donne un nom à ton équipe.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 15,
                ),

                _buildSectionTitle(
                  'DESCRIPTION',
                ),

                const SizedBox(
                  height: 8,
                ),

                TextFormField(
                  controller:
                      _descriptionController,
                  maxLength: 250,
                  maxLines: 4,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      _inputDecoration(
                    'Présente ton équipe...',
                    Icons.description,
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                _buildSectionTitle(
                  'JEUX',
                ),

                const SizedBox(
                  height: 8,
                ),

                _buildGames(),

                const SizedBox(
                  height: 20,
                ),

                _buildSectionTitle(
                  'PLATEFORMES',
                ),

                const SizedBox(
                  height: 8,
                ),

                _buildPlatforms(),

                const SizedBox(
                  height: 20,
                ),

                _buildSectionTitle(
                  'TAILLE MAXIMALE',
                ),

                const SizedBox(
                  height: 8,
                ),

                _buildMaxMembers(),

                const SizedBox(
                  height: 20,
                ),

                _buildSectionTitle(
                  'RECRUTEMENT',
                ),

                const SizedBox(
                  height: 8,
                ),

                _buildRecruitment(),

                const SizedBox(
                  height: 30,
                ),

                _buildInfoBox(),

                const SizedBox(
                  height: 25,
                ),

                SizedBox(
                  width:
                      double.infinity,
                  height: 55,
                  child:
                      ElevatedButton.icon(
                    onPressed:
                        _isSaving
                            ? null
                            : _saveTeam,
                    icon:
                        _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Colors.black,
                                ),
                              )
                            : Icon(
                                isEditing
                                    ? Icons.save
                                    : Icons.groups,
                              ),
                    label: Text(
                      _isSaving
                          ? 'SAUVEGARDE...'
                          : isEditing
                              ? 'ENREGISTRER'
                              : 'CRÉER L’ÉQUIPE',
                    ),
                    style:
                        ElevatedButton
                            .styleFrom(
                      backgroundColor:
                          Colors.amber,
                      foregroundColor:
                          Colors.black,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // IMAGE
  // ===========================================================================

  Widget _buildImagePicker() {
    return Center(
      child: GestureDetector(
        onTap:
            _pickImage,
        child: Stack(
          clipBehavior:
              Clip.none,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration:
                  BoxDecoration(
                color:
                    const Color(
                  0xff2b1a12,
                ),
                borderRadius:
                    BorderRadius.circular(
                  25,
                ),
                border:
                    Border.all(
                  color:
                      Colors.amber,
                  width: 2,
                ),
              ),
              child:
                  _buildImagePreview(),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child:
                  Container(
                padding:
                    const EdgeInsets.all(
                  8,
                ),
                decoration:
                    const BoxDecoration(
                  color:
                      Colors.amber,
                  shape:
                      BoxShape.circle,
                ),
                child:
                    const Icon(
                  Icons.edit,
                  color:
                      Colors.black,
                  size: 18,
                ),
              ),
            ),
            if (_imagePath != null)
              Positioned(
                left: -8,
                bottom: -8,
                child:
                    GestureDetector(
                  onTap: () {
                    setState(() {
                      _imagePath =
                          null;
                    });
                  },
                  child:
                      Container(
                    padding:
                        const EdgeInsets.all(
                      7,
                    ),
                    decoration:
                        const BoxDecoration(
                      color:
                          Colors.redAccent,
                      shape:
                          BoxShape.circle,
                    ),
                    child:
                        const Icon(
                      Icons.delete_outline,
                      color:
                          Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final String? imagePath =
        _imagePath;

    if (imagePath == null ||
        imagePath.isEmpty) {
      return const Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            color: Colors.amber,
            size: 48,
          ),
          SizedBox(
            height: 8,
          ),
          Text(
            'Ajouter une image',
            style:
                TextStyle(
              color:
                  Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    if (imagePath.startsWith(
          'http://',
        ) ||
        imagePath.startsWith(
          'https://',
        )) {
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(
          23,
        ),
        child:
            Image.network(
          imagePath,
          fit:
              BoxFit.cover,
          errorBuilder:
              (
            context,
            error,
            stackTrace,
          ) {
            return const Icon(
              Icons.groups,
              color:
                  Colors.amber,
              size: 48,
            );
          },
        ),
      );
    }

    final File file =
        File(imagePath);

    if (file.existsSync()) {
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(
          23,
        ),
        child:
            Image.file(
          file,
          fit:
              BoxFit.cover,
        ),
      );
    }

    return const Icon(
      Icons.groups,
      color: Colors.amber,
      size: 48,
    );
  }

  // ===========================================================================
  // CHOIX
  // ===========================================================================

  Widget _buildGames() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          _availableGames.map(
        (game) {
          final bool selected =
              _selectedGames.contains(
            game,
          );

          return FilterChip(
            label:
                Text(game),
            selected:
                selected,
            onSelected:
                (value) {
              setState(() {
                if (value) {
                  _selectedGames.add(
                    game,
                  );
                } else {
                  _selectedGames.remove(
                    game,
                  );
                }
              });
            },
            selectedColor:
                Colors.amber,
            checkmarkColor:
                Colors.black,
            backgroundColor:
                const Color(
              0xff2b1a12,
            ),
            side:
                const BorderSide(
              color:
                  Colors.amber,
            ),
            labelStyle:
                TextStyle(
              color: selected
                  ? Colors.black
                  : Colors.white,
              fontWeight:
                  FontWeight.bold,
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildPlatforms() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          _availablePlatforms.map(
        (platform) {
          final bool selected =
              _selectedPlatforms.contains(
            platform,
          );

          return FilterChip(
            label:
                Text(platform),
            selected:
                selected,
            onSelected:
                (value) {
              setState(() {
                if (value) {
                  _selectedPlatforms.add(
                    platform,
                  );
                } else {
                  _selectedPlatforms.remove(
                    platform,
                  );
                }
              });
            },
            selectedColor:
                Colors.amber,
            checkmarkColor:
                Colors.black,
            backgroundColor:
                const Color(
              0xff2b1a12,
            ),
            side:
                const BorderSide(
              color:
                  Colors.amber,
            ),
            labelStyle:
                TextStyle(
              color: selected
                  ? Colors.black
                  : Colors.white,
              fontWeight:
                  FontWeight.bold,
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildMaxMembers() {
    return Container(
      padding:
          const EdgeInsets.all(
        15,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
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
      child: Row(
        children: [
          const Icon(
            Icons.people,
            color:
                Colors.amber,
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Text(
              '$_maxMembers membres',
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed:
                _maxMembers > 2
                    ? () {
                        setState(() {
                          _maxMembers--;
                        });
                      }
                    : null,
            icon:
                const Icon(
              Icons.remove,
            ),
            color:
                Colors.amber,
          ),
          IconButton(
            onPressed:
                _maxMembers < 50
                    ? () {
                        setState(() {
                          _maxMembers++;
                        });
                      }
                    : null,
            icon:
                const Icon(
              Icons.add,
            ),
            color:
                Colors.amber,
          ),
        ],
      ),
    );
  }

  Widget _buildRecruitment() {
    return Container(
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
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
      child:
          SwitchListTile(
        secondary:
            Icon(
          _recruitmentOpen
              ? Icons.lock_open
              : Icons.lock_outline,
          color:
              Colors.amber,
        ),
        title:
            const Text(
          'Recrutement ouvert',
          style:
              TextStyle(
            color:
                Colors.white,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle:
            Text(
          _recruitmentOpen
              ? 'L’équipe pourra apparaître dans « Trouver une équipe ».'
              : 'Aucune nouvelle demande ne sera acceptée.',
          style:
              const TextStyle(
            color:
                Colors.white60,
            fontSize: 12,
          ),
        ),
        value:
            _recruitmentOpen,
        activeThumbColor:
            Colors.amber,
        onChanged:
            (value) {
          setState(() {
            _recruitmentOpen =
                value;
          });
        },
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding:
          const EdgeInsets.all(
        15,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border:
            Border.all(
          color:
              Colors.white24,
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color:
                Colors.amber,
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Text(
              widget.isEditing
                  ? 'Les modifications sont enregistrées sur cette équipe. Les rôles et les membres ne changent pas.'
                  : 'Tu seras automatiquement le Chef de cette équipe. Tu pourras ensuite nommer un Admin dans « Mes équipes ».',
              style:
                  const TextStyle(
                color:
                    Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
  ) {
    return Text(
      title,
      style:
          const TextStyle(
        color:
            Colors.amber,
        fontWeight:
            FontWeight.bold,
        fontSize: 14,
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      hintText:
          hint,
      hintStyle:
          const TextStyle(
        color:
            Colors.white38,
      ),
      prefixIcon:
          Icon(
        icon,
        color:
            Colors.amber,
      ),
      filled:
          true,
      fillColor:
          const Color(
        0xff2b1a12,
      ),
      counterStyle:
          const TextStyle(
        color:
            Colors.white38,
      ),
      border:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        borderSide:
            const BorderSide(
          color:
              Colors.white24,
        ),
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        borderSide:
            const BorderSide(
          color:
              Colors.white24,
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        borderSide:
            const BorderSide(
          color:
              Colors.amber,
          width: 2,
        ),
      ),
    );
  }
}
