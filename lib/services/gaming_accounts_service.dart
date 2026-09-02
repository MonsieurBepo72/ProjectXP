import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supabase_service.dart';

enum GamingPlatformProvider {
  steam,
  playstation,
  xbox,
  nintendo,
  epic,
}

extension GamingPlatformProviderX on GamingPlatformProvider {
  String get key {
    switch (this) {
      case GamingPlatformProvider.steam:
        return 'steam';
      case GamingPlatformProvider.playstation:
        return 'playstation';
      case GamingPlatformProvider.xbox:
        return 'xbox';
      case GamingPlatformProvider.nintendo:
        return 'nintendo';
      case GamingPlatformProvider.epic:
        return 'epic';
    }
  }

  String get label {
    switch (this) {
      case GamingPlatformProvider.steam:
        return 'Steam';
      case GamingPlatformProvider.playstation:
        return 'PlayStation';
      case GamingPlatformProvider.xbox:
        return 'Xbox';
      case GamingPlatformProvider.nintendo:
        return 'Nintendo';
      case GamingPlatformProvider.epic:
        return 'Epic Games';
    }
  }
}

class GamingAccountLink {
  final GamingPlatformProvider provider;
  final String providerUserId;
  final String displayName;
  final String? avatarUrl;
  final DateTime? linkedAt;
  final DateTime? updatedAt;

  const GamingAccountLink({
    required this.provider,
    required this.providerUserId,
    required this.displayName,
    required this.avatarUrl,
    required this.linkedAt,
    required this.updatedAt,
  });

  factory GamingAccountLink.fromJson(Map<String, dynamic> json) {
    final String providerKey =
        json['provider']?.toString().trim().toLowerCase() ?? '';

    final GamingPlatformProvider provider =
        GamingPlatformProvider.values.firstWhere(
      (value) => value.key == providerKey,
      orElse: () => GamingPlatformProvider.steam,
    );

    String? nullable(String key) {
      final String value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return GamingAccountLink(
      provider: provider,
      providerUserId:
          json['provider_user_id']?.toString().trim() ?? '',
      displayName: json['display_name']?.toString().trim() ?? '',
      avatarUrl: nullable('avatar_url'),
      linkedAt: DateTime.tryParse(
        json['linked_at']?.toString() ?? '',
      ),
      updatedAt: DateTime.tryParse(
        json['updated_at']?.toString() ?? '',
      ),
    );
  }
}

class GamingAccountsException implements Exception {
  final String message;

  const GamingAccountsException(this.message);

  @override
  String toString() => message;
}

class GamingAccountsService {
  GamingAccountsService._();

  static const String _table = 'project_xp_platform_accounts';
  static const String _callbackScheme = 'projectxp';
  static const String _callbackHost = 'platform-auth';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final ValueNotifier<String?> lastCallbackMessage =
      ValueNotifier<String?>(null);

  static AppLinks? _appLinks;
  static StreamSubscription<Uri>? _linkSubscription;
  static Future<void>? _initializationFuture;

  static User? get permanentUser {
    final User? user = SupabaseService.currentUser;
    if (user == null || user.isAnonymous) {
      return null;
    }
    return user;
  }

  static bool get hasPermanentCloudAccount => permanentUser != null;

  static Future<void> initialize() {
    return _initializationFuture ??= _initializeInternal();
  }

  static Future<void> _initializeInternal() async {
    _appLinks = AppLinks();

    try {
      final Uri? initial = await _appLinks!.getInitialLink();
      if (initial != null) {
        await _handleIncomingUri(initial);
      }
    } catch (error) {
      debugPrint('Lien plateforme initial ignoré : $error');
    }

    await _linkSubscription?.cancel();
    _linkSubscription = _appLinks!.uriLinkStream.listen(
      (Uri uri) {
        unawaited(_handleIncomingUri(uri));
      },
      onError: (Object error) {
        debugPrint('Lien plateforme invalide : $error');
      },
    );
  }

