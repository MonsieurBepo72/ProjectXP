import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_moderation_service.dart';
import 'project_xp_message_send_result.dart';
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
                'id, conversation_id, sender_id, content, created_at, read_at',
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
  // TEMPS RÉEL D'UNE CONVERSATION
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
  // ===========================================================================

  static Future<ProjectXpMessageSendResult> sendMessage({
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
      return ProjectXpMessageSendResult.failure;
    }

    // Premier bouclier local pour les termes critiques déjà connus.
    final ContentModerationResult localModeration =
        ContentModerationService.checkTextImmediate(
      cleanContent,
    );

    if (localModeration.blocked) {
      return ProjectXpMessageSendResult.denied;
    }

    try {
      final response =
          await SupabaseService.client.functions.invoke(
        'send-moderated-message',
        body: <String, dynamic>{
          'surface': 'private',
          'conversation_id':
              cleanConversationId,
          'content':
              cleanContent,
        },
      );

      final dynamic rawData =
          response.data;

      final Map<String, dynamic> data =
          rawData is Map
              ? Map<String, dynamic>.from(
                  rawData,
                )
              : <String, dynamic>{};

      final String status =
          data['status']
                  ?.toString()
                  .trim() ??
              '';

      switch (status) {
        case 'sent':
          return ProjectXpMessageSendResult.success;

        case 'blocked':
          return ProjectXpMessageSendResult.denied;

        case 'rate_limited':
          return ProjectXpMessageSendResult.rateLimit;

        default:
          return ProjectXpMessageSendResult.failure;
      }
    } on FunctionException catch (error) {
      if (error.status == 429) {
        return ProjectXpMessageSendResult.rateLimit;
      }

      return ProjectXpMessageSendResult.failure;
    } catch (_) {
      return ProjectXpMessageSendResult.failure;
    }
  }

  // ===========================================================================
  // MARQUER UNE CONVERSATION COMME LUE
  //
  // Le RPC Supabase ne marque que les messages reçus :
  // sender_id != auth.uid()
  // ===========================================================================

  static Future<bool> markConversationRead(
    String conversationId,
  ) async {
    final String cleanConversationId =
        conversationId.trim();

    if (cleanConversationId.isEmpty) {
      return false;
    }

    try {
      await SupabaseService.client.rpc(
        'mark_private_conversation_read',
        params: {
          'p_conversation_id':
              cleanConversationId,
        },
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // NOMBRE TOTAL DE MESSAGES PRIVÉS NON LUS
  // ===========================================================================

  static Future<int> getUnreadCount() async {
    final String? userId =
        currentUserId;

    if (userId == null ||
        userId.isEmpty) {
      return 0;
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('private_messages')
              .select(
                'id, sender_id, read_at',
              );

      int count = 0;

      for (final dynamic item in response) {
        final Map<String, dynamic> message =
            Map<String, dynamic>.from(
          item as Map,
        );

        final String senderId =
            message['sender_id']
                    ?.toString()
                    .trim() ??
                '';

        final dynamic readAt =
            message['read_at'];

        if (senderId.isNotEmpty &&
            senderId != userId &&
            readAt == null) {
          count++;
        }
      }

      return count;
    } catch (_) {
      return 0;
    }
  }

  // ===========================================================================
  // BADGE TEMPS RÉEL DES MESSAGES NON LUS
  //
  // RLS limite automatiquement le flux aux conversations accessibles au joueur.
  // Le stream contient l'état courant puis réagit aux nouveaux messages et aux
  // changements de read_at.
  // ===========================================================================

  static Stream<int> unreadCountStream() {
    final String? userId =
        currentUserId;

    if (userId == null ||
        userId.isEmpty) {
      return Stream<int>.value(
        0,
      );
    }

    return SupabaseService.client
        .from('private_messages')
        .stream(
          primaryKey: [
            'id',
          ],
        )
        .map(
          (
            List<Map<String, dynamic>> rows,
          ) {
            int count = 0;

            for (final Map<String, dynamic> row
                in rows) {
              final String senderId =
                  row['sender_id']
                          ?.toString()
                          .trim() ??
                      '';

              if (senderId.isNotEmpty &&
                  senderId != userId &&
                  row['read_at'] == null) {
                count++;
              }
            }

            return count;
          },
        );
  }

  // ===========================================================================
  // BOÎTE DE RÉCEPTION
  //
  // Retourne une ligne par conversation avec :
  //
  // conversation_id
  // friend_id
  // friend_profile
  // last_message
  // last_message_at
  // last_sender_id
  // unread_count
  //
  // Les conversations sont triées par activité la plus récente.
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> getInbox() async {
    final String? userId =
        currentUserId;

    if (userId == null ||
        userId.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final List<dynamic> conversationsResponse =
          await SupabaseService.client
              .from('private_conversations')
              .select(
                'id, user_a, user_b, created_at',
              )
              .or(
                'user_a.eq.$userId,user_b.eq.$userId',
              )
              .order(
                'created_at',
                ascending: false,
              );

      final List<Map<String, dynamic>> conversations =
          conversationsResponse
              .map(
                (dynamic item) =>
                    Map<String, dynamic>.from(
                  item as Map,
                ),
              )
              .toList();

      if (conversations.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final Set<String> friendIds =
          <String>{};

      final List<String> conversationIds =
          <String>[];

      for (final Map<String, dynamic> conversation
          in conversations) {
        final String conversationId =
            conversation['id']
                    ?.toString()
                    .trim() ??
                '';

        final String userA =
            conversation['user_a']
                    ?.toString()
                    .trim() ??
                '';

        final String userB =
            conversation['user_b']
                    ?.toString()
                    .trim() ??
                '';

        if (conversationId.isNotEmpty) {
          conversationIds.add(
            conversationId,
          );
        }

        final String friendId =
            userA == userId
                ? userB
                : userA;

        if (friendId.isNotEmpty) {
          friendIds.add(
            friendId,
          );
        }
      }

      final Map<String, Map<String, dynamic>>
          profilesById =
          <String, Map<String, dynamic>>{};

      if (friendIds.isNotEmpty) {
        final List<dynamic> profilesResponse =
            await SupabaseService.client
                .from('tavern_profiles')
                .select(
                  'id, display_name, avatar_url, avatar_data, public_profile_data',
                )
                .inFilter(
                  'id',
                  friendIds.toList(),
                );

        for (final dynamic item
            in profilesResponse) {
          final Map<String, dynamic> profile =
              Map<String, dynamic>.from(
            item as Map,
          );

          final String profileId =
              profile['id']
                      ?.toString()
                      .trim() ??
                  '';

          if (profileId.isNotEmpty) {
            profilesById[profileId] =
                profile;
          }
        }
      }

      final Map<String, List<Map<String, dynamic>>>
          messagesByConversation =
          <String, List<Map<String, dynamic>>>{};

      if (conversationIds.isNotEmpty) {
        final List<dynamic> messagesResponse =
            await SupabaseService.client
                .from('private_messages')
                .select(
                  'id, conversation_id, sender_id, content, created_at, read_at',
                )
                .inFilter(
                  'conversation_id',
                  conversationIds,
                )
                .order(
                  'created_at',
                  ascending: false,
                );

        for (final dynamic item
            in messagesResponse) {
          final Map<String, dynamic> message =
              Map<String, dynamic>.from(
            item as Map,
          );

          final String conversationId =
              message['conversation_id']
                      ?.toString()
                      .trim() ??
                  '';

          if (conversationId.isEmpty) {
            continue;
          }

          messagesByConversation
              .putIfAbsent(
                conversationId,
                () =>
                    <Map<String, dynamic>>[],
              )
              .add(
                message,
              );
        }
      }

      final List<Map<String, dynamic>> result =
          <Map<String, dynamic>>[];

      for (final Map<String, dynamic> conversation
          in conversations) {
        final String conversationId =
            conversation['id']
                    ?.toString()
                    .trim() ??
                '';

        final String userA =
            conversation['user_a']
                    ?.toString()
                    .trim() ??
                '';

        final String userB =
            conversation['user_b']
                    ?.toString()
                    .trim() ??
                '';

        final String friendId =
            userA == userId
                ? userB
                : userA;

        final List<Map<String, dynamic>> messages =
            messagesByConversation[
                    conversationId] ??
                <Map<String, dynamic>>[];

        Map<String, dynamic>? lastMessage;

        if (messages.isNotEmpty) {
          lastMessage =
              messages.first;
        }

        int unreadCount = 0;

        for (final Map<String, dynamic> message
            in messages) {
          final String senderId =
              message['sender_id']
                      ?.toString()
                      .trim() ??
                  '';

          if (senderId.isNotEmpty &&
              senderId != userId &&
              message['read_at'] == null) {
            unreadCount++;
          }
        }

        result.add(
          <String, dynamic>{
            ...conversation,
            'conversation_id':
                conversationId,
            'friend_id':
                friendId,
            'friend_profile':
                profilesById[friendId],
            'last_message':
                lastMessage?['content'],
            'last_message_at':
                lastMessage?['created_at'] ??
                    conversation['created_at'],
            'last_sender_id':
                lastMessage?['sender_id'],
            'unread_count':
                unreadCount,
          },
        );
      }

      result.sort(
        (
          Map<String, dynamic> a,
          Map<String, dynamic> b,
        ) {
          final DateTime? dateA =
              DateTime.tryParse(
            a['last_message_at']
                    ?.toString() ??
                '',
          );

          final DateTime? dateB =
              DateTime.tryParse(
            b['last_message_at']
                    ?.toString() ??
                '',
          );

          if (dateA == null &&
              dateB == null) {
            return 0;
          }

          if (dateA == null) {
            return 1;
          }

          if (dateB == null) {
            return -1;
          }

          return dateB.compareTo(
            dateA,
          );
        },
      );

      return result;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===========================================================================
  // ACTIVITÉ TEMPS RÉEL DE LA BOÎTE DE RÉCEPTION
  //
  // Sert à demander un rafraîchissement de la liste des conversations dès
  // qu'un message privé est ajouté ou que son état de lecture change.
  // ===========================================================================

  static Stream<List<Map<String, dynamic>>> inboxActivityStream() {
    return SupabaseService.client
        .from('private_messages')
        .stream(
          primaryKey: [
            'id',
          ],
        );
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
