import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/compagnie_team_invitation.dart';
import '../models/team_model.dart';
import 'supabase_service.dart';
import 'team_storage.dart';

enum CompagnieInvitationCreateResult {
  success,
  invalid,
  notAllowed,
  alreadyMember,
  teamFull,
  alreadyPending,
}

class CompagnieInvitationStorage {
  static const String _storageKey =
      'project_xp_compagnie_team_invitations';

  static const String _legacyStorageKey =
      'project_xp_squad_team_invitations';

  static const String _onlineTable =
      'compagnie_team_invitations';

  // ==========================================================================
  // API PRINCIPALE : LOCAL + ONLINE
  // ==========================================================================

  static Future<List<CompagnieTeamInvitation>>
      loadAll() async {
    final List<CompagnieTeamInvitation> local =
        await _loadLegacyAll();

    final List<CompagnieTeamInvitation> online =
        await _loadOnlineVisible();

    return _mergeAndSort(
      local,
      online,
    );
  }

  static Future<CompagnieInvitationCreateResult>
      createInvitation({
    required TeamModel team,
    required String inviterId,
    required String inviterName,
    required String inviteeId,
    required String inviteeName,
  }) async {
    final String cleanInviteeId =
        inviteeId.trim();

    // Un UUID correspond à l'identité sociale Supabase utilisée par les vrais
    // profils de "Trouver des joueurs". Les anciens comptes locaux continuent
    // à utiliser l'ancien stockage pour ne casser aucune fonctionnalité.
    if (_isUuid(cleanInviteeId) &&
        SupabaseService.currentUser != null) {
      return await _createOnlineInvitation(
        team: team,
        inviterName: inviterName,
        inviteeId: cleanInviteeId,
        inviteeName: inviteeName,
      );
    }

    return await _createLegacyInvitation(
      team: team,
      inviterId: inviterId,
      inviterName: inviterName,
      inviteeId: inviteeId,
      inviteeName: inviteeName,
    );
  }

  static Future<List<CompagnieTeamInvitation>>
      incomingForUser(
    String userId,
  ) async {
    final List<CompagnieTeamInvitation> local =
        await _legacyIncomingForUser(userId);

    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (socialUserId.isEmpty) {
      return local;
    }

    final List<CompagnieTeamInvitation> online =
        await _loadOnlineWhere(
      column: 'invitee_id',
      value: socialUserId,
    );

    return _mergeAndSort(local, online);
  }

  static Future<List<CompagnieTeamInvitation>>
      pendingIncomingForUser(
    String userId,
  ) async {
    final List<CompagnieTeamInvitation> all =
        await incomingForUser(userId);

    return all
        .where(
          (CompagnieTeamInvitation invitation) =>
              invitation.isPending,
        )
        .toList();
  }

  static Future<List<CompagnieTeamInvitation>>
      outgoingForUser(
    String userId,
  ) async {
    final List<CompagnieTeamInvitation> local =
        await _legacyOutgoingForUser(userId);

    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (socialUserId.isEmpty) {
      return local;
    }

    final List<CompagnieTeamInvitation> online =
        await _loadOnlineWhere(
      column: 'inviter_id',
      value: socialUserId,
    );

    return _mergeAndSort(local, online);
  }

  static Future<List<CompagnieTeamInvitation>>
      pendingForTeam(
    String teamId,
  ) async {
    final List<CompagnieTeamInvitation> local =
        await _legacyPendingForTeam(teamId);

    if (SupabaseService.currentUser == null) {
      return local;
    }

    final List<CompagnieTeamInvitation> online =
        await _loadOnlineTeamPending(teamId);

    return _mergeAndSort(local, online);
  }

