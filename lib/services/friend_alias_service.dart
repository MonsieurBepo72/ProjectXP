import 'supabase_service.dart';

class FriendAliasService {
  FriendAliasService._();

  static String? get currentUserId {
    return SupabaseService.currentUser?.id;
  }

  static Future<String?> getAlias(
    String friendId,
  ) async {
    final String? userId = currentUserId;
    final String cleanFriendId = friendId.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanFriendId.isEmpty ||
        userId == cleanFriendId) {
      return null;
    }

    try {
      final Map<String, dynamic>? response =
          await SupabaseService.client
              .from('friend_aliases')
              .select('nickname')
              .eq('owner_id', userId)
              .eq('friend_id', cleanFriendId)
              .maybeSingle();

      final String nickname =
          response?['nickname']?.toString().trim() ?? '';

      return nickname.isEmpty ? null : nickname;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setAlias({
    required String friendId,
    required String nickname,
  }) async {
    final String? userId = currentUserId;
    final String cleanFriendId = friendId.trim();
    final String cleanNickname = nickname.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanFriendId.isEmpty ||
        userId == cleanFriendId ||
        cleanNickname.isEmpty ||
        cleanNickname.length > 30) {
      return false;
    }

    try {
      await SupabaseService.client
          .from('friend_aliases')
          .upsert(
        <String, dynamic>{
          'owner_id': userId,
          'friend_id': cleanFriendId,
          'nickname': cleanNickname,
          'updated_at': DateTime.now()
              .toUtc()
              .toIso8601String(),
        },
        onConflict: 'owner_id,friend_id',
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeAlias(
    String friendId,
  ) async {
    final String? userId = currentUserId;
    final String cleanFriendId = friendId.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanFriendId.isEmpty ||
        userId == cleanFriendId) {
      return false;
    }

    try {
      await SupabaseService.client
          .from('friend_aliases')
          .delete()
          .eq('owner_id', userId)
          .eq('friend_id', cleanFriendId);

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>>
      getAliases() async {
    final String? userId = currentUserId;

    if (userId == null || userId.isEmpty) {
      return <String, String>{};
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('friend_aliases')
              .select('friend_id, nickname')
              .eq('owner_id', userId);

      final Map<String, String> aliases =
          <String, String>{};

      for (final dynamic item in response) {
        final Map<String, dynamic> row =
            Map<String, dynamic>.from(item as Map);

        final String friendId =
            row['friend_id']?.toString().trim() ?? '';

        final String nickname =
            row['nickname']?.toString().trim() ?? '';

        if (friendId.isNotEmpty &&
            nickname.isNotEmpty) {
          aliases[friendId] = nickname;
        }
      }

      return aliases;
    } catch (_) {
      return <String, String>{};
    }
  }

  static String resolveDisplayName({
    required String publicDisplayName,
    String? alias,
  }) {
    final String cleanAlias = alias?.trim() ?? '';

    if (cleanAlias.isNotEmpty) {
      return cleanAlias;
    }

    final String cleanPublicName =
        publicDisplayName.trim();

    if (cleanPublicName.isNotEmpty) {
      return cleanPublicName;
    }

    return 'Aventurier';
  }
}
