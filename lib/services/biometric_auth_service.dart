import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class BiometricAuthService {
  BiometricAuthService._();

  static final LocalAuthentication _auth =
      LocalAuthentication();

  /// Un seul compte biométrique actif à la fois sur l'appareil.
  ///
  /// local_auth confirme l'identité locale mais ne dit pas "quel compte
  /// Project XP" est devant l'écran. On mémorise donc explicitement le compte
  /// choisi après une connexion par mot de passe réussie.
  static const String _enabledUserIdKey =
      'project_xp_biometric_user_id';

  static Future<bool> isBiometricAvailable() async {
    try {
      final bool supported =
          await _auth.isDeviceSupported();

      if (!supported) {
        return false;
      }

      final bool canCheck =
          await _auth.canCheckBiometrics;

      if (!canCheck) {
        return false;
      }

      final List<BiometricType> enrolled =
          await _auth
              .getAvailableBiometrics();

      return enrolled.isNotEmpty;
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isDeviceAuthenticationAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Empreinte / visage uniquement.
  ///
  /// Utilisé pour activer la connexion biométrique et pour les connexions
  /// suivantes.
  static Future<bool> authenticateBiometricOnly({
    String reason =
        'Authentifie-toi pour accéder à Project XP.',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Authentification locale de l'appareil avec biométrie OU PIN/code.
  ///
  /// Cette méthode sert uniquement à sécuriser la migration des anciens comptes
  /// qui n'avaient aucun vrai mot de passe enregistré.
  static Future<bool> authenticateDeviceOwner({
    String reason =
        'Confirme que cet appareil t’appartient pour sécuriser ton ancien compte Project XP.',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enableForCurrentAccount() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty) {
      return false;
    }

    final bool available =
        await isBiometricAvailable();

    if (!available) {
      return false;
    }

    final bool authenticated =
        await authenticateBiometricOnly(
      reason:
          'Confirme ton empreinte ou ton visage pour activer la connexion biométrique à Project XP.',
    );

    if (!authenticated) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.setString(
      _enabledUserIdKey,
      userId.trim(),
    );
  }

  static Future<void> disable() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(
      _enabledUserIdKey,
    );
  }

  static Future<String?> getEnabledUserId() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? value =
        prefs.getString(
      _enabledUserIdKey,
    );

    if (value == null ||
        value.trim().isEmpty) {
      return null;
    }

    return value.trim();
  }

  static Future<String?> getEnabledUsername() async {
    final String? userId =
        await getEnabledUserId();

    if (userId == null) {
      return null;
    }

    return AuthService.getUsernameForUserId(
      userId,
    );
  }

  static Future<bool> canUseBiometricLogin() async {
    final String? userId =
        await getEnabledUserId();

    if (userId == null) {
      return false;
    }

    final List<Map<String, dynamic>> accounts =
        await AuthService.getLocalAccounts();

    final bool accountStillExists =
        accounts.any(
      (account) =>
          account['id']?.toString() ==
          userId,
    );

    if (!accountStillExists) {
      await disable();
      return false;
    }

    return isBiometricAvailable();
  }
}
