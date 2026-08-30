import '../models/avatar_model.dart';
import 'auth_service.dart';
import 'avatar_storage.dart';
import 'profile_storage.dart';
import 'supabase_service.dart';

class TavernProfileService {
  TavernProfileService._();

  // ===========================================================================
  // SYNCHRONISATION DU PROFIL TAVERNE
  // ===========================================================================

  static Future<bool> syncCurrentProfile() async {
    try {
      // -----------------------------------------------------------------------
      // UTILISATEUR SUPABASE
      // -----------------------------------------------------------------------

      final supabaseUser =
          SupabaseService.currentUser;

      if (supabaseUser == null) {
        return false;
      }

      // -----------------------------------------------------------------------
      // PSEUDO PROJECT XP
      // -----------------------------------------------------------------------

      final String? localUsername =
          await AuthService.getCurrentUsername();

      final String cleanUsername =
          localUsername?.trim() ?? '';

      if (cleanUsername.length < 2) {
        return false;
      }

      // -----------------------------------------------------------------------
      // AVATAR PROJECT XP
      // -----------------------------------------------------------------------

      final AvatarModel? avatar =
          await AvatarStorage.loadCurrentAvatar();

      final Map<String, dynamic>? avatarData =
          _buildPublicAvatarData(
        avatar,
      );

      // -----------------------------------------------------------------------
      // PROFIL PUBLIC PROJECT XP
      // -----------------------------------------------------------------------

      final Map<String, dynamic> localProfile =
          await ProfileStorage.loadProfile();

      final Map<String, dynamic> publicProfileData =
          _buildPublicProfileData(
        localProfile,
      );

      // -----------------------------------------------------------------------
      // SYNCHRONISATION SUPABASE
      // -----------------------------------------------------------------------

      await SupabaseService.client
          .from('tavern_profiles')
          .upsert(
        {
          'id': supabaseUser.id,
          'display_name': cleanUsername,
          'avatar_data': avatarData,
          'public_profile_data':
              publicProfileData,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'id',
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // AVATAR PUBLIC
  // ===========================================================================

  static Map<String, dynamic>? _buildPublicAvatarData(
    AvatarModel? avatar,
  ) {
    if (avatar == null) {
      return null;
    }

    if (avatar.creationMode ==
        AvatarCreationMode.photo) {
      return {
        'creationMode':
            AvatarCreationMode.photo.name,
      };
    }

    return {
      'creationMode':
          AvatarCreationMode.manual.name,
      'skin':
          avatar.skin.name,
      'hair':
          avatar.hair.name,
      'beard':
          avatar.beard.name,
      'outfit':
          avatar.outfit.name,
      'accessory':
          avatar.accessory.name,
      'glasses':
          avatar.glasses.name,
    };
  }

  // ===========================================================================
  // PROFIL PUBLIC
  //
  // IMPORTANT :
  //
  // Ne sont PAS synchronisés :
  // - email
  // - userId local
  // - id local
  // - réseaux non visibles
  // ===========================================================================

  static Map<String, dynamic> _buildPublicProfileData(
    Map<String, dynamic> profile,
  ) {
    final String description =
        profile['description']
                ?.toString()
                .trim() ??
            '';

    // -------------------------------------------------------------------------
    // JEUX
    // -------------------------------------------------------------------------

    final List<String> games =
        <String>[];

    final dynamic rawGames =
        profile['games'];

    if (rawGames is List) {
      for (final dynamic item in rawGames) {
        final String value =
            item.toString().trim();

        if (value.isNotEmpty) {
          games.add(
            value,
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // PLATEFORMES
    // -------------------------------------------------------------------------

    final List<Map<String, dynamic>> platforms =
        <Map<String, dynamic>>[];

    final dynamic rawPlatforms =
        profile['platforms'];

    if (rawPlatforms is List) {
      for (final dynamic item in rawPlatforms) {
        if (item is! Map) {
          continue;
        }

        platforms.add(
          item.map(
            (key, value) => MapEntry(
              key.toString(),
              value?.toString() ?? '',
            ),
          ),
        );
      }
    }

    // -------------------------------------------------------------------------
    // DISPONIBILITÉS
    // -------------------------------------------------------------------------

    final Map<String, List<String>> availability =
        <String, List<String>>{};

    final dynamic rawAvailability =
        profile['availability'];

    if (rawAvailability is Map) {
      for (final MapEntry<dynamic, dynamic> entry
          in rawAvailability.entries) {
        if (entry.value is! List) {
          continue;
        }

        availability[
            entry.key.toString()] =
            (entry.value as List)
                .map(
                  (item) =>
                      item.toString().trim(),
                )
                .where(
                  (item) =>
                      item.isNotEmpty,
                )
                .toList();
      }
    }

    // -------------------------------------------------------------------------
    // RÉSEAUX VISIBLES UNIQUEMENT
    // -------------------------------------------------------------------------

    final List<Map<String, dynamic>> visibleNetworks =
        <Map<String, dynamic>>[];

    final dynamic rawNetworks =
        profile['networks'];

    if (rawNetworks is List) {
      for (final dynamic item in rawNetworks) {
        if (item is! Map) {
          continue;
        }

        final String visibility =
            item['visibilite']
                    ?.toString()
                    .trim()
                    .toLowerCase() ??
                '';

        if (visibility != 'visible') {
          continue;
        }

        final Map<String, dynamic> network =
            item.map(
          (key, value) => MapEntry(
            key.toString(),
            value?.toString() ?? '',
          ),
        );

        visibleNetworks.add(
          network,
        );
      }
    }

    // -------------------------------------------------------------------------
    // COULEUR DU CHAT
    // -------------------------------------------------------------------------

    final String chatColor =
        profile['chatColor']?.toString().trim() ?? '#C56CFF';

    // -------------------------------------------------------------------------
    // DONNÉES PUBLIQUES FINALES
    // -------------------------------------------------------------------------

    return {
      'description': description,
      'games': games,
      'platforms': platforms,
      'availability': availability,
      'networks': visibleNetworks,
      'chat_color': chatColor,
    };
  }

  // ===========================================================================
  // LECTURE DU PROFIL ACTUEL
  // ===========================================================================

  static Future<Map<String, dynamic>?>
      getCurrentProfile() async {
    try {
      final supabaseUser =
          SupabaseService.currentUser;

      if (supabaseUser == null) {
        return null;
      }

      final Map<String, dynamic>? profile =
          await SupabaseService.client
              .from('tavern_profiles')
              .select()
              .eq(
                'id',
                supabaseUser.id,
              )
              .maybeSingle();

      return profile;
    } catch (_) {
      return null;
    }
  }
}