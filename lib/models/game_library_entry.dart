enum GamePlatform {
  steam,
  playstation,
  xbox,
  epic,
  nintendo,
  pc,
  other,
}

extension GamePlatformX on GamePlatform {
  String get label {
    switch (this) {
      case GamePlatform.steam:
        return 'Steam';
      case GamePlatform.playstation:
        return 'PlayStation';
      case GamePlatform.xbox:
        return 'Xbox';
      case GamePlatform.epic:
        return 'Epic Games';
      case GamePlatform.nintendo:
        return 'Nintendo';
      case GamePlatform.pc:
        return 'PC';
      case GamePlatform.other:
        return 'Autre';
    }
  }

  String get achievementLabel {
    switch (this) {
      case GamePlatform.playstation:
        return 'Trophées';
      case GamePlatform.xbox:
      case GamePlatform.steam:
      case GamePlatform.epic:
      case GamePlatform.nintendo:
      case GamePlatform.pc:
      case GamePlatform.other:
        return 'Succès';
    }
  }
}

enum GameStatus {
  unclassified,
  backlog,
  inProgress,
  completed,
  abandoned,
}

extension GameStatusX on GameStatus {
  String get label {
    switch (this) {
      case GameStatus.unclassified:
        return 'À classer';
      case GameStatus.backlog:
        return 'À jouer';
      case GameStatus.inProgress:
        return 'En cours';
      case GameStatus.completed:
        return 'Terminé';
      case GameStatus.abandoned:
        return 'Abandonné';
    }
  }
}

enum GameSource {
  manual,
  steam,
}

class GameAchievementSummary {
  final int unlocked;
  final int total;

  final int bronzeUnlocked;
  final int bronzeTotal;
  final int silverUnlocked;
  final int silverTotal;
  final int goldUnlocked;
  final int goldTotal;
  final int platinumUnlocked;
  final int platinumTotal;

  final int scoreEarned;
  final int scoreTotal;

  const GameAchievementSummary({
    this.unlocked = 0,
    this.total = 0,
    this.bronzeUnlocked = 0,
    this.bronzeTotal = 0,
    this.silverUnlocked = 0,
    this.silverTotal = 0,
    this.goldUnlocked = 0,
    this.goldTotal = 0,
    this.platinumUnlocked = 0,
    this.platinumTotal = 0,
    this.scoreEarned = 0,
    this.scoreTotal = 0,
  });

  GameAchievementSummary copyWith({
    int? unlocked,
    int? total,
    int? bronzeUnlocked,
    int? bronzeTotal,
    int? silverUnlocked,
    int? silverTotal,
    int? goldUnlocked,
    int? goldTotal,
    int? platinumUnlocked,
    int? platinumTotal,
    int? scoreEarned,
    int? scoreTotal,
  }) {
    return GameAchievementSummary(
      unlocked: unlocked ?? this.unlocked,
      total: total ?? this.total,
      bronzeUnlocked: bronzeUnlocked ?? this.bronzeUnlocked,
      bronzeTotal: bronzeTotal ?? this.bronzeTotal,
      silverUnlocked: silverUnlocked ?? this.silverUnlocked,
      silverTotal: silverTotal ?? this.silverTotal,
      goldUnlocked: goldUnlocked ?? this.goldUnlocked,
      goldTotal: goldTotal ?? this.goldTotal,
      platinumUnlocked:
          platinumUnlocked ?? this.platinumUnlocked,
      platinumTotal:
          platinumTotal ?? this.platinumTotal,
      scoreEarned: scoreEarned ?? this.scoreEarned,
      scoreTotal: scoreTotal ?? this.scoreTotal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unlocked': unlocked,
      'total': total,
      'bronzeUnlocked': bronzeUnlocked,
      'bronzeTotal': bronzeTotal,
      'silverUnlocked': silverUnlocked,
      'silverTotal': silverTotal,
      'goldUnlocked': goldUnlocked,
      'goldTotal': goldTotal,
      'platinumUnlocked': platinumUnlocked,
      'platinumTotal': platinumTotal,
      'scoreEarned': scoreEarned,
      'scoreTotal': scoreTotal,
    };
  }

