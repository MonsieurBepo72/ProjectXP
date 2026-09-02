import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_model.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

class AvatarStorage {
  static const String _prefix =
      'project_xp_avatar_';

  static String _key(
    String userId,
  ) {
    return '$_prefix$userId';
  }

  // ===========================================================================
  // SAUVEGARDE
  // ===========================================================================

  static Future<bool> saveAvatar(
    AvatarModel avatar,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.setString(
      _key(avatar.userId),
      jsonEncode(
        avatar.toJson(),
      ),
    );
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  static Future<AvatarModel?> loadAvatar(
    String userId,
  ) async {
    final String cleanUserId =
        userId.trim();

    if (cleanUserId.isEmpty) {
      return null;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? raw =
        prefs.getString(
      _key(cleanUserId),
    );

    if (raw != null &&
        raw.isNotEmpty) {
      try {
        final dynamic decoded =
            jsonDecode(raw);

        if (decoded is Map) {
          AvatarModel avatar =
              AvatarModel.fromJson(
            Map<String, dynamic>.from(
              decoded,
            ),
          );

          // Sécurité : la clé du compte est la source de vérité.
          if (avatar.userId != cleanUserId) {
            avatar = avatar.copyWith(
              userId: cleanUserId,
            );

            await saveAvatar(
              avatar,
            );
          }

          return avatar;
        }
      } catch (_) {
        // Si l'avatar local est illisible, on tente le profil public online.
      }
    }

    // Les membres d'une Compagnie arrivés depuis un autre téléphone sont
    // identifiés par leur UUID Supabase. Ils n'ont naturellement aucun avatar
    // dans les SharedPreferences locales : on lit alors leur avatar public.
    if (!_looksLikeUuid(cleanUserId) ||
        SupabaseService.currentUser == null) {
      return null;
    }

    return _loadPublicAvatar(
      cleanUserId,
    );
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
              .eq(
                'id',
                userId,
              )
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

      final DateTime now =
          DateTime.now();

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
          generatedImagePath:
              avatarUrl,
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
    return await loadAvatar(
          userId,
        ) !=
        null;
  }

  // ===========================================================================
  // COMPTE ACTIF
  // ===========================================================================

  static Future<AvatarModel?>
      loadCurrentAvatar() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null) {
      return null;
    }

    return loadAvatar(
      userId,
    );
  }

  static Future<bool>
      hasCurrentAvatar() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null) {
      return false;
    }

    return hasAvatar(
      userId,
    );
  }

  // ===========================================================================
  // INVENTAIRE
  // ===========================================================================

  static Future<List<String>>
      getStoredAvatarUserIds() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith(_prefix),
        )
        .map(
          (key) => key.substring(
            _prefix.length,
          ),
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toList();
  }
}
