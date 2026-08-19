import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'navigation/project_xp_page_transitions.dart';
import 'screens/intro_splash_screen.dart';
import 'services/app_audio_service.dart';
import 'services/app_notification_service.dart';
import 'services/auth_service.dart';
import 'services/computer_settings_service.dart';
import 'services/local_account_repair_service.dart';
import 'widgets/global_tap_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // ORIENTATION
  // ===========================================================================

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ===========================================================================
  // INITIALISATION DES SERVICES
  // ===========================================================================

  await AuthService.initialize();

  await LocalAccountRepairService.runOnce();

  await ComputerSettingsService.initialize();

  await AppAudioService.instance.initialize();

  await AppNotificationService.instance.initialize();

  // ===========================================================================
  // LANCEMENT
  // ===========================================================================

  runApp(
    const ProjectXP(),
  );
}

// =============================================================================
// APPLICATION
// =============================================================================

class ProjectXP extends StatelessWidget {
  const ProjectXP({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      // =========================================================================
      // CONFIGURATION GÉNÉRALE
      // =========================================================================

      debugShowCheckedModeBanner: false,

      title: 'Project XP',

      // =========================================================================
      // THÈME PROJECT XP
      // =========================================================================

      theme: ThemeData(
        useMaterial3: true,

        brightness: Brightness.dark,

        scaffoldBackgroundColor: const Color(
          0xff160e09,
        ),

        // =======================================================================
        // TRANSITIONS GLOBALES PROJECT XP
        //
        // Toutes les pages utilisant MaterialPageRoute
        // bénéficieront automatiquement de :
        //
        // écran actuel
        // → noir
        // → nouvel écran
        //
        // Android
        // iPhone / iPad
        // Windows
        // macOS
        // Linux
        // Web selon la plateforme détectée
        //
        // Plus besoin de créer manuellement une animation
        // dans chaque Navigator.push().
        // =======================================================================

        pageTransitionsTheme:
            const PageTransitionsTheme(
          builders: {
            TargetPlatform.android:
                ProjectXpPageTransitionsBuilder(),

            TargetPlatform.iOS:
                ProjectXpPageTransitionsBuilder(),

            TargetPlatform.windows:
                ProjectXpPageTransitionsBuilder(),

            TargetPlatform.macOS:
                ProjectXpPageTransitionsBuilder(),

            TargetPlatform.linux:
                ProjectXpPageTransitionsBuilder(),

            TargetPlatform.fuchsia:
                ProjectXpPageTransitionsBuilder(),
          },
        ),
      ),

      // =========================================================================
      // FEEDBACK GLOBAL
      // =========================================================================

      builder: (
        context,
        child,
      ) {
        return GlobalTapFeedback(
          child:
              child ??
              const SizedBox.shrink(),
        );
      },

      // =========================================================================
      // PREMIER ÉCRAN
      //
      // On conserve exactement ton lancement actuel.
      // =========================================================================

      home: const IntroSplashScreen(),
    );
  }
}