  factory GameAchievementSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    int read(String key) {
      final dynamic value = json[key];
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return GameAchievementSummary(
      unlocked: read('unlocked'),
      total: read('total'),
      bronzeUnlocked: read('bronzeUnlocked'),
      bronzeTotal: read('bronzeTotal'),
      silverUnlocked: read('silverUnlocked'),
      silverTotal: read('silverTotal'),
      goldUnlocked: read('goldUnlocked'),
      goldTotal: read('goldTotal'),
      platinumUnlocked: read('platinumUnlocked'),
      platinumTotal: read('platinumTotal'),
      scoreEarned: read('scoreEarned'),
      scoreTotal: read('scoreTotal'),
    );
  }
}

class GameLibraryEntry {
  final String id;
  final String title;
  final GamePlatform platform;
  final GameStatus status;
  final bool favorite;
  final int progressPercent;
  final GameSource source;

  /// Identifiant de la plateforme source (ex: Steam AppID).
  final String? externalId;

  /// Identifiant du catalogue général (IGDB pour V1.8.1).
  final String? catalogId;
  final String? coverUrl;
  final String? summary;
  final int? releaseYear;
  final List<String> genres;
  final List<String> catalogPlatforms;

  final int playtimeMinutes;
  final GameAchievementSummary achievements;
  final DateTime addedAt;
  final DateTime updatedAt;

  const GameLibraryEntry({
    required this.id,
    required this.title,
    required this.platform,
    required this.status,
    required this.favorite,
    required this.progressPercent,
    required this.source,
    required this.externalId,
    this.catalogId,
    required this.coverUrl,
    this.summary,
    this.releaseYear,
    this.genres = const <String>[],
    this.catalogPlatforms = const <String>[],
    required this.playtimeMinutes,
    required this.achievements,
    required this.addedAt,
    required this.updatedAt,
  });

