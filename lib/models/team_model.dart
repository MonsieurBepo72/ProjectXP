class TeamModel {
  final String id;

  final String name;
  final String description;

  final List<String> games;
  final List<String> platforms;

  final int maxMembers;

  /// true = l'équipe peut apparaître dans "Trouver une équipe"
  /// et accepter des demandes pour la rejoindre.
  final bool recruitmentOpen;

  /// Identifiant unique du propriétaire / Chef.
  final String ownerId;

  /// Nom affiché du propriétaire / Chef.
  final String ownerName;

  /// Identifiant du leader historique.
  ///
  /// Dans l'interface Project XP, ce rôle est affiché comme "Admin".
  /// Null = aucun Admin.
  final String? leaderId;

  /// Nom affiché de l'Admin.
  final String? leaderName;

  /// Chemin local ou URL de l'image de l'équipe.
  final String? imagePath;

  /// Identifiants uniques des membres.
  ///
  /// Le propriétaire doit toujours être présent.
  final List<String> memberIds;

  final DateTime createdAt;

  const TeamModel({
    required this.id,
    required this.name,
    required this.description,
    required this.games,
    required this.platforms,
    required this.maxMembers,
    this.recruitmentOpen = true,
    required this.ownerId,
    required this.ownerName,
    required this.leaderId,
    required this.leaderName,
    required this.imagePath,
    required this.memberIds,
    required this.createdAt,
  });

  // ===========================================================================
  // COPIE
  // ===========================================================================

  TeamModel copyWith({
    String? name,
    String? description,
    List<String>? games,
    List<String>? platforms,
    int? maxMembers,
    bool? recruitmentOpen,
    String? ownerId,
    String? ownerName,
    String? leaderId,
    String? leaderName,
    String? imagePath,
    List<String>? memberIds,

    /// Permet explicitement de supprimer l'Admin.
    bool clearLeader = false,

    /// Permet explicitement de supprimer l'image.
    bool clearImagePath = false,
  }) {
    return TeamModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      games: games ?? this.games,
      platforms: platforms ?? this.platforms,
      maxMembers: maxMembers ?? this.maxMembers,
      recruitmentOpen:
          recruitmentOpen ?? this.recruitmentOpen,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      leaderId:
          clearLeader ? null : leaderId ?? this.leaderId,
      leaderName:
          clearLeader ? null : leaderName ?? this.leaderName,
      imagePath:
          clearImagePath ? null : imagePath ?? this.imagePath,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt,
    );
  }

  // ===========================================================================
  // CONVERSION
  // ===========================================================================

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'games': games,
      'platforms': platforms,
      'maxMembers': maxMembers,
      'recruitmentOpen': recruitmentOpen,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'leaderId': leaderId,
      'leaderName': leaderName,
      'imagePath': imagePath,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // ===========================================================================
  // LECTURE
  // ===========================================================================

  factory TeamModel.fromMap(
    Map<String, dynamic> map,
  ) {
    return TeamModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description:
          map['description']?.toString() ?? '',
      games: map['games'] is List
          ? List<String>.from(
              (map['games'] as List).map(
                (e) => e.toString(),
              ),
            )
          : [],
      platforms: map['platforms'] is List
          ? List<String>.from(
              (map['platforms'] as List).map(
                (e) => e.toString(),
              ),
            )
          : [],
      maxMembers: map['maxMembers'] is int
          ? map['maxMembers'] as int
          : 5,

      // Compatibilité avec les équipes déjà enregistrées
      // avant l'ajout du recrutement.
      recruitmentOpen:
          map['recruitmentOpen'] is bool
              ? map['recruitmentOpen'] as bool
              : true,

      ownerId:
          map['ownerId']?.toString() ?? '',
      ownerName:
          map['ownerName']?.toString() ?? '',
      leaderId:
          map['leaderId']?.toString(),
      leaderName:
          map['leaderName']?.toString(),
      imagePath:
          map['imagePath']?.toString(),
      memberIds: map['memberIds'] is List
          ? List<String>.from(
              (map['memberIds'] as List).map(
                (e) => e.toString(),
              ),
            )
          : [],
      createdAt:
          DateTime.tryParse(
            map['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
    );
  }

  // ===========================================================================
  // UTILITAIRES DE RÔLES
  // ===========================================================================

  bool isOwner(
    String userId,
  ) {
    return ownerId == userId;
  }

  bool isLeader(
    String userId,
  ) {
    return leaderId == userId;
  }

  bool isMember(
    String userId,
  ) {
    return memberIds.contains(userId);
  }

  bool canManageTeam(
    String userId,
  ) {
    return isOwner(userId) ||
        isLeader(userId);
  }

  bool canLeave(
    String userId,
  ) {
    if (isOwner(userId)) {
      return false;
    }

    return isMember(userId);
  }

  String roleLabelFor(
    String userId,
  ) {
    if (isOwner(userId)) {
      return 'CHEF';
    }

    if (isLeader(userId)) {
      return 'ADMIN';
    }

    if (isMember(userId)) {
      return 'MEMBRE';
    }

    return '';
  }
}
