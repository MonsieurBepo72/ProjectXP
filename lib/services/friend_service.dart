import 'supabase_service.dart';

enum FriendRelationshipState {
  self,
  none,
  outgoingPending,
  incomingPending,
  friends,
}

enum FriendRequestSendResult {
  sent,
  alreadyPending,
  incomingPending,
  alreadyFriends,
  invalidUser,
  error,
}

enum FriendRequestResponseResult {
  accepted,
  declined,
  error,
}

class FriendService {
  FriendService._();

  // ===========================================================================
  // UTILISATEUR ACTUEL
  // ===========================================================================

  static String? get currentUserId {
    return SupabaseService.currentUser?.id;
  }

  // ===========================================================================
  // ENVOYER UNE DEMANDE D'AMI
  //
  // La logique sensible est gérée côté Supabase par :
  //
  // public.send_friend_request(uuid)
  //
  // Résultats possibles :
  // - sent
  // - already_pending
  // - incoming_pending
  // - already_friends
  // ===========================================================================

  static Future<FriendRequestSendResult> sendFriendRequest(
    String receiverId,
  ) async {
    final String? senderId =
        currentUserId;

    final String cleanReceiverId =
        receiverId.trim();

    if (senderId == null ||
        senderId.isEmpty ||
        cleanReceiverId.isEmpty ||
        senderId == cleanReceiverId) {
      return FriendRequestSendResult.invalidUser;
    }

    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'send_friend_request',
        params: {
          'p_receiver_id':
              cleanReceiverId,
        },
      );

      final String result =
          response?.toString().trim() ?? '';

