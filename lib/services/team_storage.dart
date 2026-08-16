import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/team_model.dart';
import 'auth_service.dart';

class TeamStorage {
  static const String _storageKey = 'teams_data';

  // ===========================================================================
  // CHARGER TOUTES LES ÉQUIPES
  // ===========================================================================

  static Future<List<TeamModel>> loadTeams() async {
    final prefs = await SharedPreferences.getInstance();

    final String? savedData = prefs.getString(_storageKey);

    if (savedData == null || savedData.isEmpty) {
      return [];
    }

    try {
      final dynamic decoded = jsonDecode(savedData);

      if (decoded is! List) {
        return [];
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
      return [];
    }
  }

  // ===========================================================================
  // SAUVEGARDER TOUTES LES ÉQUIPES
  // ===========================================================================

  static Future<bool> saveTeams(
    List<TeamModel> teams,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> data = teams
        .map((team) => team.toMap())
        .toList();

    return prefs.setString(
      _storageKey,
      jsonEncode(data),
    );
  }

  // ===========================================================================
  // AJOUTER UNE ÉQUIPE
  // ===========================================================================

  static Future<bool> addTeam(
    TeamModel team,
  ) async {
    final List<TeamModel> teams = await loadTeams();

    // Empêche la création de deux équipes avec le même ID.
    final bool alreadyExists = teams.any(
      (existingTeam) => existingTeam.id == team.id,
    );

    if (alreadyExists) {
      return false;
    }

    teams.add(team);

    return saveTeams(teams);
  }

  // ===========================================================================
  // MODIFIER UNE ÉQUIPE
  // ===========================================================================

  static Future<bool> updateTeam(
    TeamModel updatedTeam,
  ) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == updatedTeam.id,
    );

