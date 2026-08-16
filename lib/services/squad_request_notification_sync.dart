import 'app_notification_service.dart';
import 'auth_service.dart';
import 'computer_settings_service.dart';
import 'squad_request_storage.dart';

class SquadRequestNotificationSync {
  const SquadRequestNotificationSync._();

  /// À appeler quand le Hall devient visible.
  ///
  /// Si le compte connecté a reçu une nouvelle demande
  /// de Squad, Android reçoit une vraie notification,
  /// une seule fois par demande.
  static Future<void> syncForCurrentUser() async {
    if (!ComputerSettingsService
        .current.notificationsEnabled) {
      return;
    }

    final bool systemAllowed =
        await AppNotificationService
            .instance
            .areSystemNotificationsEnabled();

    if (!systemAllowed) {
      return;
    }

    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty) {
      return;
    }

    final requests =
        await SquadRequestStorage
            .pendingIncomingForUser(
      userId,
    );

    for (final request in requests) {
      if (request.androidNotifiedUserIds
          .contains(userId)) {
        continue;
      }

      await AppNotificationService
          .instance
          .show(
        title:
            'Nouvelle demande Squad',
        body:
            '${request.requesterName} souhaite rejoindre ${request.teamName}.',
        payload:
            'squad_join_request:${request.id}',
      );

      await SquadRequestStorage
          .markAndroidNotified(
        requestId: request.id,
        userId: userId,
      );
    }
  }
}
