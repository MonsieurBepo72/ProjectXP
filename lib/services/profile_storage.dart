import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'team_storage.dart';

class ProfileStorage {
  // ===========================================================================
  // ANCIEN FORMAT
  //
  // On le garde comme miroir de compatibilité, mais il n'est plus la source
  // principale. Les données ne sont jamais supprimées pendant la migration.
  // ===========================================================================

  static const String _legacyProfileKey =
      'profile_data';

  static const String _legacyProfileUserIdKey =
      'profile_user_id';

  static const String _legacyMigrationTargetKey =
      'project_xp_profile_legacy_migrated_to';

  // ===========================================================================
  // NOUVEAU FORMAT
  // ===========================================================================

  static String _profileKey(
    String userId,
  ) {
    return 'project_xp_profile_$userId';
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  static Future<Map<String, dynamic>>
      loadProfile() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    final String? username =
        await AuthService.getCurrentUsername();

    final String? email =
        await AuthService.getCurrentEmail();

    if (userId == null ||
        userId.isEmpty) {
      return _defaultProfile(
        userId: '',
        username:
            username ?? 'Mon aventurier',
        email: email ?? '',
      );
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String key =
        _profileKey(userId);

    final String? accountRaw =
        prefs.getString(key);

    if (accountRaw != null &&
        accountRaw.isNotEmpty) {
      final Map<String, dynamic> data =
          _decodeProfile(
        accountRaw,
      );

      final Map<String, dynamic> normalized =
          _normalizeIdentity(
        data,
        userId: userId,
        username: username,
        email: email,
      );

      await _writeProfile(
        prefs,
        userId,
        normalized,
      );

      return normalized;
    }

    // -------------------------------------------------------------------------
    // Migration de l'ancien profil global.
    //
    // Il n'est copié qu'une seule fois vers le compte qui était actif lors de
    // la migration. Cela évite qu'un deuxième compte récupère par erreur le
    // profil du premier.
    // -------------------------------------------------------------------------

    final String? migrationTarget =
        prefs.getString(
      _legacyMigrationTargetKey,
    );

    final String? legacyRaw =
        prefs.getString(
      _legacyProfileKey,
    );

    final bool canUseLegacyProfile =
        legacyRaw != null &&
            legacyRaw.isNotEmpty &&
            (migrationTarget == null ||
                migrationTarget ==
                    userId);

    if (canUseLegacyProfile) {
      final Map<String, dynamic> legacyData =
          _decodeProfile(
        legacyRaw,
      );

      final Map<String, dynamic> migrated =
          _normalizeIdentity(
        legacyData,
        userId: userId,
        username: username,
        email: email,
      );

      await prefs.setString(
        _legacyMigrationTargetKey,
        userId,
      );

      await _writeProfile(
        prefs,
        userId,
        migrated,
      );

      return migrated;
    }

    final Map<String, dynamic> fresh =
        _defaultProfile(
      userId: userId,
      username:
          username ?? 'Mon aventurier',
      email: email ?? '',
    );

    await _writeProfile(
      prefs,
      userId,
      fresh,
    );

    return fresh;
  }

  // ===========================================================================
  // PROFIL D'UN AUTRE JOUEUR
  //
  // Lecture seule : cette méthode ne change jamais le compte actif et
  // n'écrase jamais le miroir legacy profile_data.
  // L'e-mail n'est volontairement pas exposé au profil public.
  // ===========================================================================

  static Future<Map<String, dynamic>>
      loadProfileForUser(
    String userId,
  ) async {
    final String cleanUserId =
        userId.trim();

    if (cleanUserId.isEmpty) {
      return _defaultProfile(
        userId: '',
        username: 'Joueur',
        email: '',
      );
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? username =
        await AuthService.getUsernameForUserId(
      cleanUserId,
    );

    final String? raw =
        prefs.getString(
      _profileKey(cleanUserId),
    );

    if (raw == null ||
        raw.isEmpty) {
      final Map<String, dynamic> fresh =
          _defaultProfile(
        userId: cleanUserId,
        username:
            username ?? 'Joueur',
        email: '',
      );

      fresh.remove('email');

      return fresh;
    }

    final Map<String, dynamic> data =
        _decodeProfile(raw);

    final String storedPseudo =
        data['pseudo']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic> result = {
      ...data,
      'id': cleanUserId,
      'userId': cleanUserId,
      'pseudo': username?.trim().isNotEmpty ==
              true
          ? username!.trim()
          : (storedPseudo.isNotEmpty
              ? storedPseudo
              : 'Joueur'),
    };

    result.remove('email');

    return result;
  }

  // ===========================================================================
  // SAUVEGARDE
  // ===========================================================================

  static Future<bool> saveProfile({
    required String pseudo,
    required String description,
    required List<String> games,
    required List<Map<String, String>>
        platforms,
    required Map<String, List<String>>
        availability,
    required List<Map<String, String>>
        networks,
    required String chatColor,
  }) async {
    final String? userId =
        await AuthService.getCurrentUserId();

    final String? email =
        await AuthService.getCurrentEmail();

    if (userId == null ||
        userId.isEmpty) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final Map<String, dynamic> oldData =
        await _loadExistingAccountProfile(
      prefs,
      userId,
    );

    final String cleanPseudo =
        pseudo.trim().isEmpty
            ? 'Mon aventurier'
            : pseudo.trim();

    final bool usernameAvailable =
        await AuthService.isUsernameAvailable(
      cleanPseudo,
      excludeUserId: userId,
    );

    if (!usernameAvailable) {
      return false;
    }

    final bool usernameUpdated =
        await AuthService.updateCurrentUsername(
      cleanPseudo,
    );

    if (!usernameUpdated) {
      return false;
    }

    final Map<String, dynamic> data = {
      ...oldData,

      // Les deux noms sont conservés afin que l'ancien code et le nouveau code
      // retrouvent toujours le même ID.
      'id': userId,
      'userId': userId,

      'email':
          email?.trim().toLowerCase() ?? '',

      'pseudo': cleanPseudo,
      'description': description,
      'games':
          List<String>.from(games),

      'platforms': platforms
          .map(
            (item) =>
                Map<String, String>.from(
              item,
            ),
          )
          .toList(),

      'availability': availability.map(
        (key, value) =>
            MapEntry(
          key,
          List<String>.from(value),
        ),
      ),

      'networks': networks
          .map(
            (item) =>
                Map<String, String>.from(
              item,
            ),
          )
          .toList(),

      // Couleur d'identité utilisée dans le Comptoir (pseudo, avatar, bulle).
      'chatColor': chatColor,
    };

    final bool saved =
        await _writeProfile(
      prefs,
      userId,
      data,
    );

    // Les équipes déjà créées par CE compte gardent le même ID,
    // mais leur nom de Chef/Admin est actualisé.
    await TeamStorage
        .syncCurrentUserDisplayName(
      cleanPseudo,
    );

    return saved;
  }

  static Future<bool> saveChatColor(
    String chatColor,
  ) async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null || userId.isEmpty) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final Map<String, dynamic> data =
        await _loadExistingAccountProfile(
      prefs,
      userId,
    );

    if (data.isEmpty) {
      final String? username =
          await AuthService.getCurrentUsername();
      final String? email =
          await AuthService.getCurrentEmail();

      data.addAll(
        _defaultProfile(
          userId: userId,
          username: username ?? 'Mon aventurier',
          email: email ?? '',
        ),
      );
    }

    data['chatColor'] = chatColor;

    return _writeProfile(
      prefs,
      userId,
      data,
    );
  }

