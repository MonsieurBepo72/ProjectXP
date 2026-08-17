import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../models/compagnie_join_request.dart';
import '../models/compagnie_team_invitation.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage.dart';
import '../services/compagnie_invitation_storage.dart';
import '../services/compagnie_request_storage.dart';
import '../widgets/avatar_renderer.dart';
import 'public_profile_screen.dart';

class CompagniePhoneScreen extends StatefulWidget {
  const CompagniePhoneScreen({
    super.key,
  });

  @override
  State<CompagniePhoneScreen> createState() =>
      _CompagniePhoneScreenState();
}

class _CompagniePhoneScreenState
    extends State<CompagniePhoneScreen> {
  String _currentUserId = '';

  List<CompagnieJoinRequest> _incomingRequests =
      <CompagnieJoinRequest>[];

  List<CompagnieJoinRequest> _outgoingRequests =
      <CompagnieJoinRequest>[];

  List<CompagnieTeamInvitation>
      _incomingInvitations =
      <CompagnieTeamInvitation>[];

  List<CompagnieTeamInvitation>
      _outgoingInvitations =
      <CompagnieTeamInvitation>[];

  final Map<String, String> _resolvedNames =
      <String, String>{};

  final Map<String, AvatarModel?> _avatars =
      <String, AvatarModel?>{};

  bool _loading = true;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  Future<void> _load() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    final String id = userId?.trim() ?? '';

    if (id.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _currentUserId = '';
        _incomingRequests =
            <CompagnieJoinRequest>[];
        _outgoingRequests =
            <CompagnieJoinRequest>[];
        _incomingInvitations =
            <CompagnieTeamInvitation>[];
        _outgoingInvitations =
            <CompagnieTeamInvitation>[];
        _loading = false;
      });
      return;
    }

    final List<CompagnieJoinRequest>
        incomingRequests =
        await CompagnieRequestStorage
            .incomingForUser(id);

    final List<CompagnieJoinRequest>
        outgoingRequests =
        await CompagnieRequestStorage
            .outgoingForUser(id);

    final List<CompagnieTeamInvitation>
        incomingInvitations =
        await CompagnieInvitationStorage
            .incomingForUser(id);

    final List<CompagnieTeamInvitation>
        outgoingInvitations =
        await CompagnieInvitationStorage
            .outgoingForUser(id);

    final Set<String> peopleIds =
        <String>{};

    for (final CompagnieJoinRequest request
        in incomingRequests) {
      peopleIds.add(request.requesterId);
    }

    for (final CompagnieTeamInvitation invitation
        in incomingInvitations) {
      peopleIds.add(invitation.inviterId);
    }

    for (final CompagnieTeamInvitation invitation
        in outgoingInvitations) {
      peopleIds.add(invitation.inviteeId);
    }

    final Map<String, String> names =
        <String, String>{};

    final Map<String, AvatarModel?> avatars =
        <String, AvatarModel?>{};

    for (final String personId in peopleIds) {
      final String? username =
          await AuthService
              .getUsernameForUserId(personId);

      if (username != null &&
          username.trim().isNotEmpty) {
        names[personId] = username.trim();
      }

      avatars[personId] =
          await AvatarStorage.loadAvatar(
        personId,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUserId = id;
      _incomingRequests = incomingRequests;
      _outgoingRequests = outgoingRequests;
      _incomingInvitations =
          incomingInvitations;
      _outgoingInvitations =
          outgoingInvitations;
      _resolvedNames
        ..clear()
        ..addAll(names);
      _avatars
        ..clear()
        ..addAll(avatars);
      _loading = false;
    });
  }

  String _nameFor(
    String userId,
    String fallback,
  ) {
    final String resolved =
        _resolvedNames[userId]?.trim() ?? '';

    if (resolved.isNotEmpty) {
      return resolved;
    }

    final String cleanFallback =
        fallback.trim();

    return cleanFallback.isEmpty
        ? 'Joueur'
        : cleanFallback;
  }

  Future<void> _openProfile(
    String userId,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            PublicProfileScreen(
          userId: userId,
        ),
      ),
    );
  }

  // ===========================================================================
  // DEMANDES D'ADHÉSION
  // ===========================================================================

  Future<void> _acceptRequest(
    CompagnieJoinRequest request,
  ) async {
    if (_actionInProgress ||
        !request.isPending) {
      return;
    }

    final String name = _nameFor(
      request.requesterId,
      request.requesterName,
    );

    final bool? confirmed = await _confirm(
      title: 'Accepter la demande',
      message:
          'Ajouter $name à ${request.teamName} ?',
      actionLabel: 'ACCEPTER',
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
      handlerUserId: _currentUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible d’accepter cette demande. L’équipe est peut-être complète ou tes droits ont changé.',
      );
      return;
    }

    _showMessage(
      '$name a rejoint ${request.teamName}.',
    );
    await _load();
  }

  Future<void> _rejectRequest(
    CompagnieJoinRequest request,
  ) async {
    if (_actionInProgress ||
        !request.isPending) {
      return;
    }

    final String name = _nameFor(
      request.requesterId,
      request.requesterName,
    );

    final bool? confirmed = await _confirm(
      title: 'Refuser la demande',
      message:
          'Refuser la demande de $name ?',
      actionLabel: 'REFUSER',
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
      handlerUserId: _currentUserId,
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

    _showMessage(
      'Demande de $name refusée.',
    );
    await _load();
  }

  // ===========================================================================
  // INVITATIONS D'ÉQUIPE
  // ===========================================================================

  Future<void> _acceptInvitation(
    CompagnieTeamInvitation invitation,
  ) async {
    if (_actionInProgress ||
        !invitation.isPending) {
      return;
    }

    final bool? confirmed = await _confirm(
      title: 'Rejoindre l’équipe',
      message:
          'Accepter l’invitation et rejoindre ${invitation.teamName} ?',
      actionLabel: 'REJOINDRE',
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
      inviteeId: _currentUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible d’accepter cette invitation. L’équipe est peut-être complète ou n’existe plus.',
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
    if (_actionInProgress ||
        !invitation.isPending) {
      return;
    }

    final bool? confirmed = await _confirm(
      title: 'Refuser l’invitation',
      message:
          'Refuser l’invitation de ${invitation.teamName} ?',
      actionLabel: 'REFUSER',
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
      inviteeId: _currentUserId,
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

  Future<void> _cancelInvitation(
    CompagnieTeamInvitation invitation,
  ) async {
    if (_actionInProgress ||
        !invitation.isPending) {
      return;
    }

    final String inviteeName = _nameFor(
      invitation.inviteeId,
      invitation.inviteeName,
    );

    final bool? confirmed = await _confirm(
      title: 'Annuler l’invitation',
      message:
          'Annuler l’invitation envoyée à $inviteeName pour ${invitation.teamName} ?',
      actionLabel: 'ANNULER L’INVITATION',
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
            .cancelInvitation(
      invitationId: invitation.id,
      requesterId: _currentUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible d’annuler cette invitation.',
      );
      return;
    }

    _showMessage('Invitation annulée.');
    await _load();
  }

  // ===========================================================================
  // OUTILS
  // ===========================================================================

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String actionLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
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
          actions: [
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
                actionLabel,
                style: TextStyle(
                  color: destructive
                      ? Colors.redAccent
                      : const Color(
                          0xffffc857,
                        ),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  int get _pendingIncomingCount {
    return _incomingRequests
            .where((request) => request.isPending)
            .length +
        _incomingInvitations
            .where((invitation) => invitation.isPending)
            .length;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
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
          'COMMUNICATEUR XP',
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
                color: const Color(0xffffc857),
                backgroundColor:
                    const Color(0xff21150e),
                onRefresh: _load,
                child: ListView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    20,
                    16,
                    32,
                  ),
                  children: [
                    _PhoneHeader(
                      pendingCount:
                          _pendingIncomingCount,
                    ),
                    const SizedBox(height: 22),

                    const _SectionTitle(
                      icon: Icons.mail_outline,
                      title: 'INVITATIONS REÇUES',
                    ),
                    const SizedBox(height: 10),
                    if (_incomingInvitations.isEmpty)
                      const _EmptyInbox(
                        text:
                            'Aucune invitation d’équipe reçue.',
                      )
                    else
                      ..._incomingInvitations.map(
                        (invitation) =>
                            _IncomingInvitationCard(
                          invitation: invitation,
                          inviterName: _nameFor(
                            invitation.inviterId,
                            invitation.inviterName,
                          ),
                          inviterAvatar:
                              _avatars[
                                invitation.inviterId
                              ],
                          busy: _actionInProgress,
                          onTapProfile: () {
                            _openProfile(
                              invitation.inviterId,
                            );
                          },
                          onAccept: () {
                            _acceptInvitation(
                              invitation,
                            );
                          },
                          onReject: () {
                            _rejectInvitation(
                              invitation,
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 24),

                    const _SectionTitle(
                      icon: Icons.person_add_alt_1,
                      title: 'DEMANDES POUR TES ÉQUIPES',
                    ),
                    const SizedBox(height: 10),
                    if (_incomingRequests.isEmpty)
                      const _EmptyInbox(
                        text:
                            'Aucune demande reçue pour tes équipes.',
                      )
                    else
                      ..._incomingRequests.map(
                        (request) =>
                            _IncomingRequestCard(
                          request: request,
                          requesterName: _nameFor(
                            request.requesterId,
                            request.requesterName,
                          ),
                          requesterAvatar:
                              _avatars[
                                request.requesterId
                              ],
                          busy: _actionInProgress,
                          onTapProfile: () {
                            _openProfile(
                              request.requesterId,
                            );
                          },
                          onAccept: () {
                            _acceptRequest(request);
                          },
                          onReject: () {
                            _rejectRequest(request);
                          },
                        ),
                      ),

                    const SizedBox(height: 24),

                    const _SectionTitle(
                      icon: Icons.outbox_outlined,
                      title: 'TES DEMANDES ENVOYÉES',
                    ),
                    const SizedBox(height: 10),
                    if (_outgoingRequests.isEmpty)
                      const _EmptyInbox(
                        text:
                            'Tu n’as envoyé aucune demande.',
                      )
                    else
                      ..._outgoingRequests.map(
                        (request) =>
                            _OutgoingRequestCard(
                          request: request,
                        ),
                      ),

                    const SizedBox(height: 24),

                    const _SectionTitle(
                      icon: Icons.send_outlined,
                      title: 'INVITATIONS ENVOYÉES',
                    ),
                    const SizedBox(height: 10),
                    if (_outgoingInvitations.isEmpty)
                      const _EmptyInbox(
                        text:
                            'Tu n’as envoyé aucune invitation.',
                      )
                    else
                      ..._outgoingInvitations.map(
                        (invitation) =>
                            _OutgoingInvitationCard(
                          invitation: invitation,
                          inviteeName: _nameFor(
                            invitation.inviteeId,
                            invitation.inviteeName,
                          ),
                          inviteeAvatar:
                              _avatars[
                                invitation.inviteeId
                              ],
                          busy: _actionInProgress,
                          onTapProfile: () {
                            _openProfile(
                              invitation.inviteeId,
                            );
                          },
                          onCancel: () {
                            _cancelInvitation(
                              invitation,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// WIDGETS
// =============================================================================

class _PhoneHeader extends StatelessWidget {
  final int pendingCount;

  const _PhoneHeader({
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff21150e),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xffffc857),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Badge(
            isLabelVisible: pendingCount > 0,
            label: Text(
              pendingCount.toString(),
            ),
            child: const Icon(
              Icons.smartphone,
              color: Color(0xffffc857),
              size: 38,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'CENTRE COMPAGNIE',
                  style: TextStyle(
                    color: Color(0xffffc857),
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pendingCount == 0
                      ? 'Aucune action en attente.'
                      : '$pendingCount action(s) à traiter.',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xffffc857),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class _IncomingInvitationCard
    extends StatelessWidget {
  final CompagnieTeamInvitation invitation;
  final String inviterName;
  final AvatarModel? inviterAvatar;
  final bool busy;
  final VoidCallback onTapProfile;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingInvitationCard({
    required this.invitation,
    required this.inviterName,
    required this.inviterAvatar,
    required this.busy,
    required this.onTapProfile,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      leading: _PersonAvatar(
        avatar: inviterAvatar,
      ),
      title: invitation.teamName,
      subtitle:
          'Invitation envoyée par $inviterName',
      status: invitation.status,
      onTap: onTapProfile,
      footer: invitation.isPending
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      side: const BorderSide(
                        color: Colors.redAccent,
                      ),
                    ),
                    child: const Text('REFUSER'),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        busy ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xffffc857),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text(
                      'REJOINDRE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _IncomingRequestCard
    extends StatelessWidget {
  final CompagnieJoinRequest request;
  final String requesterName;
  final AvatarModel? requesterAvatar;
  final bool busy;
  final VoidCallback onTapProfile;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingRequestCard({
    required this.request,
    required this.requesterName,
    required this.requesterAvatar,
    required this.busy,
    required this.onTapProfile,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      leading: _PersonAvatar(
        avatar: requesterAvatar,
      ),
      title: requesterName,
      subtitle:
          'Souhaite rejoindre ${request.teamName}',
      status: request.status,
      onTap: onTapProfile,
      footer: request.isPending
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      side: const BorderSide(
                        color: Colors.redAccent,
                      ),
                    ),
                    child: const Text('REFUSER'),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        busy ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xffffc857),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text(
                      'ACCEPTER',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _OutgoingRequestCard
    extends StatelessWidget {
  final CompagnieJoinRequest request;

  const _OutgoingRequestCard({
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      leading: const Icon(
        Icons.shield_outlined,
        color: Color(0xffffc857),
        size: 32,
      ),
      title: request.teamName,
      subtitle: request.isAccepted
          ? 'Ta demande a été acceptée.'
          : request.isRejected
              ? 'Ta demande a été refusée.'
              : 'En attente de réponse.',
      status: request.status,
    );
  }
}

class _OutgoingInvitationCard
    extends StatelessWidget {
  final CompagnieTeamInvitation invitation;
  final String inviteeName;
  final AvatarModel? inviteeAvatar;
  final bool busy;
  final VoidCallback onTapProfile;
  final VoidCallback onCancel;

  const _OutgoingInvitationCard({
    required this.invitation,
    required this.inviteeName,
    required this.inviteeAvatar,
    required this.busy,
    required this.onTapProfile,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      leading: _PersonAvatar(
        avatar: inviteeAvatar,
      ),
      title: inviteeName,
      subtitle:
          'Invitation pour ${invitation.teamName}',
      status: invitation.status,
      onTap: onTapProfile,
      footer: invitation.isPending
          ? Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed:
                    busy ? null : onCancel,
                icon: const Icon(
                  Icons.close,
                  size: 17,
                ),
                label: const Text(
                  'ANNULER L’INVITATION',
                ),
                style: TextButton.styleFrom(
                  foregroundColor:
                      Colors.redAccent,
                ),
              ),
            )
          : null,
    );
  }
}

class _ActionCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback? onTap;
  final Widget? footer;

  const _ActionCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xff21150e),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: status == 'pending'
              ? const Color(0xffffc857)
                  .withValues(alpha: 0.28)
              : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 2,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: status),
                ],
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final String text;
    final IconData icon;

    switch (status) {
      case 'accepted':
        text = 'ACCEPTÉ';
        icon = Icons.check_circle;
        break;
      case 'rejected':
        text = 'REFUSÉ';
        icon = Icons.cancel;
        break;
      case 'cancelled':
        text = 'ANNULÉ';
        icon = Icons.block;
        break;
      case 'pending':
      default:
        text = 'ATTENTE';
        icon = Icons.schedule;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff3a271c),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: const Color(0xffffc857),
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xffffc857),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  final AvatarModel? avatar;

  const _PersonAvatar({
    required this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final AvatarModel? value = avatar;

    return Container(
      width: 52,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xff160e09),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: const Color(0xffffc857),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: value == null
          ? const Icon(
              Icons.person,
              color: Color(0xffffc857),
              size: 28,
            )
          : FittedBox(
              fit: BoxFit.contain,
              child: AvatarRenderer(
                avatar: value,
                size: 48,
                showFrame: false,
                compactHeadCrop: true,
              ),
            ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final String text;

  const _EmptyInbox({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff21150e),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
        ),
      ),
    );
  }
}