    if (index == -1) {
      return false;
    }

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }

  // ===========================================================================
  // RÉCUPÉRER UNE ÉQUIPE
  // ===========================================================================

  static Future<TeamModel?> getTeam(
    String teamId,
  ) async {
    final List<TeamModel> teams = await loadTeams();

    for (final TeamModel team in teams) {
      if (team.id == teamId) {
        return team;
      }
    }

    return null;
  }

  // ===========================================================================
  // TRANSFÉRER LA PROPRIÉTÉ
  // ===========================================================================

  /// Transfère la propriété à un membre de l'équipe.
  ///
  /// L'utilisateur qui effectue l'action doit être le propriétaire actuel.
  ///
  /// Après transfert :
  /// - l'ancien propriétaire devient membre normal ;
  /// - le nouveau propriétaire devient propriétaire ;
  /// - le leader reste inchangé sauf si le nouveau propriétaire était leader.
  static Future<bool> transferOwnership({
    required String teamId,
    required String currentOwnerId,
    required String newOwnerId,
    required String newOwnerName,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Seul le propriétaire actuel peut transférer la propriété.
    if (team.ownerId != currentOwnerId) {
      return false;
    }

    // Le nouveau propriétaire doit être membre de l'équipe.
    if (!team.memberIds.contains(newOwnerId)) {
      return false;
    }

    // Impossible de transférer à soi-même.
    if (newOwnerId == currentOwnerId) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds);

    // Sécurité : l'ancien propriétaire reste membre après le transfert.
    if (!updatedMembers.contains(currentOwnerId)) {
      updatedMembers.add(currentOwnerId);
    }

    // Le nouveau propriétaire doit rester membre.
    if (!updatedMembers.contains(newOwnerId)) {
      updatedMembers.add(newOwnerId);
    }

    // Si le nouveau propriétaire était leader,
    // il n'a plus besoin du rôle de leader.
    final bool newOwnerWasLeader =
        team.leaderId == newOwnerId;

    final TeamModel updatedTeam = team.copyWith(
      ownerId: newOwnerId,
      ownerName: newOwnerName,
      clearLeader: newOwnerWasLeader,
      memberIds: updatedMembers,
    );

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }

  // ===========================================================================
  // NOMMER UN LEADER
  // ===========================================================================

  /// Nomme un membre comme leader.
  ///
  /// Seul le propriétaire peut effectuer cette action.
  static Future<bool> setLeader({
    required String teamId,
    required String ownerId,
    required String leaderId,
    required String leaderName,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Seul le propriétaire peut nommer un leader.
    if (team.ownerId != ownerId) {
      return false;
    }

    // Le leader doit être membre de l'équipe.
    if (!team.memberIds.contains(leaderId)) {
      return false;
    }

    // Le propriétaire n'a pas besoin du rôle de leader.
    if (leaderId == team.ownerId) {
      return false;
    }

    final TeamModel updatedTeam = team.copyWith(
      leaderId: leaderId,
      leaderName: leaderName,
    );

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }

  // ===========================================================================
  // RETIRER LE LEADER
  // ===========================================================================

  /// Retire le rôle de leader.
  ///
  /// Seul le propriétaire peut effectuer cette action.
  static Future<bool> removeLeader({
    required String teamId,
    required String ownerId,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Seul le propriétaire peut retirer le leader.
    if (team.ownerId != ownerId) {
      return false;
    }

    // Aucun leader à retirer.
    if (team.leaderId == null) {
      return false;
    }

    final TeamModel updatedTeam = team.copyWith(
      clearLeader: true,
    );

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }

  // ===========================================================================
  // QUITTER UNE ÉQUIPE
  // ===========================================================================

  /// Permet à un membre ou à un leader de quitter l'équipe.
  ///
  /// Le propriétaire ne peut jamais quitter directement.
  static Future<bool> leaveTeam({
    required String teamId,
    required String userId,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Le propriétaire doit d'abord transférer la propriété
    // ou supprimer l'équipe.
    if (team.ownerId == userId) {
      return false;
    }

    // L'utilisateur doit être membre.
    if (!team.memberIds.contains(userId)) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds);

    updatedMembers.remove(userId);

    // Si le leader quitte l'équipe, son rôle est automatiquement retiré.
    final bool wasLeader = team.leaderId == userId;

    final TeamModel updatedTeam = team.copyWith(
      memberIds: updatedMembers,
      clearLeader: wasLeader,
    );

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }

  // ===========================================================================
  // SUPPRIMER UNE ÉQUIPE
  // ===========================================================================

  /// Supprime définitivement une équipe.
  ///
  /// Seul le propriétaire peut supprimer l'équipe.
  static Future<bool> deleteTeam({
    required String teamId,
    required String ownerId,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Seul le propriétaire peut supprimer l'équipe.
    if (team.ownerId != ownerId) {
      return false;
    }

    teams.removeAt(index);

    return saveTeams(teams);
  }

  // ===========================================================================
  // AJOUTER UN MEMBRE
  // ===========================================================================

  /// Ajoute un utilisateur à une équipe.
  ///
  /// Le propriétaire ou le leader peut effectuer cette action.
  static Future<bool> addMember({
    required String teamId,
    required String requesterId,
    required String memberId,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Propriétaire ou leader uniquement.
    if (!team.canManageTeam(requesterId)) {
      return false;
    }

    // Déjà membre.
    if (team.memberIds.contains(memberId)) {
      return false;
    }

    // Équipe pleine.
    if (team.memberIds.length >= team.maxMembers) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds);

    updatedMembers.add(memberId);

    final TeamModel updatedTeam = team.copyWith(
      memberIds: updatedMembers,
    );

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }

  // ===========================================================================
  // RETIRER UN MEMBRE
  // ===========================================================================

  /// Retire un membre de l'équipe.
  ///
  /// Le propriétaire ou le leader peut effectuer cette action.
  ///
  /// Le propriétaire ne peut jamais être retiré.
  static Future<bool> removeMember({
    required String teamId,
    required String requesterId,
    required String memberId,
  }) async {
    final List<TeamModel> teams = await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    // Propriétaire ou leader uniquement.
    if (!team.canManageTeam(requesterId)) {
      return false;
    }

    // Impossible de retirer le propriétaire.
    if (memberId == team.ownerId) {
      return false;
    }

    // Le membre doit exister.
    if (!team.memberIds.contains(memberId)) {
      return false;
    }

    final List<String> updatedMembers =
        List<String>.from(team.memberIds);

    updatedMembers.remove(memberId);

    // Si le membre était leader, son rôle est retiré.
    final bool wasLeader = team.leaderId == memberId;

    final TeamModel updatedTeam = team.copyWith(
      memberIds: updatedMembers,
      clearLeader: wasLeader,
    );

    teams[index] = updatedTeam;

    return saveTeams(teams);
  }


  // ===========================================================================
  // OUVRIR / FERMER LE RECRUTEMENT
  // ===========================================================================

  /// Modifie l'état du recrutement.
  ///
  /// Le Chef ou l'Admin peut effectuer cette action.
  static Future<bool> setRecruitmentOpen({
    required String teamId,
    required String requesterId,
    required bool isOpen,
  }) async {
    final List<TeamModel> teams =
        await loadTeams();

    final int index = teams.indexWhere(
      (team) => team.id == teamId,
    );

    if (index == -1) {
      return false;
    }

    final TeamModel team = teams[index];

    if (!team.canManageTeam(requesterId)) {
      return false;
    }

    teams[index] = team.copyWith(
      recruitmentOpen: isOpen,
    );

    return saveTeams(teams);
  }


  // ===========================================================================
  // COMPTE ACTIF
  // ===========================================================================

  /// Retourne uniquement les équipes liées au compte actuellement actif.
  ///
  /// L'ID du compte vient toujours d'AuthService.
  static Future<List<TeamModel>>
      loadTeamsForCurrentUser() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.isEmpty) {
      return <TeamModel>[];
    }

    final List<TeamModel> teams =
        await loadTeams();

    return teams.where(
      (team) {
        return team.ownerId == userId ||
            team.memberIds.contains(
              userId,
            );
      },
    ).toList();
  }

  /// Met à jour uniquement le nom affiché du compte actif dans ses équipes.
  ///
  /// Les IDs NE SONT JAMAIS réécrits : cela évite de fusionner deux anciens
  /// comptes ou deux comptes de test par erreur.
  static Future<bool>
      syncCurrentUserDisplayName(
    String username,
  ) async {
    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.isEmpty) {
      return false;
    }

    final String cleanUsername =
        username.trim();

    if (cleanUsername.isEmpty) {
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
        ownerName: isOwner
            ? cleanUsername
            : null,
        leaderName: isLeader
            ? cleanUsername
            : null,
      );

      teams[index] = team;
      changed = true;
    }

    if (!changed) {
      return true;
    }

    return saveTeams(teams);
  }

  // ===========================================================================
  // SUPPRIMER TOUTES LES DONNÉES
  // ===========================================================================
  //
  // Utile pendant le développement.
  // ===========================================================================

  static Future<bool> clearTeams() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.remove(_storageKey);
  }
}