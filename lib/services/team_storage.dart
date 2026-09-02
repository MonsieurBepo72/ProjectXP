import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/team_model.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

class TeamStorage {
  static const String _storageKey = 'teams_data';
  static const String _onlineTable = 'compagnie_online_teams';

  // ==========================================================================
  // CACHE LOCAL
  // ==========================================================================

  static Future<List<TeamModel>> _loadLocalTeams() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? savedData =
        prefs.getString(_storageKey);

    if (savedData == null || savedData.isEmpty) {
      return <TeamModel>[];
    }

    try {
      final dynamic decoded =
          jsonDecode(savedData);

      if (decoded is! List) {
        return <TeamModel>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => TeamModel.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return <TeamModel>[];
    }
  }

  static Future<bool> _saveLocalTeams(
    List<TeamModel> teams,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.setString(
      _storageKey,
      jsonEncode(
        teams
            .map(
              (TeamModel team) => team.toMap(),
            )
            .toList(),
      ),
    );
  }

  // ==========================================================================
  // CHARGEMENT
  //
  // SharedPreferences reste un cache de compatibilité. Supabase devient la
  // couche commune uniquement pour les équipes du joueur courant : cela rend
  // les invitations cross-device possibles sans ouvrir encore la recherche
  // d'équipes distante.
  // ==========================================================================

  static Future<List<TeamModel>> loadTeams() async {
    final List<TeamModel> localTeams =
        await _loadLocalTeams();

    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (localUserId.isEmpty ||
        socialUserId.isEmpty) {
      return localTeams;
    }

    try {
      // Première migration douce : les équipes locales dont le compte actif
      // est Chef sont créées en ligne. Les anciens membres purement locaux ne
      // sont jamais inventés comme identités Supabase.
      for (final TeamModel team in localTeams) {
        if (team.ownerId == localUserId) {
          await _syncTeamOnline(
            team,
            localUserId: localUserId,
            socialUserId: socialUserId,
          );
        }
      }

      final List<dynamic> response =
          await SupabaseService.client
              .from(_onlineTable)
              .select()
              .order(
                'created_at',
                ascending: true,
              );

      final List<TeamModel> onlineTeams =
          response
              .map(
                (dynamic item) =>
                    _teamFromOnlineRow(
                  Map<String, dynamic>.from(
                    item as Map,
                  ),
                  localUserId: localUserId,
                  socialUserId: socialUserId,
                ),
              )
              .where(
                (TeamModel team) =>
                    team.id.isNotEmpty,
              )
              .toList();

      final Map<String, TeamModel> merged =
          <String, TeamModel>{
        for (final TeamModel team in localTeams)
          team.id: team,
      };

      // La version Supabase gagne pour les identités online, mais on conserve
      // les anciens membres purement locaux déjà présents sur cet appareil.
      // Ainsi, la migration des invitations n'efface aucune donnée historique.
      for (final TeamModel onlineTeam in onlineTeams) {
        final TeamModel? localTeam =
            merged[onlineTeam.id];

        if (localTeam == null) {
          merged[onlineTeam.id] = onlineTeam;
          continue;
        }

        final List<String> legacyLocalMembers =
            localTeam.memberIds
                .where(
                  (String memberId) =>
                      memberId != localUserId &&
                      !_isUuid(memberId),
                )
                .toList();

        final List<String> combinedMembers =
            <String>{
          ...onlineTeam.memberIds,
          ...legacyLocalMembers,
        }.toList();

        final bool keepLegacyLeader =
            onlineTeam.leaderId == null &&
                localTeam.leaderId != null &&
                localTeam.leaderId != localUserId &&
                !_isUuid(localTeam.leaderId!);

        merged[onlineTeam.id] =
            onlineTeam.copyWith(
          memberIds: combinedMembers,
          leaderId: keepLegacyLeader
              ? localTeam.leaderId
              : null,
          leaderName: keepLegacyLeader
              ? localTeam.leaderName
              : null,
        );
      }

      final List<TeamModel> result =
          merged.values.toList()
            ..sort(
              (TeamModel a, TeamModel b) =>
                  a.createdAt.compareTo(b.createdAt),
            );

      await _saveLocalTeams(result);

      // Les membres arrivés depuis Supabase utilisent leur UUID social. Les
      // anciens écrans d'équipe résolvent encore les pseudos via AuthService.
      // On enrichit donc uniquement les stubs legacy locaux avec le vrai
      // display_name public, sans transformer ces profils distants en comptes
      // de connexion locaux.
      await _cacheRemoteMemberDisplayNames(
        result,
      );

      return result;
    } catch (_) {
      // Si Supabase est momentanément indisponible, l'ancien comportement
      // local reste utilisable.
      return localTeams;
    }
  }

