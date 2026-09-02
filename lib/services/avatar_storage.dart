import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_model.dart';
import 'auth_service.dart';
import 'cloud_data_service.dart';
import 'supabase_service.dart';

class AvatarStorage {
  static const String _prefix =
      'project_xp_avatar_';

  static String _key(String userId) =>
      '$_prefix$userId';

  // ===========================================================================
  // SAUVEGARDE
  //
  // Local d'abord, Cloud ensuite. Le réseau ne peut donc jamais faire perdre
  // un avatar qui vient d'être validé sur l'appareil.
  // ===========================================================================

  static Future<bool> saveAvatar(
    AvatarModel avatar,
  ) async {
    final bool localSaved =
        await _saveLocalAvatar(avatar);

    if (!localSaved) {
      return false;
    }

    await CloudDataService.savePrivateAvatar(
      avatar,
    );

    return true;
  }

  static Future<bool> _saveLocalAvatar(
    AvatarModel avatar,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.setString(
      _key(avatar.userId),
      jsonEncode(avatar.toJson()),
    );
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  static Future<AvatarModel?> loadAvatar(
    String userId,
  ) async {
    final String cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return null;
    }

    final AvatarModel? localAvatar =
        await _loadLocalAvatar(cleanUserId);

    final String currentLocalUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    // Pour le compte actif, le Cloud privé devient la source commune entre
    // appareils. On conserve updatedAt afin de récupérer aussi une éventuelle
    // modification faite hors-ligne avant le retour du réseau.
    if (currentLocalUserId.isNotEmpty &&
        cleanUserId == currentLocalUserId &&
        CloudDataService.permanentUser != null) {
      final CloudReadResult<AvatarModel> cloud =
          await CloudDataService.loadPrivateAvatar(
        localUserId: cleanUserId,
      );

      if (cloud.available) {
        if (!cloud.found || cloud.value == null) {
          if (localAvatar != null) {
            await CloudDataService.savePrivateAvatar(
              localAvatar,
            );
          }

          return localAvatar;
        }

        final AvatarModel cloudAvatar =
            cloud.value!;

        if (localAvatar != null &&
            localAvatar.updatedAt.isAfter(
              cloudAvatar.updatedAt,
            )) {
          await CloudDataService.savePrivateAvatar(
            localAvatar,
          );
          return localAvatar;
        }

        await _saveLocalAvatar(
          cloudAvatar,
        );
        return cloudAvatar;
      }
    }

    if (localAvatar != null) {
      return localAvatar;
    }

    // Les profils distants continuent d'utiliser leur représentation publique
    // Taverne. Le stockage privé Cloud n'est jamais exposé à un autre joueur.
    if (!_looksLikeUuid(cleanUserId) ||
        SupabaseService.currentUser == null) {
      return null;
    }

    return _loadPublicAvatar(cleanUserId);
  }

  static Future<AvatarModel?> _loadLocalAvatar(
    String userId,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? raw =
        prefs.getString(_key(userId));

    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final dynamic decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return null;
      }

      AvatarModel avatar =
          AvatarModel.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      if (avatar.userId != userId) {
        avatar = avatar.copyWith(
          userId: userId,
          updatedAt: avatar.updatedAt,
        );
        await _saveLocalAvatar(avatar);
      }

      return avatar;
    } catch (_) {
      return null;
    }
  }

  static Future<AvatarModel?> _loadPublicAvatar(
    String userId,
  ) async {
    try {
      final Map<String, dynamic>? profile =
          await SupabaseService.client
              .from('tavern_profiles')
              .select(
                'avatar_url, avatar_data',
              )
              .eq('id', userId)
              .maybeSingle();

      if (profile == null) {
        return null;
      }

      final Map<String, dynamic>? avatarData =
          profile['avatar_data'] is Map
              ? Map<String, dynamic>.from(
                  profile['avatar_data'] as Map,
                )
              : null;

      if (avatarData == null) {
        return null;
      }

      final String creationMode =
          avatarData['creationMode']
                  ?.toString()
                  .trim() ??
              '';

      final DateTime now = DateTime.now();

      if (creationMode == 'photo') {
        final String avatarUrl =
            profile['avatar_url']
                    ?.toString()
                    .trim() ??
                '';

        if (avatarUrl.isEmpty) {
          return null;
        }

        return AvatarModel(
          userId: userId,
          creationMode:
              AvatarCreationMode.photo,
          generatedImagePath: avatarUrl,
          createdAt: now,
          updatedAt: now,
        );
      }

      if (creationMode != 'manual') {
        return null;
      }

      return AvatarModel.fromJson(
        <String, dynamic>{
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
        },
      );
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeUuid(
    String value,
  ) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }

  static Future<bool> hasAvatar(
    String userId,
  ) async {
    return await loadAvatar(userId) != null;
  }

  // ===========================================================================
  // COMPTE ACTIF
  // ===========================================================================

  static Future<AvatarModel?> loadCurrentAvatar() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null) {
      return null;
    }

    return loadAvatar(userId);
  }

  static Future<bool> hasCurrentAvatar() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null) {
      return false;
    }

    return hasAvatar(userId);
  }

  static Future<void> syncCurrentAvatarWithCloud() async {
    await loadCurrentAvatar();
  }

  // ===========================================================================
  // INVENTAIRE
  // ===========================================================================

  static Future<List<String>> getStoredAvatarUserIds() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .map(
          (key) => key.substring(_prefix.length),
        )
        .where((id) => id.isNotEmpty)
        .toList();
  }
}
