import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_service.dart';

class CloudSessionAlignmentResult {
  final bool success;
  final bool requiresLegacyDecision;
  final String message;

  const CloudSessionAlignmentResult({
    required this.success,
    required this.requiresLegacyDecision,
    required this.message,
  });

  const CloudSessionAlignmentResult.ok([String message = ''])
      : this(
          success: true,
          requiresLegacyDecision: false,
          message: message,
        );

  const CloudSessionAlignmentResult.fail(String message)
      : this(
          success: false,
          requiresLegacyDecision: false,
          message: message,
        );

  const CloudSessionAlignmentResult.legacyDecision(String message)
      : this(
          success: false,
          requiresLegacyDecision: true,
          message: message,
        );
}

enum CloudLocalAccountKind {
  unknown,
  localOnly,
  cloud,
}

class _CloudBinding {
  final String authUserId;
  final String loginEmail;

  const _CloudBinding({
    required this.authUserId,
    required this.loginEmail,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'auth_user_id': authUserId,
        'login_email': loginEmail,
      };

  static _CloudBinding? fromJson(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final Map<String, dynamic> value = Map<String, dynamic>.from(raw);
    final String authUserId = value['auth_user_id']?.toString().trim() ?? '';
    final String loginEmail =
        value['login_email']?.toString().trim().toLowerCase() ?? '';

    if (authUserId.isEmpty || loginEmail.isEmpty) {
      return null;
    }

    return _CloudBinding(
      authUserId: authUserId,
      loginEmail: loginEmail,
    );
  }
}

/// Étape 04A.2 — garde-fou entre le compte Project XP local et Supabase.
///
/// Invariants :
/// - un compte Cloud permanent ne doit jamais utiliser la session d'un autre
///   compte local ;
/// - après un logout Cloud explicite, le mot de passe est requis pour rouvrir
///   la session Supabase ;
/// - aucun mot de passe ni refresh token n'est sauvegardé par ce service ;
/// - les comptes locaux non Cloud peuvent continuer à utiliser une session
///   Supabase anonyme.
class CloudSessionGuardService {
  CloudSessionGuardService._();

  static const String _bindingPrefix =
      'project_xp_cloud_session_binding_v1_';

  static const String _classificationPrefix =
      'project_xp_cloud_session_classification_v1_';

  static SupabaseClient get _client => SupabaseService.client;

  static String _bindingKey(String localUserId) =>
      '$_bindingPrefix${localUserId.trim()}';

  static String _classificationKey(String localUserId) =>
      '$_classificationPrefix${localUserId.trim()}';

  static Future<CloudLocalAccountKind> currentLocalAccountKind() async {
    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (localUserId.isEmpty) {
      return CloudLocalAccountKind.unknown;
    }

    if (await _loadBinding(localUserId) != null) {
      return CloudLocalAccountKind.cloud;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String value =
        prefs.getString(_classificationKey(localUserId))?.trim() ?? '';

    if (value == 'local_only') {
      return CloudLocalAccountKind.localOnly;
    }

    return CloudLocalAccountKind.unknown;
  }

  static Future<void> _markLocalOnly(String localUserId) async {
    final String cleanLocalUserId = localUserId.trim();
    if (cleanLocalUserId.isEmpty) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _classificationKey(cleanLocalUserId),
      'local_only',
    );
  }

  /// À utiliser juste après la création d'un nouveau compte local.
  /// Ce compte vient d'être créé sur cet appareil : il est donc explicitement
  /// classé local tant qu'il n'est pas converti en compte Cloud.
  static Future<bool> prepareNewLocalAccountSocialSession() async {
    if (!await AuthService.isLoggedIn()) {
      return false;
    }

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (localUserId.isEmpty) {
      return false;
    }

    await _markLocalOnly(localUserId);

    final User? existing = SupabaseService.currentUser;
    if (existing != null && !existing.isAnonymous) {
      final bool matches = await _permanentSessionMatchesLocal(
        user: existing,
        localUserId: localUserId,
      );

      if (matches) {
        return true;
      }

      try {
        await _client.auth.signOut();
      } catch (_) {}
    }

    final User? current = SupabaseService.currentUser;
    if (current != null && current.isAnonymous) {
      return true;
    }

    try {
      await SupabaseService.ensureAnonymousSession();
    } catch (error) {
      // Le compte vient d'être créé localement et son statut est connu. Une
      // panne réseau ne doit pas empêcher l'accès aux données locales ; les
      // fonctions sociales resteront simplement en attente.
      debugPrint('Session sociale locale différée : $error');
    }

    return true;
  }