  GameLibraryEntry copyWith({
    String? id,
    String? title,
    GamePlatform? platform,
    GameStatus? status,
    bool? favorite,
    int? progressPercent,
    GameSource? source,
    String? externalId,
    bool clearExternalId = false,
    String? catalogId,
    bool clearCatalogId = false,
    String? coverUrl,
    bool clearCoverUrl = false,
    String? summary,
    bool clearSummary = false,
    int? releaseYear,
    bool clearReleaseYear = false,
    List<String>? genres,
    List<String>? catalogPlatforms,
    int? playtimeMinutes,
    GameAchievementSummary? achievements,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) {
    return GameLibraryEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      favorite: favorite ?? this.favorite,
      progressPercent:
          (progressPercent ?? this.progressPercent).clamp(0, 100).toInt(),
      source: source ?? this.source,
      externalId:
          clearExternalId ? null : externalId ?? this.externalId,
      catalogId:
          clearCatalogId ? null : catalogId ?? this.catalogId,
      coverUrl: clearCoverUrl ? null : coverUrl ?? this.coverUrl,
      summary: clearSummary ? null : summary ?? this.summary,
      releaseYear:
          clearReleaseYear ? null : releaseYear ?? this.releaseYear,
      genres: genres ?? this.genres,
      catalogPlatforms: catalogPlatforms ?? this.catalogPlatforms,
      playtimeMinutes:
          (playtimeMinutes ?? this.playtimeMinutes)
              .clamp(0, 1 << 31)
              .toInt(),
      achievements: achievements ?? this.achievements,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasCatalogMetadata =>
      (catalogId?.isNotEmpty ?? false) ||
      (coverUrl?.isNotEmpty ?? false) ||
      summary != null ||
      releaseYear != null ||
      genres.isNotEmpty;

  String get achievementProgressText {
    if (platform == GamePlatform.playstation) {
      final int earned = achievements.bronzeUnlocked +
          achievements.silverUnlocked +
          achievements.goldUnlocked +
          achievements.platinumUnlocked;
      final int available = achievements.bronzeTotal +
          achievements.silverTotal +
          achievements.goldTotal +
          achievements.platinumTotal;

      if (available > 0) {
        return '$earned / $available trophées';
      }
    }

    if (platform == GamePlatform.xbox &&
        achievements.scoreTotal > 0) {
      return '${achievements.scoreEarned} / '
          '${achievements.scoreTotal} G';
    }

    if (achievements.total > 0) {
      return '${achievements.unlocked} / ${achievements.total} '
          '${platform.achievementLabel.toLowerCase()}';
    }

    return 'Aucun '
        '${platform.achievementLabel.toLowerCase()} renseigné';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'platform': platform.name,
      'status': status.name,
      'favorite': favorite,
      'progressPercent': progressPercent,
      'source': source.name,
      'externalId': externalId,
      'catalogId': catalogId,
      'coverUrl': coverUrl,
      'summary': summary,
      'releaseYear': releaseYear,
      'genres': genres,
      'catalogPlatforms': catalogPlatforms,
      'playtimeMinutes': playtimeMinutes,
      'achievements': achievements.toJson(),
      'addedAt': addedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory GameLibraryEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    T enumValue<T extends Enum>(
      List<T> values,
      dynamic raw,
      T fallback,
    ) {
      final String name = raw?.toString() ?? '';
      for (final T value in values) {
        if (value.name == name) {
          return value;
        }
      }
      return fallback;
    }

    int readInt(String key) {
      final dynamic value = json[key];
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    int? readNullableInt(String key) {
      final dynamic value = json[key];
      if (value == null) {
        return null;
      }
      if (value is int) {
        return value;
      }
      return int.tryParse(value.toString());
    }

    DateTime readDate(String key) {
      return DateTime.tryParse(json[key]?.toString() ?? '') ??
          DateTime.now();
    }

    List<String> readStringList(String key) {
      final dynamic value = json[key];
      if (value is! List) {
        return <String>[];
      }
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    String? readNullableString(String key) {
      final String value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    final dynamic achievementRaw = json['achievements'];

    return GameLibraryEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Jeu',
      platform: enumValue<GamePlatform>(
        GamePlatform.values,
        json['platform'],
        GamePlatform.other,
      ),
      status: enumValue<GameStatus>(
        GameStatus.values,
        json['status'],
        GameStatus.unclassified,
      ),
      favorite: json['favorite'] == true,
      progressPercent:
          readInt('progressPercent').clamp(0, 100).toInt(),
      source: enumValue<GameSource>(
        GameSource.values,
        json['source'],
        GameSource.manual,
      ),
      externalId: readNullableString('externalId'),
      catalogId: readNullableString('catalogId'),
      coverUrl: readNullableString('coverUrl'),
      summary: readNullableString('summary'),
      releaseYear: readNullableInt('releaseYear'),
      genres: readStringList('genres'),
      catalogPlatforms: readStringList('catalogPlatforms'),
      playtimeMinutes: readInt('playtimeMinutes'),
      achievements: achievementRaw is Map
          ? GameAchievementSummary.fromJson(
              Map<String, dynamic>.from(achievementRaw),
            )
          : const GameAchievementSummary(),
      addedAt: readDate('addedAt'),
      updatedAt: readDate('updatedAt'),
    );
  }
}

class GamingActivityEvent {
  final String id;
  final String title;
  final String detail;
  final DateTime createdAt;

  const GamingActivityEvent({
    required this.id,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'detail': detail,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory GamingActivityEvent.fromJson(
    Map<String, dynamic> json,
  ) {
    return GamingActivityEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Activité',
      detail: json['detail']?.toString() ?? '',
      createdAt: DateTime.tryParse(
            json['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
    );
  }
}
