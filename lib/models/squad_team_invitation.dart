class SquadTeamInvitation {
  final String id;

  final String teamId;
  final String teamName;

  final String inviterId;
  final String inviterName;

  final String inviteeId;
  final String inviteeName;

  /// pending / accepted / rejected / cancelled
  final String status;

  final String? handledByUserId;
  final DateTime createdAt;
  final DateTime? handledAt;

  const SquadTeamInvitation({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.inviterId,
    required this.inviterName,
    required this.inviteeId,
    required this.inviteeName,
    required this.status,
    required this.handledByUserId,
    required this.createdAt,
    required this.handledAt,
  });

  bool get isPending =>
      status == 'pending';

  bool get isAccepted =>
      status == 'accepted';

  bool get isRejected =>
      status == 'rejected';

  bool get isCancelled =>
      status == 'cancelled';

  SquadTeamInvitation copyWith({
    String? status,
    String? handledByUserId,
    DateTime? handledAt,
    bool clearHandledBy = false,
    bool clearHandledAt = false,
  }) {
    return SquadTeamInvitation(
      id: id,
      teamId: teamId,
      teamName: teamName,
      inviterId: inviterId,
      inviterName: inviterName,
      inviteeId: inviteeId,
      inviteeName: inviteeName,
      status: status ?? this.status,
      handledByUserId:
          clearHandledBy
              ? null
              : handledByUserId ??
                  this.handledByUserId,
      createdAt: createdAt,
      handledAt:
          clearHandledAt
              ? null
              : handledAt ??
                  this.handledAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'teamId': teamId,
      'teamName': teamName,
      'inviterId': inviterId,
      'inviterName': inviterName,
      'inviteeId': inviteeId,
      'inviteeName': inviteeName,
      'status': status,
      'handledByUserId':
          handledByUserId,
      'createdAt':
          createdAt.toIso8601String(),
      'handledAt':
          handledAt?.toIso8601String(),
    };
  }

  factory SquadTeamInvitation.fromMap(
    Map<String, dynamic> map,
  ) {
    return SquadTeamInvitation(
      id: map['id']?.toString() ?? '',
      teamId:
          map['teamId']?.toString() ?? '',
      teamName:
          map['teamName']?.toString() ?? '',
      inviterId:
          map['inviterId']?.toString() ?? '',
      inviterName:
          map['inviterName']?.toString() ??
              'Joueur',
      inviteeId:
          map['inviteeId']?.toString() ?? '',
      inviteeName:
          map['inviteeName']?.toString() ??
              'Joueur',
      status:
          map['status']?.toString() ??
              'pending',
      handledByUserId:
          map['handledByUserId']
              ?.toString(),
      createdAt:
          DateTime.tryParse(
            map['createdAt']?.toString() ??
                '',
          ) ??
          DateTime.now(),
      handledAt: DateTime.tryParse(
        map['handledAt']?.toString() ?? '',
      ),
    );
  }
}
