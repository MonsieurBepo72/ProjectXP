import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'biometric_auth_service.dart';
import 'cloud_session_guard_service.dart';
import 'online_presence_service.dart';
import 'project_xp_startup_service.dart';
import 'supabase_service.dart';

class AccountDeletionResult {
  final bool success;
  final String message;

  const AccountDeletionResult._({
    required this.success,
    required this.message,
  });

  const AccountDeletionResult.success()
      : this._(
          success: true,
          message: 'Compte Project XP supprimé.',
        );

  const AccountDeletionResult.deletedWithLocalCleanupWarning()
      : this._(
          success: true,
          message:
              'Le compte Project XP a bien été supprimé, mais certaines '
              'données locales n’ont pas pu être nettoyées. Ferme puis relance '
              'l’application avant de créer un nouveau compte.',
        );

  const AccountDeletionResult.failure(String message)
      : this._(
          success: false,
          message: message,
        );
}

class AccountDeletionService {
  AccountDeletionService._();

  static const String _deleteConfirmation =
      'DELETE_PROJECT_XP_ACCOUNT_PERMANENTLY';

  /// Suppression définitive du compte actuellement actif.
  ///
  /// Ordre volontaire :
  /// 1. preuve locale par mot de passe ;
  /// 2. vérification que la session Supabase appartient bien au même compte ;
  /// 3. suppression serveur de l'identité + données Cloud/sociales ;
  /// 4. seulement après confirmation serveur, purge locale ciblée.
  ///
  /// Ainsi une panne réseau ne peut jamais donner l'impression qu'un compte
  /// Cloud a été supprimé alors qu'il existe encore.
  static Future<AccountDeletionResult> deleteCurrentAccount({
    required String currentPassword,
  }) async {
    final String password = currentPassword;
    if (password.isEmpty) {
      return const AccountDeletionResult.failure(
        'Entre ton mot de passe Project XP.',
      );
    }

    final bool localPasswordValid =
        await AuthService.verifyCurrentPassword(password);

    if (!localPasswordValid) {
      return const AccountDeletionResult.failure(
        'Le mot de passe Project XP est incorrect.',
      );
    }

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';
    final String email =
        (await AuthService.getCurrentEmail())?.trim().toLowerCase() ?? '';

    if (localUserId.isEmpty) {
      return const AccountDeletionResult.failure(
        'Impossible de retrouver le compte Project XP actif.',
      );
    }

    final _DeletionIdentityResult identity =
        await _resolveDeletionIdentity(
      localUserId: localUserId,
      email: email,
      password: password,
    );

    if (!identity.success || identity.authUserId.isEmpty) {
      return AccountDeletionResult.failure(identity.message);
    }

    final String authUserId = identity.authUserId;

    try {
      final FunctionResponse response =
          await SupabaseService.client.functions.invoke(
        'delete-account',
        body: <String, dynamic>{
          'confirmation': _deleteConfirmation,
          'projectXpUserId': localUserId,
        },
      );

      final dynamic raw = response.data;
      if (raw is! Map) {
        return const AccountDeletionResult.failure(
          'Project XP n’a pas reçu de confirmation valide du serveur. '
          'Aucune donnée locale n’a été supprimée.',
        );
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(raw);

      if (data['ok'] != true) {
        final String message = data['error']?.toString().trim() ?? '';
        return AccountDeletionResult.failure(
          message.isEmpty
              ? 'La suppression du compte a été refusée par le serveur. '
                  'Aucune donnée locale n’a été supprimée.'
              : message,
        );
      }
    } on FunctionException catch (error) {
      final String detail = _functionErrorMessage(error.details);
      return AccountDeletionResult.failure(
        detail.isEmpty
            ? 'Impossible de supprimer le compte côté serveur pour le moment. '
                'Aucune donnée locale n’a été supprimée.'
            : detail,
      );
    } catch (_) {
      return const AccountDeletionResult.failure(
        'Impossible de contacter le serveur de suppression. '
        'Vérifie ta connexion Internet puis réessaie. '
        'Aucune donnée locale n’a été supprimée.',
      );
    }

    try {
      await _purgeCurrentDeviceData(
        localUserId: localUserId,
        authUserId: authUserId,
      );
    } catch (_) {
      // L'identité serveur est déjà détruite. On tente une purge minimale afin
      // que le compte ne puisse plus être réouvert depuis ce téléphone.
      try {
        await BiometricAuthService.disableForCurrentAccount();
        await AuthService.deleteCurrentLocalAccount(
          relatedUserIds: <String>[authUserId],
        );
      } catch (_) {}

      try {
        await SupabaseService.client.auth.signOut();
      } catch (_) {}

      ProjectXpStartupService.instance.notifyLocalLogout();

      return const AccountDeletionResult.deletedWithLocalCleanupWarning();
    }

    return const AccountDeletionResult.success();
  }

  static Future<_DeletionIdentityResult> _resolveDeletionIdentity({
    required String localUserId,
    required String email,
    required String password,
  }) async {
    CloudLocalAccountKind kind =
        await CloudSessionGuardService.currentLocalAccountKind();

    User? user = SupabaseService.currentUser;

    if (kind == CloudLocalAccountKind.cloud) {
      // Si la session permanente a disparu, on utilise le mot de passe déjà
      // saisi pour la réaligner. Aucun secret n'est conservé.
      if (user == null || user.isAnonymous) {
        final CloudSessionAlignmentResult alignment =
            await CloudSessionGuardService.alignAfterPasswordLogin(
          password: password,
          legacyDecisionOnInvalidCredentials: false,
        );

        if (!alignment.success) {
          return const _DeletionIdentityResult.failure(
            'La session Cloud de ce compte doit être reconnectée avant sa '
            'suppression définitive.',
          );
        }

        user = SupabaseService.currentUser;
      }

      if (user == null || user.isAnonymous) {
        return const _DeletionIdentityResult.failure(
          'Impossible de confirmer l’identité Cloud du compte.',
        );
      }

      try {
        final dynamic raw = await SupabaseService.client
            .from('project_xp_cloud_accounts')
            .select('project_xp_user_id, email')
            .eq('auth_user_id', user.id)
            .maybeSingle();

        if (raw is! Map) {
          return const _DeletionIdentityResult.failure(
            'Le lien entre le compte local et le compte Cloud est incomplet. '
            'La suppression a été bloquée par sécurité.',
          );
        }

        final Map<String, dynamic> mapping =
            Map<String, dynamic>.from(raw);
        final String mappedLocalId =
            mapping['project_xp_user_id']?.toString().trim() ?? '';
        final String mappedEmail =
            mapping['email']?.toString().trim().toLowerCase() ?? '';

        if (mappedLocalId != localUserId ||
            (email.isNotEmpty &&
                mappedEmail.isNotEmpty &&
                mappedEmail != email)) {
          return const _DeletionIdentityResult.failure(
            'Sécurité : la session Cloud ouverte ne correspond pas au compte '
            'Project XP local. La suppression a été annulée.',
          );
        }
      } catch (_) {
        return const _DeletionIdentityResult.failure(
          'Impossible de vérifier le lien Cloud pour le moment. '
          'Réessaie avec une connexion Internet stable.',
        );
      }

      return _DeletionIdentityResult.success(user.id);
    }

    if (kind == CloudLocalAccountKind.localOnly) {
      final bool aligned = await CloudSessionGuardService
          .ensureAlignedSessionWithoutPassword();
      user = SupabaseService.currentUser;

      if (!aligned || user == null || !user.isAnonymous) {
        return const _DeletionIdentityResult.failure(
          'Impossible de confirmer la session sociale de ce compte local. '
          'Reconnecte-toi puis réessaie.',
        );
      }

      return _DeletionIdentityResult.success(user.id);
    }

    // Ancien compte non classé : on ne choisit jamais automatiquement quelle
    // identité Supabase supprimer. Une session déjà alignée peut toutefois être
    // reconnue sans mot de passe.
    final bool aligned =
        await CloudSessionGuardService.ensureAlignedSessionWithoutPassword();
    user = SupabaseService.currentUser;

    if (!aligned || user == null) {
      return const _DeletionIdentityResult.failure(
        'Le statut Cloud de cet ancien compte doit d’abord être confirmé '
        'depuis une reconnexion normale.',
      );
    }

    kind = user.isAnonymous
        ? CloudLocalAccountKind.localOnly
        : CloudLocalAccountKind.cloud;

    if (kind == CloudLocalAccountKind.cloud) {
      try {
        final dynamic raw = await SupabaseService.client
            .from('project_xp_cloud_accounts')
            .select('project_xp_user_id')
            .eq('auth_user_id', user.id)
            .maybeSingle();
        final String mappedLocalId = raw is Map
            ? raw['project_xp_user_id']?.toString().trim() ?? ''
            : '';

        if (mappedLocalId != localUserId) {
          return const _DeletionIdentityResult.failure(
            'Sécurité : impossible d’identifier avec certitude le compte '
            'Cloud à supprimer.',
          );
        }
      } catch (_) {
        return const _DeletionIdentityResult.failure(
          'Impossible de vérifier l’identité Cloud pour le moment.',
        );
      }
    }

    return _DeletionIdentityResult.success(user.id);
  }

  static Future<void> _purgeCurrentDeviceData({
    required String localUserId,
    required String authUserId,
  }) async {
    await OnlinePresenceService.instance.stop();
    await BiometricAuthService.disableForCurrentAccount();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await _deleteGeneratedAvatarFile(
      prefs,
      localUserId,
    );
    await _deleteWallpaperFile(
      prefs,
      localUserId,
    );

    await _cleanTeamsCache(
      prefs,
      localUserId: localUserId,
      authUserId: authUserId,
    );
    await _cleanInvitationCache(
      prefs,
      key: 'project_xp_compagnie_team_invitations',
      localUserId: localUserId,
      authUserId: authUserId,
    );
    await _cleanInvitationCache(
      prefs,
      key: 'project_xp_squad_team_invitations',
      localUserId: localUserId,
      authUserId: authUserId,
    );
    await _cleanJoinRequestCache(
      prefs,
      key: 'project_xp_compagnie_join_requests',
      localUserId: localUserId,
      authUserId: authUserId,
    );
    await _cleanJoinRequestCache(
      prefs,
      key: 'project_xp_squad_join_requests',
      localUserId: localUserId,
      authUserId: authUserId,
    );

    final Set<String> keysToRemove = <String>{
      'project_xp_avatar_$localUserId',
      'project_xp_profile_$localUserId',
      'project_xp_game_library_v1_$localUserId',
      'project_xp_gaming_activity_v1_$localUserId',
      'project_xp_steam_reference_$localUserId',
      'project_xp_steam_id_$localUserId',
      'project_xp_steam_sync_issues_$localUserId',
      'project_xp_steam_sync_issue_retries_$localUserId',
      'project_xp_notification_center_seen_v1_$localUserId',
      'project_xp_phone_wallpaper_v1_$localUserId',
      'project_xp_cloud_session_binding_v1_$localUserId',
      'project_xp_cloud_session_classification_v1_$localUserId',
      'project_xp_game_library_cloud_migrated_v1_$authUserId',
      'project_xp_game_library_cloud_dirty_v1_$authUserId',
      'project_xp_game_library_pending_deletes_v1_$authUserId',
      'project_xp_gaming_activity_cloud_dirty_v1_$authUserId',
    };

    for (final String key in keysToRemove) {
      await prefs.remove(key);
    }

    final String migrationTarget =
        prefs.getString('project_xp_profile_legacy_migrated_to')?.trim() ?? '';
    if (migrationTarget == localUserId) {
      await prefs.remove('project_xp_profile_legacy_migrated_to');
      await prefs.remove('profile_data');
      await prefs.remove('profile_user_id');
    }

    await prefs.remove('project_xp_session_expires_at');

    await AuthService.deleteCurrentLocalAccount(
      relatedUserIds: <String>[authUserId],
    );

    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {
      // L'utilisateur Auth vient d'être supprimé : le serveur peut déjà refuser
      // la révocation. La session expirée ne sera plus utilisable.
    }

    ProjectXpStartupService.instance.notifyLocalLogout();
  }

  static Future<void> _deleteGeneratedAvatarFile(
    SharedPreferences prefs,
    String localUserId,
  ) async {
    final String raw =
        prefs.getString('project_xp_avatar_$localUserId') ?? '';
    if (raw.isEmpty) {
      return;
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final String path =
          decoded['generatedImagePath']?.toString().trim() ?? '';
      if (path.isEmpty ||
          path.startsWith('http://') ||
          path.startsWith('https://')) {
        return;
      }

      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Une ancienne image déjà absente ne doit pas bloquer la suppression.
    }
  }

  static Future<void> _deleteWallpaperFile(
    SharedPreferences prefs,
    String localUserId,
  ) async {
    final String key = 'project_xp_phone_wallpaper_v1_$localUserId';
    final String path = prefs.getString(key)?.trim() ?? '';

    if (path.isNotEmpty) {
      try {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> _cleanTeamsCache(
    SharedPreferences prefs, {
    required String localUserId,
    required String authUserId,
  }) async {
    const String key = 'teams_data';
    final String raw = prefs.getString(key) ?? '';
    if (raw.isEmpty) {
      return;
    }

    final Set<String> ids = <String>{localUserId, authUserId};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      final List<dynamic> kept = <dynamic>[];

      for (final dynamic item in decoded) {
        if (item is! Map) {
          kept.add(item);
          continue;
        }

        final Map<String, dynamic> team =
            Map<String, dynamic>.from(item);
        final String ownerId = team['ownerId']?.toString().trim() ?? '';

        // Une équipe possédée par le compte supprimé est également supprimée
        // côté serveur : elle ne doit pas survivre dans le cache local.
        if (ids.contains(ownerId)) {
          continue;
        }

        final List<String> memberIds = _stringList(team['memberIds'])
          ..removeWhere(ids.contains);
        team['memberIds'] = memberIds;

        final String leaderId = team['leaderId']?.toString().trim() ?? '';
        if (ids.contains(leaderId)) {
          team['leaderId'] = null;
          team['leaderName'] = null;
        }

        kept.add(team);
      }

      await prefs.setString(key, jsonEncode(kept));
    } catch (_) {
      // Ne détruit pas un cache partagé illisible : les données des autres
      // comptes sur l'appareil doivent rester prioritaires.
    }
  }

  static Future<void> _cleanInvitationCache(
    SharedPreferences prefs, {
    required String key,
    required String localUserId,
    required String authUserId,
  }) async {
    final String raw = prefs.getString(key) ?? '';
    if (raw.isEmpty) {
      return;
    }

    final Set<String> ids = <String>{localUserId, authUserId};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      final List<dynamic> kept = decoded.where((dynamic item) {
        if (item is! Map) {
          return true;
        }

        final Map<String, dynamic> row =
            Map<String, dynamic>.from(item);
        final String inviter = row['inviterId']?.toString().trim() ?? '';
        final String invitee = row['inviteeId']?.toString().trim() ?? '';
        final String handled =
            row['handledByUserId']?.toString().trim() ?? '';

        return !ids.contains(inviter) &&
            !ids.contains(invitee) &&
            !ids.contains(handled);
      }).toList();

      await prefs.setString(key, jsonEncode(kept));
    } catch (_) {}
  }

  static Future<void> _cleanJoinRequestCache(
    SharedPreferences prefs, {
    required String key,
    required String localUserId,
    required String authUserId,
  }) async {
    final String raw = prefs.getString(key) ?? '';
    if (raw.isEmpty) {
      return;
    }

    final Set<String> ids = <String>{localUserId, authUserId};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      final List<dynamic> kept = <dynamic>[];

      for (final dynamic item in decoded) {
        if (item is! Map) {
          kept.add(item);
          continue;
        }

        final Map<String, dynamic> row =
            Map<String, dynamic>.from(item);
        final String requester =
            row['requesterId']?.toString().trim() ?? '';

        if (ids.contains(requester)) {
          continue;
        }

        final List<String> recipients = _stringList(row['recipientIds'])
          ..removeWhere(ids.contains);
        final List<String> notified =
            _stringList(row['androidNotifiedUserIds'])
              ..removeWhere(ids.contains);

        if (recipients.isEmpty) {
          continue;
        }

        row['recipientIds'] = recipients;
        row['androidNotifiedUserIds'] = notified;

        final String handled =
            row['handledByUserId']?.toString().trim() ?? '';
        if (ids.contains(handled)) {
          row['handledByUserId'] = null;
        }

        kept.add(row);
      }

      await prefs.setString(key, jsonEncode(kept));
    } catch (_) {}
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return <String>[];
    }

    return value
        .map((dynamic item) => item.toString().trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  static String _functionErrorMessage(dynamic raw) {
    if (raw is Map && raw['error'] != null) {
      return raw['error'].toString().trim();
    }

    final String value = raw?.toString().trim() ?? '';
    if (value.isEmpty) {
      return '';
    }

    if (value.contains('404') || value.contains('Function not found')) {
      return 'La fonction de suppression Project XP n’est pas encore déployée.';
    }

    return 'Suppression du compte indisponible : $value';
  }
}

class _DeletionIdentityResult {
  final bool success;
  final String authUserId;
  final String message;

  const _DeletionIdentityResult._({
    required this.success,
    required this.authUserId,
    required this.message,
  });

  const _DeletionIdentityResult.success(String authUserId)
      : this._(
          success: true,
          authUserId: authUserId,
          message: '',
        );

  const _DeletionIdentityResult.failure(String message)
      : this._(
          success: false,
          authUserId: '',
          message: message,
        );
}
