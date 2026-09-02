import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_service.dart';

enum CloudIdentityState {
  unavailable,
  anonymous,
  permanent,
}

class CloudIdentityStatus {
  final CloudIdentityState state;
  final String? authUserId;
  final String? projectXpUserId;
  final String? username;
  final String? email;
  final bool mappingReady;
  final String? error;

  const CloudIdentityStatus({
    required this.state,
    this.authUserId,
    this.projectXpUserId,
    this.username,
    this.email,
    this.mappingReady = false,
    this.error,
  });

  bool get isPermanent =>
      state == CloudIdentityState.permanent;
}

class CloudIdentityActionResult {
  final bool success;
  final String message;

  const CloudIdentityActionResult({
    required this.success,
    required this.message,
  });

  const CloudIdentityActionResult.ok(
    String message,
  ) : this(
          success: true,
          message: message,
        );

  const CloudIdentityActionResult.fail(
    String message,
  ) : this(
          success: false,
          message: message,
        );
}

class CloudIdentityService {
  CloudIdentityService._();

  static SupabaseClient get _client =>
      SupabaseService.client;

  static Future<CloudIdentityStatus>
      loadStatus() async {
    try {
      final User? user =
          await SupabaseService.ensureAnonymousSession();

      if (user == null) {
        return const CloudIdentityStatus(
          state: CloudIdentityState.unavailable,
          error:
              'Impossible d’ouvrir la session Supabase.',
        );
      }

      Map<String, dynamic>? mapping;

      try {
        final dynamic raw = await _client
            .from('project_xp_cloud_accounts')
            .select(
              'auth_user_id, project_xp_user_id, username, email',
            )
            .eq('auth_user_id', user.id)
            .maybeSingle();

        if (raw is Map) {
          mapping =
              Map<String, dynamic>.from(raw);
        }
      } catch (_) {
        // Avant l'installation de la migration V1.9,
        // l'écran reste utilisable et explique simplement
        // que le mapping n'est pas encore prêt.
      }

      return CloudIdentityStatus(
        state: user.isAnonymous
            ? CloudIdentityState.anonymous
            : CloudIdentityState.permanent,
        authUserId: user.id,
        projectXpUserId:
            mapping?['project_xp_user_id']
                ?.toString(),
        username:
            mapping?['username']?.toString() ??
                user.userMetadata?['username']
                    ?.toString(),
        email: mapping?['email']?.toString() ??
            user.email,
        mappingReady: mapping != null,
      );
    } catch (error) {
      return CloudIdentityStatus(
        state: CloudIdentityState.unavailable,
        error: error.toString(),
      );
    }
  }

