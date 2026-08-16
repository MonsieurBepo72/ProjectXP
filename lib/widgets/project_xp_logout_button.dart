import 'package:flutter/material.dart';

import 'package:project_xp/screens/splash_screen.dart';
import 'package:project_xp/services/session_service.dart';

class ProjectXpLogoutButton
    extends StatelessWidget {
  const ProjectXpLogoutButton({
    super.key,
  });

  Future<void> _logout(
    BuildContext context,
  ) async {
    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(
            0xff21150e,
          ),
          title:
              const Text(
            'Déconnexion',
            style:
                TextStyle(
              color:
                  Color(
                0xffffc857,
              ),
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content:
              const Text(
            'Tu veux vraiment te déconnecter de Project XP ?',
            style:
                TextStyle(
              color:
                  Colors.white70,
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
              child:
                  const Text(
                'ANNULER',
                style:
                    TextStyle(
                  color:
                      Colors.white54,
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
              child:
                  const Text(
                'SE DÉCONNECTER',
                style:
                    TextStyle(
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

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) =>
            const SplashScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child:
          OutlinedButton.icon(
        onPressed: () =>
            _logout(context),
        icon:
            const Icon(
          Icons.logout,
        ),
        label:
            const Text(
          'SE DÉCONNECTER',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
            letterSpacing:
                1,
          ),
        ),
        style:
            OutlinedButton.styleFrom(
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
    );
  }
}
