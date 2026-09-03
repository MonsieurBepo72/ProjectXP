import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_model.dart';
import 'auth_service.dart';
import 'cloud_data_service.dart';
import 'supabase_service.dart';

class AvatarStorage {
  static const String _prefix = 'project_xp_avatar_';
  static const Duration _cloudRefreshCooldown = Duration(minutes: 1);

  static Future<void>? _cloudRefreshTask;
  static DateTime? _lastCloudRefreshAt;
  static int _localRevision = 0;
  static final Map<String, AvatarModel?> _localCache = <String, AvatarModel?>{};

  static String _key(String userId) => '$_prefix$userId';

  // ===========================================================================
  // SAUVEGARDE : L'AVATAR LOCAL EST VALIDÉ AVANT TOUT APPEL RÉSEAU
  // ===========================================================================

  static Future<bool> saveAvatar(AvatarModel avatar) async {
    final bool saved = await _saveLocalAvatar(avatar);
    if (!saved) return false;

    if (CloudDataService.permanentUser != null) {
      unawaited(CloudDataService.savePrivateAvatar(avatar).then<void>((_) {}));
    }
    return true;
  }

  static Future<bool> _saveLocalAvatar(AvatarModel avatar) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool saved = await prefs.setString(
      _key(avatar.userId),
      jsonEncode(avatar.toJson()),
    );
    if (saved) {
      _localCache[avatar.userId] = avatar;
      _localRevision += 1;
    }
    return saved;
  }

  // ===========================================================================
  // CHARGEMENT : CACHE LOCAL IMMÉDIAT POUR LE COMPTE ACTIF
  // ===========================================================================

  static Future<AvatarModel?> loadAvatar(String userId) async {
    final String cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) return null;

    final AvatarModel? localAvatar = await _loadLocalAvatar(cleanUserId);
    final String currentUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (currentUserId.isNotEmpty &&
        cleanUserId == currentUserId &&
        CloudDataService.permanentUser != null) {
      if (localAvatar != null) {
        _scheduleCloudRefresh(cleanUserId, localAvatar);
        return localAvatar;
      }

      // Un nouvel appareil n'a encore aucun cache : une première lecture Cloud
      // est nécessaire, puis les ouvertures suivantes redeviennent instantanées.
      return _resolvePrivateAvatarWithCloud(
        userId: cleanUserId,
        localAvatar: null,
        revision: _localRevision,
      );
    }

    if (localAvatar != null) return localAvatar;

    // Un autre joueur utilise uniquement l'avatar public de la Taverne.
    if (!_looksLikeUuid(cleanUserId) || SupabaseService.currentUser == null) {
      return null;
    }
    return _loadPublicAvatar(cleanUserId);
  }

  static void _scheduleCloudRefresh(String userId, AvatarModel localAvatar) {
    if (_cloudRefreshTask != null) return;

    final DateTime now = DateTime.now();
    if (_lastCloudRefreshAt != null &&
        now.difference(_lastCloudRefreshAt!) < _cloudRefreshCooldown) {
      return;
    }

    final int revision = _localRevision;
    final Future<void> task = _refreshCloudAvatar(
      userId,
      localAvatar,
      revision,
    );
    _cloudRefreshTask = task;
    unawaited(task);
  }

  static Future<void> _refreshCloudAvatar(
    String userId,
    AvatarModel localAvatar,
    int revision,
  ) async {
    try {
      await _resolvePrivateAvatarWithCloud(
        userId: userId,
        localAvatar: localAvatar,
        revision: revision,
      );
    } catch (_) {
      // L'avatar local reste affiché si Supabase est lent ou indisponible.
    } finally {
      _lastCloudRefreshAt = DateTime.now();
      _cloudRefreshTask = null;
    }
  }

  static Future<AvatarModel?> _resolvePrivateAvatarWithCloud({
    required String userId,
    required AvatarModel? localAvatar,
    required int revision,
  }) async {
    final CloudReadResult<AvatarModel> cloud =
        await CloudDataService.loadPrivateAvatar(localUserId: userId);

    if (!cloud.available) return localAvatar;
    if (_localRevision != revision) return _loadLocalAvatar(userId);

    if (!cloud.found || cloud.value == null) {
      if (localAvatar != null && _localRevision == revision) {
        unawaited(
          CloudDataService.savePrivateAvatar(localAvatar).then<void>((_) {}),
        );
      }
      return localAvatar;
    }

    final AvatarModel cloudAvatar = cloud.value!;
    if (localAvatar != null &&
        localAvatar.updatedAt.isAfter(cloudAvatar.updatedAt)) {
      if (_localRevision == revision) {
        unawaited(
          CloudDataService.savePrivateAvatar(localAvatar).then<void>((_) {}),
        );
      }
      return localAvatar;
    }

    if (_localRevision != revision) return _loadLocalAvatar(userId);
    await _saveLocalAvatar(cloudAvatar);
    return cloudAvatar;
  }

  static Future<AvatarModel?> _loadLocalAvatar(String userId) async {
    if (_localCache.containsKey(userId)) {
      return _localCache[userId];
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) {
      _localCache[userId] = null;
      return null;
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      AvatarModel avatar = AvatarModel.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (avatar.userId != userId) {
        avatar = avatar.copyWith(userId: userId, updatedAt: avatar.updatedAt);
        await _saveLocalAvatar(avatar);
      } else {
        _localCache[userId] = avatar;
      }
      return avatar;
    } catch (_) {
      return null;
    }
  }

  static Future<AvatarModel?> _loadPublicAvatar(String userId) async {
    try {
      final Map<String, dynamic>? profile = await SupabaseService.client
          .from('tavern_profiles')
          .select('avatar_url, avatar_data')
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) return null;
      final Map<String, dynamic>? avatarData = profile['avatar_data'] is Map
          ? Map<String, dynamic>.from(profile['avatar_data'] as Map)
          : null;
      if (avatarData == null) return null;

      final String creationMode =
          avatarData['creationMode']?.toString().trim() ?? '';
      final DateTime now = DateTime.now();

      if (creationMode == 'photo') {
        final String avatarUrl = profile['avatar_url']?.toString().trim() ?? '';
        if (avatarUrl.isEmpty) return null;
        return AvatarModel(
          userId: userId,
          creationMode: AvatarCreationMode.photo,
          generatedImagePath: avatarUrl,
          createdAt: now,
          updatedAt: now,
        );
      }

      if (creationMode != 'manual') return null;

      return AvatarModel.fromJson(<String, dynamic>{
        'userId': userId,
        'creationMode': 'manual',
        'skin': avatarData['skin'],
        'hair': avatarData['hair'],
        'beard': avatarData['beard'],
        'outfit': avatarData['outfit'],
        'accessory': avatarData['accessory'],
        'glasses': avatarData['glasses'],
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }

  static Future<bool> hasAvatar(String userId) async =>
      await loadAvatar(userId) != null;

  static Future<AvatarModel?> loadCurrentAvatar() async {
    final String? userId = await AuthService.getCurrentUserId();
    if (userId == null) return null;
    return loadAvatar(userId);
  }

  static Future<bool> hasCurrentAvatar() async {
    final String? userId = await AuthService.getCurrentUserId();
    if (userId == null) return false;
    return hasAvatar(userId);
  }

  static Future<void> syncCurrentAvatarWithCloud() async {
    final String? userId = await AuthService.getCurrentUserId();
    if (userId == null ||
        userId.isEmpty ||
        CloudDataService.permanentUser == null) {
      return;
    }
    final AvatarModel? local = await _loadLocalAvatar(userId);
    await _resolvePrivateAvatarWithCloud(
      userId: userId,
      localAvatar: local,
      revision: _localRevision,
    );
  }

  static Future<List<String>> getStoredAvatarUserIds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .map((key) => key.substring(_prefix.length))
        .where((id) => id.isNotEmpty)
        .toList();
  }
}
