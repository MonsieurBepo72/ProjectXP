import 'supabase_service.dart';

class PrivateMessageService {
  PrivateMessageService._();

  // ===========================================================================
  // UTILISATEUR ACTUEL
  // ===========================================================================

  static String? get currentUserId {
    return SupabaseService.currentUser?.id;
  }

  // ===========================================================================
  // CRÉER / RÉCUPÉRER UNE CONVERSATION PRIVÉE
  //
  // La fonction Supabase :
  //
  // public.get_or_create_private_conversation(uuid)
  //
  // vérifie côté serveur que les deux joueurs sont bien amis.
  // ===========================================================================

  static Future<String?> getOrCreateConversation(
    String otherUserId,
  ) async {
    final String? userId =
        currentUserId;

    final String cleanOtherUserId =
        otherUserId.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanOtherUserId.isEmpty ||
        userId == cleanOtherUserId) {
      return null;
    }

    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'get_or_create_private_conversation',
        params: {
          'p_other_user_id':
              cleanOtherUserId,
        },
      );

      final String conversationId =
          response?.toString().trim() ?? '';

      if (conversationId.isEmpty) {
        return null;
      }

      return conversationId;
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // RÉCUPÉRER LES MESSAGES D'UNE CONVERSATION
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> getMessages(
    String conversationId,
  ) async {
    final String cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('private_messages')
              .select(
                'id, conversation_id, sender_id, content, created_at',
              )
              .eq(
                'conversation_id',
                cleanConversationId,
              )
              .order(
                'created_at',
                ascending: true,
              );

      return response
          .map(
            (dynamic item) =>
                Map<String, dynamic>.from(
              item as Map,
            ),
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===========================================================================
  // TEMPS RÉEL
  //
  // Le Stream renvoie :
  // - les messages déjà présents
  // - les nouveaux messages reçus
  //
  // RLS Supabase garantit que l'utilisateur ne reçoit que les conversations
  // auxquelles il appartient.
  // ===========================================================================

  static Stream<List<Map<String, dynamic>>> messageStream(
    String conversationId,
  ) {
    final String cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(
        <Map<String, dynamic>>[],
      );
    }

    return SupabaseService.client
        .from('private_messages')
        .stream(
          primaryKey: [
            'id',
          ],
        )
        .eq(
          'conversation_id',
          cleanConversationId,
        )
        .order(
          'created_at',
          ascending: true,
        )
        .map(
          (
            List<Map<String, dynamic>> rows,
          ) =>
              _deduplicateMessages(
            rows,
          ),
        );
  }

  // ===========================================================================
  // ENVOYER UN MESSAGE
  //
  // La policy Supabase vérifie :
  // - sender_id = auth.uid()
  // - utilisateur membre de la conversation
  // - amitié toujours existante
  // ===========================================================================

  static Future<bool> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final String? userId =
        currentUserId;

    final String cleanConversationId =
        conversationId.trim();

    final String cleanContent =
        content.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanConversationId.isEmpty ||
        cleanContent.isEmpty ||
        cleanContent.length > 2000) {
      return false;
    }

    try {
      await SupabaseService.client
          .from('private_messages')
          .insert(
        {
          'conversation_id':
              cleanConversationId,
          'sender_id':
              userId,
          'content':
              cleanContent,
        },
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // SAVOIR SI UN MESSAGE EST À MOI
  // ===========================================================================

  static bool isMine(
    Map<String, dynamic> message,
  ) {
    final String? userId =
        currentUserId;

    if (userId == null ||
        userId.isEmpty) {
      return false;
    }

    return message['sender_id']
            ?.toString() ==
        userId;
  }

  // ===========================================================================
  // OUTILS
  // ===========================================================================

  static List<Map<String, dynamic>> _deduplicateMessages(
    List<Map<String, dynamic>> rows,
  ) {
    final Map<String, Map<String, dynamic>>
        messagesById =
        <String, Map<String, dynamic>>{};

    for (final Map<String, dynamic> row
        in rows) {
      final String id =
          row['id']?.toString().trim() ?? '';

      if (id.isEmpty) {
        continue;
      }

      messagesById[id] =
          Map<String, dynamic>.from(
        row,
      );
    }

    final List<Map<String, dynamic>> result =
        messagesById.values.toList();

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

        if (dateA == null &&
            dateB == null) {
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
}
