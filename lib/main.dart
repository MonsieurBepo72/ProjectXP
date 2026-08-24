import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'navigation/project_xp_page_transitions.dart';
import 'screens/intro_splash_screen.dart';
import 'services/app_audio_service.dart';
import 'services/app_notification_service.dart';
import 'services/auth_service.dart';
import 'services/computer_settings_service.dart';
import 'services/local_account_repair_service.dart';
import 'services/supabase_service.dart';
import 'services/tavern_profile_service.dart';
import 'widgets/global_tap_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // FIREBASE
  //
  // Utilisé notamment pour les notifications push de Project XP.
  // La configuration est générée automatiquement par FlutterFire dans :
  // lib/firebase_options.dart
  // ===========================================================================

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ===========================================================================
  // ORIENTATION
  // ===========================================================================

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ===========================================================================
  // SUPABASE
  //
  // Backend social de Project XP :
  // - Taverne
  // - Channels
  // - Messages
  // - Mur des Aventuriers
  // - Fonctions sociales futures
  // ===========================================================================

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // ===========================================================================
  // SESSION SOCIALE SUPABASE
  // ===========================================================================

  try {
    final user =
        await SupabaseService.ensureAnonymousSession();

    debugPrint(
      'Supabase connecté : ${user?.id}',
    );
  } catch (error) {
    debugPrint(
      'Connexion Supabase impossible : $error',
    );
  }

  // ===========================================================================
  // INITIALISATION DES SERVICES PROJECT XP
  // ===========================================================================

  await AuthService.initialize();

  await LocalAccountRepairService.runOnce();

  await ComputerSettingsService.initialize();

  await AppAudioService.instance.initialize();

  await AppNotificationService.instance.initialize();

  // ===========================================================================
  // PROFIL PUBLIC DE LA TAVERNE
  //
  // Une fois le compte local Project XP chargé :
  //
  // pseudo Project XP
  //        ↓
  // tavern_profiles.display_name
  //
  // Si le profil existe déjà :
  // → il est mis à jour.
  //
  // S'il n'existe pas :
  // → il est créé.
  //
  // Une panne Supabase ne bloque pas le reste de Project XP.
  // ===========================================================================

  try {
    final bool profileSynced =
        await TavernProfileService.syncCurrentProfile();

    debugPrint(
      'Profil Taverne synchronisé : $profileSynced',
    );

    if (profileSynced) {
      final profile =
          await TavernProfileService.getCurrentProfile();

      debugPrint(
        'Profil Taverne : $profile',
      );
    }
  } catch (error) {
    debugPrint(
      'Synchronisation du profil Taverne impossible : $error',
    );
  }

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
        // =======================================================================

        pageTransitionsTheme: const PageTransitionsTheme(
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
          child: child ?? const SizedBox.shrink(),
        );
      },

      // =========================================================================
      // PREMIER ÉCRAN
      // =========================================================================

      home: const IntroSplashScreen(),
    );
  }
}