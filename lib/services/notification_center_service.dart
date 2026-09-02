import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/compagnie_join_request.dart';
import '../models/compagnie_team_invitation.dart';
import 'auth_service.dart';
import 'compagnie_invitation_storage.dart';
import 'compagnie_request_storage.dart';
import 'supabase_service.dart';

class AcceptedFriendNotification {
  const AcceptedFriendNotification({
    required this.requestId,
    required this.friendUserId,
    required this.friendName,
    required this.createdAt,
  });

  final String requestId;
  final String friendUserId;
  final String friendName;
  final DateTime createdAt;

  String get eventId =>
      'friend_request_accepted:$requestId';
}

class NotificationCenterSnapshot {
  const NotificationCenterSnapshot({
    required this.localUserId,
    required this.pendingIncomingInvitations,
    required this.pendingIncomingJoinRequests,
    required this.acceptedOutgoingInvitations,
    required this.acceptedFriendRequests,
    required this.seenInformationalEventIds,
  });

  final String localUserId;

  final List<CompagnieTeamInvitation>
      pendingIncomingInvitations;

  final List<CompagnieJoinRequest>
      pendingIncomingJoinRequests;

  final List<CompagnieTeamInvitation>
      acceptedOutgoingInvitations;

  final List<AcceptedFriendNotification>
      acceptedFriendRequests;

  final Set<String> seenInformationalEventIds;

  int get pendingActionCount =>
      pendingIncomingInvitations.length +
      pendingIncomingJoinRequests.length;

  String acceptedInvitationEventId(
    CompagnieTeamInvitation invitation,
  ) {
    return 'compagnie_invitation_accepted:${invitation.id}';
  }

  bool isAcceptedInvitationUnread(
    CompagnieTeamInvitation invitation,
  ) {
    return !seenInformationalEventIds.contains(
      acceptedInvitationEventId(invitation),
    );
  }

  bool isAcceptedFriendUnread(
    AcceptedFriendNotification notification,
  ) {
    return !seenInformationalEventIds.contains(
      notification.eventId,
    );
  }

  int get unreadInformationalCount {
    int count = 0;

    for (final CompagnieTeamInvitation invitation
        in acceptedOutgoingInvitations) {
      if (isAcceptedInvitationUnread(invitation)) {
        count++;
      }
    }

    for (final AcceptedFriendNotification notification
        in acceptedFriendRequests) {
      if (isAcceptedFriendUnread(notification)) {
        count++;
      }
    }

    return count;
  }

  int get unreadCount =>
      pendingActionCount +
      unreadInformationalCount;

  Set<String> get informationalEventIds {
    return <String>{
      for (final CompagnieTeamInvitation invitation
          in acceptedOutgoingInvitations)
        acceptedInvitationEventId(invitation),
      for (final AcceptedFriendNotification notification
          in acceptedFriendRequests)
        notification.eventId,
    };
  }
}

class NotificationCenterService {
  NotificationCenterService._();

  static const String _seenPrefix =
      'project_xp_notification_center_seen_v1_';

  static final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();

  static StreamSubscription<List<Map<String, dynamic>>>?
      _compagnieInvitationRealtimeSubscription;

  static StreamSubscription<List<Map<String, dynamic>>>?
      _friendRequestRealtimeSubscription;

  static Timer? _realtimeRefreshDebounce;
  static String _boundSocialUserId = '';

  /// Compteur partagé du Centre de notifications.
  ///
  /// Les messages privés et les demandes d'amis reçues gardent leurs propres
  /// compteurs : ce stream couvre uniquement le vrai Centre de notifications.
  static Stream<int> unreadCountStream() async* {
    await _ensureRealtimeBindings();

    yield await unreadCount();
    yield* _unreadCountController.stream;
  }

  /// Force une remise à jour après une action locale (accepter/refuser, etc.).
  static Future<void> refreshUnreadCount() async {
    await _ensureRealtimeBindings();

    final int count = await unreadCount();

    if (!_unreadCountController.isClosed) {
      _unreadCountController.add(
        count < 0 ? 0 : count,
      );
    }
  }