  /// Première étape de conversion :
  /// - vérifie le vrai mot de passe Project XP local ;
  /// - conserve l'utilisateur Supabase social actuel ;
  /// - demande à Supabase de lier l'e-mail du compte local.
  ///
  /// Supabase envoie ensuite l'e-mail de vérification.
  static Future<CloudIdentityActionResult>
      beginUpgrade({
    required String currentPassword,
  }) async {
    final bool validLocalPassword =
        await AuthService.verifyCurrentPassword(
      currentPassword,
    );

    if (!validLocalPassword) {
      return const CloudIdentityActionResult.fail(
        'Le mot de passe Project XP est incorrect.',
      );
    }

    final String email =
        (await AuthService.getCurrentEmail())
                ?.trim()
                .toLowerCase() ??
            '';

    final String username =
        (await AuthService.getCurrentUsername())
                ?.trim() ??
            '';

    final String projectXpUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    if (email.isEmpty ||
        username.isEmpty ||
        projectXpUserId.isEmpty) {
      return const CloudIdentityActionResult.fail(
        'Le compte local Project XP est incomplet.',
      );
    }

    final User? user =
        await SupabaseService.ensureAnonymousSession();

    if (user == null) {
      return const CloudIdentityActionResult.fail(
        'Impossible d’ouvrir la session Supabase.',
      );
    }

    if (!user.isAnonymous) {
      final CloudIdentityActionResult result =
          await _ensureCloudMapping();

      if (result.success) {
        return const CloudIdentityActionResult.ok(
          'Ton compte Project XP est déjà un compte Cloud.',
        );
      }

      return result;
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(
          email: email,
          data: <String, dynamic>{
            'project_xp_user_id':
                projectXpUserId,
            'username': username,
          },
        ),
      );

      return CloudIdentityActionResult.ok(
        'Un code de vérification a été envoyé à $email.',
      );
    } on AuthException catch (error) {
      return CloudIdentityActionResult.fail(
        _friendlyAuthError(error.message),
      );
    } catch (error) {
      return CloudIdentityActionResult.fail(
        'Impossible de lancer la vérification : $error',
      );
    }
  }

  /// Variante sécurisée quand le mot de passe local a été oublié.
  ///
  /// On ne tente jamais de récupérer l'ancien mot de passe : il n'existe
  /// qu'en hash Argon2id dans le stockage local. La possession de l'adresse
  /// e-mail devient donc la preuve d'identité avant toute réinitialisation.
  static Future<CloudIdentityActionResult>
      beginForgottenPasswordUpgrade() async {
    final String email =
        (await AuthService.getCurrentEmail())
                ?.trim()
                .toLowerCase() ??
            '';

    final String username =
        (await AuthService.getCurrentUsername())
                ?.trim() ??
            '';

    final String projectXpUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    if (email.isEmpty ||
        username.isEmpty ||
        projectXpUserId.isEmpty) {
      return const CloudIdentityActionResult.fail(
        'Le compte local Project XP est incomplet.',
      );
    }

    final User? user =
        await SupabaseService.ensureAnonymousSession();

    if (user == null) {
      return const CloudIdentityActionResult.fail(
        'Impossible d’ouvrir la session Supabase.',
      );
    }

    if (!user.isAnonymous) {
      final CloudIdentityActionResult mapping =
          await _ensureCloudMapping();

      if (mapping.success) {
        return const CloudIdentityActionResult.fail(
          'Ce compte est déjà Cloud. La réinitialisation depuis un autre appareil sera branchée sur l’écran de connexion dans l’étape suivante.',
        );
      }

      return mapping;
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(
          email: email,
          data: <String, dynamic>{
            'project_xp_user_id': projectXpUserId,
            'username': username,
          },
        ),
      );

      return CloudIdentityActionResult.ok(
        'Un code de vérification a été envoyé à $email.',
      );
    } on AuthException catch (error) {
      // V1.9.1a DIAGNOSTIC : on affiche temporairement le message brut renvoyé
      // par Supabase afin d'identifier précisément l'échec AVANT l'envoi OTP.
      // Une fois la cause corrigée, ce message redeviendra volontairement
      // plus lisible pour l'utilisateur final.
      return CloudIdentityActionResult.fail(
        'DIAGNOSTIC SUPABASE : ${error.message}',
      );
    } catch (error) {
      return CloudIdentityActionResult.fail(
        'DIAGNOSTIC TECHNIQUE : $error',
      );
    }
  }

  /// Finalise une activation Cloud après oubli du mot de passe.
  ///
  /// Ordre volontaire :
  /// 1. vérifier le code reçu par e-mail ;
  /// 2. enregistrer le nouveau mot de passe côté Supabase ;
  /// 3. remplacer le hash local par le même nouveau mot de passe ;
  /// 4. créer le mapping Cloud stable.
  static Future<CloudIdentityActionResult>
      completeForgottenPasswordUpgrade({
    required String otp,
    required String newPassword,
  }) async {
    final String code = otp.trim();

    if (code.length < 6) {
      return const CloudIdentityActionResult.fail(
        'Entre le code reçu par e-mail.',
      );
    }

    final String? passwordError =
        AuthService.validatePassword(newPassword);

    if (passwordError != null) {
      return CloudIdentityActionResult.fail(
        passwordError,
      );
    }

    final String email =
        (await AuthService.getCurrentEmail())
                ?.trim()
                .toLowerCase() ??
            '';

    if (email.isEmpty) {
      return const CloudIdentityActionResult.fail(
        'Aucune adresse e-mail n’est associée au compte.',
      );
    }

    try {
      await _client.auth.verifyOTP(
        type: OtpType.emailChange,
        token: code,
        email: email,
      );

      await _client.auth.updateUser(
        UserAttributes(
          password: newPassword,
        ),
      );

      final bool localPasswordSaved =
          await AuthService.setPasswordForEmail(
        email: email,
        password: newPassword,
      );

      if (!localPasswordSaved) {
        return const CloudIdentityActionResult.fail(
          'L’e-mail a bien été vérifié, mais le nouveau mot de passe n’a pas pu être enregistré localement.',
        );
      }

      final CloudIdentityActionResult mapping =
          await _ensureCloudMapping();

      if (!mapping.success) {
        return mapping;
      }

      return const CloudIdentityActionResult.ok(
        'Mot de passe réinitialisé et compte Cloud Project XP activé.',
      );
    } on AuthException catch (error) {
      return CloudIdentityActionResult.fail(
        _friendlyAuthError(error.message),
      );
    } catch (error) {
      return CloudIdentityActionResult.fail(
        'Impossible de finaliser la réinitialisation : $error',
      );
    }
  }

  /// Deuxième étape :
  /// - valide le code reçu par e-mail ;
  /// - ajoute le mot de passe au même utilisateur Supabase ;
  /// - crée la correspondance stable :
  ///   auth.uid() <-> ID historique Project XP.
  static Future<CloudIdentityActionResult>
      completeUpgrade({
    required String otp,
    required String password,
  }) async {
    final String code = otp.trim();

    if (code.length < 6) {
      return const CloudIdentityActionResult.fail(
        'Entre le code reçu par e-mail.',
      );
    }

    final bool validLocalPassword =
        await AuthService.verifyCurrentPassword(
      password,
    );

    if (!validLocalPassword) {
      return const CloudIdentityActionResult.fail(
        'Le mot de passe Project XP est incorrect.',
      );
    }

    final String email =
        (await AuthService.getCurrentEmail())
                ?.trim()
                .toLowerCase() ??
            '';

    if (email.isEmpty) {
      return const CloudIdentityActionResult.fail(
        'Aucune adresse e-mail n’est associée au compte.',
      );
    }

    try {
      await _client.auth.verifyOTP(
        type: OtpType.emailChange,
        token: code,
        email: email,
      );

      await _client.auth.updateUser(
        UserAttributes(
          password: password,
        ),
      );

      final CloudIdentityActionResult mapping =
          await _ensureCloudMapping();

      if (!mapping.success) {
        return mapping;
      }

      return const CloudIdentityActionResult.ok(
        'Compte Cloud Project XP activé.',
      );
    } on AuthException catch (error) {
      return CloudIdentityActionResult.fail(
        _friendlyAuthError(error.message),
      );
    } catch (error) {
      return CloudIdentityActionResult.fail(
        'Impossible de finaliser le compte Cloud : $error',
      );
    }
  }

  static Future<CloudIdentityActionResult>
      _ensureCloudMapping() async {
    final User? user =
        _client.auth.currentUser;

    if (user == null ||
        user.isAnonymous) {
      return const CloudIdentityActionResult.fail(
        'Le compte Supabase n’est pas encore permanent.',
      );
    }

    final String projectXpUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    final String username =
        (await AuthService.getCurrentUsername())
                ?.trim() ??
            '';

    final String email =
        (await AuthService.getCurrentEmail())
                ?.trim()
                .toLowerCase() ??
            '';

    if (projectXpUserId.isEmpty ||
        username.isEmpty ||
        email.isEmpty) {
      return const CloudIdentityActionResult.fail(
        'Le compte Project XP local est incomplet.',
      );
    }

    try {
      await _client
          .from('project_xp_cloud_accounts')
          .upsert(
        <String, dynamic>{
          'auth_user_id': user.id,
          'project_xp_user_id':
              projectXpUserId,
          'username': username,
          'email': email,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'auth_user_id',
      );

      return const CloudIdentityActionResult.ok(
        'Identité Cloud synchronisée.',
      );
    } on PostgrestException catch (error) {
      return CloudIdentityActionResult.fail(
        'La table Cloud n’est pas prête : ${error.message}',
      );
    } catch (error) {
      return CloudIdentityActionResult.fail(
        'Impossible de synchroniser l’identité : $error',
      );
    }
  }

  /// Utilisé plus tard par l'écran de connexion d'un nouvel appareil.
  ///
  /// Cette méthode est déjà prête : elle se connecte au vrai compte
  /// Supabase puis reconstruit le compte local avec le même ID historique
  /// Project XP. L'écran de connexion sera branché dans l'étape suivante.
  static Future<CloudIdentityActionResult>
      signInCloudAndRestoreLocal({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response =
          await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final User? user = response.user;

      if (user == null) {
        return const CloudIdentityActionResult.fail(
          'Connexion Cloud impossible.',
        );
      }

      final dynamic raw = await _client
          .from('project_xp_cloud_accounts')
          .select(
            'project_xp_user_id, username, email',
          )
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (raw is! Map) {
        return const CloudIdentityActionResult.fail(
          'Ce compte Cloud n’a pas encore de profil Project XP associé.',
        );
      }

      final Map<String, dynamic> row =
          Map<String, dynamic>.from(raw);

      final String projectXpUserId =
          row['project_xp_user_id']
                  ?.toString()
                  .trim() ??
              '';

      final String username =
          row['username']?.toString().trim() ??
              '';

      final String cloudEmail =
          row['email']
                  ?.toString()
                  .trim()
                  .toLowerCase() ??
              email.trim().toLowerCase();

      if (projectXpUserId.isEmpty ||
          username.isEmpty ||
          cloudEmail.isEmpty) {
        return const CloudIdentityActionResult.fail(
          'Les informations du compte Cloud sont incomplètes.',
        );
      }

      final bool restored =
          await _materializeLocalAccount(
        projectXpUserId:
            projectXpUserId,
        username: username,
        email: cloudEmail,
        password: password,
      );

      if (!restored) {
        return const CloudIdentityActionResult.fail(
          'Le compte Cloud est valide, mais la copie locale n’a pas pu être restaurée.',
        );
      }

      return const CloudIdentityActionResult.ok(
        'Compte Project XP restauré sur cet appareil.',
      );
    } on AuthException catch (error) {
      return CloudIdentityActionResult.fail(
        _friendlyAuthError(error.message),
      );
    } catch (error) {
      return CloudIdentityActionResult.fail(
        'Connexion Cloud impossible : $error',
      );
    }
  }

  static Future<bool> _materializeLocalAccount({
    required String projectXpUserId,
    required String username,
    required String email,
    required String password,
  }) async {
    final List<Map<String, dynamic>> localAccounts =
        await AuthService.getLocalAccounts();

    for (final Map<String, dynamic> account
        in localAccounts) {
      if (account['id']?.toString() ==
          projectXpUserId) {
        return AuthService.activateLocalAccountById(
          projectXpUserId,
        );
      }
    }

    final AuthRegisterResult registerResult =
        await AuthService.register(
      username: username,
      email: email,
      password: password,
    );

    if (registerResult !=
        AuthRegisterResult.success) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    const String accountsKey =
        'project_xp_accounts_v2';

    final String? raw =
        prefs.getString(accountsKey);

    if (raw == null || raw.isEmpty) {
      return false;
    }

    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is! List) {
        return false;
      }

      final List<Map<String, dynamic>> accounts =
          decoded
              .whereType<Map>()
              .map(
                (item) =>
                    Map<String, dynamic>.from(
                  item,
                ),
              )
              .toList();

      final int index =
          accounts.lastIndexWhere(
        (account) =>
            account['email']
                ?.toString()
                .trim()
                .toLowerCase() ==
            email.trim().toLowerCase(),
      );

      if (index < 0) {
        return false;
      }

      final String generatedId =
          accounts[index]['id']
                  ?.toString() ??
              '';

      accounts[index] = <String, dynamic>{
        ...accounts[index],
        'id': projectXpUserId,
        'cloudRestoredAt':
            DateTime.now()
                .toUtc()
                .toIso8601String(),
      };

      await prefs.setString(
        accountsKey,
        jsonEncode(accounts),
      );

      await prefs.setString(
        'project_xp_user_id',
        projectXpUserId,
      );
      await prefs.setString(
        'project_xp_username',
        username,
      );
      await prefs.setString(
        'project_xp_email',
        email.trim().toLowerCase(),
      );
      await prefs.setBool(
        'project_xp_is_logged_in',
        true,
      );

      // Aucun avatar/bibliothèque n'existe normalement encore
      // pour le compte fraîchement restauré. On retire seulement
      // les éventuelles clés vides du compte temporaire généré.
      if (generatedId.isNotEmpty &&
          generatedId != projectXpUserId) {
        await prefs.remove(
          'project_xp_avatar_$generatedId',
        );
        await prefs.remove(
          'project_xp_game_library_$generatedId',
        );
        await prefs.remove(
          'project_xp_gaming_activity_$generatedId',
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Au moment de la vraie déconnexion d'un compte permanent,
  /// on déconnecte aussi Supabase. On ne le fait pas aux anciens
  /// comptes anonymes pour ne pas détruire leur identité sociale.
  static Future<void>
      signOutPermanentCloudUser() async {
    final User? user =
        _client.auth.currentUser;

    if (user != null &&
        !user.isAnonymous) {
      await _client.auth.signOut();
    }
  }

  static String _friendlyAuthError(
    String raw,
  ) {
    final String value =
        raw.toLowerCase();

    if (value.contains('already') &&
        value.contains('registered')) {
      return 'Cette adresse e-mail possède déjà un compte Cloud Project XP.';
    }

    if (value.contains('invalid') &&
        value.contains('token')) {
      return 'Le code de vérification est incorrect ou expiré.';
    }

    if (value.contains('password')) {
      return 'Le mot de passe n’a pas pu être enregistré.';
    }

    if (value.contains('email')) {
      return 'L’adresse e-mail n’a pas pu être vérifiée.';
    }

    return raw;
  }
}