      switch (result) {
        case 'sent':
          return FriendRequestSendResult.sent;

        case 'already_pending':
          return FriendRequestSendResult
              .alreadyPending;

        case 'incoming_pending':
          return FriendRequestSendResult
              .incomingPending;

        case 'already_friends':
          return FriendRequestSendResult
              .alreadyFriends;

        default:
          return FriendRequestSendResult.error;
      }
    } catch (_) {
      return FriendRequestSendResult.error;
    }
  }

  // ===========================================================================
  // ÉTAT DE LA RELATION AVEC UN JOUEUR
  // ===========================================================================

  static Future<FriendRelationshipState>
      getRelationshipState(
    String otherUserId,
  ) async {
    final String? userId =
        currentUserId;

    final String cleanOtherUserId =
        otherUserId.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanOtherUserId.isEmpty) {
      return FriendRelationshipState.none;
    }

    if (userId == cleanOtherUserId) {
      return FriendRelationshipState.self;
    }

    try {
      // -----------------------------------------------------------------------
      // AMITIÉ EXISTANTE
      // -----------------------------------------------------------------------

      final Map<String, dynamic>? friendship =
          await SupabaseService.client
              .from('friendships')
              .select(
                'id',
              )
              .or(
                'and(user_a.eq.$userId,user_b.eq.$cleanOtherUserId),'
                'and(user_a.eq.$cleanOtherUserId,user_b.eq.$userId)',
              )
              .maybeSingle();

      if (friendship != null) {
        return FriendRelationshipState.friends;
      }

      // -----------------------------------------------------------------------
      // DEMANDE ENVOYÉE PAR NOUS
      // -----------------------------------------------------------------------

      final Map<String, dynamic>? outgoing =
          await SupabaseService.client
              .from('friend_requests')
              .select(
                'id',
              )
              .eq(
                'sender_id',
                userId,
              )
              .eq(
                'receiver_id',
                cleanOtherUserId,
              )
              .eq(
                'status',
                'pending',
              )
              .maybeSingle();

      if (outgoing != null) {
        return FriendRelationshipState
            .outgoingPending;
      }

      // -----------------------------------------------------------------------
      // DEMANDE REÇUE DE L'AUTRE JOUEUR
      // -----------------------------------------------------------------------

      final Map<String, dynamic>? incoming =
          await SupabaseService.client
              .from('friend_requests')
              .select(
                'id',
              )
              .eq(
                'sender_id',
                cleanOtherUserId,
              )
              .eq(
                'receiver_id',
                userId,
              )
              .eq(
                'status',
                'pending',
              )
              .maybeSingle();

      if (incoming != null) {
        return FriendRelationshipState
            .incomingPending;
      }

      return FriendRelationshipState.none;
    } catch (_) {
      return FriendRelationshipState.none;
    }
  }

  // ===========================================================================
  // DEMANDES REÇUES
  //
  // Chaque ligne contient également :
  //
  // sender_profile
  //
  // avec :
  // - display_name
  // - avatar_url
  // - avatar_data
  // - public_profile_data
  // ===========================================================================

  static Future<List<Map<String, dynamic>>>
      getIncomingRequests() async {
    final String? userId =
        currentUserId;

    if (userId == null ||
        userId.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('friend_requests')
              .select()
              .eq(
                'receiver_id',
                userId,
              )
              .eq(
                'status',
                'pending',
              )
              .order(
                'created_at',
                ascending: false,
              );

      final List<Map<String, dynamic>> requests =
          response
              .map(
                (item) =>
                    Map<String, dynamic>.from(
                  item as Map,
                ),
              )
              .toList();

      if (requests.isEmpty) {
        return requests;
      }

      final Set<String> senderIds =
          requests
              .map(
                (request) =>
                    request['sender_id']
                        ?.toString()
                        .trim() ??
                    '',
              )
              .where(
                (id) => id.isNotEmpty,
              )
              .toSet();

      if (senderIds.isEmpty) {
        return requests;
      }

      final List<dynamic> profilesResponse =
          await SupabaseService.client
              .from('tavern_profiles')
              .select(
                'id, display_name, avatar_url, avatar_data, public_profile_data',
              )
              .inFilter(
                'id',
                senderIds.toList(),
              );

      final Map<String, Map<String, dynamic>>
          profilesById =
          <String, Map<String, dynamic>>{};

      for (final dynamic item
          in profilesResponse) {
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

      return requests.map(
        (request) {
          final String senderId =
              request['sender_id']
                      ?.toString() ??
                  '';

          return <String, dynamic>{
            ...request,
            'sender_profile':
                profilesById[senderId],
          };
        },
      ).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===========================================================================
  // ACCEPTER / REFUSER UNE DEMANDE
  //
  // La fonction Supabase vérifie que l'utilisateur connecté est bien le
  // destinataire de la demande.
  // ===========================================================================

  static Future<FriendRequestResponseResult>
      respondToFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    final String cleanRequestId =
        requestId.trim();

    if (cleanRequestId.isEmpty) {
      return FriendRequestResponseResult.error;
    }

    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'respond_to_friend_request',
        params: {
          'p_request_id':
              cleanRequestId,
          'p_accept':
              accept,
        },
      );

      final String result =
          response?.toString().trim() ?? '';

      if (result == 'accepted') {
        return FriendRequestResponseResult.accepted;
      }

      if (result == 'declined') {
        return FriendRequestResponseResult.declined;
      }

      return FriendRequestResponseResult.error;
    } catch (_) {
      return FriendRequestResponseResult.error;
    }
  }

  // ===========================================================================
  // ANNULER UNE DEMANDE ENVOYÉE
  // ===========================================================================

  static Future<bool> cancelOutgoingRequest(
    String receiverId,
  ) async {
    final String? userId =
        currentUserId;

    final String cleanReceiverId =
        receiverId.trim();

    if (userId == null ||
        userId.isEmpty ||
        cleanReceiverId.isEmpty) {
      return false;
    }

    try {
      await SupabaseService.client
          .from('friend_requests')
          .delete()
          .eq(
            'sender_id',
            userId,
          )
          .eq(
            'receiver_id',
            cleanReceiverId,
          )
          .eq(
            'status',
            'pending',
          );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // LISTE DES AMIS
  //
  // Retourne les amitiés de l'utilisateur courant avec :
  //
  // friend_id
  // friend_profile
  //
  // friend_profile contient :
  // - display_name
  // - avatar_url
  // - avatar_data
  // - public_profile_data
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> getFriends() async {
    final String? userId =
        currentUserId;

    if (userId == null ||
        userId.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('friendships')
              .select()
              .or(
                'user_a.eq.$userId,user_b.eq.$userId',
              )
              .order(
                'created_at',
                ascending: false,
              );

      final List<Map<String, dynamic>> friendships =
          response
              .map(
                (item) =>
                    Map<String, dynamic>.from(
                  item as Map,
                ),
              )
              .toList();

      if (friendships.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final Set<String> friendIds =
          <String>{};

      for (final Map<String, dynamic> friendship
          in friendships) {
        final String userA =
            friendship['user_a']
                    ?.toString()
                    .trim() ??
                '';

        final String userB =
            friendship['user_b']
                    ?.toString()
                    .trim() ??
                '';

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

      if (friendIds.isEmpty) {
        return <Map<String, dynamic>>[];
      }

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

      final Map<String, Map<String, dynamic>>
          profilesById =
          <String, Map<String, dynamic>>{};

      for (final dynamic item
          in profilesResponse) {
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

      final List<Map<String, dynamic>> result =
          <Map<String, dynamic>>[];

      for (final Map<String, dynamic> friendship
          in friendships) {
        final String userA =
            friendship['user_a']
                    ?.toString()
                    .trim() ??
                '';

        final String userB =
            friendship['user_b']
                    ?.toString()
                    .trim() ??
                '';

        final String friendId =
            userA == userId
                ? userB
                : userA;

        if (friendId.isEmpty) {
          continue;
        }

        result.add(
          <String, dynamic>{
            ...friendship,
            'friend_id':
                friendId,
            'friend_profile':
                profilesById[friendId],
          },
        );
      }

      return result;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  // ===========================================================================
  // SUPPRIMER UNE AMITIÉ
  // ===========================================================================

  static Future<bool> removeFriend(
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
      return false;
    }

    try {
      await SupabaseService.client
          .from('friendships')
          .delete()
          .or(
            'and(user_a.eq.$userId,user_b.eq.$cleanOtherUserId),'
            'and(user_a.eq.$cleanOtherUserId,user_b.eq.$userId)',
          );

      return true;
    } catch (_) {
      return false;
    }
  }
}