  static Future<void> _ensureRealtimeBindings() async {
    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (socialUserId.isEmpty) {
      return;
    }

    if (_boundSocialUserId == socialUserId &&
        _compagnieInvitationRealtimeSubscription != null) {
      return;
    }

    await _compagnieInvitationRealtimeSubscription?.cancel();
    await _friendRequestRealtimeSubscription?.cancel();

    _boundSocialUserId = socialUserId;

    // Pas de filtre volontairement : la RLS Supabase ne laisse remonter que
    // les lignes visibles par l'utilisateur. Cela permet de détecter aussi
    // bien une invitation reçue que l'acceptation d'une invitation envoyée.
    _compagnieInvitationRealtimeSubscription =
        SupabaseService.client
            .from('compagnie_team_invitations')
            .stream(
              primaryKey: <String>['id'],
            )
            .listen(
      (_) {
        _scheduleRealtimeRefresh();
      },
      onError: (_) {
        // Le chargement manuel reste disponible même si Realtime est coupé.
      },
    );

    // Les demandes d'amis reçues ne sont PAS dupliquées dans Notifications.
    // On écoute néanmoins la table pour détecter uniquement les événements
    // informatifs tels que « X a accepté ta demande », quand la ligne est
    // conservée avec le statut accepted côté Supabase.
    _friendRequestRealtimeSubscription =
        SupabaseService.client
            .from('friend_requests')
            .stream(
              primaryKey: <String>['id'],
            )
            .listen(
      (_) {
        _scheduleRealtimeRefresh();
      },
      onError: (_) {},
    );
  }

  static void _scheduleRealtimeRefresh() {
    _realtimeRefreshDebounce?.cancel();

    _realtimeRefreshDebounce = Timer(
      const Duration(milliseconds: 140),
      () {
        unawaited(
          refreshUnreadCount(),
        );
      },
    );
  }

  static Future<NotificationCenterSnapshot>
      loadSnapshot() async {
    final String localUserId =
        (await AuthService.getCurrentUserId())
                ?.trim() ??
            '';

    if (localUserId.isEmpty) {
      return const NotificationCenterSnapshot(
        localUserId: '',
        pendingIncomingInvitations:
            <CompagnieTeamInvitation>[],
        pendingIncomingJoinRequests:
            <CompagnieJoinRequest>[],
        acceptedOutgoingInvitations:
            <CompagnieTeamInvitation>[],
        acceptedFriendRequests:
            <AcceptedFriendNotification>[],
        seenInformationalEventIds:
            <String>{},
      );
    }

    final List<CompagnieTeamInvitation>
        incomingInvitations =
        await CompagnieInvitationStorage
            .incomingForUser(localUserId);

    final List<CompagnieJoinRequest>
        incomingJoinRequests =
        await CompagnieRequestStorage
            .incomingForUser(localUserId);

    final List<CompagnieTeamInvitation>
        outgoingInvitations =
        await CompagnieInvitationStorage
            .outgoingForUser(localUserId);

    final List<AcceptedFriendNotification>
        acceptedFriendRequests =
        await _loadAcceptedOutgoingFriendRequests();

    final Set<String> seenIds =
        await _loadSeenIds(localUserId);

    final List<CompagnieTeamInvitation>
        pendingInvitations =
        incomingInvitations
            .where(
              (CompagnieTeamInvitation invitation) =>
                  invitation.isPending,
            )
            .toList()
          ..sort(
            (CompagnieTeamInvitation a,
                    CompagnieTeamInvitation b) =>
                b.createdAt.compareTo(a.createdAt),
          );

    final List<CompagnieJoinRequest>
        pendingRequests =
        incomingJoinRequests
            .where(
              (CompagnieJoinRequest request) =>
                  request.isPending,
            )
            .toList()
          ..sort(
            (CompagnieJoinRequest a,
                    CompagnieJoinRequest b) =>
                b.createdAt.compareTo(a.createdAt),
          );

    final List<CompagnieTeamInvitation>
        acceptedInvitations =
        outgoingInvitations
            .where(
              (CompagnieTeamInvitation invitation) =>
                  invitation.isAccepted,
            )
            .toList()
          ..sort(
            (CompagnieTeamInvitation a,
                    CompagnieTeamInvitation b) =>
                (b.handledAt ?? b.createdAt)
                    .compareTo(
                  a.handledAt ?? a.createdAt,
                ),
          );

    return NotificationCenterSnapshot(
      localUserId: localUserId,
      pendingIncomingInvitations:
          pendingInvitations,
      pendingIncomingJoinRequests:
          pendingRequests,
      acceptedOutgoingInvitations:
          acceptedInvitations.take(30).toList(),
      acceptedFriendRequests:
          acceptedFriendRequests.take(30).toList(),
      seenInformationalEventIds: seenIds,
    );
  }

