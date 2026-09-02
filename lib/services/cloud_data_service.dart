import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/avatar_model.dart';
import '../models/game_library_entry.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

class CloudReadResult<T> {
  final bool available;
  final bool found;
  final T? value;

  const CloudReadResult._({
    required this.available,
    required this.found,
    required this.value,
  });

  const CloudReadResult.unavailable()
      : this._(
          available: false,
          found: false,
          value: null,
        );

  const CloudReadResult.missing()
      : this._(
          available: true,
          found: false,
          value: null,
        );

  const CloudReadResult.found(T value)
      : this._(
          available: true,
          found: true,
          value: value,
        );
}

class CloudDataService {
  CloudDataService._();

  static const String _profileTable =
      'project_xp_cloud_profiles';
  static const String _libraryTable =
      'project_xp_game_library';
  static const String _activityTable =
      'project_xp_gaming_activity';
  static const String _avatarBucket =
      'project-xp-private-avatars';

  static SupabaseClient get _client =>
      SupabaseService.client;

  static User? get permanentUser {
    final User? user =
        SupabaseService.currentUser;

    if (user == null || user.isAnonymous) {
      return null;
    }

    return user;
  }

  static Future<String?> _projectXpUserId() async {
    final String value =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    return value.isEmpty ? null : value;
  }

  // ===========================================================================
  // PROFIL PRIVÉ
  // ===========================================================================

  static Future<CloudReadResult<Map<String, dynamic>>>
      loadPrivateProfile() async {
    final User? user = permanentUser;

    if (user == null) {
      return const CloudReadResult.unavailable();
    }

    try {
      final dynamic raw = await _client
          .from(_profileTable)
          .select('profile_data')
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (raw is! Map) {
        return const CloudReadResult.missing();
      }

      final dynamic profileRaw =
          raw['profile_data'];

      if (profileRaw is! Map ||
          profileRaw.isEmpty) {
        return const CloudReadResult.missing();
      }

      return CloudReadResult.found(
        Map<String, dynamic>.from(
          profileRaw,
        ),
      );
    } catch (_) {
      return const CloudReadResult.unavailable();
    }
  }

