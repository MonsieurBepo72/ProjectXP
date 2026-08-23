import 'package:flutter/material.dart';

import '../../models/avatar_model.dart';
import '../../services/avatar_storage.dart';
import '../../widgets/avatar_renderer.dart';
import '../hall_screen.dart';

class AvatarPreviewScreen
    extends StatefulWidget {
  final AvatarModel avatar;

  // true = sauvegarde réellement l'avatar
  // false = test uniquement
  final bool saveOnValidate;

  const AvatarPreviewScreen({
    super.key,
    required this.avatar,
    this.saveOnValidate = true,
  });

  @override
  State<AvatarPreviewScreen> createState() =>
      _AvatarPreviewScreenState();
}

class _AvatarPreviewScreenState
    extends State<AvatarPreviewScreen> {
  bool _saving = false;

  Future<void> _validateAvatar() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (widget.saveOnValidate) {
        await AvatarStorage.saveAvatar(
          widget.avatar,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) =>
              const HallScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de sauvegarder l’avatar : $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final bool isTest =
        !widget.saveOnValidate;

    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        foregroundColor:
            const Color(0xffffc857),
        elevation: 0,
        title: Text(
          isTest
              ? 'Aperçu du test'
              : 'Ton aventurier',
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (
            BuildContext context,
            BoxConstraints constraints,
          ) {
            final bool compact =
                constraints.maxHeight < 650;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                compact ? 10 : 20,
                24,
                compact ? 14 : 30,
              ),
              child: Column(
                children: [
                  Text(
                    isTest
                        ? 'MODE DEV'
                        : 'VOICI TON AVENTURIER',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color: const Color(
                        0xffffc857,
                      ),
                      fontSize:
                          compact ? 21 : 24,
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),

                  SizedBox(
                    height: compact ? 5 : 8,
                  ),

                  Text(
                    isTest
                        ? 'Pour le moment, ta photo est utilisée comme résultat de test. '
                            'Ton avatar actuel ne sera pas remplacé.'
                        : 'Tu pourras modifier ton avatar plus tard depuis ton profil.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize:
                          compact ? 13 : 14,
                      height: 1.35,
                    ),
                  ),

                  SizedBox(
                    height: compact ? 8 : 12,
                  ),

                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: AvatarRenderer(
                          avatar:
                              widget.avatar,
                          size: 285,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    height: compact ? 8 : 14,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height:
                        compact ? 50 : 54,
                    child:
                        OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              Navigator.pop(
                                context,
                              );
                            },
                      icon: const Icon(
                        Icons.edit,
                      ),
                      label: const Text(
                        'MODIFIER',
                      ),
                      style:
                          OutlinedButton.styleFrom(
                        foregroundColor:
                            const Color(
                          0xffffc857,
                        ),
                        side:
                            const BorderSide(
                          color: Color(
                            0xffffc857,
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                    height: compact ? 8 : 12,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height:
                        compact ? 52 : 56,
                    child:
                        ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : _validateAvatar,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 3,
                              ),
                            )
                          : Icon(
                              isTest
                                  ? Icons.check
                                  : Icons
                                      .check_circle,
                            ),
                      label: Text(
                        _saving
                            ? 'CHARGEMENT...'
                            : isTest
                                ? 'TERMINER LE TEST'
                                : 'VALIDER MON AVATAR',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                          letterSpacing:
                              0.8,
                        ),
                      ),
                      style:
                          ElevatedButton.styleFrom(
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
            );
          },
        ),
      ),
    );
  }
}
