enum GamePlatform { steam, playstation, xbox, epic, nintendo, pc, other }

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

enum GameStatus { unclassified, backlog, inProgress, completed, abandoned }

extension GameStatusX on GameStatus {
  String get label {
    switch (this) {
      case GameStatus.unclassified:
        return 'À classer';
      case GameStatus.backlog:
        return 'Pas commencé';
      case GameStatus.inProgress:
        return 'En cours';
      case GameStatus.completed:
        return 'Terminé';
      case GameStatus.abandoned:
        return 'Abandonné';
    }
  }
}

enum GameSource { manual, steam }

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
      platinumUnlocked: platinumUnlocked ?? this.platinumUnlocked,
      platinumTotal: platinumTotal ?? this.platinumTotal,
      scoreEarned: scoreEarned ?? this.scoreEarned,
      scoreTotal: scoreTotal ?? this.scoreTotal,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
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

  factory GameAchievementSummary.fromJson(Map<String, dynamic> json) {
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

enum GameAchievementKind { generic, bronze, silver, gold, platinum }

class GameAchievementDetail {
  final String id;
  final String name;
  final String description;
  final String? iconUrl;
  final bool hidden;
  final GameAchievementKind kind;
  final int scoreValue;
  final String? groupName;
  final bool platformUnlocked;
  final bool manuallyUnlocked;
  final DateTime? platformUnlockedAt;
  final DateTime? manuallyUnlockedAt;

  const GameAchievementDetail({
    required this.id,
    required this.name,
    this.description = '',
    this.iconUrl,
    this.hidden = false,
    this.kind = GameAchievementKind.generic,
    this.scoreValue = 0,
    this.groupName,
    this.platformUnlocked = false,
    this.manuallyUnlocked = false,
    this.platformUnlockedAt,
    this.manuallyUnlockedAt,
  });

  bool get isUnlocked => platformUnlocked || manuallyUnlocked;

  GameAchievementDetail copyWith({
    String? id,
    String? name,
    String? description,
    String? iconUrl,
    bool clearIconUrl = false,
    bool? hidden,
    GameAchievementKind? kind,
    int? scoreValue,
    String? groupName,
    bool clearGroupName = false,
    bool? platformUnlocked,
    bool? manuallyUnlocked,
    DateTime? platformUnlockedAt,
    bool clearPlatformUnlockedAt = false,
    DateTime? manuallyUnlockedAt,
    bool clearManuallyUnlockedAt = false,
  }) {
    return GameAchievementDetail(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: clearIconUrl ? null : iconUrl ?? this.iconUrl,
      hidden: hidden ?? this.hidden,
      kind: kind ?? this.kind,
      scoreValue: scoreValue ?? this.scoreValue,
      groupName: clearGroupName ? null : groupName ?? this.groupName,
      platformUnlocked: platformUnlocked ?? this.platformUnlocked,
      manuallyUnlocked: manuallyUnlocked ?? this.manuallyUnlocked,
      platformUnlockedAt: clearPlatformUnlockedAt
          ? null
          : platformUnlockedAt ?? this.platformUnlockedAt,
      manuallyUnlockedAt: clearManuallyUnlockedAt
          ? null
          : manuallyUnlockedAt ?? this.manuallyUnlockedAt,
    );
  }

  GameAchievementDetail withManualState(bool unlocked) {
    if (platformUnlocked) {
      return this;
    }

    return copyWith(
      manuallyUnlocked: unlocked,
      manuallyUnlockedAt: unlocked ? DateTime.now() : null,
      clearManuallyUnlockedAt: !unlocked,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'iconUrl': iconUrl,
    'hidden': hidden,
    'kind': kind.name,
    'scoreValue': scoreValue,
    'groupName': groupName,
    'platformUnlocked': platformUnlocked,
    'manuallyUnlocked': manuallyUnlocked,
    'platformUnlockedAt': platformUnlockedAt?.toIso8601String(),
    'manuallyUnlockedAt': manuallyUnlockedAt?.toIso8601String(),
  };

  factory GameAchievementDetail.fromJson(Map<String, dynamic> json) {
    final String rawKind = json['kind']?.toString() ?? '';
    final GameAchievementKind kind = GameAchievementKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => GameAchievementKind.generic,
    );

    DateTime? readDate(String key) {
      final String raw = json[key]?.toString() ?? '';
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    String? readNullableString(String key) {
      final String value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return GameAchievementDetail(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Succès',
      description: json['description']?.toString() ?? '',
      iconUrl: readNullableString('iconUrl'),
      hidden: json['hidden'] == true,
      kind: kind,
      scoreValue: int.tryParse(json['scoreValue']?.toString() ?? '') ?? 0,
      groupName: readNullableString('groupName'),
      platformUnlocked: json['platformUnlocked'] == true,
      manuallyUnlocked: json['manuallyUnlocked'] == true,
      platformUnlockedAt: readDate('platformUnlockedAt'),
      manuallyUnlockedAt: readDate('manuallyUnlockedAt'),
    );
  }
}

class GamePlatformProfile {
  final GamePlatform platform;
  final GameSource source;
  final String? externalId;
  final int playtimeMinutes;
  final GameAchievementSummary achievements;
  final List<GameAchievementDetail> achievementDetails;
  final bool achievementCatalogInitialized;
  final DateTime? achievementsLastSyncedAt;
  final DateTime? lastPlayedAt;

  const GamePlatformProfile({
    required this.platform,
    required this.source,
    this.externalId,
    this.playtimeMinutes = 0,
    this.achievements = const GameAchievementSummary(),
    this.achievementDetails = const <GameAchievementDetail>[],
    this.achievementCatalogInitialized = false,
    this.achievementsLastSyncedAt,
    this.lastPlayedAt,
  });

  GamePlatformProfile copyWith({
    GamePlatform? platform,
    GameSource? source,
    String? externalId,
    bool clearExternalId = false,
    int? playtimeMinutes,
    GameAchievementSummary? achievements,
    List<GameAchievementDetail>? achievementDetails,
    bool? achievementCatalogInitialized,
    DateTime? achievementsLastSyncedAt,
    bool clearAchievementsLastSyncedAt = false,
    DateTime? lastPlayedAt,
    bool clearLastPlayedAt = false,
  }) {
    return GamePlatformProfile(
      platform: platform ?? this.platform,
      source: source ?? this.source,
      externalId: clearExternalId ? null : externalId ?? this.externalId,
      playtimeMinutes: (playtimeMinutes ?? this.playtimeMinutes)
          .clamp(0, 1 << 31)
          .toInt(),
      achievements: achievements ?? this.achievements,
      achievementDetails: achievementDetails ?? this.achievementDetails,
      achievementCatalogInitialized:
          achievementCatalogInitialized ?? this.achievementCatalogInitialized,
      achievementsLastSyncedAt: clearAchievementsLastSyncedAt
          ? null
          : achievementsLastSyncedAt ?? this.achievementsLastSyncedAt,
      lastPlayedAt: clearLastPlayedAt
          ? null
          : lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  int get detailedAchievementUnlockedCount =>
      achievementDetails.where((achievement) => achievement.isUnlocked).length;

  GameAchievementSummary get computedAchievementSummary {
    if (achievementDetails.isEmpty) {
      return achievements;
    }

    int bronzeUnlocked = 0;
    int bronzeTotal = 0;
    int silverUnlocked = 0;
    int silverTotal = 0;
    int goldUnlocked = 0;
    int goldTotal = 0;
    int platinumUnlocked = 0;
    int platinumTotal = 0;
    int scoreEarned = 0;
    int scoreTotal = 0;

    for (final GameAchievementDetail achievement in achievementDetails) {
      final bool unlocked = achievement.isUnlocked;

      switch (achievement.kind) {
        case GameAchievementKind.bronze:
          bronzeTotal += 1;
          if (unlocked) bronzeUnlocked += 1;
          break;
        case GameAchievementKind.silver:
          silverTotal += 1;
          if (unlocked) silverUnlocked += 1;
          break;
        case GameAchievementKind.gold:
          goldTotal += 1;
          if (unlocked) goldUnlocked += 1;
          break;
        case GameAchievementKind.platinum:
          platinumTotal += 1;
          if (unlocked) platinumUnlocked += 1;
          break;
        case GameAchievementKind.generic:
          break;
      }

      scoreTotal += achievement.scoreValue;
      if (unlocked) scoreEarned += achievement.scoreValue;
    }

    return achievements.copyWith(
      unlocked: detailedAchievementUnlockedCount,
      total: achievementDetails.length,
      bronzeUnlocked: bronzeUnlocked,
      bronzeTotal: bronzeTotal,
      silverUnlocked: silverUnlocked,
      silverTotal: silverTotal,
      goldUnlocked: goldUnlocked,
      goldTotal: goldTotal,
      platinumUnlocked: platinumUnlocked,
      platinumTotal: platinumTotal,
      scoreEarned: scoreTotal > 0 ? scoreEarned : achievements.scoreEarned,
      scoreTotal: scoreTotal > 0 ? scoreTotal : achievements.scoreTotal,
    );
  }

  bool get hasAchievementData {
    final GameAchievementSummary current = computedAchievementSummary;
    return achievementDetails.isNotEmpty ||
        current.total > 0 ||
        current.bronzeTotal > 0 ||
        current.silverTotal > 0 ||
        current.goldTotal > 0 ||
        current.platinumTotal > 0 ||
        current.scoreTotal > 0;
  }

  bool get achievementCatalogKnownEmpty =>
      achievementCatalogInitialized && !hasAchievementData;

  int? get completionPercent {
    final GameAchievementSummary current = computedAchievementSummary;

    int percentWithoutFalseHundred(int earned, int available) {
      if (available <= 0) {
        return 0;
      }
      if (earned >= available) {
        return 100;
      }
      return ((earned / available) * 100).round().clamp(0, 99).toInt();
    }

    if (platform == GamePlatform.playstation) {
      final int earned =
          current.bronzeUnlocked +
          current.silverUnlocked +
          current.goldUnlocked +
          current.platinumUnlocked;
      final int available =
          current.bronzeTotal +
          current.silverTotal +
          current.goldTotal +
          current.platinumTotal;
      if (available > 0) {
        return percentWithoutFalseHundred(earned, available);
      }
    }

    if (platform == GamePlatform.xbox && current.scoreTotal > 0) {
      return percentWithoutFalseHundred(
        current.scoreEarned,
        current.scoreTotal,
      );
    }

    if (current.total > 0) {
      return percentWithoutFalseHundred(current.unlocked, current.total);
    }

    return null;
  }

  String get progressText {
    final GameAchievementSummary current = computedAchievementSummary;

    if (platform == GamePlatform.playstation) {
      final int earned =
          current.bronzeUnlocked +
          current.silverUnlocked +
          current.goldUnlocked +
          current.platinumUnlocked;
      final int available =
          current.bronzeTotal +
          current.silverTotal +
          current.goldTotal +
          current.platinumTotal;
      if (available > 0) {
        return '$earned / $available trophées';
      }
    }

    if (platform == GamePlatform.xbox && current.scoreTotal > 0) {
      return '${current.scoreEarned} / ${current.scoreTotal} G';
    }

    if (current.total > 0) {
      return '${current.unlocked} / ${current.total} '
          '${platform.achievementLabel.toLowerCase()}';
    }

    return 'Progression inconnue';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'platform': platform.name,
    'source': source.name,
    'externalId': externalId,
    'playtimeMinutes': playtimeMinutes,
    'achievements': computedAchievementSummary.toJson(),
    'achievementDetails': achievementDetails
        .map((achievement) => achievement.toJson())
        .toList(),
    'achievementCatalogInitialized': achievementCatalogInitialized,
    'achievementsLastSyncedAt': achievementsLastSyncedAt?.toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
  };

  factory GamePlatformProfile.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, dynamic raw, T fallback) {
      final String name = raw?.toString() ?? '';
      for (final T value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final dynamic achievementRaw = json['achievements'];
    final dynamic detailsRaw = json['achievementDetails'];
    final List<GameAchievementDetail> details = detailsRaw is List
        ? detailsRaw
              .whereType<Map>()
              .map(
                (item) => GameAchievementDetail.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((achievement) => achievement.id.trim().isNotEmpty)
              .toList()
        : <GameAchievementDetail>[];

    final String externalId = json['externalId']?.toString().trim() ?? '';

    return GamePlatformProfile(
      platform: enumValue<GamePlatform>(
        GamePlatform.values,
        json['platform'],
        GamePlatform.other,
      ),
      source: enumValue<GameSource>(
        GameSource.values,
        json['source'],
        GameSource.manual,
      ),
      externalId: externalId.isEmpty ? null : externalId,
      playtimeMinutes:
          int.tryParse(json['playtimeMinutes']?.toString() ?? '') ?? 0,
      achievements: achievementRaw is Map
          ? GameAchievementSummary.fromJson(
              Map<String, dynamic>.from(achievementRaw),
            )
          : const GameAchievementSummary(),
      achievementDetails: details,
      achievementCatalogInitialized:
          json['achievementCatalogInitialized'] == true || details.isNotEmpty,
      achievementsLastSyncedAt: DateTime.tryParse(
        json['achievementsLastSyncedAt']?.toString() ?? '',
      ),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt']?.toString() ?? ''),
    );
  }
}

class GameLibraryEntry {
  final String id;
  final String title;
  final GamePlatform platform;
  final GameStatus status;

  /// `true` quand Project XP a déduit l'état depuis une plateforme.
  /// Un choix manuel peut passer cette valeur à false, mais une synchronisation
  /// disposant de données fiables peut ensuite corriger cet état. Pour un jeu
  /// sans donnée de complétion exploitable, Terminé / Abandonné restent des
  /// informations personnelles utiles.
  final bool statusAutomatic;

  final bool favorite;
  final int progressPercent;
  final GameSource source;
  final String? externalId;
  final String? catalogId;
  final String? coverUrl;
  final List<String> coverFallbackUrls;
  final String? summary;
  final int? releaseYear;
  final List<String> genres;
  final List<String> catalogPlatforms;
  final int playtimeMinutes;
  final GameAchievementSummary achievements;
  final List<GameAchievementDetail> achievementDetails;
  final bool achievementCatalogInitialized;
  final DateTime? achievementsLastSyncedAt;
  final List<GamePlatformProfile> platformProfiles;
  final DateTime addedAt;

  /// Dernière action volontaire du joueur sur la fiche.
  final DateTime? personalUpdatedAt;

  /// Dernière activité significative utilisée par le tri actuel de la
  /// Bibliothèque. Une synchronisation purement technique ne doit pas la
  /// déplacer ; une vraie partie ou un nouveau succès peut en revanche
  /// l'actualiser avec sa date réelle.
  final DateTime updatedAt;

  const GameLibraryEntry({
    required this.id,
    required this.title,
    required this.platform,
    required this.status,
    this.statusAutomatic = false,
    required this.favorite,
    required this.progressPercent,
    required this.source,
    required this.externalId,
    this.catalogId,
    required this.coverUrl,
    this.coverFallbackUrls = const <String>[],
    this.summary,
    this.releaseYear,
    this.genres = const <String>[],
    this.catalogPlatforms = const <String>[],
    required this.playtimeMinutes,
    required this.achievements,
    this.achievementDetails = const <GameAchievementDetail>[],
    this.achievementCatalogInitialized = false,
    this.achievementsLastSyncedAt,
    this.platformProfiles = const <GamePlatformProfile>[],
    required this.addedAt,
    this.personalUpdatedAt,
    required this.updatedAt,
  });

  DateTime get effectivePersonalUpdatedAt => personalUpdatedAt ?? addedAt;

  GameLibraryEntry copyWith({
    String? id,
    String? title,
    GamePlatform? platform,
    GameStatus? status,
    bool? statusAutomatic,
    bool? favorite,
    int? progressPercent,
    GameSource? source,
    String? externalId,
    bool clearExternalId = false,
    String? catalogId,
    bool clearCatalogId = false,
    String? coverUrl,
    bool clearCoverUrl = false,
    List<String>? coverFallbackUrls,
    String? summary,
    bool clearSummary = false,
    int? releaseYear,
    bool clearReleaseYear = false,
    List<String>? genres,
    List<String>? catalogPlatforms,
    int? playtimeMinutes,
    GameAchievementSummary? achievements,
    List<GameAchievementDetail>? achievementDetails,
    bool? achievementCatalogInitialized,
    DateTime? achievementsLastSyncedAt,
    bool clearAchievementsLastSyncedAt = false,
    List<GamePlatformProfile>? platformProfiles,
    DateTime? addedAt,
    DateTime? personalUpdatedAt,
    bool clearPersonalUpdatedAt = false,
    DateTime? updatedAt,
  }) {
    return GameLibraryEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      statusAutomatic: statusAutomatic ?? this.statusAutomatic,
      favorite: favorite ?? this.favorite,
      progressPercent: (progressPercent ?? this.progressPercent)
          .clamp(0, 100)
          .toInt(),
      source: source ?? this.source,
      externalId: clearExternalId ? null : externalId ?? this.externalId,
      catalogId: clearCatalogId ? null : catalogId ?? this.catalogId,
      coverUrl: clearCoverUrl ? null : coverUrl ?? this.coverUrl,
      coverFallbackUrls: coverFallbackUrls ?? this.coverFallbackUrls,
      summary: clearSummary ? null : summary ?? this.summary,
      releaseYear: clearReleaseYear ? null : releaseYear ?? this.releaseYear,
      genres: genres ?? this.genres,
      catalogPlatforms: catalogPlatforms ?? this.catalogPlatforms,
      playtimeMinutes: (playtimeMinutes ?? this.playtimeMinutes)
          .clamp(0, 1 << 31)
          .toInt(),
      achievements: achievements ?? this.achievements,
      achievementDetails: achievementDetails ?? this.achievementDetails,
      achievementCatalogInitialized:
          achievementCatalogInitialized ?? this.achievementCatalogInitialized,
      achievementsLastSyncedAt: clearAchievementsLastSyncedAt
          ? null
          : achievementsLastSyncedAt ?? this.achievementsLastSyncedAt,
      platformProfiles: platformProfiles ?? this.platformProfiles,
      addedAt: addedAt ?? this.addedAt,
      personalUpdatedAt: clearPersonalUpdatedAt
          ? null
          : personalUpdatedAt ?? this.personalUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<GamePlatformProfile> get resolvedPlatformProfiles {
    if (platformProfiles.isNotEmpty) return platformProfiles;
    return <GamePlatformProfile>[
      GamePlatformProfile(
        platform: platform,
        source: source,
        externalId: externalId,
        playtimeMinutes: playtimeMinutes,
        achievements: achievements,
        achievementDetails: achievementDetails,
        achievementCatalogInitialized: achievementCatalogInitialized,
        achievementsLastSyncedAt: achievementsLastSyncedAt,
      ),
    ];
  }

  GamePlatformProfile? platformProfile(GamePlatform target) {
    for (final GamePlatformProfile profile in resolvedPlatformProfiles) {
      if (profile.platform == target) return profile;
    }
    return null;
  }

  bool get hasSteamConnection => platformProfile(GamePlatform.steam) != null;

  bool get hasOfficialPlatformConnection => resolvedPlatformProfiles.any(
    (profile) => profile.externalId?.trim().isNotEmpty == true,
  );

  List<String> get coverCandidates {
    final List<String> result = <String>[];

    void add(String? raw) {
      final String value = raw?.trim() ?? '';
      if (value.isEmpty || result.contains(value)) return;
      result.add(value);
    }

    final GamePlatformProfile? steam = platformProfile(GamePlatform.steam);
    final String steamAppId = steam?.externalId?.trim() ?? '';
    final String primary = coverUrl?.trim() ?? '';
    final bool primaryLooksLikeSteamAsset =
        steamAppId.isNotEmpty && primary.contains('/steam/apps/$steamAppId/');

    if (!primaryLooksLikeSteamAsset) add(primary);

    if (RegExp(r'^\d+$').hasMatch(steamAppId)) {
      add(
        'https://shared.cloudflare.steamstatic.com/'
        'store_item_assets/steam/apps/'
        '$steamAppId/library_600x900_2x.jpg',
      );
      add(
        'https://shared.cloudflare.steamstatic.com/'
        'store_item_assets/steam/apps/'
        '$steamAppId/library_600x900.jpg',
      );
      add(
        'https://cdn.akamai.steamstatic.com/steam/apps/'
        '$steamAppId/library_600x900_2x.jpg',
      );
      add(
        'https://cdn.akamai.steamstatic.com/steam/apps/'
        '$steamAppId/library_600x900.jpg',
      );
      add(
        'https://cdn.akamai.steamstatic.com/steam/apps/'
        '$steamAppId/header.jpg',
      );
    }

    add(primary);

    for (final String fallback in coverFallbackUrls) {
      final String normalized = fallback.toLowerCase();
      final bool tinySteamIcon =
          normalized.contains('/public/images/apps/') ||
          normalized.contains('steamcommunity/public/images/apps/');
      if (!tinySteamIcon) add(fallback);
    }

    return result;
  }

  List<GamePlatform> get connectedPlatforms => resolvedPlatformProfiles
      .map((profile) => profile.platform)
      .toSet()
      .toList();

  GamePlatformProfile? get bestCompletionProfile {
    GamePlatformProfile? best;
    int bestValue = -1;

    for (final GamePlatformProfile profile in resolvedPlatformProfiles) {
      final int? value = profile.completionPercent;
      if (value == null) continue;
      if (value > bestValue) {
        best = profile;
        bestValue = value;
      }
    }

    return best;
  }

  int? get bestCompletionPercent => bestCompletionProfile?.completionPercent;

  bool get allAchievementCatalogsKnownEmpty {
    final List<GamePlatformProfile> profiles = resolvedPlatformProfiles;
    return profiles.isNotEmpty &&
        profiles.every((profile) => profile.achievementCatalogKnownEmpty);
  }

  String get platformSummaryText =>
      connectedPlatforms.map((item) => item.label).join(' • ');

  int get totalPlaytimeMinutes => resolvedPlatformProfiles.fold<int>(
    0,
    (sum, profile) => sum + profile.playtimeMinutes,
  );

  GameLibraryEntry withPlatformProfile(GamePlatformProfile incoming) {
    final List<GamePlatformProfile> next = List<GamePlatformProfile>.from(
      resolvedPlatformProfiles,
    );
    final int index = next.indexWhere(
      (profile) => profile.platform == incoming.platform,
    );

    if (index == -1) {
      next.add(incoming);
    } else {
      next[index] = incoming;
    }

    next.sort((a, b) => a.platform.index.compareTo(b.platform.index));
    return copyWith(platformProfiles: next);
  }

  bool get hasCatalogMetadata =>
      (catalogId?.isNotEmpty ?? false) ||
      (coverUrl?.isNotEmpty ?? false) ||
      summary != null ||
      releaseYear != null ||
      genres.isNotEmpty;

  int get detailedAchievementUnlockedCount =>
      achievementDetails.where((achievement) => achievement.isUnlocked).length;

  GameAchievementSummary get computedAchievementSummary {
    if (achievementDetails.isEmpty) return achievements;

    int bronzeUnlocked = 0;
    int bronzeTotal = 0;
    int silverUnlocked = 0;
    int silverTotal = 0;
    int goldUnlocked = 0;
    int goldTotal = 0;
    int platinumUnlocked = 0;
    int platinumTotal = 0;
    int scoreEarned = 0;
    int scoreTotal = 0;

    for (final GameAchievementDetail achievement in achievementDetails) {
      final bool unlocked = achievement.isUnlocked;
      switch (achievement.kind) {
        case GameAchievementKind.bronze:
          bronzeTotal += 1;
          if (unlocked) bronzeUnlocked += 1;
          break;
        case GameAchievementKind.silver:
          silverTotal += 1;
          if (unlocked) silverUnlocked += 1;
          break;
        case GameAchievementKind.gold:
          goldTotal += 1;
          if (unlocked) goldUnlocked += 1;
          break;
        case GameAchievementKind.platinum:
          platinumTotal += 1;
          if (unlocked) platinumUnlocked += 1;
          break;
        case GameAchievementKind.generic:
          break;
      }
      scoreTotal += achievement.scoreValue;
      if (unlocked) scoreEarned += achievement.scoreValue;
    }

    return achievements.copyWith(
      unlocked: detailedAchievementUnlockedCount,
      total: achievementDetails.length,
      bronzeUnlocked: bronzeUnlocked,
      bronzeTotal: bronzeTotal,
      silverUnlocked: silverUnlocked,
      silverTotal: silverTotal,
      goldUnlocked: goldUnlocked,
      goldTotal: goldTotal,
      platinumUnlocked: platinumUnlocked,
      platinumTotal: platinumTotal,
      scoreEarned: scoreTotal > 0 ? scoreEarned : achievements.scoreEarned,
      scoreTotal: scoreTotal > 0 ? scoreTotal : achievements.scoreTotal,
    );
  }

  String get achievementProgressText {
    final GameAchievementSummary current = computedAchievementSummary;

    if (platform == GamePlatform.playstation) {
      final int earned =
          current.bronzeUnlocked +
          current.silverUnlocked +
          current.goldUnlocked +
          current.platinumUnlocked;
      final int available =
          current.bronzeTotal +
          current.silverTotal +
          current.goldTotal +
          current.platinumTotal;
      if (available > 0) return '$earned / $available trophées';
    }

    if (platform == GamePlatform.xbox && current.scoreTotal > 0) {
      return '${current.scoreEarned} / ${current.scoreTotal} G';
    }

    if (current.total > 0) {
      return '${current.unlocked} / ${current.total} '
          '${platform.achievementLabel.toLowerCase()}';
    }

    return 'Aucun ${platform.achievementLabel.toLowerCase()} renseigné';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'platform': platform.name,
    'status': status.name,
    'statusAutomatic': statusAutomatic,
    'favorite': favorite,
    'progressPercent': progressPercent,
    'source': source.name,
    'externalId': externalId,
    'catalogId': catalogId,
    'coverUrl': coverUrl,
    'coverFallbackUrls': coverFallbackUrls,
    'summary': summary,
    'releaseYear': releaseYear,
    'genres': genres,
    'catalogPlatforms': catalogPlatforms,
    'playtimeMinutes': playtimeMinutes,
    'achievements': computedAchievementSummary.toJson(),
    'achievementDetails': achievementDetails
        .map((achievement) => achievement.toJson())
        .toList(),
    'achievementCatalogInitialized': achievementCatalogInitialized,
    'achievementsLastSyncedAt': achievementsLastSyncedAt?.toIso8601String(),
    'platformProfiles': resolvedPlatformProfiles
        .map((profile) => profile.toJson())
        .toList(),
    'addedAt': addedAt.toIso8601String(),
    'personalUpdatedAt': personalUpdatedAt?.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory GameLibraryEntry.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, dynamic raw, T fallback) {
      final String name = raw?.toString() ?? '';
      for (final T value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    int readInt(String key) {
      final dynamic value = json[key];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    int? readNullableInt(String key) {
      final dynamic value = json[key];
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    DateTime readDate(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '') ?? DateTime.now();

    List<String> readStringList(String key) {
      final dynamic value = json[key];
      if (value is! List) return <String>[];
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
    final dynamic detailsRaw = json['achievementDetails'];
    final dynamic platformProfilesRaw = json['platformProfiles'];

    final List<GameAchievementDetail> details = detailsRaw is List
        ? detailsRaw
              .whereType<Map>()
              .map(
                (item) => GameAchievementDetail.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((achievement) => achievement.id.trim().isNotEmpty)
              .toList()
        : <GameAchievementDetail>[];

    final List<GamePlatformProfile> platformProfiles =
        platformProfilesRaw is List
        ? platformProfilesRaw
              .whereType<Map>()
              .map(
                (item) => GamePlatformProfile.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : <GamePlatformProfile>[];

    final GameStatus storedStatus = enumValue<GameStatus>(
      GameStatus.values,
      json['status'],
      GameStatus.unclassified,
    );

    bool profileHasStarted(GamePlatformProfile profile) {
      final GameAchievementSummary summary = profile.computedAchievementSummary;
      return profile.playtimeMinutes > 0 ||
          summary.unlocked > 0 ||
          summary.bronzeUnlocked > 0 ||
          summary.silverUnlocked > 0 ||
          summary.goldUnlocked > 0 ||
          summary.platinumUnlocked > 0;
    }

    final bool legacyHasStarted =
        readInt('playtimeMinutes') > 0 ||
        details.any((achievement) => achievement.isUnlocked) ||
        platformProfiles.any(profileHasStarted);

    // Les anciennes fiches Steam étaient laissées « À classer ». On peut les
    // migrer sans ambiguïté : aucune activité => Pas commencé, sinon En cours.
    final GameStatus status = storedStatus == GameStatus.unclassified
        ? (legacyHasStarted ? GameStatus.inProgress : GameStatus.backlog)
        : storedStatus;

    // Les anciennes données n'avaient pas statusAutomatic : seul l'ancien état
    // « À classer » est considéré comme une classification automatique.
    final bool statusAutomatic = json.containsKey('statusAutomatic')
        ? json['statusAutomatic'] == true
        : storedStatus == GameStatus.unclassified;

    final DateTime addedAt = readDate('addedAt');
    DateTime recentAt = readDate('updatedAt');

    // Pour une ancienne fiche automatique, l'ancien updatedAt pouvait être la
    // date d'une simple synchro. On le remplace par une vraie activité connue.
    if (storedStatus == GameStatus.unclassified &&
        !json.containsKey('personalUpdatedAt')) {
      recentAt = addedAt;

      void consider(DateTime? candidate) {
        if (candidate != null && candidate.isAfter(recentAt)) {
          recentAt = candidate;
        }
      }

      for (final GamePlatformProfile profile in platformProfiles) {
        consider(profile.lastPlayedAt);
        for (final GameAchievementDetail achievement
            in profile.achievementDetails) {
          if (achievement.isUnlocked) {
            consider(
              achievement.platformUnlockedAt ?? achievement.manuallyUnlockedAt,
            );
          }
        }
      }
    }

    return GameLibraryEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Jeu',
      platform: enumValue<GamePlatform>(
        GamePlatform.values,
        json['platform'],
        GamePlatform.other,
      ),
      status: status,
      statusAutomatic: statusAutomatic,
      favorite: json['favorite'] == true,
      progressPercent: readInt('progressPercent').clamp(0, 100).toInt(),
      source: enumValue<GameSource>(
        GameSource.values,
        json['source'],
        GameSource.manual,
      ),
      externalId: readNullableString('externalId'),
      catalogId: readNullableString('catalogId'),
      coverUrl: readNullableString('coverUrl'),
      coverFallbackUrls: readStringList('coverFallbackUrls'),
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
      achievementDetails: details,
      achievementCatalogInitialized:
          json['achievementCatalogInitialized'] == true || details.isNotEmpty,
      achievementsLastSyncedAt: DateTime.tryParse(
        json['achievementsLastSyncedAt']?.toString() ?? '',
      ),
      platformProfiles: platformProfiles,
      addedAt: addedAt,
      personalUpdatedAt: DateTime.tryParse(
        json['personalUpdatedAt']?.toString() ?? '',
      ),
      updatedAt: recentAt,
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

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GamingActivityEvent.fromJson(Map<String, dynamic> json) {
    return GamingActivityEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Activité',
      detail: json['detail']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