  static Future<bool> hasPendingInvitation({
    required String teamId,
    required String inviteeId,
  }) async {
    final bool legacy =
        await _legacyHasPendingInvitation(
      teamId: teamId,
      inviteeId: inviteeId,
    );

    if (legacy) {
      return true;
    }

    if (!_isUuid(inviteeId) ||
        SupabaseService.currentUser == null) {
      return false;
    }

    try {
      final Map<String, dynamic>? row =
          await SupabaseService.client
              .from(_onlineTable)
              .select('id')
              .eq('team_id', teamId)
              .eq('invitee_id', inviteeId.trim())
              .eq('status', 'pending')
              .maybeSingle();

      return row != null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> acceptInvitation({
    required String invitationId,
    required String inviteeId,
  }) async {
    if (_isUuid(invitationId) &&
        SupabaseService.currentUser != null) {
      try {
        final dynamic response =
            await SupabaseService.client.rpc(
          'project_xp_accept_compagnie_invitation',
          params: <String, dynamic>{
            'p_invitation_id': invitationId.trim(),
          },
        );

        final bool success =
            response == true ||
                response?.toString() == 'true';

        if (success) {
          // Met immédiatement à jour le cache local : l'équipe reçue devient
          // visible dans "Mes équipes" sur ce téléphone.
          await TeamStorage.loadTeams();
        }

        return success;
      } catch (_) {
        return false;
      }
    }

    return _legacyAcceptInvitation(
      invitationId: invitationId,
      inviteeId: inviteeId,
    );
  }

  static Future<bool> rejectInvitation({
    required String invitationId,
    required String inviteeId,
  }) async {
    if (_isUuid(invitationId) &&
        SupabaseService.currentUser != null) {
      try {
        final dynamic response =
            await SupabaseService.client.rpc(
          'project_xp_reject_compagnie_invitation',
          params: <String, dynamic>{
            'p_invitation_id': invitationId.trim(),
          },
        );

        return response == true ||
            response?.toString() == 'true';
      } catch (_) {
        return false;
      }
    }

    return _legacyRejectInvitation(
      invitationId: invitationId,
      inviteeId: inviteeId,
    );
  }

  static Future<bool> cancelInvitation({
    required String invitationId,
    required String requesterId,
  }) async {
    if (_isUuid(invitationId) &&
        SupabaseService.currentUser != null) {
      try {
        final dynamic response =
            await SupabaseService.client.rpc(
          'project_xp_cancel_compagnie_invitation',
          params: <String, dynamic>{
            'p_invitation_id': invitationId.trim(),
          },
        );

        return response == true ||
            response?.toString() == 'true';
      } catch (_) {
        return false;
      }
    }

    return _legacyCancelInvitation(
      invitationId: invitationId,
      requesterId: requesterId,
    );
  }

  static Future<bool> closePendingAsAccepted({
    required String teamId,
    required String inviteeId,
    required String handledByUserId,
  }) async {
    bool onlineOk = true;

    if (_isUuid(inviteeId) &&
        SupabaseService.currentUser != null) {
      try {
        final dynamic response =
            await SupabaseService.client.rpc(
          'project_xp_close_compagnie_invitation_as_accepted',
          params: <String, dynamic>{
            'p_team_id': teamId,
            'p_invitee_id': inviteeId.trim(),
          },
        );

        onlineOk = response == true ||
            response?.toString() == 'true';
      } catch (_) {
        onlineOk = false;
      }
    }

    final bool localOk =
        await _legacyClosePendingAsAccepted(
      teamId: teamId,
      inviteeId: inviteeId,
      handledByUserId: handledByUserId,
    );

    return onlineOk && localOk;
  }

  // ==========================================================================
  // ONLINE
  // ==========================================================================

  static Future<CompagnieInvitationCreateResult>
      _createOnlineInvitation({
    required TeamModel team,
    required String inviterName,
    required String inviteeId,
    required String inviteeName,
  }) async {
    final String currentSocialId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (currentSocialId.isEmpty ||
        inviteeId.isEmpty ||
        currentSocialId == inviteeId) {
      return CompagnieInvitationCreateResult.invalid;
    }

    final bool teamReady =
        await TeamStorage.ensureOnline(team);

    if (!teamReady) {
      return CompagnieInvitationCreateResult.invalid;
    }

    try {
      final dynamic response =
          await SupabaseService.client.rpc(
        'project_xp_send_compagnie_invitation',
        params: <String, dynamic>{
          'p_team_id': team.id,
          'p_invitee_id': inviteeId,
          'p_inviter_name':
              inviterName.trim().isEmpty
                  ? 'Joueur'
                  : inviterName.trim(),
          'p_invitee_name':
              inviteeName.trim().isEmpty
                  ? 'Joueur'
                  : inviteeName.trim(),
        },
      );

      final String result =
          response?.toString().trim() ?? '';

      switch (result) {
        case 'success':
          return CompagnieInvitationCreateResult.success;
        case 'not_allowed':
          return CompagnieInvitationCreateResult.notAllowed;
        case 'already_member':
          return CompagnieInvitationCreateResult.alreadyMember;
        case 'team_full':
          return CompagnieInvitationCreateResult.teamFull;
        case 'already_pending':
          return CompagnieInvitationCreateResult.alreadyPending;
        case 'invalid':
        default:
          return CompagnieInvitationCreateResult.invalid;
      }
    } catch (_) {
      return CompagnieInvitationCreateResult.invalid;
    }
  }

  static Future<List<CompagnieTeamInvitation>>
      _loadOnlineVisible() async {
    if (SupabaseService.currentUser == null) {
      return <CompagnieTeamInvitation>[];
    }

    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from(_onlineTable)
              .select()
              .order(
                'created_at',
                ascending: false,
              );

      return response
          .map(
            (dynamic item) =>
                _fromOnlineRow(
              Map<String, dynamic>.from(
                item as Map,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return <CompagnieTeamInvitation>[];
    }
  }

  static Future<List<CompagnieTeamInvitation>>
      _loadOnlineWhere({
    required String column,
    required String value,
  }) async {
    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from(_onlineTable)
              .select()
              .eq(column, value)
              .order(
                'created_at',
                ascending: false,
              );

      return response
          .map(
            (dynamic item) =>
                _fromOnlineRow(
              Map<String, dynamic>.from(
                item as Map,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return <CompagnieTeamInvitation>[];
    }
  }

  static Future<List<CompagnieTeamInvitation>>
      _loadOnlineTeamPending(
    String teamId,
  ) async {
    try {
      final List<dynamic> response =
          await SupabaseService.client
              .from(_onlineTable)
              .select()
              .eq('team_id', teamId)
              .eq('status', 'pending')
              .order(
                'created_at',
                ascending: false,
              );

      return response
          .map(
            (dynamic item) =>
                _fromOnlineRow(
              Map<String, dynamic>.from(
                item as Map,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return <CompagnieTeamInvitation>[];
    }
  }

  static CompagnieTeamInvitation _fromOnlineRow(
    Map<String, dynamic> row,
  ) {
    return CompagnieTeamInvitation(
      id: row['id']?.toString() ?? '',
      teamId:
          row['team_id']?.toString() ?? '',
      teamName:
          row['team_name']?.toString() ?? '',
      inviterId:
          row['inviter_id']?.toString() ?? '',
      inviterName:
          row['inviter_name']?.toString() ??
              'Joueur',
      inviteeId:
          row['invitee_id']?.toString() ?? '',
      inviteeName:
          row['invitee_name']?.toString() ??
              'Joueur',
      status:
          row['status']?.toString() ?? 'pending',
      handledByUserId:
          row['handled_by_user_id']?.toString(),
      createdAt: DateTime.tryParse(
            row['created_at']?.toString() ?? '',
          )?.toLocal() ??
          DateTime.now(),
      handledAt: DateTime.tryParse(
        row['handled_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  // ==========================================================================
  // LEGACY LOCAL
  // ==========================================================================

  static Future<List<CompagnieTeamInvitation>>
      _loadLegacyAll() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    String? raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      final String? legacyRaw =
          prefs.getString(_legacyStorageKey);

      if (legacyRaw != null &&
          legacyRaw.isNotEmpty) {
        await prefs.setString(
          _storageKey,
          legacyRaw,
        );
        raw = legacyRaw;
      }
    }

    if (raw == null || raw.isEmpty) {
      return <CompagnieTeamInvitation>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <CompagnieTeamInvitation>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (Map item) =>
                CompagnieTeamInvitation.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return <CompagnieTeamInvitation>[];
    }
  }

  static Future<bool> _saveLegacyAll(
    List<CompagnieTeamInvitation> invitations,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.setString(
      _storageKey,
      jsonEncode(
        invitations
            .map(
              (CompagnieTeamInvitation invitation) =>
                  invitation.toMap(),
            )
            .toList(),
      ),
    );
  }

  static Future<CompagnieInvitationCreateResult>
      _createLegacyInvitation({
    required TeamModel team,
    required String inviterId,
    required String inviterName,
    required String inviteeId,
    required String inviteeName,
  }) async {
    final String cleanInviterId = inviterId.trim();
    final String cleanInviteeId = inviteeId.trim();
    final String cleanInviterName = inviterName.trim();
    final String cleanInviteeName = inviteeName.trim();

    if (cleanInviterId.isEmpty ||
        cleanInviteeId.isEmpty ||
        cleanInviterId == cleanInviteeId ||
        cleanInviteeName.isEmpty) {
      return CompagnieInvitationCreateResult.invalid;
    }

    final TeamModel? latestTeam =
        await _getLocalTeam(team.id);

    if (latestTeam == null) {
      return CompagnieInvitationCreateResult.invalid;
    }

    if (!latestTeam.canManageTeam(cleanInviterId)) {
      return CompagnieInvitationCreateResult.notAllowed;
    }

    if (latestTeam.memberIds.contains(cleanInviteeId)) {
      return CompagnieInvitationCreateResult.alreadyMember;
    }

    if (latestTeam.memberIds.length >=
        latestTeam.maxMembers) {
      return CompagnieInvitationCreateResult.teamFull;
    }

    final List<CompagnieTeamInvitation> invitations =
        await _loadLegacyAll();

    final bool alreadyPending =
        invitations.any(
      (CompagnieTeamInvitation invitation) =>
          invitation.teamId == latestTeam.id &&
          invitation.inviteeId == cleanInviteeId &&
          invitation.isPending,
    );

    if (alreadyPending) {
      return CompagnieInvitationCreateResult.alreadyPending;
    }

    invitations.add(
      CompagnieTeamInvitation(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
        teamId: latestTeam.id,
        teamName: latestTeam.name,
        inviterId: cleanInviterId,
        inviterName: cleanInviterName.isEmpty
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
        await _saveLegacyAll(invitations);

    return saved
        ? CompagnieInvitationCreateResult.success
        : CompagnieInvitationCreateResult.invalid;
  }

  static Future<TeamModel?> _getLocalTeam(
    String teamId,
  ) async {
    final List<TeamModel> teams =
        await TeamStorage.loadTeams();

    for (final TeamModel team in teams) {
      if (team.id == teamId) {
        return team;
      }
    }

    return null;
  }

  static Future<List<CompagnieTeamInvitation>>
      _legacyIncomingForUser(
    String userId,
  ) async {
    final List<CompagnieTeamInvitation> all =
        await _loadLegacyAll();

    final List<CompagnieTeamInvitation> result =
        all
            .where(
              (CompagnieTeamInvitation invitation) =>
                  invitation.inviteeId == userId,
            )
            .toList();

    result.sort(
      (CompagnieTeamInvitation a,
              CompagnieTeamInvitation b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<List<CompagnieTeamInvitation>>
      _legacyOutgoingForUser(
    String userId,
  ) async {
    final List<CompagnieTeamInvitation> all =
        await _loadLegacyAll();

    final List<CompagnieTeamInvitation> result =
        all
            .where(
              (CompagnieTeamInvitation invitation) =>
                  invitation.inviterId == userId,
            )
            .toList();

    result.sort(
      (CompagnieTeamInvitation a,
              CompagnieTeamInvitation b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<List<CompagnieTeamInvitation>>
      _legacyPendingForTeam(
    String teamId,
  ) async {
    final List<CompagnieTeamInvitation> all =
        await _loadLegacyAll();

    final List<CompagnieTeamInvitation> result =
        all
            .where(
              (CompagnieTeamInvitation invitation) =>
                  invitation.teamId == teamId &&
                  invitation.isPending,
            )
            .toList();

    result.sort(
      (CompagnieTeamInvitation a,
              CompagnieTeamInvitation b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<bool> _legacyHasPendingInvitation({
    required String teamId,
    required String inviteeId,
  }) async {
    final List<CompagnieTeamInvitation> all =
        await _loadLegacyAll();

    return all.any(
      (CompagnieTeamInvitation invitation) =>
          invitation.teamId == teamId &&
          invitation.inviteeId == inviteeId &&
          invitation.isPending,
    );
  }

  static Future<bool> _legacyAcceptInvitation({
    required String invitationId,
    required String inviteeId,
  }) async {
    final List<CompagnieTeamInvitation> invitations =
        await _loadLegacyAll();

    final int index = invitations.indexWhere(
      (CompagnieTeamInvitation invitation) =>
          invitation.id == invitationId,
    );

    if (index == -1) {
      return false;
    }

    final CompagnieTeamInvitation invitation =
        invitations[index];

    if (!invitation.isPending ||
        invitation.inviteeId != inviteeId) {
      return false;
    }

    final TeamModel? team =
        await TeamStorage.getTeam(invitation.teamId);

    if (team == null) {
      return false;
    }

    if (!team.memberIds.contains(inviteeId)) {
      if (team.memberIds.length >=
          team.maxMembers) {
        return false;
      }

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

    invitations[index] = invitation.copyWith(
      status: 'accepted',
      handledByUserId: inviteeId,
      handledAt: DateTime.now(),
    );

    return _saveLegacyAll(invitations);
  }

  static Future<bool> _legacyRejectInvitation({
    required String invitationId,
    required String inviteeId,
  }) async {
    final List<CompagnieTeamInvitation> invitations =
        await _loadLegacyAll();

    final int index = invitations.indexWhere(
      (CompagnieTeamInvitation invitation) =>
          invitation.id == invitationId,
    );

    if (index == -1) {
      return false;
    }

    final CompagnieTeamInvitation invitation =
        invitations[index];

    if (!invitation.isPending ||
        invitation.inviteeId != inviteeId) {
      return false;
    }

    invitations[index] = invitation.copyWith(
      status: 'rejected',
      handledByUserId: inviteeId,
      handledAt: DateTime.now(),
    );

    return _saveLegacyAll(invitations);
  }

  static Future<bool> _legacyCancelInvitation({
    required String invitationId,
    required String requesterId,
  }) async {
    final List<CompagnieTeamInvitation> invitations =
        await _loadLegacyAll();

    final int index = invitations.indexWhere(
      (CompagnieTeamInvitation invitation) =>
          invitation.id == invitationId,
    );

    if (index == -1) {
      return false;
    }

    final CompagnieTeamInvitation invitation =
        invitations[index];

    if (!invitation.isPending) {
      return false;
    }

    final TeamModel? team =
        await TeamStorage.getTeam(invitation.teamId);

    final bool allowed =
        invitation.inviterId == requesterId ||
            (team != null &&
                team.canManageTeam(requesterId));

    if (!allowed) {
      return false;
    }

    invitations[index] = invitation.copyWith(
      status: 'cancelled',
      handledByUserId: requesterId,
      handledAt: DateTime.now(),
    );

    return _saveLegacyAll(invitations);
  }

  static Future<bool> _legacyClosePendingAsAccepted({
    required String teamId,
    required String inviteeId,
    required String handledByUserId,
  }) async {
    final List<CompagnieTeamInvitation> invitations =
        await _loadLegacyAll();

    bool changed = false;

    for (int index = 0;
        index < invitations.length;
        index++) {
      final CompagnieTeamInvitation invitation =
          invitations[index];

      if (invitation.teamId == teamId &&
          invitation.inviteeId == inviteeId &&
          invitation.isPending) {
        invitations[index] = invitation.copyWith(
          status: 'accepted',
          handledByUserId: handledByUserId,
          handledAt: DateTime.now(),
        );
        changed = true;
      }
    }

    if (!changed) {
      return true;
    }

    return _saveLegacyAll(invitations);
  }

  // ==========================================================================
  // OUTILS
  // ==========================================================================

  static List<CompagnieTeamInvitation> _mergeAndSort(
    List<CompagnieTeamInvitation> first,
    List<CompagnieTeamInvitation> second,
  ) {
    final Map<String, CompagnieTeamInvitation> merged =
        <String, CompagnieTeamInvitation>{};

    for (final CompagnieTeamInvitation invitation
        in first) {
      merged[invitation.id] = invitation;
    }

    for (final CompagnieTeamInvitation invitation
        in second) {
      merged[invitation.id] = invitation;
    }

    final List<CompagnieTeamInvitation> result =
        merged.values.toList()
          ..sort(
            (CompagnieTeamInvitation a,
                    CompagnieTeamInvitation b) =>
                b.createdAt.compareTo(a.createdAt),
          );

    return result;
  }

  static bool _isUuid(
    String value,
  ) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }
}
