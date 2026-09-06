import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'cloud_session_guard_service.dart';
import 'project_xp_startup_service.dart';
import 'push_device_token_service.dart';

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

    // Migration Étape 04A.2 : un ancien compte peut avoir été créé avant que
    // Project XP mémorise explicitement s'il est local-only ou Cloud. Tant que
    // ce statut est inconnu, on n'entre pas dans l'app avec une identité
    // Supabase possiblement héritée d'un autre compte. Une session permanente
    // déjà alignée peut être reconnue sans mot de passe ; sinon on force une
    // reconnexion par mot de passe une seule fois.
    final CloudLocalAccountKind accountKind =
        await CloudSessionGuardService.currentLocalAccountKind();

    if (accountKind == CloudLocalAccountKind.unknown) {
      final bool alreadyAligned =
          await CloudSessionGuardService.ensureAlignedSessionWithoutPassword();

      if (!alreadyAligned) {
        await logout();
        return false;
      }
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

    // Le service de démarrage principal n'est exécuté qu'une fois par processus.
    // Après un logout/login sans redémarrer l'application, on relance donc
    // explicitement les synchronisations liées AU COMPTE ACTUEL.
    unawaited(
      ProjectXpStartupService.instance
          .resumeAfterLocalAuthentication(),
    );
  }

  /// Verrouille uniquement l'accès local à Project XP.
  ///
  /// Contrairement à [logout], cette action conserve la session Supabase
  /// correctement alignée et le token FCM. Elle est destinée à un verrouillage
  /// de l'application sur le même appareil : la biométrie peut alors réouvrir
  /// le même compte sans stocker le mot de passe.
  ///
  /// Aucune synchronisation personnelle n'est relancée tant que le compte local
  /// n'a pas été réauthentifié.
  static Future<void> lock() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(_expiresAtKey);
    await AuthService.logout();
    ProjectXpStartupService.instance.notifyLocalLogout();
  }

  /// Déconnexion de la session locale.
  ///
  /// Étape 04A.1 : avant de marquer le compte local comme déconnecté,
  /// on retire le token FCM de CET appareil pour l'utilisateur Supabase courant.
  /// Les données locales (profil/avatar/bibliothèque) restent conservées.
  ///
  /// Étape 04A.2 : après le nettoyage FCM, la session Supabase permanente est
  /// mémorisée puis fermée. Le prochain login par mot de passe devra réaligner
  /// explicitement le même compte Cloud avant les synchronisations personnelles.
  static Future<void> logout() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    try {
      final String token =
          (await FirebaseMessaging.instance.getToken())
                  ?.trim() ??
              '';

      if (token.isNotEmpty) {
        await PushDeviceTokenService.removeToken(token);
      }

      // Même si la suppression Supabase échoue ou si une ancienne ligne reste
      // encore en base, on invalide aussi le token de cette installation.
      // Le prochain login obtiendra un nouveau token puis le réenregistrera.
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // La déconnexion locale ne doit jamais être bloquée si Firebase/FCM
      // est indisponible. Le garde-fou de saveToken empêche ensuite tout
      // réenregistrement tant que le compte local reste déconnecté.
    }

    // Mémorise le mapping du compte permanent AVANT de fermer Supabase.
    // Ainsi le prochain login sait qu'il doit réauthentifier ce même compte
    // Cloud au lieu de retomber silencieusement sur une session anonyme.
    await CloudSessionGuardService.rememberCurrentPermanentBinding();
    await CloudSessionGuardService.signOutPermanentSession();

    await prefs.remove(_expiresAtKey);
    await AuthService.logout();
    ProjectXpStartupService.instance.notifyLocalLogout();
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
