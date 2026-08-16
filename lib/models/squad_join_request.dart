class SquadJoinRequest {
  final String id;

  final String teamId;
  final String teamName;

  final String requesterId;
  final String requesterName;

  /// Chef + Admin pouvant traiter la demande.
  final List<String> recipientIds;

  /// pending / accepted / rejected
  final String status;

  /// Utilisateur ayant accepté/refusé.
  final String? handledByUserId;

  /// Évite de renvoyer la même notification Android
  /// à chaque ouverture du Hall.
  final List<String> androidNotifiedUserIds;

  final DateTime createdAt;
  final DateTime? handledAt;

  const SquadJoinRequest({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.requesterId,
    required this.requesterName,
    required this.recipientIds,
    required this.status,
    required this.handledByUserId,
    required this.androidNotifiedUserIds,
    required this.createdAt,
    required this.handledAt,
  });

  bool get isPending =>
      status == 'pending';

  bool get isAccepted =>
      status == 'accepted';

  bool get isRejected =>
      status == 'rejected';

  SquadJoinRequest copyWith({
    List<String>? recipientIds,
    String? status,
    String? handledByUserId,
    List<String>? androidNotifiedUserIds,
    DateTime? handledAt,
    bool clearHandledBy = false,
    bool clearHandledAt = false,
  }) {
    return SquadJoinRequest(
      id: id,
      teamId: teamId,
      teamName: teamName,
      requesterId: requesterId,
      requesterName: requesterName,
      recipientIds:
          recipientIds ?? this.recipientIds,
      status:
          status ?? this.status,
      handledByUserId: clearHandledBy
          ? null
          : handledByUserId ??
              this.handledByUserId,
      androidNotifiedUserIds:
          androidNotifiedUserIds ??
              this.androidNotifiedUserIds,
      createdAt: createdAt,
      handledAt: clearHandledAt
          ? null
          : handledAt ??
              this.handledAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'teamId': teamId,
      'teamName': teamName,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'recipientIds': recipientIds,
      'status': status,
      'handledByUserId': handledByUserId,
      'androidNotifiedUserIds':
          androidNotifiedUserIds,
      'createdAt':
          createdAt.toIso8601String(),
      'handledAt':
          handledAt?.toIso8601String(),
    };
  }

  factory SquadJoinRequest.fromMap(
    Map<String, dynamic> map,
  ) {
    return SquadJoinRequest(
      id:
          map['id']?.toString() ?? '',
      teamId:
          map['teamId']?.toString() ?? '',
      teamName:
          map['teamName']?.toString() ?? '',
      requesterId:
          map['requesterId']?.toString() ??
              '',
      requesterName:
          map['requesterName']?.toString() ??
              'Joueur',
      recipientIds:
          map['recipientIds'] is List
              ? List<String>.from(
                  (map['recipientIds']
                          as List)
                      .map(
                    (e) =>
                        e.toString(),
                  ),
                )
              : <String>[],
      status:
          map['status']?.toString() ??
              'pending',
      handledByUserId:
          map['handledByUserId']
              ?.toString(),
      androidNotifiedUserIds:
          map['androidNotifiedUserIds']
                  is List
              ? List<String>.from(
                  (map['androidNotifiedUserIds']
                          as List)
                      .map(
                    (e) =>
                        e.toString(),
                  ),
                )
              : <String>[],
      createdAt:
          DateTime.tryParse(
            map['createdAt']
                    ?.toString() ??
                '',
          ) ??
          DateTime.now(),
      handledAt:
          DateTime.tryParse(
        map['handledAt']?.toString() ??
            '',
      ),
    );
  }
}