  static Future<bool> savePrivateProfile(
    Map<String, dynamic> profile,
  ) async {
    final User? user = permanentUser;
    final String? projectXpUserId =
        await _projectXpUserId();

    if (user == null ||
        projectXpUserId == null) {
      return false;
    }

    try {
      final DateTime now = DateTime.now().toUtc();

      await _client
          .from(_profileTable)
          .upsert(
        <String, dynamic>{
          'auth_user_id': user.id,
          'project_xp_user_id':
              projectXpUserId,
          'profile_data': profile,
          'profile_updated_at':
              now.toIso8601String(),
          'updated_at':
              now.toIso8601String(),
        },
        onConflict: 'auth_user_id',
      );

      final String pseudo =
          profile['pseudo']?.toString().trim() ?? '';

      if (pseudo.isNotEmpty) {
        await _client
            .from('project_xp_cloud_accounts')
            .update(
          <String, dynamic>{
            'username': pseudo,
            'updated_at':
                now.toIso8601String(),
          },
        ).eq(
          'auth_user_id',
          user.id,
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // AVATAR PRIVÉ
  //
  // L'avatar manuel est entièrement sérialisé dans PostgreSQL.
  // Pour le mode photo, le fichier est sauvegardé dans un bucket PRIVÉ :
  // il ne devient jamais une URL publique par cette couche Cloud.
  // ===========================================================================

  static Future<CloudReadResult<AvatarModel>>
      loadPrivateAvatar({
    required String localUserId,
  }) async {
    final User? user = permanentUser;

    if (user == null) {
      return const CloudReadResult.unavailable();
    }

    try {
      final dynamic raw = await _client
          .from(_profileTable)
          .select(
            'avatar_data, avatar_photo_path',
          )
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (raw is! Map) {
        return const CloudReadResult.missing();
      }

      final dynamic avatarRaw =
          raw['avatar_data'];

      if (avatarRaw is! Map ||
          avatarRaw.isEmpty) {
        return const CloudReadResult.missing();
      }

      final AvatarModel decodedAvatar =
          AvatarModel.fromJson(
        Map<String, dynamic>.from(
          avatarRaw,
        ),
      );

      AvatarModel avatar =
          decodedAvatar.copyWith(
        userId: localUserId,
        updatedAt: decodedAvatar.updatedAt,
      );

      if (avatar.creationMode ==
          AvatarCreationMode.photo) {
        final String remotePhotoPath =
            raw['avatar_photo_path']
                    ?.toString()
                    .trim() ??
                '';

        if (remotePhotoPath.isNotEmpty) {
          final String? localPath =
              await _downloadPrivateAvatarPhoto(
            remotePhotoPath,
            authUserId: user.id,
          );

          if (localPath != null) {
            avatar = avatar.copyWith(
              userId: localUserId,
              generatedImagePath:
                  localPath,
              updatedAt: avatar.updatedAt,
            );
          } else {
            avatar = avatar.copyWith(
              userId: localUserId,
              clearGeneratedImagePath:
                  true,
              updatedAt: avatar.updatedAt,
            );
          }
        }
      }

      return CloudReadResult.found(
        avatar,
      );
    } catch (_) {
      return const CloudReadResult.unavailable();
    }
  }

  static Future<bool> savePrivateAvatar(
    AvatarModel avatar,
  ) async {
    final User? user = permanentUser;
    final String? projectXpUserId =
        await _projectXpUserId();

    if (user == null ||
        projectXpUserId == null) {
      return false;
    }

    try {
      final String? previousPhotoPath =
          await _existingAvatarPhotoPath(
        user.id,
      );

      String? cloudPhotoPath;

      if (avatar.creationMode ==
          AvatarCreationMode.photo) {
        cloudPhotoPath =
            await _uploadPrivateAvatarPhoto(
          avatar,
          authUserId: user.id,
        );

        if (cloudPhotoPath == null &&
            previousPhotoPath != null) {
          // Si le fichier local n'est momentanément plus accessible,
          // on ne détruit surtout pas la sauvegarde Cloud précédente.
          cloudPhotoPath =
              previousPhotoPath;
        }

        if (cloudPhotoPath == null) {
          // Une photo sans fichier Cloud ne doit jamais être considérée comme
          // sauvegardée : le cache local reste intact et un prochain sync
          // retentera l'upload.
          return false;
        }
      }

      final Map<String, dynamic> avatarData =
          Map<String, dynamic>.from(
        avatar.toJson(),
      );

      // Un chemin Android local n'a aucun sens sur un autre appareil.
      avatarData['generatedImagePath'] = null;

      final DateTime now = DateTime.now().toUtc();

      await _client
          .from(_profileTable)
          .upsert(
        <String, dynamic>{
          'auth_user_id': user.id,
          'project_xp_user_id':
              projectXpUserId,
          'avatar_data': avatarData,
          'avatar_photo_path':
              cloudPhotoPath,
          'avatar_updated_at':
              avatar.updatedAt
                  .toUtc()
                  .toIso8601String(),
          'updated_at':
              now.toIso8601String(),
        },
        onConflict: 'auth_user_id',
      );

      if (avatar.creationMode ==
              AvatarCreationMode.manual &&
          previousPhotoPath != null) {
        try {
          await _client.storage
              .from(_avatarBucket)
              .remove(
            <String>[
              previousPhotoPath,
            ],
          );
        } catch (_) {
          // La donnée PostgreSQL est déjà correcte : un ancien fichier isolé
          // ne doit jamais faire échouer la sauvegarde de l'avatar.
        }
      } else if (previousPhotoPath != null &&
          cloudPhotoPath != null &&
          previousPhotoPath !=
              cloudPhotoPath) {
        try {
          await _client.storage
              .from(_avatarBucket)
              .remove(
            <String>[
              previousPhotoPath,
            ],
          );
        } catch (_) {
          // Nettoyage non bloquant.
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _existingAvatarPhotoPath(
    String authUserId,
  ) async {
    try {
      final dynamic raw = await _client
          .from(_profileTable)
          .select('avatar_photo_path')
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (raw is! Map) {
        return null;
      }

      final String value =
          raw['avatar_photo_path']
                  ?.toString()
                  .trim() ??
              '';

      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _uploadPrivateAvatarPhoto(
    AvatarModel avatar, {
    required String authUserId,
  }) async {
    final String localPath =
        avatar.generatedImagePath?.trim() ?? '';

    if (localPath.isEmpty ||
        localPath.startsWith('http://') ||
        localPath.startsWith('https://')) {
      return null;
    }

    final File file = File(localPath);

    if (!await file.exists()) {
      return null;
    }

    final String extension =
        _safeImageExtension(localPath);
    final String remotePath =
        '$authUserId/avatar$extension';

    await _client.storage
        .from(_avatarBucket)
        .upload(
      remotePath,
      file,
      fileOptions: FileOptions(
        upsert: true,
        contentType:
            _imageContentType(extension),
      ),
    );

    return remotePath;
  }

  static Future<String?> _downloadPrivateAvatarPhoto(
    String remotePath, {
    required String authUserId,
  }) async {
    try {
      final bytes = await _client.storage
          .from(_avatarBucket)
          .download(
        remotePath,
      );

      final Directory appDirectory =
          await getApplicationDocumentsDirectory();

      final Directory avatarDirectory = Directory(
        '${appDirectory.path}'
        '${Platform.pathSeparator}'
        'avatars',
      );

      if (!await avatarDirectory.exists()) {
        await avatarDirectory.create(
          recursive: true,
        );
      }

      final String extension =
          _safeImageExtension(remotePath);
      final File localFile = File(
        '${avatarDirectory.path}'
        '${Platform.pathSeparator}'
        'cloud_avatar_$authUserId$extension',
      );

      await localFile.writeAsBytes(
        bytes,
        flush: true,
      );

      return localFile.path;
    } catch (_) {
      return null;
    }
  }

  static String _safeImageExtension(
    String path,
  ) {
    final String lower = path.toLowerCase();

    if (lower.endsWith('.png')) {
      return '.png';
    }
    if (lower.endsWith('.webp')) {
      return '.webp';
    }
    if (lower.endsWith('.heic')) {
      return '.heic';
    }
    if (lower.endsWith('.jpeg')) {
      return '.jpeg';
    }
    return '.jpg';
  }

  static String _imageContentType(
    String extension,
  ) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.jpeg':
      case '.jpg':
      default:
        return 'image/jpeg';
    }
  }


  static Future<bool> _cloudSectionInitialized(
    String column,
    String authUserId,
  ) async {
    try {
      final dynamic raw = await _client
          .from(_profileTable)
          .select(column)
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (raw is! Map) {
        return false;
      }

      return raw[column] == true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // BIBLIOTHÈQUE
  // ===========================================================================

  static Future<CloudReadResult<List<GameLibraryEntry>>>
      loadLibrary() async {
    final User? user = permanentUser;

    if (user == null) {
      return const CloudReadResult.unavailable();
    }

    try {
      final List<dynamic> response =
          await _client
              .from(_libraryTable)
              .select('game_data')
              .eq('auth_user_id', user.id);

      if (response.isEmpty) {
        final bool initialized =
            await _cloudSectionInitialized(
          'library_initialized',
          user.id,
        );

        if (initialized) {
          return const CloudReadResult.found(
            <GameLibraryEntry>[],
          );
        }

        return const CloudReadResult.missing();
      }

      final List<GameLibraryEntry> entries =
          <GameLibraryEntry>[];

      for (final dynamic item in response) {
        if (item is! Map) {
          continue;
        }

        final dynamic data =
            item['game_data'];

        if (data is! Map) {
          continue;
        }

        final GameLibraryEntry entry =
            GameLibraryEntry.fromJson(
          Map<String, dynamic>.from(data),
        );

        if (entry.id.isNotEmpty) {
          entries.add(entry);
        }
      }

      entries.sort(
        (a, b) =>
            b.updatedAt.compareTo(a.updatedAt),
      );

      return CloudReadResult.found(entries);
    } catch (_) {
      return const CloudReadResult.unavailable();
    }
  }

  static Future<bool> replaceLibrary(
    List<GameLibraryEntry> entries,
  ) async {
    if (permanentUser == null) {
      return false;
    }

    try {
      final dynamic response =
          await _client.rpc(
        'project_xp_replace_game_library',
        params: <String, dynamic>{
          'p_entries': entries
              .map((entry) => entry.toJson())
              .toList(),
        },
      );

      return response == true ||
          response?.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // FIL D'AVENTURE
  // ===========================================================================

  static Future<CloudReadResult<List<GamingActivityEvent>>>
      loadGamingActivity() async {
    final User? user = permanentUser;

    if (user == null) {
      return const CloudReadResult.unavailable();
    }

    try {
      final List<dynamic> response =
          await _client
              .from(_activityTable)
              .select('event_data')
              .eq('auth_user_id', user.id)
              .order(
                'created_at',
                ascending: false,
              );

      if (response.isEmpty) {
        final bool initialized =
            await _cloudSectionInitialized(
          'activity_initialized',
          user.id,
        );

        if (initialized) {
          return const CloudReadResult.found(
            <GamingActivityEvent>[],
          );
        }

        return const CloudReadResult.missing();
      }

      final List<GamingActivityEvent> events =
          <GamingActivityEvent>[];

      for (final dynamic item in response) {
        if (item is! Map) {
          continue;
        }

        final dynamic data =
            item['event_data'];

        if (data is! Map) {
          continue;
        }

        events.add(
          GamingActivityEvent.fromJson(
            Map<String, dynamic>.from(data),
          ),
        );
      }

      events.sort(
        (a, b) =>
            b.createdAt.compareTo(a.createdAt),
      );

      return CloudReadResult.found(events);
    } catch (_) {
      return const CloudReadResult.unavailable();
    }
  }

  static Future<bool> replaceGamingActivity(
    List<GamingActivityEvent> events,
  ) async {
    if (permanentUser == null) {
      return false;
    }

    try {
      final dynamic response =
          await _client.rpc(
        'project_xp_replace_gaming_activity',
        params: <String, dynamic>{
          'p_events': events
              .map((event) => event.toJson())
              .toList(),
        },
      );

      return response == true ||
          response?.toString() == 'true';
    } catch (_) {
      return false;
    }
  }
}
