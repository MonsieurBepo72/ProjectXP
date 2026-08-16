import 'dart:io';

import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../models/team_model.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage.dart';
import '../services/team_storage.dart';
import '../widgets/avatar_renderer.dart';
import 'create_team_screen.dart';
import 'public_profile_screen.dart';

class TeamDetailsScreen
    extends StatefulWidget {
  final String teamId;
  final String currentUserId;
  final String currentUsername;

  const TeamDetailsScreen({
    super.key,
    required this.teamId,
    required this.currentUserId,
    required this.currentUsername,
  });

  @override
  State<TeamDetailsScreen> createState() =>
      _TeamDetailsScreenState();
}

class _TeamDetailsScreenState
    extends State<TeamDetailsScreen> {
  TeamModel? _team;

  final Map<String, String> _memberNames =
      <String, String>{};

  final Map<String, AvatarModel?> _memberAvatars =
      <String, AvatarModel?>{};

  bool _isLoading = true;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  Future<void> _loadTeam() async {
    final TeamModel? team =
        await TeamStorage.getTeam(
      widget.teamId,
    );

    final Map<String, String> memberNames =
        <String, String>{};

    final Map<String, AvatarModel?> memberAvatars =
        <String, AvatarModel?>{};

    if (team != null) {
      for (final String memberId
          in team.memberIds) {
        final String? username =
            await AuthService
                .getUsernameForUserId(
          memberId,
        );

        if (username != null &&
            username.trim().isNotEmpty) {
          memberNames[memberId] =
              username.trim();
        }

        memberAvatars[memberId] =
            await AvatarStorage.loadAvatar(
          memberId,
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _team = team;
      _memberNames
        ..clear()
        ..addAll(memberNames);
      _memberAvatars
        ..clear()
        ..addAll(memberAvatars);
      _isLoading = false;
    });
  }

  // ===========================================================================
  // MODIFICATION ÉQUIPE
  // ===========================================================================

  Future<void> _editTeam() async {
    final TeamModel? team =
        _team;

    if (team == null ||
        !team.isOwner(
          widget.currentUserId,
        )) {
      return;
    }

    final TeamModel? updated =
        await Navigator.push<TeamModel>(
      context,
      MaterialPageRoute<TeamModel>(
        builder: (context) =>
            CreateTeamScreen(
          teamToEdit: team,
        ),
      ),
    );

    if (updated == null ||
        !mounted) {
      return;
    }

    setState(() {
      _team = updated;
    });

    _showMessage(
      'Équipe modifiée.',
    );
  }

  // ===========================================================================
  // RECRUTEMENT
  // ===========================================================================

  Future<void> _toggleRecruitment() async {
    final TeamModel? team =
        _team;

    if (team == null ||
        !team.canManageTeam(
          widget.currentUserId,
        )) {
      return;
    }

    final bool newValue =
        !team.recruitmentOpen;

    setState(() {
      _actionInProgress = true;
    });

    final bool success =
        await TeamStorage
            .setRecruitmentOpen(
      teamId: team.id,
      requesterId:
          widget.currentUserId,
      isOpen: newValue,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _actionInProgress = false;
    });

    if (!success) {
      _showMessage(
        'Impossible de modifier le recrutement.',
      );
      return;
    }

    await _loadTeam();

    if (!mounted) {
      return;
    }

    _showMessage(
      newValue
          ? 'Recrutement ouvert.'
          : 'Recrutement fermé.',
    );
  }

  // ===========================================================================
  // MEMBRES / RÔLES
  // ===========================================================================

  Future<void> _openMemberProfile(
    String memberId,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            PublicProfileScreen(
          userId: memberId,
        ),
      ),
    );
  }

  Future<void> _openMemberActions(
    String memberId,
  ) async {
    final TeamModel? team =
        _team;

    if (team == null) {
      return;
    }

    final bool isCurrentUser =
        memberId ==
            widget.currentUserId;

    final bool isOwner =
        team.isOwner(
      widget.currentUserId,
    );

    final bool isAdmin =
        team.isLeader(
      widget.currentUserId,
    );

    final bool targetIsOwner =
        team.isOwner(memberId);

    final bool targetIsAdmin =
        team.isLeader(memberId);

    final List<_MemberAction>
        actions = [];

    if (isOwner &&
        !targetIsOwner) {
      if (targetIsAdmin) {
        actions.add(
          const _MemberAction(
            id: 'remove_admin',
            icon:
                Icons.shield_outlined,
            label:
                'Retirer le rôle Admin',
          ),
        );
      } else {
        actions.add(
          const _MemberAction(
            id: 'make_admin',
            icon:
                Icons.shield,
            label:
                'Nommer Admin',
          ),
        );
      }

      actions.add(
        const _MemberAction(
          id: 'transfer',
          icon:
              Icons.workspace_premium,
          label:
              'Transférer le rôle de Chef',
        ),
      );

      actions.add(
        const _MemberAction(
          id: 'remove',
          icon:
              Icons.person_remove,
          label:
              'Retirer de l’équipe',
          destructive: true,
        ),
      );
    } else if (isAdmin &&
        !targetIsOwner &&
        !isCurrentUser) {
      actions.add(
        const _MemberAction(
          id: 'remove',
          icon:
              Icons.person_remove,
          label:
              'Retirer de l’équipe',
          destructive: true,
        ),
      );
    }

    if (actions.isEmpty) {
      return;
    }

    final String? action =
        await showModalBottomSheet<String>(
      context: context,
      backgroundColor:
          const Color(0xff2b1a12),
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              16,
              18,
              24,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration:
                      BoxDecoration(
                    color:
                        Colors.white24,
                    borderRadius:
                        BorderRadius.circular(
                      10,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  _memberName(
                    team,
                    memberId,
                  ),
                  style:
                      const TextStyle(
                    color:
                        Colors.amber,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                ...actions.map(
                  (item) =>
                      ListTile(
                    leading:
                        Icon(
                      item.icon,
                      color: item.destructive
                          ? Colors.redAccent
                          : Colors.amber,
                    ),
                    title:
                        Text(
                      item.label,
                      style:
                          TextStyle(
                        color: item.destructive
                            ? Colors.redAccent
                            : Colors.white,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(
                        sheetContext,
                        item.id,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    switch (action) {
      case 'make_admin':
        await _setAdmin(
          memberId,
        );
        break;

      case 'remove_admin':
        await _removeAdmin();
        break;

      case 'transfer':
        await _transferOwnership(
          memberId,
        );
        break;

      case 'remove':
        await _removeMember(
          memberId,
        );
        break;
    }
  }

  Future<void> _setAdmin(
    String memberId,
  ) async {
    final TeamModel? team =
        _team;

    if (team == null) {
      return;
    }

    final String memberName =
        _memberName(
      team,
      memberId,
    );

    final bool? confirmed =
        await _confirm(
      title: 'Nommer Admin',
      message:
          'Nommer $memberName Admin de ${team.name} ?',
      confirmLabel:
          'NOMMER',
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await TeamStorage.setLeader(
      teamId: team.id,
      ownerId:
          widget.currentUserId,
      leaderId: memberId,
      leaderName: memberName,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de nommer cet Admin.',
      );
      return;
    }

    await _loadTeam();

    if (!mounted) {
      return;
    }

    _showMessage(
      '$memberName est maintenant Admin.',
    );
  }

  Future<void> _removeAdmin() async {
    final TeamModel? team =
        _team;

    if (team == null ||
        team.leaderId == null) {
      return;
    }

    final bool? confirmed =
        await _confirm(
      title:
          'Retirer le rôle Admin',
      message:
          'Retirer le rôle Admin à ${team.leaderName ?? 'ce membre'} ?',
      confirmLabel:
          'RETIRER',
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await TeamStorage.removeLeader(
      teamId: team.id,
      ownerId:
          widget.currentUserId,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de retirer le rôle Admin.',
      );
      return;
    }

    await _loadTeam();
  }

  Future<void> _transferOwnership(
    String memberId,
  ) async {
    final TeamModel? team =
        _team;

    if (team == null) {
      return;
    }

    final String memberName =
        _memberName(
      team,
      memberId,
    );

    final bool? confirmed =
        await _confirm(
      title:
          'Transférer le rôle de Chef',
      message:
          'Tu ne seras plus Chef de ${team.name}. Transférer la propriété à $memberName ?',
      confirmLabel:
          'TRANSFÉRER',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await TeamStorage
            .transferOwnership(
      teamId: team.id,
      currentOwnerId:
          widget.currentUserId,
      newOwnerId: memberId,
      newOwnerName: memberName,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de transférer la propriété.',
      );
      return;
    }

    await _loadTeam();

    if (!mounted) {
      return;
    }

    _showMessage(
      '$memberName est maintenant Chef.',
    );
  }

  Future<void> _removeMember(
    String memberId,
  ) async {
    final TeamModel? team =
        _team;

    if (team == null) {
      return;
    }

    final String memberName =
        _memberName(
      team,
      memberId,
    );

    final bool? confirmed =
        await _confirm(
      title:
          'Retirer un membre',
      message:
          'Retirer $memberName de ${team.name} ?',
      confirmLabel:
          'RETIRER',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await TeamStorage.removeMember(
      teamId: team.id,
      requesterId:
          widget.currentUserId,
      memberId: memberId,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de retirer ce membre.',
      );
      return;
    }

    await _loadTeam();
  }

  // ===========================================================================
  // QUITTER / DISSOUDRE
  // ===========================================================================

  Future<void> _leaveTeam() async {
    final TeamModel? team =
        _team;

    if (team == null ||
        !team.canLeave(
          widget.currentUserId,
        )) {
      return;
    }

    final bool? confirmed =
        await _confirm(
      title:
          'Quitter l’équipe',
      message:
          'Quitter définitivement ${team.name} ?',
      confirmLabel:
          'QUITTER',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await TeamStorage.leaveTeam(
      teamId: team.id,
      userId:
          widget.currentUserId,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de quitter cette équipe.',
      );
      return;
    }

    Navigator.pop(
      context,
      true,
    );
  }

  Future<void> _deleteTeam() async {
    final TeamModel? team =
        _team;

    if (team == null ||
        !team.isOwner(
          widget.currentUserId,
        )) {
      return;
    }

    final bool? confirmed =
        await _confirm(
      title:
          'Dissoudre l’équipe',
      message:
          'Cette action supprimera définitivement ${team.name}. Continuer ?',
      confirmLabel:
          'DISSOUDRE',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await TeamStorage.deleteTeam(
      teamId: team.id,
      ownerId:
          widget.currentUserId,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de dissoudre cette équipe.',
      );
      return;
    }

    Navigator.pop(
      context,
      true,
    );
  }

  // ===========================================================================
  // OUTILS
  // ===========================================================================

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
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
            style:
                const TextStyle(
              color:
                  Colors.amber,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style:
                const TextStyle(
              color:
                  Colors.white70,
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
              child:
                  const Text(
                'ANNULER',
                style:
                    TextStyle(
                  color:
                      Colors.white60,
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
                style:
                    TextStyle(
                  color: destructive
                      ? Colors.redAccent
                      : Colors.amber,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _memberName(
    TeamModel team,
    String memberId,
  ) {
    final String resolved =
        _memberNames[memberId]
                ?.trim() ??
            '';

    if (resolved.isNotEmpty) {
      return resolved;
    }

    if (memberId == team.ownerId) {
      final String ownerName =
          team.ownerName.trim();

      if (ownerName.isNotEmpty) {
        return ownerName;
      }
    }

    if (memberId ==
        team.leaderId) {
      final String leaderName =
          team.leaderName?.trim() ?? '';

      if (leaderName.isNotEmpty) {
        return leaderName;
      }
    }

    if (memberId ==
        widget.currentUserId) {
      final String name =
          widget.currentUsername
              .trim();

      if (name.isNotEmpty) {
        return name;
      }
    }

    return 'Joueur';
  }

  String _roleLabel(
    TeamModel team,
    String memberId,
  ) {
    if (memberId == team.ownerId) {
      return 'CHEF';
    }

    if (memberId ==
        team.leaderId) {
      return 'ADMIN';
    }

    return 'MEMBRE';
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor:
            Color(0xff1b120d),
        body: Center(
          child:
              CircularProgressIndicator(
            color:
                Colors.amber,
          ),
        ),
      );
    }

    final TeamModel? team =
        _team;

    if (team == null) {
      return Scaffold(
        backgroundColor:
            const Color(0xff1b120d),
        appBar: AppBar(
          backgroundColor:
              const Color(0xff5c3317),
          foregroundColor:
              Colors.amber,
          title:
              const Text(
            'ÉQUIPE',
          ),
        ),
        body:
            const Center(
          child: Text(
            'Cette équipe n’existe plus.',
            style:
                TextStyle(
              color:
                  Colors.white70,
            ),
          ),
        ),
      );
    }

    final bool isOwner =
        team.isOwner(
      widget.currentUserId,
    );

    final bool canManage =
        team.canManageTeam(
      widget.currentUserId,
    );

    final String role =
        team.roleLabelFor(
      widget.currentUserId,
    );

    return Scaffold(
      backgroundColor:
          const Color(0xff1b120d),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff5c3317),
        foregroundColor:
            Colors.amber,
        title: Text(
          team.name,
          overflow:
              TextOverflow.ellipsis,
        ),
        actions: [
          if (isOwner)
            IconButton(
              onPressed:
                  _editTeam,
              tooltip:
                  'Modifier l’équipe',
              icon:
                  const Icon(
                Icons.edit,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color:
              Colors.amber,
          backgroundColor:
              const Color(0xff2b1a12),
          onRefresh:
              _loadTeam,
          child: ListView(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              20,
              18,
              35,
            ),
            children: [
              Center(
                child:
                    _TeamImage(
                  imagePath:
                      team.imagePath,
                  size: 170,
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              Text(
                team.name,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Colors.amber,
                  fontSize: 27,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 7,
              ),

              Center(
                child:
                    _RoleChip(
                  role: role,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              Text(
                team.description.isEmpty
                    ? 'Aucune description.'
                    : team.description,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Colors.white70,
                  height: 1.45,
                ),
              ),

              const SizedBox(
                height: 22,
              ),

              _InfoRow(
                icon:
                    Icons.workspace_premium,
                label: 'Chef',
                value:
                    team.ownerName,
              ),

              const SizedBox(
                height: 9,
              ),

              _InfoRow(
                icon:
                    Icons.people,
                label: 'Membres',
                value:
                    '${team.memberIds.length}/${team.maxMembers}',
              ),

              const SizedBox(
                height: 9,
              ),

              _InfoRow(
                icon: team.recruitmentOpen
                    ? Icons.lock_open
                    : Icons.lock_outline,
                label:
                    'Recrutement',
                value: team.recruitmentOpen
                    ? 'OUVERT'
                    : 'FERMÉ',
              ),

              if (canManage) ...[
                const SizedBox(
                  height: 12,
                ),
                OutlinedButton.icon(
                  onPressed:
                      _actionInProgress
                          ? null
                          : _toggleRecruitment,
                  icon: Icon(
                    team.recruitmentOpen
                        ? Icons.lock_outline
                        : Icons.lock_open,
                  ),
                  label: Text(
                    team.recruitmentOpen
                        ? 'FERMER LE RECRUTEMENT'
                        : 'OUVRIR LE RECRUTEMENT',
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        Colors.amber,
                    side:
                        const BorderSide(
                      color:
                          Colors.amber,
                    ),
                  ),
                ),
              ],

              const SizedBox(
                height: 26,
              ),

              const _SectionTitle(
                icon:
                    Icons.sports_esports,
                title: 'JEUX',
              ),

              const SizedBox(
                height: 10,
              ),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: team.games
                    .map(
                      (game) =>
                          _Tag(
                        icon:
                            Icons.games,
                        text:
                            game,
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(
                height: 26,
              ),

              const _SectionTitle(
                icon:
                    Icons.devices,
                title:
                    'PLATEFORMES',
              ),

              const SizedBox(
                height: 10,
              ),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: team.platforms
                    .map(
                      (platform) =>
                          _Tag(
                        icon:
                            Icons.devices,
                        text:
                            platform,
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(
                height: 28,
              ),

              const _SectionTitle(
                icon:
                    Icons.people,
                title:
                    'MEMBRES',
              ),

              const SizedBox(
                height: 10,
              ),

              ...team.memberIds.map(
                (memberId) {
                  final bool hasActions =
                      (isOwner &&
                              memberId !=
                                  team.ownerId) ||
                          (team.isLeader(
                                widget.currentUserId,
                              ) &&
                              memberId !=
                                  team.ownerId &&
                              memberId !=
                                  widget.currentUserId);

                  return _MemberCard(
                    name:
                        _memberName(
                      team,
                      memberId,
                    ),
                    role:
                        _roleLabel(
                      team,
                      memberId,
                    ),
                    avatar:
                        _memberAvatars[
                      memberId
                    ],
                    isCurrentUser:
                        memberId ==
                            widget.currentUserId,
                    hasActions:
                        hasActions,
                    onTapProfile: () {
                      _openMemberProfile(
                        memberId,
                      );
                    },
                    onTapActions: () {
                      _openMemberActions(
                        memberId,
                      );
                    },
                  );
                },
              ),

              const SizedBox(
                height: 28,
              ),

              if (isOwner) ...[
                SizedBox(
                  width:
                      double.infinity,
                  child:
                      OutlinedButton.icon(
                    onPressed:
                        _editTeam,
                    icon:
                        const Icon(
                      Icons.edit,
                    ),
                    label:
                        const Text(
                      'MODIFIER L’ÉQUIPE',
                    ),
                    style:
                        OutlinedButton
                            .styleFrom(
                      foregroundColor:
                          Colors.amber,
                      side:
                          const BorderSide(
                        color:
                            Colors.amber,
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                SizedBox(
                  width:
                      double.infinity,
                  child:
                      OutlinedButton.icon(
                    onPressed:
                        _deleteTeam,
                    icon:
                        const Icon(
                      Icons.delete_forever,
                    ),
                    label:
                        const Text(
                      'DISSOUDRE L’ÉQUIPE',
                    ),
                    style:
                        OutlinedButton
                            .styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      side:
                          const BorderSide(
                        color:
                            Colors.redAccent,
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ] else if (team.canLeave(
                widget.currentUserId,
              )) ...[
                SizedBox(
                  width:
                      double.infinity,
                  child:
                      OutlinedButton.icon(
                    onPressed:
                        _leaveTeam,
                    icon:
                        const Icon(
                      Icons.logout,
                    ),
                    label:
                        const Text(
                      'QUITTER L’ÉQUIPE',
                    ),
                    style:
                        OutlinedButton
                            .styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      side:
                          const BorderSide(
                        color:
                            Colors.redAccent,
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(
                height: 18,
              ),

              const Text(
                'Les invitations et demandes reçues sont gérées depuis le téléphone du Hall.',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Colors.white38,
                  fontSize: 11,
                  height: 1.4,
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

class _MemberAction {
  final String id;
  final IconData icon;
  final String label;
  final bool destructive;

  const _MemberAction({
    required this.id,
    required this.icon,
    required this.label,
    this.destructive = false,
  });
}

class _TeamImage
    extends StatelessWidget {
  final String? imagePath;
  final double size;

  const _TeamImage({
    required this.imagePath,
    required this.size,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: size,
      height: size,
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border:
            Border.all(
          color:
              Colors.amber,
          width: 2,
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      child:
          _buildContent(),
    );
  }

  Widget _buildContent() {
    final String? path =
        imagePath;

    if (path == null ||
        path.isEmpty) {
      return Icon(
        Icons.groups,
        color:
            Colors.amber,
        size:
            size * 0.45,
      );
    }

    if (path.startsWith(
          'http://',
        ) ||
        path.startsWith(
          'https://',
        )) {
      return Image.network(
        path,
        fit:
            BoxFit.cover,
        errorBuilder:
            (
          context,
          error,
          stackTrace,
        ) {
          return Icon(
            Icons.groups,
            color:
                Colors.amber,
            size:
                size * 0.45,
          );
        },
      );
    }

    final File file =
        File(path);

    if (file.existsSync()) {
      return Image.file(
        file,
        fit:
            BoxFit.cover,
      );
    }

    return Icon(
      Icons.groups,
      color:
          Colors.amber,
      size:
          size * 0.45,
    );
  }
}

class _RoleChip
    extends StatelessWidget {
  final String role;

  const _RoleChip({
    required this.role,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final IconData icon =
        role == 'CHEF'
            ? Icons.workspace_premium
            : role == 'ADMIN'
                ? Icons.shield
                : Icons.person;

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border:
            Border.all(
          color:
              Colors.amber,
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                Colors.amber,
            size: 16,
          ),
          const SizedBox(
            width: 6,
          ),
          Text(
            role,
            style:
                const TextStyle(
              color:
                  Colors.amber,
              fontSize: 11,
              fontWeight:
                  FontWeight.bold,
              letterSpacing:
                  0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        13,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        border:
            Border.all(
          color:
              Colors.white12,
        ),
      ),
      child:
          Row(
        children: [
          Icon(
            icon,
            color:
                Colors.amber,
            size: 20,
          ),
          const SizedBox(
            width: 10,
          ),
          Text(
            '$label : ',
            style:
                const TextStyle(
              color:
                  Colors.white54,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          Expanded(
            child:
                Text(
              value,
              textAlign:
                  TextAlign.right,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle
    extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color:
              Colors.amber,
          size: 20,
        ),
        const SizedBox(
          width: 8,
        ),
        Text(
          title,
          style:
              const TextStyle(
            color:
                Colors.amber,
            fontSize: 16,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _Tag
    extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Tag({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff3d291e,
        ),
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        border:
            Border.all(
          color:
              Colors.white24,
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                Colors.amber,
            size: 15,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            text,
            style:
                const TextStyle(
              color:
                  Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard
    extends StatelessWidget {
  final String name;
  final String role;
  final AvatarModel? avatar;
  final bool isCurrentUser;
  final bool hasActions;
  final VoidCallback onTapProfile;
  final VoidCallback onTapActions;

  const _MemberCard({
    required this.name,
    required this.role,
    required this.avatar,
    required this.isCurrentUser,
    required this.hasActions,
    required this.onTapProfile,
    required this.onTapActions,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 9,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        border:
            Border.all(
          color:
              role == 'CHEF'
                  ? Colors.amber
                  : Colors.white12,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        child: InkWell(
          onTap:
              onTapProfile,
          borderRadius:
              BorderRadius.circular(
            13,
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(
              12,
            ),
            child: Row(
              children: [
                _MemberAvatar(
                  avatar: avatar,
                ),
                const SizedBox(
                  width: 11,
                ),
                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCurrentUser
                            ? '$name (toi)'
                            : name,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        role,
                        style:
                            const TextStyle(
                          color:
                              Colors.amber,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.bold,
                          letterSpacing:
                              0.8,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      const Text(
                        'Appuie pour voir le profil',
                        style:
                            TextStyle(
                          color:
                              Colors.white38,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasActions)
                  IconButton(
                    onPressed:
                        onTapActions,
                    tooltip:
                        'Actions du membre',
                    icon:
                        const Icon(
                      Icons.more_vert,
                      color:
                          Colors.amber,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color:
                        Colors.white24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberAvatar
    extends StatelessWidget {
  final AvatarModel? avatar;

  const _MemberAvatar({
    required this.avatar,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final AvatarModel? value =
        avatar;

    return Container(
      width: 52,
      height: 62,
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff1b120d,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        border:
            Border.all(
          color:
              Colors.amber,
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      alignment:
          Alignment.center,
      child: value == null
          ? const Icon(
              Icons.person,
              color:
                  Colors.amber,
              size: 30,
            )
          : FittedBox(
              fit:
                  BoxFit.contain,
              child:
                  AvatarRenderer(
                avatar: value,
                size: 48,
                showFrame: false,
                compactHeadCrop: true,
              ),
            ),
    );
  }
}