  // ===========================================================================
  // OUTILS
  // ===========================================================================

  static Future<Map<String, dynamic>>
      _loadExistingAccountProfile(
    SharedPreferences prefs,
    String userId,
  ) async {
    final String? raw =
        prefs.getString(
      _profileKey(userId),
    );

    if (raw == null ||
        raw.isEmpty) {
      return <String, dynamic>{};
    }

    return _decodeProfile(raw);
  }

  static Map<String, dynamic> _decodeProfile(
    String raw,
  ) {
    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (_) {
      // On ne détruit jamais l'ancienne valeur.
    }

    return <String, dynamic>{};
  }

  static Map<String, dynamic>
      _normalizeIdentity(
    Map<String, dynamic> data, {
    required String userId,
    required String? username,
    required String? email,
  }) {
    final String existingPseudo =
        data['pseudo']
                ?.toString()
                .trim() ??
            '';

    return {
      ...data,
      'id': userId,
      'userId': userId,
      'email':
          email?.trim().toLowerCase() ?? '',
      'pseudo': username?.trim().isNotEmpty ==
              true
          ? username!.trim()
          : (existingPseudo.isNotEmpty
              ? existingPseudo
              : 'Mon aventurier'),
    };
  }

  static Map<String, dynamic> _defaultProfile({
    required String userId,
    required String username,
    required String email,
  }) {
    return {
      'id': userId,
      'userId': userId,
      'email': email.trim().toLowerCase(),
      'pseudo': username.trim().isNotEmpty
          ? username.trim()
          : 'Mon aventurier',
      'description':
          "Je cherche des compagnons pour partir à l'aventure !",
      'games': <String>[],
      'platforms':
          <Map<String, String>>[],
      'availability':
          <String, List<String>>{
        'Lundi': <String>[],
        'Mardi': <String>[],
        'Mercredi': <String>[],
        'Jeudi': <String>[],
        'Vendredi': <String>[],
        'Samedi': <String>[],
        'Dimanche': <String>[],
      },
      'networks':
          <Map<String, String>>[],
      'chatColor': '#C56CFF',
    };
  }

  static Future<bool> _writeProfile(
    SharedPreferences prefs,
    String userId,
    Map<String, dynamic> data,
  ) async {
    final String encoded =
        jsonEncode(data);

    final bool accountSaved =
        await prefs.setString(
      _profileKey(userId),
      encoded,
    );

    // Miroir pour les anciens écrans/services encore présents.
    // Quand on change de compte, ce miroir est remplacé par le profil actif,
    // mais chaque profil individuel reste conservé dans project_xp_profile_ID.
    await prefs.setString(
      _legacyProfileKey,
      encoded,
    );

    await prefs.setString(
      _legacyProfileUserIdKey,
      userId,
    );

    return accountSaved;
  }
}
