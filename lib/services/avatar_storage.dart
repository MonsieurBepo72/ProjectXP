import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_model.dart';
import 'auth_service.dart';

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
    if (userId.trim().isEmpty) {
      return null;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? raw =
        prefs.getString(
      _key(userId),
    );

    if (raw == null ||
        raw.isEmpty) {
      return null;
    }

    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is! Map) {
        return null;
      }

      AvatarModel avatar =
          AvatarModel.fromJson(
        Map<String, dynamic>.from(
          decoded,
        ),
      );

      // Sécurité : la clé du compte est la source de vérité.
      // Si un ancien JSON contient un autre userId, on le corrige sans
      // supprimer l'ancienne sauvegarde.
      if (avatar.userId != userId) {
        avatar = avatar.copyWith(
          userId: userId,
        );

        await saveAvatar(
          avatar,
        );
      }

      return avatar;
    } catch (_) {
      return null;
    }
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
  //
  // Les anciens avatars restent accessibles et ne sont jamais supprimés.
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