  static Future<int> unreadCount() async {
    final NotificationCenterSnapshot snapshot =
        await loadSnapshot();

    return snapshot.unreadCount;
  }

  static Future<void> markInformationalEventsSeen(
    NotificationCenterSnapshot snapshot,
  ) async {
    if (snapshot.localUserId.isEmpty ||
        snapshot.informationalEventIds.isEmpty) {
      return;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String key =
        '$_seenPrefix${snapshot.localUserId}';

    final Set<String> seen =
        (prefs.getStringList(key) ??
                const <String>[])
            .toSet();

    seen.addAll(
      snapshot.informationalEventIds,
    );

    // Garde une taille raisonnable même après une longue utilisation.
    final List<String> values =
        seen.take(500).toList();

    await prefs.setStringList(
      key,
      values,
    );
  }

  static Future<Set<String>> _loadSeenIds(
    String localUserId,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String key =
        '$_seenPrefix$localUserId';

    return (prefs.getStringList(key) ??
            const <String>[])
        .toSet();
  }

  static Future<List<AcceptedFriendNotification>>
      _loadAcceptedOutgoingFriendRequests() async {
    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (socialUserId.isEmpty) {
      return <AcceptedFriendNotification>[];
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from('friend_requests')
              .select()
              .eq(
                'sender_id',
                socialUserId,
              )
              .eq(
                'status',
                'accepted',
              )
              .order(
                'created_at',
                ascending: false,
              )
              .limit(40);

      if (response.isEmpty) {
        return <AcceptedFriendNotification>[];
      }

      final List<Map<String, dynamic>> rows =
          response
              .map(
                (dynamic item) =>
                    Map<String, dynamic>.from(
                  item as Map,
                ),
              )
              .toList();

      final Set<String> friendIds =
          rows
              .map(
                (Map<String, dynamic> row) =>
                    row['receiver_id']
                            ?.toString()
                            .trim() ??
                        '',
              )
              .where(
                (String id) => id.isNotEmpty,
              )
              .toSet();

      final Map<String, String> namesById =
          <String, String>{};

      if (friendIds.isNotEmpty) {
        final List<dynamic> profiles =
            await SupabaseService.client
                .from('tavern_profiles')
                .select(
                  'id, display_name',
                )
                .inFilter(
                  'id',
                  friendIds.toList(),
                );

        for (final dynamic item in profiles) {
          final Map<String, dynamic> profile =
              Map<String, dynamic>.from(
            item as Map,
          );

          final String id =
              profile['id']?.toString().trim() ?? '';

          final String name =
              profile['display_name']
                      ?.toString()
                      .trim() ??
                  '';

          if (id.isNotEmpty && name.isNotEmpty) {
            namesById[id] = name;
          }
        }
      }

      final List<AcceptedFriendNotification> result =
          <AcceptedFriendNotification>[];

      for (final Map<String, dynamic> row in rows) {
        final String requestId =
            row['id']?.toString().trim() ?? '';

        final String friendId =
            row['receiver_id']
                    ?.toString()
                    .trim() ??
                '';

        if (requestId.isEmpty || friendId.isEmpty) {
          continue;
        }

        final DateTime createdAt =
            DateTime.tryParse(
                  row['updated_at']?.toString() ?? '',
                )?.toLocal() ??
                DateTime.tryParse(
                  row['handled_at']?.toString() ?? '',
                )?.toLocal() ??
                DateTime.tryParse(
                  row['created_at']?.toString() ?? '',
                )?.toLocal() ??
                DateTime.now();

        result.add(
          AcceptedFriendNotification(
            requestId: requestId,
            friendUserId: friendId,
            friendName:
                namesById[friendId] ?? 'Un joueur',
            createdAt: createdAt,
          ),
        );
      }

      result.sort(
        (AcceptedFriendNotification a,
                AcceptedFriendNotification b) =>
            b.createdAt.compareTo(a.createdAt),
      );

      return result;
    } catch (_) {
      // Si les anciennes demandes acceptées ne sont pas conservées dans la
      // base, cette catégorie reste simplement vide. Aucun faux événement
      // n'est inventé.
      return <AcceptedFriendNotification>[];
    }
  }
}
