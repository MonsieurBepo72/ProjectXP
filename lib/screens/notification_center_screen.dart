import 'dart:async';

import 'package:flutter/material.dart';

import '../models/compagnie_join_request.dart';
import '../models/compagnie_team_invitation.dart';
import '../services/compagnie_invitation_storage.dart';
import '../services/compagnie_request_storage.dart';
import '../services/notification_center_service.dart';
import 'public_profile_screen.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
  });

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends State<NotificationCenterScreen> {
  NotificationCenterSnapshot? _snapshot;

  bool _loading = true;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    final NotificationCenterSnapshot snapshot =
        await NotificationCenterService.loadSnapshot();

    if (!mounted) {
      return;
    }

    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });

    // Les éléments informatifs deviennent lus une fois réellement affichés
    // dans le centre. Les actions Compagnie restent, elles, non lues tant
    // qu'elles ne sont pas traitées.
    unawaited(
      _markVisibleInformationalEventsSeen(
        snapshot,
      ),
    );
  }

  Future<void> _markVisibleInformationalEventsSeen(
    NotificationCenterSnapshot snapshot,
  ) async {
    await NotificationCenterService
        .markInformationalEventsSeen(snapshot);

    await NotificationCenterService
        .refreshUnreadCount();
  }

  Future<void> _acceptInvitation(
    CompagnieTeamInvitation invitation,
  ) async {
    final NotificationCenterSnapshot? snapshot =
        _snapshot;

    if (_actionInProgress ||
        snapshot == null ||
        !invitation.isPending) {
      return;
    }

    final bool? confirmed = await _confirm(
      title: 'Rejoindre la Compagnie',
      message:
          'Accepter l’invitation et rejoindre ${invitation.teamName} ?',
      confirmLabel: 'REJOINDRE',
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _actionInProgress = true;
    });

    final bool success =
        await CompagnieInvitationStorage
            .acceptInvitation(
      invitationId: invitation.id,
      inviteeId: snapshot.localUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible de rejoindre cette Compagnie. Elle est peut-être complète ou n’existe plus.',
      );
      return;
    }

    _showMessage(
      'Tu as rejoint ${invitation.teamName}.',
    );

    await _load();
  }

  Future<void> _rejectInvitation(
    CompagnieTeamInvitation invitation,
  ) async {
    final NotificationCenterSnapshot? snapshot =
        _snapshot;

    if (_actionInProgress ||
        snapshot == null ||
        !invitation.isPending) {
      return;
    }

    final bool? confirmed = await _confirm(
      title: 'Refuser l’invitation',
      message:
          'Refuser l’invitation de ${invitation.teamName} ?',
      confirmLabel: 'REFUSER',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _actionInProgress = true;
    });

    final bool success =
        await CompagnieInvitationStorage
            .rejectInvitation(
      invitationId: invitation.id,
      inviteeId: snapshot.localUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible de refuser cette invitation.',
      );
      return;
    }

    _showMessage('Invitation refusée.');
    await _load();
  }

  Future<void> _acceptJoinRequest(
    CompagnieJoinRequest request,
  ) async {
    final NotificationCenterSnapshot? snapshot =
        _snapshot;

    if (_actionInProgress ||
        snapshot == null ||
        !request.isPending) {
      return;
    }

    final bool? confirmed = await _confirm(
      title: 'Accepter la demande',
      message:
          'Ajouter ${request.requesterName} à ${request.teamName} ?',
      confirmLabel: 'ACCEPTER',
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _actionInProgress = true;
    });

    final bool success =
        await CompagnieRequestStorage
            .acceptRequest(
      requestId: request.id,
      handlerUserId: snapshot.localUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible d’accepter cette demande. Vérifie que la Compagnie existe toujours et qu’elle n’est pas complète.',
      );
      return;
    }

    _showMessage(
      '${request.requesterName} a rejoint ${request.teamName}.',
    );

    await _load();
  }

  Future<void> _rejectJoinRequest(
    CompagnieJoinRequest request,
  ) async {
    final NotificationCenterSnapshot? snapshot =
        _snapshot;

    if (_actionInProgress ||
        snapshot == null ||
        !request.isPending) {
      return;
    }

    final bool? confirmed = await _confirm(
      title: 'Refuser la demande',
      message:
          'Refuser la demande de ${request.requesterName} ?',
      confirmLabel: 'REFUSER',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _actionInProgress = true;
    });

    final bool success =
        await CompagnieRequestStorage
            .rejectRequest(
      requestId: request.id,
      handlerUserId: snapshot.localUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible de refuser cette demande.',
      );
      return;
    }

    _showMessage('Demande refusée.');
    await _load();
  }

  Future<void> _openFriendProfile(
    AcceptedFriendNotification notification,
  ) async {
    if (notification.friendUserId.isEmpty) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PublicProfileScreen(
          userId: notification.friendUserId,
        ),
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'RETOUR',
                style: TextStyle(
                  color: Colors.white54,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: Text(
                confirmLabel,
                style: TextStyle(
                  color: destructive
                      ? Colors.redAccent
                      : const Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  String _formatTime(
    DateTime date,
  ) {
    final DateTime now = DateTime.now();
    final DateTime local = date.toLocal();

    final bool sameDay =
        now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;

    final DateTime yesterday =
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(
          const Duration(days: 1),
        );

    final bool isYesterday =
        yesterday.year == local.year &&
        yesterday.month == local.month &&
        yesterday.day == local.day;

    final String hour =
        local.hour.toString().padLeft(2, '0');
    final String minute =
        local.minute.toString().padLeft(2, '0');

    if (sameDay) {
      return 'Aujourd’hui • $hour:$minute';
    }

    if (isYesterday) {
      return 'Hier • $hour:$minute';
    }

    final String day =
        local.day.toString().padLeft(2, '0');
    final String month =
        local.month.toString().padLeft(2, '0');

    return '$day/$month/${local.year} • $hour:$minute';
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff21150e),
        foregroundColor:
            const Color(0xffffc857),
        centerTitle: true,
        title: const Text(
          'NOTIFICATIONS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xffffc857),
                ),
              )
            : RefreshIndicator(
                color:
                    const Color(0xffffc857),
                backgroundColor:
                    const Color(0xff21150e),
                onRefresh: _load,
                child: _buildContent(),
              ),
      ),
    );
  }

  Widget _buildContent() {
    final NotificationCenterSnapshot snapshot =
        _snapshot ??
            const NotificationCenterSnapshot(
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

    final bool hasActions =
        snapshot.pendingActionCount > 0;

    final bool hasRecentActivity =
        snapshot.acceptedOutgoingInvitations.isNotEmpty ||
        snapshot.acceptedFriendRequests.isNotEmpty;

    if (!hasActions && !hasRecentActivity) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.fromLTRB(
          28,
          70,
          28,
          32,
        ),
        children: const <Widget>[
          Icon(
            Icons.notifications_none_rounded,
            color: Color(0xffffc857),
            size: 68,
          ),
          SizedBox(height: 18),
          Text(
            'Tout est calme',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 9),
          Text(
            'Les événements importants de Project XP apparaîtront ici.\nLes messages et demandes d’amis gardent leur propre espace.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              height: 1.45,
            ),
          ),
        ],
      );
    }

    final List<_RecentNotificationItem> recent =
        <_RecentNotificationItem>[
      for (final CompagnieTeamInvitation invitation
          in snapshot.acceptedOutgoingInvitations)
        _RecentNotificationItem(
          type: _RecentNotificationType.compagnieAccepted,
          date: invitation.handledAt ?? invitation.createdAt,
          unread:
              snapshot.isAcceptedInvitationUnread(invitation),
          title: 'Invitation acceptée',
          body:
              '${invitation.inviteeName} a rejoint ${invitation.teamName}.',
          friendNotification: null,
        ),
      for (final AcceptedFriendNotification notification
          in snapshot.acceptedFriendRequests)
        _RecentNotificationItem(
          type: _RecentNotificationType.friendAccepted,
          date: notification.createdAt,
          unread:
              snapshot.isAcceptedFriendUnread(notification),
          title: 'Nouvel ami',
          body:
              '${notification.friendName} a accepté ta demande d’ami.',
          friendNotification: notification,
        ),
    ]
      ..sort(
        (_RecentNotificationItem a,
                _RecentNotificationItem b) =>
            b.date.compareTo(a.date),
      );

    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        16,
        20,
        16,
        34,
      ),
      children: <Widget>[
        const _NotificationHeader(),

        if (hasActions) ...<Widget>[
          const SizedBox(height: 24),
          const _SectionTitle(
            icon: Icons.bolt_rounded,
            title: 'À TRAITER',
          ),
          const SizedBox(height: 10),

          ...snapshot.pendingIncomingInvitations.map(
            (CompagnieTeamInvitation invitation) =>
                _ActionNotificationCard(
              icon: Icons.shield_outlined,
              title: 'Invitation Compagnie',
              body:
                  '${invitation.inviterName} t’invite à rejoindre ${invitation.teamName}.',
              timeLabel:
                  _formatTime(invitation.createdAt),
              primaryLabel: 'REJOINDRE',
              secondaryLabel: 'REFUSER',
              busy: _actionInProgress,
              onPrimary: () {
                _acceptInvitation(invitation);
              },
              onSecondary: () {
                _rejectInvitation(invitation);
              },
            ),
          ),

          ...snapshot.pendingIncomingJoinRequests.map(
            (CompagnieJoinRequest request) =>
                _ActionNotificationCard(
              icon: Icons.group_add_outlined,
              title: 'Demande Compagnie',
              body:
                  '${request.requesterName} souhaite rejoindre ${request.teamName}.',
              timeLabel:
                  _formatTime(request.createdAt),
              primaryLabel: 'ACCEPTER',
              secondaryLabel: 'REFUSER',
              busy: _actionInProgress,
              onPrimary: () {
                _acceptJoinRequest(request);
              },
              onSecondary: () {
                _rejectJoinRequest(request);
              },
            ),
          ),
        ],

        if (recent.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          const _SectionTitle(
            icon: Icons.history_rounded,
            title: 'ACTIVITÉ RÉCENTE',
          ),
          const SizedBox(height: 10),

          ...recent.map(
            (_RecentNotificationItem item) {
              final bool isFriend =
                  item.type ==
                      _RecentNotificationType.friendAccepted;

              return _InfoNotificationCard(
                icon: isFriend
                    ? Icons.favorite_rounded
                    : Icons.shield_rounded,
                title: item.title,
                body: item.body,
                timeLabel: _formatTime(item.date),
                unread: item.unread,
                onTap: item.friendNotification == null
                    ? null
                    : () {
                        _openFriendProfile(
                          item.friendNotification!,
                        );
                      },
              );
            },
          ),
        ],
      ],
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        18,
        18,
        18,
        17,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff21150e),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xffffc857)
              .withValues(alpha: 0.28),
        ),
      ),
      child: const Column(
        children: <Widget>[
          Icon(
            Icons.notifications_active_outlined,
            color: Color(0xffffc857),
            size: 32,
          ),
          SizedBox(height: 9),
          Text(
            'Centre de notifications',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Ici : Compagnie et événements importants.\nMessages et demandes d’amis restent dans leurs applis dédiées.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      children: <Widget>[
        Icon(
          icon,
          color: const Color(0xffffc857),
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xffffc857),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _ActionNotificationCard extends StatelessWidget {
  const _ActionNotificationCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.busy,
    required this.onPrimary,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String timeLabel;
  final String primaryLabel;
  final String secondaryLabel;
  final bool busy;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff2b1a12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xffffc857)
              .withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xff6b4226),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xffffc857),
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : onSecondary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(
                      color: Colors.white24,
                    ),
                  ),
                  child: Text(
                    secondaryLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy
                      ? null
                      : onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xffffc857),
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    primaryLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoNotificationCard extends StatelessWidget {
  const _InfoNotificationCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.unread,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String timeLabel;
  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xff241710),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: unread
              ? const Color(0xffffc857)
                  .withValues(alpha: 0.40)
              : Colors.white12,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      width: 39,
                      height: 39,
                      decoration: BoxDecoration(
                        color: const Color(0xff3a2518),
                        borderRadius:
                            BorderRadius.circular(11),
                      ),
                      child: Icon(
                        icon,
                        color:
                            const Color(0xffffc857),
                        size: 21,
                      ),
                    ),
                    if (unread)
                      const Positioned(
                        right: -2,
                        top: -2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(
                            width: 9,
                            height: 9,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white30,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _RecentNotificationType {
  compagnieAccepted,
  friendAccepted,
}

class _RecentNotificationItem {
  const _RecentNotificationItem({
    required this.type,
    required this.date,
    required this.unread,
    required this.title,
    required this.body,
    required this.friendNotification,
  });

  final _RecentNotificationType type;
  final DateTime date;
  final bool unread;
  final String title;
  final String body;
  final AcceptedFriendNotification? friendNotification;
}
