import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'cloud_data_service.dart';
import 'team_storage.dart';

class ProfileStorage {
  static const String _legacyProfileKey = 'profile_data';
  static const String _legacyProfileUserIdKey = 'profile_user_id';
  static const String _legacyMigrationTargetKey =
      'project_xp_profile_legacy_migrated_to';
  static const Duration _cloudRefreshCooldown = Duration(minutes: 1);

  static Future<void>? _cloudRefreshTask;
  static DateTime? _lastCloudRefreshAt;
  static int _localRevision = 0;
  static String? _cachedUserId;
  static Map<String, dynamic>? _cachedProfile;

  static String _profileKey(String userId) => 'project_xp_profile_$userId';

  // ===========================================================================
  // CHARGEMENT : LE PROFIL LOCAL S'AFFICHE SANS ATTENDRE SUPABASE
  // ===========================================================================

  static Future<Map<String, dynamic>> loadProfile() async {
    final String? userId = await AuthService.getCurrentUserId();

    if (userId != null &&
        userId.isNotEmpty &&
        _cachedUserId == userId &&
        _cachedProfile != null) {
      if (CloudDataService.permanentUser != null) {
        _scheduleCloudRefresh(userId);
      }
      return Map<String, dynamic>.from(_cachedProfile!);
    }

    final String? username = await AuthService.getCurrentUsername();
    final String? email = await AuthService.getCurrentEmail();

    if (userId == null || userId.isEmpty) {
      return _defaultProfile(
        userId: '',
        username: username ?? 'Mon aventurier',
        email: email ?? '',
      );
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? existingRaw = prefs.getString(_profileKey(userId));
    final bool hadLocalProfile = existingRaw != null && existingRaw.isNotEmpty;

    final Map<String, dynamic> local = await _loadOrMigrateLocalProfile(
      prefs,
      userId: userId,
      username: username,
      email: email,
    );

    _cachedUserId = userId;
    _cachedProfile = Map<String, dynamic>.from(local);

    if (CloudDataService.permanentUser == null) {
      return local;
    }

    if (hadLocalProfile) {
      _scheduleCloudRefresh(userId);
      return local;
    }

    // Nouvel appareil : sans cache local, une lecture Cloud est nécessaire une
    // seule fois pour retrouver la vraie fiche du joueur.
    return _loadProfileWithCloud();
  }

  static void _scheduleCloudRefresh(String userId) {
    if (_cloudRefreshTask != null || CloudDataService.permanentUser == null) {
      return;
    }

    final DateTime now = DateTime.now();
    if (_lastCloudRefreshAt != null &&
        now.difference(_lastCloudRefreshAt!) < _cloudRefreshCooldown) {
      return;
    }

    final int revision = _localRevision;
    final Future<void> task = _refreshCloudCache(userId, revision);
    _cloudRefreshTask = task;
    unawaited(task);
  }

  static Future<void> _refreshCloudCache(String userId, int revision) async {
    try {
      final CloudReadResult<Map<String, dynamic>> cloud =
          await CloudDataService.loadPrivateProfile();
      if (!cloud.available || !cloud.found || cloud.value == null) {
        return;
      }
      if (_localRevision != revision) {
        return;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? username = await AuthService.getCurrentUsername();
      final String? email = await AuthService.getCurrentEmail();
      final Map<String, dynamic> local = await _loadOrMigrateLocalProfile(
        prefs,
        userId: userId,
        username: username,
        email: email,
      );
      if (_localRevision != revision) {
        return;
      }

      final DateTime? localUpdatedAt = _profileUpdatedAt(local);
      final DateTime? cloudUpdatedAt = _profileUpdatedAt(cloud.value!);

      if (localUpdatedAt != null &&
          (cloudUpdatedAt == null || localUpdatedAt.isAfter(cloudUpdatedAt))) {
        unawaited(
          CloudDataService.savePrivateProfile(local).then<void>((_) {}),
        );
        return;
      }

      final Map<String, dynamic> normalized = _normalizeIdentity(
        Map<String, dynamic>.from(cloud.value!),
        userId: userId,
        username: username,
        email: email,
      );

      if (_localRevision == revision) {
        await _writeProfile(prefs, userId, normalized);
      }
    } catch (_) {
      // Le profil local reste disponible.
    } finally {
      _lastCloudRefreshAt = DateTime.now();
      _cloudRefreshTask = null;
    }
  }

  static Future<Map<String, dynamic>> _loadProfileWithCloud() async {
    final String? userId = await AuthService.getCurrentUserId();
    String? username = await AuthService.getCurrentUsername();
    final String? email = await AuthService.getCurrentEmail();

    if (userId == null || userId.isEmpty) {
      return _defaultProfile(
        userId: '',
        username: username ?? 'Mon aventurier',
        email: email ?? '',
      );
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? existingLocalRaw = prefs.getString(_profileKey(userId));
    final bool hadAccountLocalProfile =
        existingLocalRaw != null && existingLocalRaw.isNotEmpty;

    Map<String, dynamic> localProfile = await _loadOrMigrateLocalProfile(
      prefs,
      userId: userId,
      username: username,
      email: email,
    );

    final CloudReadResult<Map<String, dynamic>> cloud =
        await CloudDataService.loadPrivateProfile();

    if (!cloud.available) {
      return localProfile;
    }

    if (!cloud.found || cloud.value == null) {
      if (_profileUpdatedAt(localProfile) == null) {
        localProfile = <String, dynamic>{
          ...localProfile,
          'updatedAt': DateTime.now().toIso8601String(),
        };
        await _writeProfile(prefs, userId, localProfile);
      }
      await CloudDataService.savePrivateProfile(localProfile);
      return localProfile;
    }

    final Map<String, dynamic> cloudProfile = Map<String, dynamic>.from(
      cloud.value!,
    );

    if (hadAccountLocalProfile) {
      final DateTime? localUpdatedAt = _profileUpdatedAt(localProfile);
      final DateTime? cloudUpdatedAt = _profileUpdatedAt(cloudProfile);
      if (localUpdatedAt != null &&
          (cloudUpdatedAt == null || localUpdatedAt.isAfter(cloudUpdatedAt))) {
        await CloudDataService.savePrivateProfile(localProfile);
        return localProfile;
      }
    }

    final String cloudPseudo = cloudProfile['pseudo']?.toString().trim() ?? '';
    if (cloudPseudo.isNotEmpty && cloudPseudo != username?.trim()) {
      final bool updated = await AuthService.updateCurrentUsername(cloudPseudo);
      if (updated) username = cloudPseudo;
    }

    final Map<String, dynamic> normalized = _normalizeIdentity(
      cloudProfile,
      userId: userId,
      username: username,
      email: email,
    );
    await _writeProfile(prefs, userId, normalized);
    return normalized;
  }

  static Future<void> syncCurrentProfileWithCloud() async {
    await _loadProfileWithCloud();
  }

  static Future<Map<String, dynamic>> _loadOrMigrateLocalProfile(
    SharedPreferences prefs, {
    required String userId,
    required String? username,
    required String? email,
  }) async {
    final String? accountRaw = prefs.getString(_profileKey(userId));
    if (accountRaw != null && accountRaw.isNotEmpty) {
      final Map<String, dynamic> normalized = _normalizeIdentity(
        _decodeProfile(accountRaw),
        userId: userId,
        username: username,
        email: email,
      );
      await _writeProfile(prefs, userId, normalized, countRevision: false);
      return normalized;
    }

    final String? migrationTarget = prefs.getString(_legacyMigrationTargetKey);
    final String? legacyRaw = prefs.getString(_legacyProfileKey);
    final bool canUseLegacyProfile =
        legacyRaw != null &&
        legacyRaw.isNotEmpty &&
        (migrationTarget == null || migrationTarget == userId);

    if (canUseLegacyProfile) {
      final Map<String, dynamic> migrated = _normalizeIdentity(
        _decodeProfile(legacyRaw),
        userId: userId,
        username: username,
        email: email,
      );
      await prefs.setString(_legacyMigrationTargetKey, userId);
      await _writeProfile(prefs, userId, migrated);
      return migrated;
    }

    final Map<String, dynamic> fresh = _defaultProfile(
      userId: userId,
      username: username ?? 'Mon aventurier',
      email: email ?? '',
    );
    await _writeProfile(prefs, userId, fresh);
    return fresh;
  }

  // ===========================================================================
  // PROFIL PUBLIC D'UN AUTRE JOUEUR
  // ===========================================================================

  static Future<Map<String, dynamic>> loadProfileForUser(String userId) async {
    final String cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) {
      return _defaultProfile(userId: '', username: 'Joueur', email: '');
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? username = await AuthService.getUsernameForUserId(
      cleanUserId,
    );
    final String? raw = prefs.getString(_profileKey(cleanUserId));

    if (raw == null || raw.isEmpty) {
      final Map<String, dynamic> fresh = _defaultProfile(
        userId: cleanUserId,
        username: username ?? 'Joueur',
        email: '',
      );
      fresh.remove('email');
      return fresh;
    }

    final Map<String, dynamic> data = _decodeProfile(raw);
    final String storedPseudo = data['pseudo']?.toString().trim() ?? '';
    final Map<String, dynamic> result = <String, dynamic>{
      ...data,
      'id': cleanUserId,
      'userId': cleanUserId,
      'pseudo': username?.trim().isNotEmpty == true
          ? username!.trim()
          : (storedPseudo.isNotEmpty ? storedPseudo : 'Joueur'),
    };
    result.remove('email');
    return result;
  }

  // ===========================================================================
  // SAUVEGARDE : LOCAL IMMÉDIAT, CLOUD APRÈS
  // ===========================================================================

  static Future<bool> saveProfile({
    required String pseudo,
    required String description,
    required List<String> games,
    required List<Map<String, String>> platforms,
    required Map<String, List<String>> availability,
    required List<Map<String, String>> networks,
    required String chatColor,
  }) async {
    final String? userId = await AuthService.getCurrentUserId();
    final String? email = await AuthService.getCurrentEmail();
    if (userId == null || userId.isEmpty) {
      return false;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> oldData = await _loadExistingAccountProfile(
      prefs,
      userId,
    );
    final String cleanPseudo = pseudo.trim().isEmpty
        ? 'Mon aventurier'
        : pseudo.trim();

    final bool usernameAvailable = await AuthService.isUsernameAvailable(
      cleanPseudo,
      excludeUserId: userId,
    );
    if (!usernameAvailable) return false;

    final bool usernameUpdated = await AuthService.updateCurrentUsername(
      cleanPseudo,
    );
    if (!usernameUpdated) return false;

    final Map<String, dynamic> data = <String, dynamic>{
      ...oldData,
      'id': userId,
      'userId': userId,
      'email': email?.trim().toLowerCase() ?? '',
      'pseudo': cleanPseudo,
      'description': description,
      'games': List<String>.from(games),
      'platforms': platforms
          .map((item) => Map<String, String>.from(item))
          .toList(),
      'availability': availability.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
      'networks': networks
          .map((item) => Map<String, String>.from(item))
          .toList(),
      'chatColor': chatColor,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final bool saved = await _writeProfile(prefs, userId, data);
    if (saved) {
      unawaited(CloudDataService.savePrivateProfile(data).then<void>((_) {}));
      unawaited(
        TeamStorage.syncCurrentUserDisplayName(cleanPseudo).then<void>((_) {}),
      );
    }
    return saved;
  }

  static Future<bool> saveChatColor(String chatColor) async {
    final String? userId = await AuthService.getCurrentUserId();
    if (userId == null || userId.isEmpty) return false;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = await _loadExistingAccountProfile(
      prefs,
      userId,
    );

    if (data.isEmpty) {
      final String? username = await AuthService.getCurrentUsername();
      final String? email = await AuthService.getCurrentEmail();
      data.addAll(
        _defaultProfile(
          userId: userId,
          username: username ?? 'Mon aventurier',
          email: email ?? '',
        ),
      );
    }

    data['chatColor'] = chatColor;
    data['updatedAt'] = DateTime.now().toIso8601String();
    final bool saved = await _writeProfile(prefs, userId, data);
    if (saved) {
      unawaited(CloudDataService.savePrivateProfile(data).then<void>((_) {}));
    }
    return saved;
  }

  // ===========================================================================
  // OUTILS
  // ===========================================================================

  static Future<Map<String, dynamic>> _loadExistingAccountProfile(
    SharedPreferences prefs,
    String userId,
  ) async {
    if (_cachedUserId == userId && _cachedProfile != null) {
      return Map<String, dynamic>.from(_cachedProfile!);
    }

    final String? raw = prefs.getString(_profileKey(userId));
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    return _decodeProfile(raw);
  }

  static Map<String, dynamic> _decodeProfile(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // On ne détruit jamais l'ancienne valeur.
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _normalizeIdentity(
    Map<String, dynamic> data, {
    required String userId,
    required String? username,
    required String? email,
  }) {
    final String existingPseudo = data['pseudo']?.toString().trim() ?? '';
    return <String, dynamic>{
      ...data,
      'id': userId,
      'userId': userId,
      'email': email?.trim().toLowerCase() ?? '',
      'pseudo': username?.trim().isNotEmpty == true
          ? username!.trim()
          : (existingPseudo.isNotEmpty ? existingPseudo : 'Mon aventurier'),
    };
  }

  static DateTime? _profileUpdatedAt(Map<String, dynamic> profile) =>
      DateTime.tryParse(profile['updatedAt']?.toString() ?? '');

  static Map<String, dynamic> _defaultProfile({
    required String userId,
    required String username,
    required String email,
  }) {
    return <String, dynamic>{
      'id': userId,
      'userId': userId,
      'email': email.trim().toLowerCase(),
      'pseudo': username.trim().isNotEmpty ? username.trim() : 'Mon aventurier',
      'description': "Je cherche des compagnons pour partir à l'aventure !",
      'games': <String>[],
      'platforms': <Map<String, String>>[],
      'availability': <String, List<String>>{
        'Lundi': <String>[],
        'Mardi': <String>[],
        'Mercredi': <String>[],
        'Jeudi': <String>[],
        'Vendredi': <String>[],
        'Samedi': <String>[],
        'Dimanche': <String>[],
      },
      'networks': <Map<String, String>>[],
      'chatColor': '#C56CFF',
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  static Future<bool> _writeProfile(
    SharedPreferences prefs,
    String userId,
    Map<String, dynamic> data, {
    bool countRevision = true,
  }) async {
    final String encoded = jsonEncode(data);
    final bool accountSaved = await prefs.setString(
      _profileKey(userId),
      encoded,
    );
    if (accountSaved) {
      _cachedUserId = userId;
      _cachedProfile = Map<String, dynamic>.from(data);
    }
    await prefs.setString(_legacyProfileKey, encoded);
    await prefs.setString(_legacyProfileUserIdKey, userId);
    if (accountSaved && countRevision) {
      _localRevision += 1;
    }
    return accountSaved;
  }
}
