import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class SessionService {
  // Durée de validité d'une session locale.
  // Tu peux la changer plus tard si tu veux.
  static const Duration sessionDuration = Duration(days: 30);

  static const String _expiresAtKey =
      'project_xp_session_expires_at';

  /// Vérifie la session au démarrage.
  ///
  /// - pas connecté => false
  /// - session invalide => déconnexion + false
  /// - session expirée => déconnexion + false
  /// - ancienne session sans date d'expiration => migration automatique
  /// - session valide => true
  static Future<bool> validateSessionAtStartup() async {
    final bool isLoggedIn =
        await AuthService.isLoggedIn();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    if (!isLoggedIn) {
      await prefs.remove(_expiresAtKey);
      return false;
    }

    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null || userId.trim().isEmpty) {
      await logout();
      return false;
    }

    final int? expiresAtMillis =
        prefs.getInt(_expiresAtKey);

    // Compatibilité avec les anciennes sessions :
    // si l'utilisateur était déjà connecté avant l'ajout
    // du système d'expiration, on lui crée une session
    // valide de 30 jours à partir de maintenant.
    if (expiresAtMillis == null) {
      await startNewSession();
      return true;
    }

    final DateTime expiresAt =
        DateTime.fromMillisecondsSinceEpoch(
      expiresAtMillis,
    );

    if (DateTime.now().isAfter(expiresAt) ||
        DateTime.now().isAtSameMomentAs(expiresAt)) {
      await logout();
      return false;
    }

    return true;
  }

  /// Crée / renouvelle une session locale.
  static Future<void> startNewSession() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final DateTime expiresAt =
        DateTime.now().add(sessionDuration);

    await prefs.setInt(
      _expiresAtKey,
      expiresAt.millisecondsSinceEpoch,
    );
  }

  /// Déconnexion complète de la session.
  /// Ne touche pas aux données d'avatar/profil :
  /// il retire uniquement la session de connexion.
  static Future<void> logout() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(_expiresAtKey);
    await AuthService.logout();
  }

  /// Utile uniquement pour debug / affichage.
  static Future<DateTime?> getExpirationDate() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final int? value =
        prefs.getInt(_expiresAtKey);

    if (value == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(
      value,
    );
  }
}
