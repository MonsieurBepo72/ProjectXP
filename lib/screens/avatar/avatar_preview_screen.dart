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
  Widget build(BuildContext context) {
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
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            20,
            24,
            30,
          ),
          child: Column(
            children: [
              Text(
                isTest
                    ? 'MODE DEV'
                    : 'VOICI TON AVENTURIER',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color:
                      Color(0xffffc857),
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                isTest
                    ? 'Pour le moment, ta photo est utilisée comme résultat de test. '
                        'Ton avatar actuel ne sera pas remplacé.'
                    : 'Tu pourras modifier ton avatar plus tard depuis ton profil.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const Spacer(),

              AvatarRenderer(
                avatar: widget.avatar,
                size: 285,
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
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
                      color:
                          Color(
                        0xffffc857,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
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
                              ? Icons
                                  .check
                              : Icons
                                  .check_circle,
                        ),
                  label: Text(
                    _saving
                        ? 'CHARGEMENT...'
                        : isTest
                            ? 'TERMINER LE TEST'
                            : 'VALIDER MON AVATAR',
                    style: const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing: 0.8,
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
        ),
      ),
    );
  }
}