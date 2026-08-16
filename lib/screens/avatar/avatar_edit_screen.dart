import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/avatar_model.dart';
import '../../widgets/avatar_renderer.dart';

enum _AvatarCategory {
  base,
  hair,
  beard,
  glasses,
  outfit,
  accessory,
}

class AvatarEditScreen extends StatefulWidget {
  final AvatarModel initialAvatar;

  const AvatarEditScreen({
    super.key,
    required this.initialAvatar,
  });

  @override
  State<AvatarEditScreen> createState() =>
      _AvatarEditScreenState();
}

class _AvatarEditScreenState
    extends State<AvatarEditScreen> {
  late AvatarModel avatar;

  final Random _random = Random();

  _AvatarCategory selectedCategory =
      _AvatarCategory.base;

  @override
  void initState() {
    super.initState();

    avatar = widget.initialAvatar.copyWith(
      creationMode: AvatarCreationMode.manual,
      clearGeneratedImagePath: true,
    );
  }

  void _randomize() {
    setState(() {
      avatar = avatar.copyWith(
        creationMode: AvatarCreationMode.manual,
        clearGeneratedImagePath: true,
        skin: AvatarSkin.values[
            _random.nextInt(AvatarSkin.values.length)],
        hair: AvatarHair.values[
            _random.nextInt(AvatarHair.values.length)],
        beard: AvatarBeard.values[
            _random.nextInt(AvatarBeard.values.length)],
        outfit: AvatarOutfit.values[
            _random.nextInt(AvatarOutfit.values.length)],
        glasses: AvatarGlasses.values[
            _random.nextInt(AvatarGlasses.values.length)],
        accessory: AvatarAccessory.values[
            _random.nextInt(AvatarAccessory.values.length)],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor: const Color(0xff21150e),
        foregroundColor: const Color(0xffffc857),
        title: const Text('Personnaliser'),
        actions: [
          IconButton(
            onPressed: _randomize,
            tooltip: 'Aléatoire',
            icon: const Icon(Icons.casino),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // ================================================================
            // GRAND APERÇU
            // ================================================================

            AvatarRenderer(
              avatar: avatar,
              size: 205,
            ),

            const SizedBox(height: 12),

            // ================================================================
            // CATÉGORIES
            // ================================================================

            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                children: _AvatarCategory.values.map(
                  (category) {
                    final bool selected =
                        selectedCategory == category;

                    return Padding(
                      padding: const EdgeInsets.only(
                        right: 8,
                      ),
                      child: ChoiceChip(
                        selected: selected,
                        label: Text(
                          _categoryLabel(category),
                        ),
                        avatar: Icon(
                          _categoryIcon(category),
                          size: 18,
                        ),
                        onSelected: (_) {
                          setState(() {
                            selectedCategory =
                                category;
                          });
                        },
                        selectedColor:
                            const Color(0xffffc857),
                        backgroundColor:
                            const Color(0xff2b1b12),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xffffc857)
                              : Colors.white24,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? const Color(0xff21150e)
                              : Colors.white70,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // ================================================================
            // CHOIX VISUELS
            // ================================================================

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xff21150e),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        18,
                        14,
                        18,
                        8,
                      ),
                      child: Row(
                        children: [
                          Text(
                            _categoryLabel(
                              selectedCategory,
                            ),
                            style: const TextStyle(
                              color: Color(0xffffc857),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _currentChoiceLabel(),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: _buildCurrentChoices(),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        16,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              avatar,
                            );
                          },
                          icon: const Icon(
                            Icons.check_circle,
                          ),
                          label: const Text(
                            'VALIDER MON AVATAR',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xffffc857),
                            foregroundColor:
                                const Color(0xff21150e),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentChoices() {
    switch (selectedCategory) {
      case _AvatarCategory.base:
        return _choiceGrid<AvatarSkin>(
          values: AvatarSkin.values,
          selected: avatar.skin,
          label: _skinLabel,
          buildAvatar: (value) => avatar.copyWith(
            skin: value,
          ),
          onTap: (value) {
            setState(() {
              avatar = avatar.copyWith(
                skin: value,
              );
            });
          },
        );

      case _AvatarCategory.hair:
        return _choiceGrid<AvatarHair>(
          values: AvatarHair.values,
          selected: avatar.hair,
          label: _hairLabel,
          buildAvatar: (value) => avatar.copyWith(
            hair: value,
          ),
          onTap: (value) {
            setState(() {
              avatar = avatar.copyWith(
                hair: value,
              );
            });
          },
        );

      case _AvatarCategory.beard:
        return _choiceGrid<AvatarBeard>(
          values: AvatarBeard.values,
          selected: avatar.beard,
          label: _beardLabel,
          buildAvatar: (value) => avatar.copyWith(
            beard: value,
          ),
          onTap: (value) {
            setState(() {
              avatar = avatar.copyWith(
                beard: value,
              );
            });
          },
        );

      case _AvatarCategory.glasses:
        return _choiceGrid<AvatarGlasses>(
          values: AvatarGlasses.values,
          selected: avatar.glasses,
          label: _glassesLabel,
          buildAvatar: (value) => avatar.copyWith(
            glasses: value,
          ),
          onTap: (value) {
            setState(() {
              avatar = avatar.copyWith(
                glasses: value,
              );
            });
          },
        );

      case _AvatarCategory.outfit:
        return _choiceGrid<AvatarOutfit>(
          values: AvatarOutfit.values,
          selected: avatar.outfit,
          label: _outfitLabel,
          buildAvatar: (value) => avatar.copyWith(
            outfit: value,
          ),
          onTap: (value) {
            setState(() {
              avatar = avatar.copyWith(
                outfit: value,
              );
            });
          },
        );

      case _AvatarCategory.accessory:
        return _choiceGrid<AvatarAccessory>(
          values: AvatarAccessory.values,
          selected: avatar.accessory,
          label: _accessoryLabel,
          buildAvatar: (value) => avatar.copyWith(
            accessory: value,
          ),
          onTap: (value) {
            setState(() {
              avatar = avatar.copyWith(
                accessory: value,
              );
            });
          },
        );
    }
  }

  Widget _choiceGrid<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required AvatarModel Function(T) buildAvatar,
    required ValueChanged<T> onTap,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        14,
        6,
        14,
        14,
      ),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: values.length,
      itemBuilder: (
        context,
        index,
      ) {
        final T value = values[index];
        final bool isSelected =
            selected == value;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap(value),
          child: AnimatedContainer(
            duration: const Duration(
              milliseconds: 140,
            ),
            decoration: BoxDecoration(
              color: const Color(0xff160e09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xffffc857)
                    : Colors.white12,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 6,
                    ),
                    child: AvatarRenderer(
                      avatar: buildAvatar(value),
                      size: 70,
                      showFrame: false,
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    4,
                    3,
                    4,
                    8,
                  ),
                  child: Text(
                    label(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xffffc857)
                          : Colors.white70,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _categoryLabel(
    _AvatarCategory category,
  ) {
    switch (category) {
      case _AvatarCategory.base:
        return 'Base';
      case _AvatarCategory.hair:
        return 'Cheveux';
      case _AvatarCategory.beard:
        return 'Barbe';
      case _AvatarCategory.glasses:
        return 'Lunettes';
      case _AvatarCategory.outfit:
        return 'Tenue';
      case _AvatarCategory.accessory:
        return 'Accessoire';
    }
  }

  IconData _categoryIcon(
    _AvatarCategory category,
  ) {
    switch (category) {
      case _AvatarCategory.base:
        return Icons.face;
      case _AvatarCategory.hair:
        return Icons.content_cut;
      case _AvatarCategory.beard:
        return Icons.face_retouching_natural;
      case _AvatarCategory.glasses:
        return Icons.remove_red_eye_outlined;
      case _AvatarCategory.outfit:
        return Icons.checkroom;
      case _AvatarCategory.accessory:
        return Icons.auto_awesome;
    }
  }

  String _currentChoiceLabel() {
    switch (selectedCategory) {
      case _AvatarCategory.base:
        return _skinLabel(avatar.skin);
      case _AvatarCategory.hair:
        return _hairLabel(avatar.hair);
      case _AvatarCategory.beard:
        return _beardLabel(avatar.beard);
      case _AvatarCategory.glasses:
        return _glassesLabel(avatar.glasses);
      case _AvatarCategory.outfit:
        return _outfitLabel(avatar.outfit);
      case _AvatarCategory.accessory:
        return _accessoryLabel(
          avatar.accessory,
        );
    }
  }

  String _skinLabel(
    AvatarSkin value,
  ) {
    switch (value) {
      case AvatarSkin.body01:
        return 'Teinte 1';
      case AvatarSkin.body02:
        return 'Teinte 2';
      case AvatarSkin.body03:
        return 'Teinte 3';
      case AvatarSkin.body04:
        return 'Teinte 4';
    }
  }

  String _hairLabel(
    AvatarHair value,
  ) {
    switch (value) {
      case AvatarHair.none:
        return 'Rasé';
      case AvatarHair.hair02:
        return 'Cheveux 1';
      case AvatarHair.hair03:
        return 'Cheveux 2';
      case AvatarHair.hair04:
        return 'Cheveux 3';
      case AvatarHair.hair05:
        return 'Cheveux 4';
      case AvatarHair.hair06:
        return 'Cheveux 5';
    }
  }

  String _beardLabel(
    AvatarBeard value,
  ) {
    switch (value) {
      case AvatarBeard.none:
        return 'Aucune';
      case AvatarBeard.beard02:
        return 'Barbe 1';
      case AvatarBeard.beard03:
        return 'Barbe 2';
      case AvatarBeard.beard04:
        return 'Barbe 3';
      case AvatarBeard.beard05:
        return 'Barbe 4';
    }
  }

  String _glassesLabel(
    AvatarGlasses value,
  ) {
    switch (value) {
      case AvatarGlasses.none:
        return 'Aucune';
      case AvatarGlasses.glasses01:
        return 'Lunettes 1';
      case AvatarGlasses.glasses02:
        return 'Lunettes 2';
      case AvatarGlasses.glasses03:
        return 'Lunettes 3';
      case AvatarGlasses.glasses04:
        return 'Lunettes 4';
    }
  }

  String _outfitLabel(
    AvatarOutfit value,
  ) {
    switch (value) {
      case AvatarOutfit.outfit01:
        return 'Mage';
      case AvatarOutfit.outfit02:
        return 'Rôdeur';
      case AvatarOutfit.outfit03:
        return 'Aventurier';
      case AvatarOutfit.outfit04:
        return 'Tavernier';
    }
  }

  String _accessoryLabel(
    AvatarAccessory value,
  ) {
    switch (value) {
      case AvatarAccessory.none:
        return 'Aucun';
      case AvatarAccessory.d20Badge:
        return 'Badge D20';
      case AvatarAccessory.xpMedal:
        return 'Médaille XP';
      case AvatarAccessory.potion:
        return 'Potion';
      case AvatarAccessory.gamerPouch:
        return 'Gamer pouch';
      case AvatarAccessory.heartBag:
        return 'Sac cœur';
      case AvatarAccessory.heartBook:
        return 'Livre cœur';
    }
  }
}
