import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/compagnie_join_request.dart';
import '../models/team_model.dart';
import 'auth_service.dart';
import 'compagnie_invitation_storage.dart';
import 'team_storage.dart';

class CompagnieRequestStorage {
  static const String _storageKey =
      'project_xp_compagnie_join_requests';

  // Compatibilite : copie une seule fois les anciennes donnees Squad.
  static const String _legacyStorageKey =
      'project_xp_squad_join_requests';

  // ===========================================================================
  // CHARGEMENT / SAUVEGARDE
  // ===========================================================================

  static Future<List<CompagnieJoinRequest>>
      loadAll() async {
    final SharedPreferences prefs =
        await SharedPreferences
            .getInstance();

    String? raw =
        prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      final String? legacyRaw =
          prefs.getString(_legacyStorageKey);

      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        await prefs.setString(
          _storageKey,
          legacyRaw,
        );

        raw = legacyRaw;
      }
    }

    if (raw == null ||
        raw.isEmpty) {
      return <CompagnieJoinRequest>[];
    }

    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is! List) {
        return <CompagnieJoinRequest>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                CompagnieJoinRequest
                    .fromMap(
              Map<String, dynamic>.from(
                item,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return <CompagnieJoinRequest>[];
    }
  }

  static Future<bool> _saveAll(
    List<CompagnieJoinRequest> requests,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences
            .getInstance();

    return prefs.setString(
      _storageKey,
      jsonEncode(
        requests
            .map(
              (request) =>
                  request.toMap(),
            )
            .toList(),
      ),
    );
  }

  // ===========================================================================
  // CRÉER UNE DEMANDE
  // ===========================================================================

  static Future<bool> createRequest({
    required TeamModel team,
    required String requesterId,
    required String requesterName,
  }) async {
    if (requesterId.isEmpty ||
        team.ownerId == requesterId ||
        team.memberIds.contains(
          requesterId,
        ) ||
        !team.recruitmentOpen ||
        team.memberIds.length >=
            team.maxMembers) {
      return false;
    }

    final bool invitationPending =
        await CompagnieInvitationStorage
            .hasPendingInvitation(
      teamId: team.id,
      inviteeId: requesterId,
    );

    if (invitationPending) {
      return false;
    }

    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    final bool alreadyPending =
        requests.any(
      (request) =>
          request.teamId == team.id &&
          request.requesterId ==
              requesterId &&
          request.isPending,
    );

    if (alreadyPending) {
      return false;
    }

    final List<String> recipients =
        <String>[
      team.ownerId,
      if (team.leaderId != null &&
          team.leaderId!.isNotEmpty &&
          team.leaderId !=
              team.ownerId)
        team.leaderId!,
    ];

    String resolvedRequesterName =
        requesterName.trim();

    final String? activeUserId =
        await AuthService.getCurrentUserId();

    if (activeUserId == requesterId) {
      final String? activeUsername =
          await AuthService.getCurrentUsername();

      if (activeUsername != null &&
          activeUsername.trim().isNotEmpty) {
        resolvedRequesterName =
            activeUsername.trim();
      }
    }

    if (resolvedRequesterName.isEmpty) {
      resolvedRequesterName =
          'Joueur';
    }

    final CompagnieJoinRequest request =
        CompagnieJoinRequest(
      id: DateTime.now()
          .microsecondsSinceEpoch
          .toString(),
      teamId: team.id,
      teamName: team.name,
      requesterId: requesterId,
      requesterName:
          resolvedRequesterName,
      recipientIds: recipients,
      status: 'pending',
      handledByUserId: null,
      androidNotifiedUserIds:
          const <String>[],
      createdAt: DateTime.now(),
      handledAt: null,
    );

    requests.add(request);

    return _saveAll(requests);
  }

  // ===========================================================================
  // LECTURE
  // ===========================================================================

  static Future<List<CompagnieJoinRequest>>
      incomingForUser(
    String userId,
  ) async {
    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    final List<CompagnieJoinRequest> result =
        requests
            .where(
              (request) =>
                  request.recipientIds
                      .contains(userId),
            )
            .toList();

    result.sort(
      (a, b) =>
          b.createdAt.compareTo(
        a.createdAt,
      ),
    );

    return result;
  }

  static Future<List<CompagnieJoinRequest>>
      pendingIncomingForUser(
    String userId,
  ) async {
    final List<CompagnieJoinRequest> all =
        await incomingForUser(
      userId,
    );

    return all
        .where(
          (request) =>
              request.isPending,
        )
        .toList();
  }

  static Future<List<CompagnieJoinRequest>>
      outgoingForUser(
    String userId,
  ) async {
    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    final List<CompagnieJoinRequest> result =
        requests
            .where(
              (request) =>
                  request.requesterId ==
                  userId,
            )
            .toList();

    result.sort(
      (a, b) =>
          b.createdAt.compareTo(
        a.createdAt,
      ),
    );

    return result;
  }

  static Future<List<CompagnieJoinRequest>>
      pendingForTeam(
    String teamId,
  ) async {
    final List<CompagnieJoinRequest> requests =
        await loadAll();

    final List<CompagnieJoinRequest> result =
        requests
            .where(
              (request) =>
                  request.teamId == teamId &&
                  request.isPending,
            )
            .toList();

    result.sort(
      (a, b) =>
          b.createdAt.compareTo(a.createdAt),
    );

    return result;
  }

  static Future<bool> hasPendingRequest({
    required String teamId,
    required String requesterId,
  }) async {
    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    return requests.any(
      (request) =>
          request.teamId == teamId &&
          request.requesterId ==
              requesterId &&
          request.isPending,
    );
  }

  // ===========================================================================
  // ACCEPTER
  // ===========================================================================

  static Future<bool> acceptRequest({
    required String requestId,
    required String handlerUserId,
  }) async {
    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    final int index =
        requests.indexWhere(
      (request) =>
          request.id == requestId,
    );

    if (index == -1) {
      return false;
    }

    final CompagnieJoinRequest request =
        requests[index];

    if (!request.isPending ||
        !request.recipientIds
            .contains(handlerUserId)) {
      return false;
    }

    final TeamModel? team =
        await TeamStorage.getTeam(
      request.teamId,
    );

    if (team == null ||
        !team.canManageTeam(
          handlerUserId,
        ) ||
        team.memberIds.length >=
            team.maxMembers) {
      return false;
    }

    // Si le joueur a été ajouté autrement entre-temps,
    // on considère la demande comme acceptée.
    if (!team.memberIds.contains(
      request.requesterId,
    )) {
      final bool added =
          await TeamStorage.addMember(
        teamId: team.id,
        requesterId:
            handlerUserId,
        memberId:
            request.requesterId,
      );

      if (!added) {
        return false;
      }
    }

    requests[index] =
        request.copyWith(
      status: 'accepted',
      handledByUserId:
          handlerUserId,
      handledAt: DateTime.now(),
    );

    final bool requestSaved =
        await _saveAll(requests);

    if (!requestSaved) {
      return false;
    }

    await CompagnieInvitationStorage
        .closePendingAsAccepted(
      teamId: request.teamId,
      inviteeId: request.requesterId,
      handledByUserId: handlerUserId,
    );

    return true;
  }

  // ===========================================================================
  // REFUSER
  // ===========================================================================

  static Future<bool> rejectRequest({
    required String requestId,
    required String handlerUserId,
  }) async {
    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    final int index =
        requests.indexWhere(
      (request) =>
          request.id == requestId,
    );

    if (index == -1) {
      return false;
    }

    final CompagnieJoinRequest request =
        requests[index];

    if (!request.isPending ||
        !request.recipientIds
            .contains(handlerUserId)) {
      return false;
    }

    requests[index] =
        request.copyWith(
      status: 'rejected',
      handledByUserId:
          handlerUserId,
      handledAt: DateTime.now(),
    );

    return _saveAll(requests);
  }

  // ===========================================================================
  // NOTIFICATION ANDROID DÉJÀ ENVOYÉE
  // ===========================================================================

  static Future<bool>
      markAndroidNotified({
    required String requestId,
    required String userId,
  }) async {
    final List<CompagnieJoinRequest>
        requests =
        await loadAll();

    final int index =
        requests.indexWhere(
      (request) =>
          request.id == requestId,
    );

    if (index == -1) {
      return false;
    }

    final CompagnieJoinRequest request =
        requests[index];

    if (request.androidNotifiedUserIds
        .contains(userId)) {
      return true;
    }

    final List<String> updated =
        List<String>.from(
      request.androidNotifiedUserIds,
    )..add(userId);

    requests[index] =
        request.copyWith(
      androidNotifiedUserIds:
          updated,
    );

    return _saveAll(requests);
  }

  // ===========================================================================
  // DEBUG
  // ===========================================================================

  static Future<bool> clearAll() async {
    final SharedPreferences prefs =
        await SharedPreferences
            .getInstance();

    return prefs.remove(
      _storageKey,
    );
  }
}
