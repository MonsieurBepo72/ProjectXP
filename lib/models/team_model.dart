import 'package:flutter/foundation.dart';

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
  // TODO: Enforcer l'invariant ownerId ∈ memberIds (constructeur + fromMap)
  final List<String> memberIds;

  final DateTime createdAt;

  TeamModel({
    required this.id,
    required this.name,
    required this.description,
    required List<String> games,
    required List<String> platforms,
    required this.maxMembers,
    this.recruitmentOpen = true,
    required this.ownerId,
    required this.ownerName,
    required this.leaderId,
    required this.leaderName,
    required this.imagePath,
    required List<String> memberIds,
    required this.createdAt,
  }) : games = List.unmodifiable(games),
       platforms = List.unmodifiable(platforms),
       memberIds = List.unmodifiable(memberIds);

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
      games: games != null ? List.unmodifiable(games) : this.games,
      platforms: platforms != null ? List.unmodifiable(platforms) : this.platforms,
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
      memberIds: memberIds != null ? List.unmodifiable(memberIds) : this.memberIds,
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
    final id = map['id']?.toString() ?? '';
    final name = map['name']?.toString() ?? '';
    final createdAt = DateTime.tryParse(
          map['createdAt']?.toString() ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final maxMembers = map['maxMembers'] is int
        ? map['maxMembers'] as int
        : 5;

    if (id.isEmpty) {
      debugPrint('⚠️ TeamModel.fromMap: id vide ou manquant');
    }
    if (name.isEmpty) {
      debugPrint('⚠️ TeamModel.fromMap: nom vide ou manquant');
    }
    if (map['createdAt'] == null ||
        DateTime.tryParse(map['createdAt']?.toString() ?? '') == null) {
      debugPrint('⚠️ TeamModel.fromMap: createdAt vide ou invalide');
    }
    if (map['maxMembers'] is! int) {
      debugPrint('⚠️ TeamModel.fromMap: maxMembers manquant ou invalide, valeur par défaut 5');
    }

    return TeamModel(
      id: id,
      name: name,
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
      maxMembers: maxMembers,
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
      createdAt: createdAt,
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

  // TODO: Déplacer dans la couche UI/localization — les labels français n'ont rien à faire dans le modèle
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