  /// Confirme explicitement qu'un ancien compte n'avait jamais été converti
  /// en compte Cloud. Utilisé uniquement après validation du mot de passe local
  /// et confirmation de l'utilisateur dans l'écran de connexion.
  static Future<bool> confirmCurrentAccountLocalOnly() async {
    if (!await AuthService.isLoggedIn()) {
      return false;
    }

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (localUserId.isEmpty) {
      return false;
    }

    final User? existing = SupabaseService.currentUser;
    if (existing != null && !existing.isAnonymous) {
      final bool matches = await _permanentSessionMatchesLocal(
        user: existing,
        localUserId: localUserId,
      );

      if (matches) {
        return false;
      }

      try {
        await _client.auth.signOut();
      } catch (_) {}
    }

    await _markLocalOnly(localUserId);

    final User? current = SupabaseService.currentUser;
    if (current != null && current.isAnonymous) {
      return true;
    }

    try {
      await SupabaseService.ensureAnonymousSession();
    } catch (error) {
      // Le compte est explicitement local-only : le mode local reste utilisable
      // même si Supabase est momentanément indisponible.
      debugPrint('Session sociale locale différée : $error');
    }

    return true;
  }

  static Future<_CloudBinding?> _loadBinding(String localUserId) async {
    final String cleanLocalUserId = localUserId.trim();
    if (cleanLocalUserId.isEmpty) {
      return null;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString(_bindingKey(cleanLocalUserId)) ?? '';

    if (raw.isEmpty) {
      return null;
    }

    try {
      return _CloudBinding.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveBinding({
    required String localUserId,
    required String authUserId,
    required String loginEmail,
  }) async {
    final String cleanLocalUserId = localUserId.trim();
    final String cleanAuthUserId = authUserId.trim();
    final String cleanEmail = loginEmail.trim().toLowerCase();

    if (cleanLocalUserId.isEmpty ||
        cleanAuthUserId.isEmpty ||
        cleanEmail.isEmpty) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_classificationKey(cleanLocalUserId));
    await prefs.setString(
      _bindingKey(cleanLocalUserId),
      jsonEncode(
        _CloudBinding(
          authUserId: cleanAuthUserId,
          loginEmail: cleanEmail,
        ).toJson(),
      ),
    );
  }

  static Future<bool> isCurrentLocalAccountCloudBound() async {
    return await currentLocalAccountKind() == CloudLocalAccountKind.cloud;
  }

  static Future<Map<String, dynamic>?> _mappingForAuthUser(String authUserId) async {
    try {
      final dynamic raw = await _client
          .from('project_xp_cloud_accounts')
          .select('auth_user_id, project_xp_user_id, email')
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (error) {
      debugPrint('Vérification mapping Cloud impossible : $error');
    }

    return null;
  }

  static Future<bool> _permanentSessionMatchesLocal({
    required User user,
    required String localUserId,
    bool remember = true,
  }) async {
    if (user.isAnonymous) {
      return false;
    }

    final Map<String, dynamic>? mapping = await _mappingForAuthUser(user.id);
    if (mapping == null) {
      return false;
    }

    final String mappedLocalUserId =
        mapping['project_xp_user_id']?.toString().trim() ?? '';

    if (mappedLocalUserId != localUserId.trim()) {
      return false;
    }

    if (remember) {
      final String email =
          mapping['email']?.toString().trim().toLowerCase() ??
              user.email?.trim().toLowerCase() ??
              '';

      if (email.isNotEmpty) {
        await _saveBinding(
          localUserId: localUserId,
          authUserId: user.id,
          loginEmail: email,
        );
      }
    }

    return true;
  }

  /// Valide une session déjà disponible sans disposer du mot de passe.
  ///
  /// Pour un compte Cloud connu, l'absence de session permanente alignée est
  /// considérée comme non prête : on ne retombe PAS silencieusement sur une
  /// identité anonyme, ce qui éviterait un nouveau mélange de compte.
  static Future<bool> ensureAlignedSessionWithoutPassword() async {
    if (!await AuthService.isLoggedIn()) {
      return false;
    }

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    if (localUserId.isEmpty) {
      return false;
    }

    final _CloudBinding? binding = await _loadBinding(localUserId);
    final CloudLocalAccountKind kind = await currentLocalAccountKind();
    final User? existing = SupabaseService.currentUser;

    if (existing != null && !existing.isAnonymous) {
      final bool matches = await _permanentSessionMatchesLocal(
        user: existing,
        localUserId: localUserId,
      );

      if (matches) {
        return true;
      }

      // Session permanente d'un autre compte : on la ferme immédiatement.
      try {
        await _client.auth.signOut();
      } catch (_) {}

      if (binding != null) {
        return false;
      }
    }

    final User? afterPermanentCheck = SupabaseService.currentUser;

    if (binding != null) {
      // Un compte Cloud connu doit être réauthentifié par mot de passe après
      // une vraie déconnexion. On refuse une identité anonyme de remplacement.
      if (afterPermanentCheck != null && afterPermanentCheck.isAnonymous) {
        try {
          await _client.auth.signOut();
        } catch (_) {}
      }
      return false;
    }

    if (kind == CloudLocalAccountKind.unknown) {
      // Migration 04A.2 : une ancienne identité locale non classée peut être
      // soit réellement locale, soit un compte Cloud dont la session a déjà
      // disparu. Sans mot de passe, on ne choisit jamais à sa place.
      return false;
    }

    if (afterPermanentCheck != null && afterPermanentCheck.isAnonymous) {
      return true;
    }

    final User? anonymous = await SupabaseService.ensureAnonymousSession();
    return anonymous != null || SupabaseService.currentUser != null;
  }

  /// Réaligne Supabase juste après une connexion locale validée par mot de
  /// passe. Pour un compte Cloud connu, le mot de passe est utilisé uniquement
  /// pour cet appel Supabase et n'est jamais conservé.
  static Future<CloudSessionAlignmentResult> alignAfterPasswordLogin({
    required String password,
    bool legacyDecisionOnInvalidCredentials = true,
  }) async {
    if (!await AuthService.isLoggedIn()) {
      return const CloudSessionAlignmentResult.fail(
        'Le compte Project XP local n’est pas connecté.',
      );
    }

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';
    final String localEmail =
        (await AuthService.getCurrentEmail())?.trim().toLowerCase() ?? '';

    if (localUserId.isEmpty || localEmail.isEmpty) {
      return const CloudSessionAlignmentResult.fail(
        'Le compte Project XP local est incomplet.',
      );
    }

    final _CloudBinding? binding = await _loadBinding(localUserId);
    final CloudLocalAccountKind kind = await currentLocalAccountKind();
    final User? existing = SupabaseService.currentUser;

    if (existing != null && !existing.isAnonymous) {
      final bool matches = await _permanentSessionMatchesLocal(
        user: existing,
        localUserId: localUserId,
      );

      if (matches) {
        return const CloudSessionAlignmentResult.ok();
      }

      try {
        await _client.auth.signOut();
      } catch (_) {}
    }

    if (kind == CloudLocalAccountKind.localOnly && binding == null) {
      // Le statut a déjà été vérifié lors d'un précédent login par mot de
      // passe. Il est inutile de sonder Supabase à chaque connexion locale.
      final User? current = SupabaseService.currentUser;
      if (current != null && current.isAnonymous) {
        return const CloudSessionAlignmentResult.ok();
      }

      try {
        await SupabaseService.ensureAnonymousSession();
      } catch (error) {
        // Mode local/offline autorisé pour un compte explicitement classé
        // local-only. Les tâches sociales seront bloquées par le garde startup.
        debugPrint('Session sociale locale différée : $error');
      }

      return const CloudSessionAlignmentResult.ok();
    }

    if (binding == null) {
      // Migration douce pour les comptes Cloud créés avant Étape 04A.2 : si le
      // même e-mail/mot de passe existe déjà côté Supabase, on tente de le
      // retrouver puis on n'accepte la session QUE si son mapping pointe vers
      // exactement le même ID Project XP local.
      try {
        final AuthResponse discovery = await _client.auth.signInWithPassword(
          email: localEmail,
          password: password,
        );

        final User? discoveredUser = discovery.user;
        if (discoveredUser != null && !discoveredUser.isAnonymous) {
          final bool matches = await _permanentSessionMatchesLocal(
            user: discoveredUser,
            localUserId: localUserId,
          );

          if (matches) {
            return const CloudSessionAlignmentResult.ok();
          }

          try {
            await _client.auth.signOut();
          } catch (_) {}

          return const CloudSessionAlignmentResult.fail(
            'Sécurité : un compte Cloud existe avec ces identifiants, mais il ne correspond pas à ce compte Project XP local.',
          );
        }
      } on AuthException catch (error) {
        final String message = error.message.toLowerCase();
        final bool credentialsAbsent =
            message.contains('invalid login credentials') ||
            message.contains('invalid credentials');

        if (!credentialsAbsent) {
          debugPrint('Découverte Cloud indéterminée : ${error.message}');
          return const CloudSessionAlignmentResult.fail(
            'Impossible de vérifier si ce compte possède une identité Cloud. '
            'Vérifie ta connexion Internet puis réessaie.',
          );
        }

        debugPrint('Identifiants Cloud non reconnus : ${error.message}');

        if (legacyDecisionOnInvalidCredentials) {
          // Avant 04A.2, le mot de passe local pouvait avoir été changé sans
          // mettre à jour Supabase. "Invalid credentials" est donc ambigu :
          // cela peut être un vrai compte local-only OU un ancien compte Cloud
          // avec un mot de passe différent. La décision doit être explicite.
          return const CloudSessionAlignmentResult.legacyDecision(
            'Le mot de passe local est valide, mais le statut Cloud de cet ancien compte doit être confirmé.',
          );
        }

        return const CloudSessionAlignmentResult.fail(
          'Le mot de passe Cloud Project XP n’a pas été reconnu.',
        );
      } catch (error) {
        debugPrint('Découverte Cloud impossible : $error');
        return const CloudSessionAlignmentResult.fail(
          'Impossible de vérifier la session Cloud pour le moment.',
        );
      }

      return const CloudSessionAlignmentResult.fail(
        'Impossible de déterminer le statut Cloud de ce compte.',
      );
    }

    final String cloudEmail = binding.loginEmail.isNotEmpty
        ? binding.loginEmail
        : localEmail;

    try {
      final AuthResponse response = await _client.auth.signInWithPassword(
        email: cloudEmail,
        password: password,
      );

      final User? user = response.user;
      if (user == null || user.isAnonymous) {
        try {
          await _client.auth.signOut();
        } catch (_) {}
        return const CloudSessionAlignmentResult.fail(
          'La session Cloud Project XP n’a pas pu être ouverte.',
        );
      }

      final bool matches = await _permanentSessionMatchesLocal(
        user: user,
        localUserId: localUserId,
      );

      if (!matches ||
          (binding.authUserId.isNotEmpty && binding.authUserId != user.id)) {
        try {
          await _client.auth.signOut();
        } catch (_) {}
        return const CloudSessionAlignmentResult.fail(
          'Sécurité : le compte Cloud ne correspond pas au compte Project XP local.',
        );
      }

      return const CloudSessionAlignmentResult.ok();
    } on AuthException catch (error) {
      try {
        await _client.auth.signOut();
      } catch (_) {}

      debugPrint('Réalignement Cloud refusé : ${error.message}');
      return const CloudSessionAlignmentResult.fail(
        'Le mot de passe local est valide, mais la reconnexion Cloud a échoué. '
        'Reconnecte-toi avec le mot de passe de ton compte Cloud Project XP.',
      );
    } catch (error) {
      try {
        await _client.auth.signOut();
      } catch (_) {}

      debugPrint('Réalignement Cloud impossible : $error');
      return const CloudSessionAlignmentResult.fail(
        'Impossible de vérifier la session Cloud pour le moment.',
      );
    }
  }

  /// À appeler AVANT de fermer une session permanente. Le mapping courant est
  /// mémorisé localement afin qu'au prochain login Project XP sache qu'il doit
  /// exiger une vraie réauthentification Cloud.
  static Future<void> rememberCurrentPermanentBinding() async {
    if (!await AuthService.isLoggedIn()) {
      return;
    }

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';
    final User? user = SupabaseService.currentUser;

    if (localUserId.isEmpty || user == null || user.isAnonymous) {
      return;
    }

    await _permanentSessionMatchesLocal(
      user: user,
      localUserId: localUserId,
    );
  }

  static Future<void> signOutPermanentSession() async {
    final User? user = SupabaseService.currentUser;

    if (user == null || user.isAnonymous) {
      return;
    }

    try {
      await _client.auth.signOut();
    } catch (error) {
      debugPrint('Déconnexion Cloud Supabase impossible : $error');
    }
  }
}