  static Future<bool> saveTeams(
    List<TeamModel> teams,
  ) {
    return _saveLocalTeams(teams);
  }

  // ==========================================================================
  // SYNCHRONISATION D'UNE ÉQUIPE VERS SUPABASE
  // ==========================================================================

  static Future<bool> ensureOnline(
    TeamModel team,
  ) async {
    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (localUserId.isEmpty ||
        socialUserId.isEmpty) {
      return false;
    }

    try {
      return await _syncTeamOnline(
        team,
        localUserId: localUserId,
        socialUserId: socialUserId,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _syncTeamOnline(
    TeamModel team, {
    required String localUserId,
    required String socialUserId,
  }) async {
    final String? ownerId =
        _toSocialId(
      team.ownerId,
      localUserId: localUserId,
      socialUserId: socialUserId,
    );

    if (ownerId == null) {
      return false;
    }

    final String? leaderId =
        team.leaderId == null
            ? null
            : _toSocialId(
                team.leaderId!,
                localUserId: localUserId,
                socialUserId: socialUserId,
              );

    final Set<String> memberIds =
        <String>{};

    for (final String memberId
        in team.memberIds) {
      final String? mapped =
          _toSocialId(
        memberId,
        localUserId: localUserId,
        socialUserId: socialUserId,
      );

      if (mapped != null) {
        memberIds.add(mapped);
      }
    }

    memberIds.add(ownerId);

    final dynamic response =
        await SupabaseService.client.rpc(
      'project_xp_sync_compagnie_team',
      params: <String, dynamic>{
        'p_team': <String, dynamic>{
          'id': team.id,
          'name': team.name,
          'description': team.description,
          'games': team.games,
          'platforms': team.platforms,
          'max_members': team.maxMembers,
          'recruitment_open': team.recruitmentOpen,
          'owner_id': ownerId,
          'owner_name': team.ownerName,
          'leader_id': leaderId,
          'leader_name': team.leaderName,
          'image_path': team.imagePath,
          'member_ids': memberIds.toList(),
          'created_at': team.createdAt
              .toUtc()
              .toIso8601String(),
        },
      },
    );

    return response == true ||
        response?.toString() == 'true';
  }

  static TeamModel _teamFromOnlineRow(
    Map<String, dynamic> row, {
    required String localUserId,
    required String socialUserId,
  }) {
    String mapForCurrentDevice(
      String value,
    ) {
      return value == socialUserId
          ? localUserId
          : value;
    }

    final String onlineOwnerId =
        row['owner_id']?.toString().trim() ?? '';

    final String onlineLeaderId =
        row['leader_id']?.toString().trim() ?? '';

    final List<String> onlineMembers =
        _readStringList(
      row['member_ids'],
    );

    final List<String> mappedMembers =
        onlineMembers
            .map(mapForCurrentDevice)
            .toSet()
            .toList();

    final String mappedOwnerId =
        mapForCurrentDevice(onlineOwnerId);

    if (mappedOwnerId.isNotEmpty &&
        !mappedMembers.contains(mappedOwnerId)) {
      mappedMembers.add(mappedOwnerId);
    }

    return TeamModel(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      description:
          row['description']?.toString() ?? '',
      games: _readStringList(row['games']),
      platforms:
          _readStringList(row['platforms']),
      maxMembers:
          _readInt(row['max_members'], 5),
      recruitmentOpen:
          row['recruitment_open'] is bool
              ? row['recruitment_open'] as bool
              : true,
      ownerId: mappedOwnerId,
      ownerName:
          row['owner_name']?.toString() ?? 'Joueur',
      leaderId: onlineLeaderId.isEmpty
          ? null
          : mapForCurrentDevice(onlineLeaderId),
      leaderName:
          row['leader_name']?.toString(),
      imagePath:
          row['image_path']?.toString(),
      memberIds: mappedMembers,
      createdAt: DateTime.tryParse(
            row['created_at']?.toString() ?? '',
          )?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String? _toSocialId(
    String rawId, {
    required String localUserId,
    required String socialUserId,
  }) {
    final String cleanId = rawId.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    if (cleanId == localUserId) {
      return socialUserId;
    }

    if (_isUuid(cleanId)) {
      return cleanId;
    }

    return null;
  }

  static bool _isUuid(
    String value,
  ) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }

  static List<String> _readStringList(
    dynamic value,
  ) {
    if (value is! List) {
      return <String>[];
    }

    return value
        .map(
          (dynamic item) =>
              item.toString().trim(),
        )
        .where(
          (String item) => item.isNotEmpty,
        )
        .toList();
  }

  static int _readInt(
    dynamic value,
    int fallback,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        fallback;
  }

  static Future<void> _cacheRemoteMemberDisplayNames(
    List<TeamModel> teams,
  ) async {
    if (SupabaseService.currentUser == null) {
      return;
    }

    final Set<String> remoteIds =
        <String>{};

    for (final TeamModel team in teams) {
      for (final String memberId in team.memberIds) {
        if (_isUuid(memberId)) {
          remoteIds.add(memberId.trim());
        }
      }

      final String? leaderId = team.leaderId;

      if (leaderId != null && _isUuid(leaderId)) {
        remoteIds.add(leaderId.trim());
      }

      if (_isUuid(team.ownerId)) {
        remoteIds.add(team.ownerId.trim());
      }
    }

    if (remoteIds.isEmpty) {
      return;
    }

    try {
      final List<dynamic> profiles =
          await SupabaseService.client
              .from('tavern_profiles')
              .select('id, display_name')
              .inFilter(
                'id',
                remoteIds.toList(),
              );

      if (profiles.isEmpty) {
        return;
      }

      final Map<String, String> namesById =
          <String, String>{};

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

      if (namesById.isEmpty) {
        return;
      }

      await AuthService.initialize();

      final SharedPreferences prefs =
          await SharedPreferences.getInstance();

      const String accountsKey =
          'project_xp_accounts_v2';

      final String raw =
          prefs.getString(accountsKey) ?? '[]';

      List<Map<String, dynamic>> accounts =
          <Map<String, dynamic>>[];

      try {
        final dynamic decoded =
            jsonDecode(raw);

        if (decoded is List) {
          accounts = decoded
              .whereType<Map>()
              .map(
                (Map item) =>
                    Map<String, dynamic>.from(item),
              )
              .toList();
        }
      } catch (_) {
        return;
      }

      bool changed = false;

      for (final MapEntry<String, String> entry
          in namesById.entries) {
        final int index = accounts.indexWhere(
          (Map<String, dynamic> account) =>
              account['id']?.toString().trim() ==
              entry.key,
        );

        if (index >= 0) {
          final Map<String, dynamic> account =
              Map<String, dynamic>.from(
            accounts[index],
          );

          final bool isLegacy =
              account['legacy'] == true ||
              (account['email']
                          ?.toString()
                          .trim() ??
                      '')
                  .isEmpty;

          if (!isLegacy) {
            continue;
          }

          if (account['username']
                  ?.toString()
                  .trim() !=
              entry.value) {
            account['username'] = entry.value;
            account['legacy'] = true;
            accounts[index] = account;
            changed = true;
          }

          continue;
        }

        accounts.add(
          <String, dynamic>{
            'id': entry.key,
            'username': entry.value,
            'email': '',
            'legacy': true,
            'createdAt':
                DateTime.now().toIso8601String(),
          },
        );

        changed = true;
      }

      if (changed) {
        await prefs.setString(
          accountsKey,
          jsonEncode(accounts),
        );
      }
    } catch (_) {
      // Un pseudo distant indisponible ne doit jamais bloquer les équipes.
    }
  }

  static Future<void> _callRemoteBool(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    if (SupabaseService.currentUser == null) {
      return;
    }

    try {
      await SupabaseService.client.rpc(
        functionName,
        params: params,
      );
    } catch (_) {
      // Le cache local continue de fonctionner si la partie online n'est pas
      // encore installée ou si le réseau est indisponible.
    }
  }

  static Future<String?> _mapIdForRemote(
    String id,
  ) async {
    final String localUserId =
        (await AuthService.getCurrentUserId())?.trim() ?? '';

    final String socialUserId =
        SupabaseService.currentUser?.id.trim() ?? '';

    if (localUserId.isEmpty ||
        socialUserId.isEmpty) {
      return null;
    }

    return _toSocialId(
      id,
      localUserId: localUserId,
      socialUserId: socialUserId,
    );
  }

  // ==========================================================================
  // AJOUT / MODIFICATION / LECTURE
  // ==========================================================================

  static Future<bool> addTeam(
    TeamModel team,
  ) async {
    final List<TeamModel> teams =
        await _loadLocalTeams();

    if (teams.any(
      (TeamModel existingTeam) =>
          existingTeam.id == team.id,
    )) {
      return false;
    }

    teams.add(team);

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await ensureOnline(team);
    }

    return saved;
  }

  static Future<bool> updateTeam(
    TeamModel updatedTeam,
  ) async {
    final List<TeamModel> teams =
        await _loadLocalTeams();

    final int index = teams.indexWhere(
      (TeamModel team) =>
          team.id == updatedTeam.id,
    );

    if (index == -1) {
      return false;
    }

    teams[index] = updatedTeam;

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await ensureOnline(updatedTeam);
    }

    return saved;
  }

  static Future<TeamModel?> getTeam(
    String teamId,
  ) async {
    final List<TeamModel> teams =
        await loadTeams();

    for (final TeamModel team in teams) {
      if (team.id == teamId) {
        return team;
      }
    }

    return null;
  }

  // ==========================================================================
  // RÔLES
  // ==========================================================================

  static Future<bool> transferOwnership({
    required String teamId,
    required String currentOwnerId,
    required String newOwnerId,
    required String newOwnerName,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (team.ownerId != currentOwnerId ||
        !team.memberIds.contains(newOwnerId) ||
        newOwnerId == currentOwnerId) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds);

    if (!updatedMembers.contains(currentOwnerId)) {
      updatedMembers.add(currentOwnerId);
    }

    if (!updatedMembers.contains(newOwnerId)) {
      updatedMembers.add(newOwnerId);
    }

    final TeamModel updatedTeam =
        team.copyWith(
      ownerId: newOwnerId,
      ownerName: newOwnerName,
      clearLeader:
          team.leaderId == newOwnerId,
      memberIds: updatedMembers,
    );

    teams[index] = updatedTeam;

    final bool saved =
        await _saveLocalTeams(teams);

    final String? remoteNewOwnerId =
        await _mapIdForRemote(newOwnerId);

    if (saved && remoteNewOwnerId != null) {
      await _callRemoteBool(
        'project_xp_transfer_compagnie_ownership',
        <String, dynamic>{
          'p_team_id': teamId,
          'p_new_owner_id': remoteNewOwnerId,
          'p_new_owner_name': newOwnerName,
        },
      );
    }

    return saved;
  }

  static Future<bool> setLeader({
    required String teamId,
    required String ownerId,
    required String leaderId,
    required String leaderName,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (team.ownerId != ownerId ||
        !team.memberIds.contains(leaderId) ||
        leaderId == team.ownerId) {
      return false;
    }

    teams[index] = team.copyWith(
      leaderId: leaderId,
      leaderName: leaderName,
    );

    final bool saved =
        await _saveLocalTeams(teams);

    final String? remoteLeaderId =
        await _mapIdForRemote(leaderId);

    if (saved && remoteLeaderId != null) {
      await _callRemoteBool(
        'project_xp_set_compagnie_leader',
        <String, dynamic>{
          'p_team_id': teamId,
          'p_leader_id': remoteLeaderId,
          'p_leader_name': leaderName,
        },
      );
    }

    return saved;
  }

  static Future<bool> removeLeader({
    required String teamId,
    required String ownerId,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (team.ownerId != ownerId ||
        team.leaderId == null) {
      return false;
    }

    teams[index] = team.copyWith(
      clearLeader: true,
    );

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await _callRemoteBool(
        'project_xp_remove_compagnie_leader',
        <String, dynamic>{
          'p_team_id': teamId,
        },
      );
    }

    return saved;
  }

  // ==========================================================================
  // MEMBRES
  // ==========================================================================

  static Future<bool> leaveTeam({
    required String teamId,
    required String userId,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (team.ownerId == userId ||
        !team.memberIds.contains(userId)) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds)
          ..remove(userId);

    teams[index] = team.copyWith(
      memberIds: updatedMembers,
      clearLeader: team.leaderId == userId,
    );

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await _callRemoteBool(
        'project_xp_leave_compagnie_team',
        <String, dynamic>{
          'p_team_id': teamId,
        },
      );
    }

    return saved;
  }

  static Future<bool> deleteTeam({
    required String teamId,
    required String ownerId,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1 ||
        teams[index].ownerId != ownerId) {
      return false;
    }

    teams.removeAt(index);

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await _callRemoteBool(
        'project_xp_delete_compagnie_team',
        <String, dynamic>{
          'p_team_id': teamId,
        },
      );
    }

    return saved;
  }

  static Future<bool> addMember({
    required String teamId,
    required String requesterId,
    required String memberId,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (!team.canManageTeam(requesterId) ||
        team.memberIds.contains(memberId) ||
        team.memberIds.length >= team.maxMembers) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds)
          ..add(memberId);

    teams[index] = team.copyWith(
      memberIds: updatedMembers,
    );

    final bool saved =
        await _saveLocalTeams(teams);

    final String? remoteMemberId =
        await _mapIdForRemote(memberId);

    if (saved && remoteMemberId != null) {
      await _callRemoteBool(
        'project_xp_add_compagnie_member',
        <String, dynamic>{
          'p_team_id': teamId,
          'p_member_id': remoteMemberId,
        },
      );
    }

    return saved;
  }

  static Future<bool> removeMember({
    required String teamId,
    required String requesterId,
    required String memberId,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (!team.canManageTeam(requesterId) ||
        memberId == team.ownerId ||
        !team.memberIds.contains(memberId)) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds)
          ..remove(memberId);

    teams[index] = team.copyWith(
      memberIds: updatedMembers,
      clearLeader: team.leaderId == memberId,
    );

    final bool saved =
        await _saveLocalTeams(teams);

    final String? remoteMemberId =
        await _mapIdForRemote(memberId);

    if (saved && remoteMemberId != null) {
      await _callRemoteBool(
        'project_xp_remove_compagnie_member',
        <String, dynamic>{
          'p_team_id': teamId,
          'p_member_id': remoteMemberId,
        },
      );
    }

    return saved;
  }

  // ==========================================================================
  // RECRUTEMENT
  // ==========================================================================

  static Future<bool> setRecruitmentOpen({
    required String teamId,
    required String requesterId,
    required bool isOpen,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (TeamModel team) => team.id == teamId,
    );

    if (index == -1 ||
        !teams[index].canManageTeam(requesterId)) {
      return false;
    }

    teams[index] = teams[index].copyWith(
      recruitmentOpen: isOpen,
    );

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await _callRemoteBool(
        'project_xp_set_compagnie_recruitment',
        <String, dynamic>{
          'p_team_id': teamId,
          'p_is_open': isOpen,
        },
      );
    }

    return saved;
  }

