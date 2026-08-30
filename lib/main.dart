import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'navigation/project_xp_page_transitions.dart';
import 'screens/intro_splash_screen.dart';
import 'services/project_xp_communicator_ui_service.dart';
import 'services/project_xp_startup_service.dart';
import 'widgets/global_communicator_alert.dart';
import 'widgets/global_tap_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // DÉMARRAGE CRITIQUE MINIMAL
  //
  // Ces trois opérations indépendantes sont lancées EN PARALLÈLE.
  //
  // - Firebase doit exister avant que le service FCM soit instancié.
  // - Supabase doit exister avant les streams sociaux globaux.
  // - L'orientation est verrouillée sans ajouter une attente séquentielle.
  //
  // AUCUNE connexion réseau, synchronisation de profil, audio ou migration
  // lourde n'est attendue ici.
  // ===========================================================================

  // Firebase et l'orientation sont utiles, mais ne doivent pas empêcher
  // Project XP de démarrer si une plateforme n'est pas encore configurée
  // (ex. iOS avant la future configuration FlutterFire).
  final Future<void> firebaseFuture =
      _initializeFirebaseSafely();

  final Future<void> orientationFuture =
      _setPreferredOrientationsSafely();

  // Supabase reste une dépendance critique : auth, profils et social
  // reposent dessus. Une configuration Supabase invalide doit donc rester
  // visible immédiatement au développement au lieu d'être masquée.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  await Future.wait<void>(
    <Future<void>>[
      firebaseFuture,
      orientationFuture,
    ],
  );

  // ===========================================================================
  // PREMIÈRE FRAME LE PLUS TÔT POSSIBLE
  // ===========================================================================

  runApp(
    const ProjectXP(),
  );

  // Tout le reste travaille pendant l'intro / le splash.
  unawaited(
    ProjectXpStartupService.instance.start().onError(
      (Object error, StackTrace _) {
        debugPrint(
          'Démarrage différé Project XP interrompu : $error',
        );
      },
    ),
  );
}

Future<void> _initializeFirebaseSafely() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    // Les fonctions dépendantes de Firebase (FCM, notifications) possèdent
    // leurs propres garde-fous. L'app peut donc continuer sans push.
    debugPrint(
      'Firebase indisponible au démarrage : $error',
    );
  }
}

Future<void> _setPreferredOrientationsSafely() async {
  try {
    await SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    );
  } catch (error) {
    debugPrint(
      'Verrouillage orientation indisponible : $error',
    );
  }
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
      debugShowCheckedModeBanner:
          false,

      navigatorKey:
          projectXpNavigatorKey,

      navigatorObservers:
          <NavigatorObserver>[
        projectXpRouteObserver,
      ],

      title:
          'Project XP',

      theme:
          ThemeData(
        useMaterial3:
            true,
        brightness:
            Brightness.dark,
        scaffoldBackgroundColor:
            const Color(
          0xff160e09,
        ),
        pageTransitionsTheme:
            const PageTransitionsTheme(
          builders:
              <TargetPlatform,
                  PageTransitionsBuilder>{
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

      builder: (
        BuildContext context,
        Widget? child,
      ) {
        return GlobalCommunicatorAlert(
          child:
              GlobalTapFeedback(
            child:
                child ??
                    const SizedBox.shrink(),
          ),
        );
      },

      home:
          const IntroSplashScreen(),
    );
  }
}
