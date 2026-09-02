import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/game_library_entry.dart';
import 'auth_service.dart';
import 'game_library_service.dart';
import 'supabase_service.dart';

class SteamSyncException implements Exception {
  final String message;

  const SteamSyncException(this.message);

  @override
  String toString() => message;
}

class SteamLibrarySyncResult {
  final String steamId;
  final int detected;
  final int added;
  final int updated;
  final String? warning;

  const SteamLibrarySyncResult({
    required this.steamId,
    required this.detected,
    required this.added,
    required this.updated,
    required this.warning,
  });
}

class SteamSyncService {
  SteamSyncService._();

  static const String _steamRefPrefix =
      'project_xp_steam_reference_';
  static const String _steamIdPrefix =
      'project_xp_steam_id_';

  static Future<String?> _currentUserId() {
    return AuthService.getCurrentUserId();
  }

  static Future<String?> getSavedReference() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    return prefs.getString('$_steamRefPrefix$userId');
  }

  static Future<void> _saveIdentity({
    required String reference,
    required String steamId,
  }) async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    await Future.wait<bool>([
      prefs.setString(
        '$_steamRefPrefix$userId',
        reference.trim(),
      ),
      prefs.setString(
        '$_steamIdPrefix$userId',
        steamId,
      ),
    ]);
  }

  static Future<String?> getSavedSteamId() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    return prefs.getString('$_steamIdPrefix$userId');
  }

  static Future<SteamLibrarySyncResult> syncLibrary(
    String steamReference,
  ) async {
    final String cleanReference = steamReference.trim();
    if (cleanReference.isEmpty) {
      throw const SteamSyncException(
        'Entre ton SteamID64, ton URL de profil Steam ou ton identifiant personnalisé.',
      );
    }

    await SupabaseService.ensureAnonymousSession();

    try {
      final FunctionResponse response =
          await SupabaseService.client.functions.invoke(
        'steam-sync',
        body: {
          'action': 'library',
          'steamRef': cleanReference,
        },
      );

      final dynamic raw = response.data;
      if (raw is! Map) {
        throw const SteamSyncException(
          'Réponse Steam invalide reçue par Project XP.',
        );
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(raw);
      if (data['ok'] != true) {
        throw SteamSyncException(
          data['error']?.toString() ??
              'La synchronisation Steam a échoué.',
        );
      }

      final String steamId = data['steamId']?.toString() ?? '';
      final dynamic gamesRaw = data['games'];
      if (steamId.isEmpty || gamesRaw is! List) {
        throw const SteamSyncException(
          'Steam n’a pas renvoyé de bibliothèque exploitable.',
        );
      }

      final DateTime now = DateTime.now();
      final List<GameLibraryEntry> imported = <GameLibraryEntry>[];

      for (final dynamic item in gamesRaw) {
        if (item is! Map) {
          continue;
        }
        final Map<String, dynamic> game =
            Map<String, dynamic>.from(item);
        final String appId = game['appid']?.toString() ?? '';
        final String title = game['name']?.toString().trim() ?? '';
        if (appId.isEmpty || title.isEmpty) {
          continue;
        }

        final int playtime = game['playtime_forever'] is int
            ? game['playtime_forever'] as int
            : int.tryParse(
                  game['playtime_forever']?.toString() ?? '',
                ) ??
                0;

        imported.add(
          GameLibraryEntry(
            id: 'steam_$appId',
            title: title,
            platform: GamePlatform.steam,
            status: GameStatus.unclassified,
            favorite: false,
            progressPercent: 0,
            source: GameSource.steam,
            externalId: appId,
            coverUrl:
                'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg',
            playtimeMinutes: playtime,
            achievements: const GameAchievementSummary(),
            addedAt: now,
            updatedAt: now,
          ),
        );
      }

      final ({int added, int updated}) merge =
          await GameLibraryService.mergeSteamGames(imported);
      await _saveIdentity(
        reference: cleanReference,
        steamId: steamId,
      );

      return SteamLibrarySyncResult(
        steamId: steamId,
        detected: imported.length,
        added: merge.added,
        updated: merge.updated,
        warning: data['warning']?.toString(),
      );
    } on FunctionException catch (error) {
      throw SteamSyncException(
        _friendlyFunctionError(error.details),
      );
    } on SteamSyncException {
      rethrow;
    } catch (error) {
      throw SteamSyncException(
        _friendlyFunctionError(error.toString()),
      );
    }
  }

  static Future<GameAchievementSummary> syncAchievements(
    GameLibraryEntry entry,
  ) async {
    if (entry.platform != GamePlatform.steam ||
        entry.externalId == null ||
        entry.externalId!.isEmpty) {
      throw const SteamSyncException(
        'La synchronisation automatique des succès est disponible uniquement pour les jeux Steam importés.',
      );
    }

    final String? steamId = await getSavedSteamId();
    if (steamId == null || steamId.isEmpty) {
      throw const SteamSyncException(
        'Synchronise d’abord ta bibliothèque Steam.',
      );
    }

    await SupabaseService.ensureAnonymousSession();

    try {
      final FunctionResponse response =
          await SupabaseService.client.functions.invoke(
        'steam-sync',
        body: {
          'action': 'achievements',
          'steamId': steamId,
          'appId': entry.externalId,
        },
      );
      final dynamic raw = response.data;
      if (raw is! Map) {
        throw const SteamSyncException(
          'Réponse Steam invalide.',
        );
      }
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(raw);
      if (data['ok'] != true) {
        throw SteamSyncException(
          data['error']?.toString() ??
              'Impossible de synchroniser les succès Steam.',
        );
      }

      final int unlocked = data['unlocked'] is int
          ? data['unlocked'] as int
          : int.tryParse(data['unlocked']?.toString() ?? '') ?? 0;
      final int total = data['total'] is int
          ? data['total'] as int
          : int.tryParse(data['total']?.toString() ?? '') ?? 0;

      final GameAchievementSummary summary =
          entry.achievements.copyWith(
        unlocked: unlocked,
        total: total,
      );
      await GameLibraryService.updateGame(
        entry.copyWith(achievements: summary),
      );
      return summary;
    } on FunctionException catch (error) {
      throw SteamSyncException(
        _friendlyFunctionError(error.details),
      );
    } on SteamSyncException {
      rethrow;
    } catch (error) {
      throw SteamSyncException(
        _friendlyFunctionError(error.toString()),
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
      return 'La fonction Steam n’est pas encore déployée dans Supabase. Suis le README V1.8 pour l’activer.';
    }
    if (message.contains('STEAM_WEB_API_KEY')) {
      return 'La clé Steam n’est pas encore configurée côté serveur.';
    }
    if (message.trim().isEmpty) {
      return 'Impossible de contacter la synchronisation Steam.';
    }
    return 'Synchronisation Steam indisponible : $message';
  }
}
