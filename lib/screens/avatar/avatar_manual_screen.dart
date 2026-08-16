import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/avatar_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/avatar_renderer.dart';
import 'avatar_preview_screen.dart';

class AvatarManualScreen extends StatefulWidget {
  const AvatarManualScreen({
    super.key,
  });

  @override
  State<AvatarManualScreen> createState() =>
      _AvatarManualScreenState();
}

class _AvatarManualScreenState
    extends State<AvatarManualScreen> {
  final Random _random = Random();

  AvatarSkin _skin = AvatarSkin.body02;
  AvatarHair _hair = AvatarHair.hair02;
  AvatarBeard _beard = AvatarBeard.none;
  AvatarGlasses _glasses = AvatarGlasses.none;
  AvatarOutfit _outfit = AvatarOutfit.outfit01;
  AvatarAccessory _accessory =
      AvatarAccessory.none;

  AvatarModel _buildAvatar({
    String userId = 'preview',
  }) {
    final DateTime now =
        DateTime.now();

    return AvatarModel(
      userId: userId,
      creationMode:
          AvatarCreationMode.manual,

      // Ces deux anciennes valeurs restent fixes
      // tant qu'on n'a pas créé de calques dédiés.
      faceStyle: 'Doux',
      hairColor: 'Châtain',

      skin: _skin,
      hair: _hair,
      beard: _beard,
      glasses: _glasses,
      outfit: _outfit,
      accessory: _accessory,

      createdAt: now,
      updatedAt: now,
    );
  }

  void _randomize() {
    setState(() {
      _skin = _pick(
        AvatarSkin.values,
      );

      _hair = _pick(
        AvatarHair.values,
      );

      _beard = _pick(
        AvatarBeard.values,
      );

      _glasses = _pick(
        AvatarGlasses.values,
      );

      _outfit = _pick(
        AvatarOutfit.values,
      );

      _accessory = _pick(
        AvatarAccessory.values,
      );
    });
  }

  T _pick<T>(
    List<T> values,
  ) {
    return values[
        _random.nextInt(values.length)];
  }

  Future<void> _continue() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (!mounted) {
      return;
    }

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de retrouver ton compte.',
          ),
        ),
      );

      return;
    }

    final AvatarModel avatar =
        _buildAvatar(
      userId: userId,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AvatarPreviewScreen(
          avatar: avatar,
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final AvatarModel previewAvatar =
        _buildAvatar();

    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        foregroundColor:
            const Color(0xffffc857),
        title: const Text(
          'Crée ton aventurier',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Center(
                child: AvatarRenderer(
                  avatar: previewAvatar,
                  size: 220,
                ),
              ),
            ),

            Expanded(
              child: Container(
                decoration:
                    const BoxDecoration(
                  color:
                      Color(0xff21150e),
                  borderRadius:
                      BorderRadius.vertical(
                    top:
                        Radius.circular(28),
                  ),
                  border: Border(
                    top: BorderSide(
                      color:
                          Color(0xffffc857),
                      width: 2,
                    ),
                  ),
                ),
                child:
                    SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    30,
                  ),
                  child: Column(
                    children: [
                      // ======================================================
                      // EXACTEMENT LE MÊME PRINCIPE : ← choix →
                      // ======================================================

                      _OptionSelector<AvatarSkin>(
                        label: 'Teint',
                        value: _skin,
                        values:
                            AvatarSkin.values,
                        valueLabel:
                            _skinLabel,
                        onChanged: (value) {
                          setState(() {
                            _skin = value;
                          });
                        },
                      ),

                      _OptionSelector<AvatarHair>(
                        label: 'Coiffure',
                        value: _hair,
                        values:
                            AvatarHair.values,
                        valueLabel:
                            _hairLabel,
                        onChanged: (value) {
                          setState(() {
                            _hair = value;
                          });
                        },
                      ),

                      _OptionSelector<AvatarBeard>(
                        label: 'Barbe',
                        value: _beard,
                        values:
                            AvatarBeard.values,
                        valueLabel:
                            _beardLabel,
                        onChanged: (value) {
                          setState(() {
                            _beard = value;
                          });
                        },
                      ),

                      _OptionSelector<AvatarGlasses>(
                        label: 'Lunettes',
                        value: _glasses,
                        values:
                            AvatarGlasses.values,
                        valueLabel:
                            _glassesLabel,
                        onChanged: (value) {
                          setState(() {
                            _glasses = value;
                          });
                        },
                      ),

                      _OptionSelector<AvatarOutfit>(
                        label: 'Tenue',
                        value: _outfit,
                        values:
                            AvatarOutfit.values,
                        valueLabel:
                            _outfitLabel,
                        onChanged: (value) {
                          setState(() {
                            _outfit = value;
                          });
                        },
                      ),

                      _OptionSelector<AvatarAccessory>(
                        label: 'Accessoire',
                        value: _accessory,
                        values:
                            AvatarAccessory.values,
                        valueLabel:
                            _accessoryLabel,
                        onChanged: (value) {
                          setState(() {
                            _accessory =
                                value;
                          });
                        },
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      SizedBox(
                        width:
                            double.infinity,
                        child:
                            OutlinedButton.icon(
                          onPressed:
                              _randomize,
                          icon:
                              const Icon(
                            Icons.casino,
                          ),
                          label:
                              const Text(
                            'ALÉATOIRE',
                          ),
                          style:
                              OutlinedButton
                                  .styleFrom(
                            foregroundColor:
                                const Color(
                              0xffffc857,
                            ),
                            side:
                                const BorderSide(
                              color:
                                  Color(
                                0xffffc857,
                              ),
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
                        height: 55,
                        child:
                            ElevatedButton.icon(
                          onPressed:
                              _continue,
                          icon:
                              const Icon(
                            Icons
                                .arrow_forward,
                          ),
                          label:
                              const Text(
                            'CONTINUER',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                              letterSpacing:
                                  1,
                            ),
                          ),
                          style:
                              ElevatedButton
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _skinLabel(
    AvatarSkin value,
  ) {
    switch (value) {
      case AvatarSkin.body01:
        return 'Clair';

      case AvatarSkin.body02:
        return 'Doré';

      case AvatarSkin.body03:
        return 'Mat';

      case AvatarSkin.body04:
        return 'Foncé';
    }
  }

  String _hairLabel(
    AvatarHair value,
  ) {
    switch (value) {
      case AvatarHair.none:
        return 'Rasé';

      case AvatarHair.hair02:
        return 'Ébouriffé';

      case AvatarHair.hair03:
        return 'Balayé';

      case AvatarHair.hair04:
        return 'Volumineux';

      case AvatarHair.hair05:
        return 'Ondulé';

      case AvatarHair.hair06:
        return 'Mi-long';
    }
  }

  String _beardLabel(
    AvatarBeard value,
  ) {
    switch (value) {
      case AvatarBeard.none:
        return 'Aucune';

      case AvatarBeard.beard02:
        return 'Courte';

      case AvatarBeard.beard03:
        return 'Fournie';

      case AvatarBeard.beard04:
        return 'Nordique';

      case AvatarBeard.beard05:
        return 'Bouc';
    }
  }

  String _glassesLabel(
    AvatarGlasses value,
  ) {
    switch (value) {
      case AvatarGlasses.none:
        return 'Aucune';

      case AvatarGlasses.glasses01:
        return 'Rondes';

      case AvatarGlasses.glasses02:
        return 'Carrées';

      case AvatarGlasses.glasses03:
        return 'Dorées';

      case AvatarGlasses.glasses04:
        return 'Rétro';
    }
  }

  String _outfitLabel(
    AvatarOutfit value,
  ) {
    switch (value) {
      case AvatarOutfit.outfit01:
        return 'Aventurier';

      case AvatarOutfit.outfit02:
        return 'Mage';

      case AvatarOutfit.outfit03:
        return 'Rôdeur';

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

class _OptionSelector<T>
    extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) valueLabel;
  final ValueChanged<T> onChanged;

  const _OptionSelector({
    required this.label,
    required this.value,
    required this.values,
    required this.valueLabel,
    required this.onChanged,
  });

  void _previous() {
    final int currentIndex =
        values.indexOf(value);

    final int nextIndex =
        currentIndex <= 0
            ? values.length - 1
            : currentIndex - 1;

    onChanged(
      values[nextIndex],
    );
  }

  void _next() {
    final int currentIndex =
        values.indexOf(value);

    final int nextIndex =
        currentIndex >=
                values.length - 1
            ? 0
            : currentIndex + 1;

    onChanged(
      values[nextIndex],
    );
  }

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
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(0xff2b1b12),
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.white70,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),

          IconButton(
            onPressed:
                _previous,
            icon:
                const Icon(
              Icons.chevron_left,
              color:
                  Color(0xffffc857),
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              valueLabel(value),
              textAlign:
                  TextAlign.center,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color: Colors.white,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),

          IconButton(
            onPressed:
                _next,
            icon:
                const Icon(
              Icons.chevron_right,
              color:
                  Color(0xffffc857),
            ),
          ),
        ],
      ),
    );
  }
}