  // ==========================================================================
  // COMPTE ACTIF
  // ==========================================================================

  static Future<List<TeamModel>>
      loadTeamsForCurrentUser() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty) {
      return <TeamModel>[];
    }

    final List<TeamModel> teams =
        await loadTeams();

    return teams.where(
      (TeamModel team) {
        return team.ownerId == userId ||
            team.memberIds.contains(userId);
      },
    ).toList();
  }

  static Future<bool> syncCurrentUserDisplayName(
    String username,
  ) async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty ||
        username.trim().isEmpty) {
      return false;
    }

    final List<TeamModel> teams =
        await loadTeams();

    bool changed = false;

    for (int index = 0;
        index < teams.length;
        index++) {
      TeamModel team = teams[index];

      final bool isOwner =
          team.ownerId == userId;

      final bool isLeader =
          team.leaderId == userId;

      if (!isOwner && !isLeader) {
        continue;
      }

      team = team.copyWith(
        ownerName:
            isOwner ? username.trim() : null,
        leaderName:
            isLeader ? username.trim() : null,
      );

      teams[index] = team;
      changed = true;
    }

    if (!changed) {
      return true;
    }

    final bool saved =
        await _saveLocalTeams(teams);

    if (saved) {
      await _callRemoteBool(
        'project_xp_update_compagnie_display_name',
        <String, dynamic>{
          'p_display_name': username.trim(),
        },
      );
    }

    return saved;
  }

  static Future<bool> clearTeams() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.remove(_storageKey);
  }
}