  static Future<void> _handleIncomingUri(Uri uri) async {
    if (uri.scheme != _callbackScheme || uri.host != _callbackHost) {
      return;
    }

    final String provider =
        uri.queryParameters['provider']?.trim() ?? '';
    final String status =
        uri.queryParameters['status']?.trim() ?? '';
    final String message =
        uri.queryParameters['message']?.trim() ?? '';

    if (provider == 'steam' && status == 'success') {
      lastCallbackMessage.value = 'Compte Steam lié avec succès.';
      revision.value += 1;
      return;
    }

    if (provider == 'steam' && status == 'cancelled') {
      lastCallbackMessage.value = 'Connexion Steam annulée.';
      revision.value += 1;
      return;
    }

    lastCallbackMessage.value = message.isNotEmpty
        ? message
        : 'La connexion à la plateforme a échoué.';
    revision.value += 1;
  }

  static Future<List<GamingAccountLink>> loadAccounts() async {
    final User? user = permanentUser;
    if (user == null) {
      return <GamingAccountLink>[];
    }

    try {
      final dynamic raw = await SupabaseService.client
          .from(_table)
          .select(
            'provider, provider_user_id, display_name, avatar_url, linked_at, updated_at',
          )
          .eq('auth_user_id', user.id)
          .order('provider');

      if (raw is! List) {
        return <GamingAccountLink>[];
      }

      return raw
          .whereType<Map>()
          .map(
            (item) => GamingAccountLink.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.providerUserId.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('Lecture comptes gaming impossible : $error');
      return <GamingAccountLink>[];
    }
  }

  static Future<GamingAccountLink?> account(
    GamingPlatformProvider provider,
  ) async {
    final List<GamingAccountLink> accounts = await loadAccounts();
    for (final GamingAccountLink account in accounts) {
      if (account.provider == provider) {
        return account;
      }
    }
    return null;
  }

  static Future<bool> startSteamLink() async {
    final User? user = permanentUser;
    if (user == null) {
      throw const GamingAccountsException(
        'Active d’abord ton compte Cloud Project XP pour lier Steam de façon sécurisée.',
      );
    }

    try {
      final FunctionResponse response =
          await SupabaseService.client.functions.invoke(
        'platform-auth',
        body: const <String, dynamic>{
          'action': 'steam_start',
        },
      );

      final dynamic raw = response.data;
      if (raw is! Map) {
        throw const GamingAccountsException(
          'Project XP n’a pas reçu de lien de connexion Steam valide.',
        );
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(raw);
      if (data['ok'] != true) {
        throw GamingAccountsException(
          data['error']?.toString() ??
              'Impossible de préparer la connexion Steam.',
        );
      }

      final String authUrl = data['authUrl']?.toString().trim() ?? '';
      final Uri? uri = Uri.tryParse(authUrl);
      if (uri == null || uri.scheme != 'https') {
        throw const GamingAccountsException(
          'Le lien Steam reçu est invalide.',
        );
      }

      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw const GamingAccountsException(
          'Impossible d’ouvrir Steam dans le navigateur.',
        );
      }

      return true;
    } on FunctionException catch (error) {
      throw GamingAccountsException(
        _friendlyFunctionError(error.details),
      );
    } on GamingAccountsException {
      rethrow;
    } catch (error) {
      throw GamingAccountsException(
        _friendlyFunctionError(error.toString()),
      );
    }
  }

  static Future<void> unlink(
    GamingPlatformProvider provider,
  ) async {
    final User? user = permanentUser;
    if (user == null) {
      throw const GamingAccountsException(
        'Aucun compte Cloud actif.',
      );
    }

    try {
      await SupabaseService.client
          .from(_table)
          .delete()
          .eq('auth_user_id', user.id)
          .eq('provider', provider.key);

      revision.value += 1;
    } catch (error) {
      throw GamingAccountsException(
        'Impossible de délier ${provider.label} pour le moment.',
      );
    }
  }

  static String _friendlyFunctionError(dynamic raw) {
    if (raw is Map && raw['error'] != null) {
      return raw['error'].toString();
    }

    final String message = raw?.toString() ?? '';
    if (message.contains('404') ||
        message.contains('Function not found')) {
      return 'La connexion plateformes n’est pas encore déployée côté Supabase.';
    }
    if (message.trim().isEmpty) {
      return 'Connexion plateforme indisponible.';
    }
    return 'Connexion plateforme indisponible : $message';
  }
}
