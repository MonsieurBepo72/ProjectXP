import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/app_audio_service.dart';
import 'services/app_notification_service.dart';
import 'services/auth_service.dart';
import 'services/computer_settings_service.dart';
import 'services/local_account_repair_service.dart';
import 'widgets/global_tap_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await AuthService.initialize();

  // Réparation ponctuelle des anciens comptes locaux.
  // La méthode possède son propre flag et ne s'exécute qu'une seule fois.
  await LocalAccountRepairService.runOnce();

  await ComputerSettingsService.initialize();
  await AppAudioService.instance.initialize();
  await AppNotificationService.instance.initialize();

  runApp(
    const ProjectXP(),
  );
}

class ProjectXP extends StatelessWidget {
  const ProjectXP({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Project XP',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor:
            const Color(0xff160e09),
      ),
      builder: (context, child) {
        return GlobalTapFeedback(
          child:
              child ??
              const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}
