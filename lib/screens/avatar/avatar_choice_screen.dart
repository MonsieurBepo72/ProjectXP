import 'package:flutter/material.dart';

import 'avatar_manual_screen.dart';
import 'avatar_photo_screen.dart';

class AvatarChoiceScreen extends StatelessWidget {
  const AvatarChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff160e09),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            24,
            30,
            24,
            25,
          ),
          child: Column(
            children: [
              const Text(
                'CRÉE TON AVENTURIER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Comment souhaites-tu créer ton avatar ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 40),

              Expanded(
                child: _AvatarChoiceCard(
                  icon: Icons.auto_awesome,
                  title: 'CRÉER MON AVATAR',
                  description:
                      'Personnalise ton aventurier : visage, cheveux, barbe, tenue et accessoires.',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) {
                          return const AvatarManualScreen();
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 18),

              Expanded(
                child: _AvatarChoiceCard(
                  icon: Icons.add_a_photo,
                  title: 'UTILISER UNE PHOTO',
                  description:
                      'Prends une photo ou choisis-en une dans ta galerie pour créer un aventurier inspiré de toi.',
                  badge: 'OPTIONNEL',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) {
                          return const AvatarPhotoScreen();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarChoiceCard
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  const _AvatarChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff2b1b12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xffffc857),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              if (badge != null)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xff5c3317),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color:
                            Color(0xffffc857),
                        fontSize: 10,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              Icon(
                icon,
                color: const Color(0xffffc857),
                size: 60,
              ),

              const SizedBox(height: 20),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xffffc857),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}