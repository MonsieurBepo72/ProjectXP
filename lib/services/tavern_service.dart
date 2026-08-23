import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class TavernService {
  TavernService._();

  // ===========================================================================
  // CHANNELS
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> getChannels() async {
    final List<dynamic> response =
        await SupabaseService.client
            .from('tavern_channels')
            .select()
            .order(
              'sort_order',
              ascending: true,
            );

    return response
        .map(
          (item) => Map<String, dynamic>.from(
            item as Map,
          ),
        )
        .toList();
  }

  // ===========================================================================
  // CHANNEL PAR SLUG
  // ===========================================================================

  static Future<Map<String, dynamic>?> getChannelBySlug(
    String slug,
  ) async {
    final Map<String, dynamic>? channel =
        await SupabaseService.client
            .from('tavern_channels')
            .select()
            .eq(
              'slug',
              slug,
            )
            .maybeSingle();

    return channel;
  }

  // ===========================================================================
  // PROFIL PUBLIC TAVERNE
  // ===========================================================================

  static Future<Map<String, dynamic>?> getPublicProfile(
    String userId,
  ) async {
    final String cleanUserId =
        userId.trim();

    if (cleanUserId.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic>? profile =
          await SupabaseService.client
              .from('tavern_profiles')
              .select(
                'id, display_name, avatar_url, avatar_data, public_profile_data',
              )
              .eq(
                'id',
                cleanUserId,
              )
              .maybeSingle();

      return profile;
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // MESSAGES
  //
  // La Taverne ne charge que les 50 messages les plus récents du channel.
  // Supabase conserve au maximum 200 messages par channel grâce au trigger SQL.
  //
  // Les messages sont récupérés du plus récent au plus ancien pour appliquer
  // LIMIT 50, puis _deduplicateMessages() les remet dans l'ordre chronologique
  // avant affichage.
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> getMessages(
    String channelId,
  ) async {
    final List<dynamic> response =
        await SupabaseService.client
            .from('tavern_messages')
            .select()
            .eq(
              'channel_id',
              channelId,
            )
            .order(
              'created_at',
              ascending: false,
            )
            .limit(
              50,
            );

    final List<Map<String, dynamic>> messages =
        response
            .map(
              (item) => Map<String, dynamic>.from(
                item as Map,
              ),
            )
            .toList();

    return _attachProfiles(
      _deduplicateMessages(
        messages,
      ),
    );
  }

  // ===========================================================================
  // ENVOYER UN MESSAGE
  // ===========================================================================

  static Future<bool> sendMessage({
    required String channelId,
    required String content,
  }) async {
    final User? user =
        SupabaseService.currentUser;

    if (user == null) {
      return false;
    }

    final String cleanContent =
        content.trim();

    if (cleanContent.isEmpty ||
        cleanContent.length > 2000) {
      return false;
    }

    try {
      await SupabaseService.client
          .from('tavern_messages')
          .insert(
        {
          'channel_id': channelId,
          'author_id': user.id,
          'content': cleanContent,
        },
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // TEMPS RÉEL
  //
  // Le Stream Supabase est créé une seule fois par channel côté écran.
  //
  // IMPORTANT :
  // - seuls les 50 messages les plus récents sont chargés ;
  // - les nouveaux messages arrivent en Realtime ;
  // - le 51e plus ancien sort automatiquement de la fenêtre des 50 ;
  // - _deduplicateMessages() protège toujours contre les doublons temporaires.
  // ===========================================================================

  static Stream<List<Map<String, dynamic>>> messageStream(
    String channelId,
  ) {
    return SupabaseService.client
        .from('tavern_messages')
        .stream(
          primaryKey: [
            'id',
          ],
        )
        .eq(
          'channel_id',
          channelId,
        )
        .order(
          'created_at',
          ascending: false,
        )
        .limit(
          50,
        )
        .asyncMap(
          (rows) async {
            final List<Map<String, dynamic>> messages =
                rows
                    .map(
                      (row) =>
                          Map<String, dynamic>.from(
                        row,
                      ),
                    )
                    .toList();

            return _attachProfiles(
              _deduplicateMessages(
                messages,
              ),
            );
          },
        );
  }

  // ===========================================================================
  // SUPPRESSION DES DOUBLONS
  // ===========================================================================

  static List<Map<String, dynamic>> _deduplicateMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final Map<String, Map<String, dynamic>> byId =
        <String, Map<String, dynamic>>{};

    final List<Map<String, dynamic>> withoutId =
        <Map<String, dynamic>>[];

    for (final Map<String, dynamic> message in messages) {
      final String id =
          message['id']?.toString().trim() ?? '';

      if (id.isEmpty) {
        withoutId.add(
          message,
        );
        continue;
      }

      byId[id] = message;
    }

    final List<Map<String, dynamic>> result = [
      ...byId.values,
      ...withoutId,
    ];

    result.sort(
      (
        Map<String, dynamic> a,
        Map<String, dynamic> b,
      ) {
        final DateTime? dateA =
            DateTime.tryParse(
          a['created_at']?.toString() ?? '',
        );

        final DateTime? dateB =
            DateTime.tryParse(
          b['created_at']?.toString() ?? '',
        );

        if (dateA == null && dateB == null) {
          return 0;
        }

        if (dateA == null) {
          return -1;
        }

        if (dateB == null) {
          return 1;
        }

        return dateA.compareTo(
          dateB,
        );
      },
    );

    return result;
  }

  // ===========================================================================
  // AJOUT DES PROFILS AUX MESSAGES
  //
  // Chaque message reçoit :
  //
  // message['author_profile']
  //
  // contenant :
  // - display_name
  // - avatar_url
  // - avatar_data
  // - public_profile_data
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> _attachProfiles(
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) {
      return messages;
    }

    final Set<String> authorIds =
        messages
            .map(
              (message) =>
                  message['author_id']
                      ?.toString()
                      .trim() ??
                  '',
            )
            .where(
              (id) => id.isNotEmpty,
            )
            .toSet();

    if (authorIds.isEmpty) {
      return messages;
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('tavern_profiles')
              .select(
                'id, display_name, avatar_url, avatar_data, public_profile_data',
              )
              .inFilter(
                'id',
                authorIds.toList(),
              );

      final Map<String, Map<String, dynamic>>
          profilesById =
          <String, Map<String, dynamic>>{};

      for (final dynamic item in response) {
        final Map<String, dynamic> profile =
            Map<String, dynamic>.from(
          item as Map,
        );

        final String id =
            profile['id']?.toString() ?? '';

        if (id.isNotEmpty) {
          profilesById[id] = profile;
        }
      }

      return messages.map(
        (message) {
          final String authorId =
              message['author_id']
                      ?.toString() ??
                  '';

          return <String, dynamic>{
            ...message,
            'author_profile':
                profilesById[authorId],
          };
        },
      ).toList();
    } catch (_) {
      return messages;
    }
  }
}
