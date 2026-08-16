import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/squad_team_invitation.dart';
import '../models/team_model.dart';
import 'team_storage.dart';

enum SquadInvitationCreateResult {
  success,
  invalid,
  notAllowed,
  alreadyMember,
  teamFull,
  alreadyPending,
}

class SquadInvitationStorage {
  static const String _storageKey =
      'project_xp_squad_team_invitations';

  // ===========================================================================
  // CHARGEMENT / SAUVEGARDE
  // ===========================================================================

  static Future<List<SquadTeamInvitation>>
      loadAll() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? raw =
        prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      return <SquadTeamInvitation>[];
    }

    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is! List) {
        return <SquadTeamInvitation>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                SquadTeamInvitation.fromMap(
              Map<String, dynamic>.from(
                item,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return <SquadTeamInvitation>[];
    }
  }

  static Future<bool> _saveAll(
    List<SquadTeamInvitation> invitations,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.setString(
      _storageKey,
      jsonEncode(
        invitations
            .map(
              (invitation) =>
                  invitation.toMap(),
            )
            .toList(),
      ),
    );
  }

  // ===========================================================================
  // CRÉER UNE INVITATION
  // ===========================================================================

  static Future<SquadInvitationCreateResult>
      createInvitation({
    required TeamModel team,
    required String inviterId,
    required String inviterName,
    required String inviteeId,
    required String inviteeName,
  }) async {
    final String cleanInviterId =
        inviterId.trim();

    final String cleanInviteeId =
        inviteeId.trim();

    final String cleanInviterName =
        inviterName.trim();

    final String cleanInviteeName =
        inviteeName.trim();

    if (cleanInviterId.isEmpty ||
        cleanInviteeId.isEmpty ||
        cleanInviterId == cleanInviteeId ||
        cleanInviteeName.isEmpty) {
      return SquadInvitationCreateResult.invalid;
    }

    final TeamModel? latestTeam =
        await TeamStorage.getTeam(team.id);

    if (latestTeam == null) {
      return SquadInvitationCreateResult.invalid;
    }

    if (!latestTeam.canManageTeam(
      cleanInviterId,
    )) {
      return SquadInvitationCreateResult.notAllowed;
    }

    if (latestTeam.memberIds.contains(
      cleanInviteeId,
    )) {
      return SquadInvitationCreateResult.alreadyMember;
    }

    if (latestTeam.memberIds.length >=
        latestTeam.maxMembers) {
      return SquadInvitationCreateResult.teamFull;
    }

    final List<SquadTeamInvitation>
        invitations = await loadAll();

    final bool alreadyPending =
        invitations.any(
      (invitation) =>
          invitation.teamId == latestTeam.id &&
          invitation.inviteeId ==
              cleanInviteeId &&
          invitation.isPending,
    );

    if (alreadyPending) {
      return SquadInvitationCreateResult.alreadyPending;
    }

    invitations.add(
      SquadTeamInvitation(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
        teamId: latestTeam.id,
        teamName: latestTeam.name,
        inviterId: cleanInviterId,
        inviterName:
            cleanInviterName.isEmpty
                ? 'Joueur'
                : cleanInviterName,
        inviteeId: cleanInviteeId,
        inviteeName: cleanInviteeName,
        status: 'pending',
        handledByUserId: null,
        createdAt: DateTime.now(),
        handledAt: null,
      ),
    );

    final bool saved =
        await _saveAll(invitations);

    return saved
        ? SquadInvitationCreateResult.success
        : SquadInvitationCreateResult.invalid;
  }

  // ===========================================================================
  // LECTURE
  // ===========================================================================

  static Future<List<SquadTeamInvitation>>
      incomingForUser(
    String userId,
  ) async {
    final List<SquadTeamInvitation> all =
        await loadAll();

    final List<SquadTeamInvitation> result =
        all
            .where(
              (invitation) =>
                  invitation.inviteeId == userId,
            )
            .toList();

    result.sort(
      (a, b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<List<SquadTeamInvitation>>
      pendingIncomingForUser(
    String userId,
  ) async {
    final List<SquadTeamInvitation> all =
        await incomingForUser(userId);

    return all
        .where(
          (invitation) =>
              invitation.isPending,
        )
        .toList();
  }

  static Future<List<SquadTeamInvitation>>
      outgoingForUser(
    String userId,
  ) async {
    final List<SquadTeamInvitation> all =
        await loadAll();

    final List<SquadTeamInvitation> result =
        all
            .where(
              (invitation) =>
                  invitation.inviterId == userId,
            )
            .toList();

    result.sort(
      (a, b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<List<SquadTeamInvitation>>
      pendingForTeam(
    String teamId,
  ) async {
    final List<SquadTeamInvitation> all =
        await loadAll();

    final List<SquadTeamInvitation> result =
        all
            .where(
              (invitation) =>
                  invitation.teamId == teamId &&
                  invitation.isPending,
            )
            .toList();

    result.sort(
      (a, b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<bool> hasPendingInvitation({
    required String teamId,
    required String inviteeId,
  }) async {
    final List<SquadTeamInvitation> all =
        await loadAll();

    return all.any(
      (invitation) =>
          invitation.teamId == teamId &&
          invitation.inviteeId == inviteeId &&
          invitation.isPending,
    );
  }

  // ===========================================================================
  // ACCEPTER / REFUSER / ANNULER
  // ===========================================================================

  static Future<bool> acceptInvitation({
    required String invitationId,
    required String inviteeId,
  }) async {
    final List<SquadTeamInvitation>
        invitations = await loadAll();

    final int index = invitations.indexWhere(
      (invitation) =>
          invitation.id == invitationId,
    );

    if (index == -1) {
      return false;
    }

    final SquadTeamInvitation invitation =
        invitations[index];

    if (!invitation.isPending ||
        invitation.inviteeId != inviteeId) {
      return false;
    }

    final TeamModel? team =
        await TeamStorage.getTeam(
      invitation.teamId,
    );

    if (team == null) {
      return false;
    }

    if (!team.memberIds.contains(
      inviteeId,
    )) {
      if (team.memberIds.length >=
          team.maxMembers) {
        return false;
      }

      // L'invitation représente l'autorisation d'ajouter le joueur.
      // On utilise le Chef actuel comme gestionnaire afin qu'une invitation
      // reste valide même si l'Admin qui l'avait envoyée a changé depuis.
      final bool added =
          await TeamStorage.addMember(
        teamId: team.id,
        requesterId: team.ownerId,
        memberId: inviteeId,
      );

      if (!added) {
        return false;
      }
    }

    invitations[index] =
        invitation.copyWith(
      status: 'accepted',
      handledByUserId: inviteeId,
      handledAt: DateTime.now(),
    );

    return _saveAll(invitations);
  }

  static Future<bool> rejectInvitation({
    required String invitationId,
    required String inviteeId,
  }) async {
    final List<SquadTeamInvitation>
        invitations = await loadAll();

    final int index = invitations.indexWhere(
      (invitation) =>
          invitation.id == invitationId,
    );

    if (index == -1) {
      return false;
    }

    final SquadTeamInvitation invitation =
        invitations[index];

    if (!invitation.isPending ||
        invitation.inviteeId != inviteeId) {
      return false;
    }

    invitations[index] =
        invitation.copyWith(
      status: 'rejected',
      handledByUserId: inviteeId,
      handledAt: DateTime.now(),
    );

    return _saveAll(invitations);
  }

  static Future<bool> cancelInvitation({
    required String invitationId,
    required String requesterId,
  }) async {
    final List<SquadTeamInvitation>
        invitations = await loadAll();

    final int index = invitations.indexWhere(
      (invitation) =>
          invitation.id == invitationId,
    );

    if (index == -1) {
      return false;
    }

    final SquadTeamInvitation invitation =
        invitations[index];

    if (!invitation.isPending) {
      return false;
    }

    final TeamModel? team =
        await TeamStorage.getTeam(
      invitation.teamId,
    );

    final bool allowed =
        invitation.inviterId == requesterId ||
        (team != null &&
            team.canManageTeam(requesterId));

    if (!allowed) {
      return false;
    }

    invitations[index] =
        invitation.copyWith(
      status: 'cancelled',
      handledByUserId: requesterId,
      handledAt: DateTime.now(),
    );

    return _saveAll(invitations);
  }

  /// Si un joueur rejoint l'équipe via une demande d'adhésion alors qu'une
  /// ancienne invitation était encore en attente, on clôt cette invitation.
  static Future<bool> closePendingAsAccepted({
    required String teamId,
    required String inviteeId,
    required String handledByUserId,
  }) async {
    final List<SquadTeamInvitation>
        invitations = await loadAll();

    bool changed = false;

    for (int i = 0;
        i < invitations.length;
        i++) {
      final SquadTeamInvitation invitation =
          invitations[i];

      if (invitation.teamId == teamId &&
          invitation.inviteeId == inviteeId &&
          invitation.isPending) {
        invitations[i] =
            invitation.copyWith(
          status: 'accepted',
          handledByUserId:
              handledByUserId,
          handledAt: DateTime.now(),
        );
        changed = true;
      }
    }

    if (!changed) {
      return true;
    }

    return _saveAll(invitations);
  }
}
