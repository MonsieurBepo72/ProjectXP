import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class GameCatalogException implements Exception {
  final String message;

  const GameCatalogException(this.message);

  @override
  String toString() => message;
}

class GameCatalogResult {
  final String id;
  final String title;
  final String? coverUrl;
  final String? summary;
  final int? releaseYear;
  final List<String> genres;
  final List<String> platforms;

  const GameCatalogResult({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.summary,
    required this.releaseYear,
    required this.genres,
    required this.platforms,
  });

  factory GameCatalogResult.fromJson(
    Map<String, dynamic> json,
  ) {
    List<String> readList(String key) {
      final dynamic raw = json[key];
      if (raw is! List) {
        return <String>[];
      }
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    int? readYear() {
      final dynamic raw = json['releaseYear'];
      if (raw is int) {
        return raw;
      }
      return int.tryParse(raw?.toString() ?? '');
    }

    String? readNullable(String key) {
      final String value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return GameCatalogResult(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString().trim() ?? '',
      coverUrl: readNullable('coverUrl'),
      summary: readNullable('summary'),
      releaseYear: readYear(),
      genres: readList('genres'),
      platforms: readList('platforms'),
    );
  }
}

class GameCatalogService {
  GameCatalogService._();

  static Future<List<GameCatalogResult>> searchGames(
    String query,
  ) async {
    final String cleanQuery = query.trim();
    if (cleanQuery.length < 2) {
      throw const GameCatalogException(
        'Entre au moins 2 caractères pour rechercher un jeu.',
      );
    }

    await SupabaseService.ensureAnonymousSession();

    try {
      final FunctionResponse response =
          await SupabaseService.client.functions.invoke(
        'game-catalog',
        body: {
          'action': 'search',
          'query': cleanQuery,
        },
      );

      final dynamic raw = response.data;
      if (raw is! Map) {
        throw const GameCatalogException(
          'Le catalogue a renvoyé une réponse invalide.',
        );
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(raw);
      if (data['ok'] != true) {
        throw GameCatalogException(
          data['error']?.toString() ??
              'La recherche de jeux a échoué.',
        );
      }

      final dynamic resultsRaw = data['results'];
      if (resultsRaw is! List) {
        return <GameCatalogResult>[];
      }

      return resultsRaw
          .whereType<Map>()
          .map(
            (item) => GameCatalogResult.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (result) =>
                result.id.isNotEmpty &&
                result.title.isNotEmpty,
          )
          .toList();
    } on FunctionException catch (error) {
      throw GameCatalogException(
        _friendlyFunctionError(error.details),
      );
    } on GameCatalogException {
      rethrow;
    } catch (error) {
      throw GameCatalogException(
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
      return 'Le catalogue de jeux n’est pas encore déployé dans Supabase. '
          'Suis le README V1.8.1 pour l’activer.';
    }

    if (message.contains('IGDB_CLIENT_ID') ||
        message.contains('IGDB_CLIENT_SECRET')) {
      return 'Les identifiants IGDB ne sont pas encore configurés côté serveur.';
    }

    if (message.trim().isEmpty) {
      return 'Impossible de contacter le catalogue de jeux.';
    }

    return 'Catalogue indisponible : $message';
  }
}
