import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_library_entry.dart';
import 'auth_service.dart';
import 'cloud_data_service.dart';

class GameLibraryService {
  GameLibraryService._();

  static const String _libraryPrefix =
      'project_xp_game_library_v1_';
  static const String _activityPrefix =
      'project_xp_gaming_activity_v1_';
  static const String _cloudMigratedPrefix =
      'project_xp_game_library_cloud_migrated_v1_';
  static const String _cloudDirtyPrefix =
      'project_xp_game_library_cloud_dirty_v1_';
  static const String _pendingDeletePrefix =
      'project_xp_game_library_pending_deletes_v1_';
  static const int _maxActivityEvents = 100;

  static Future<String?> _currentUserId() {
    return AuthService.getCurrentUserId();
  }

  static String _libraryKey(String userId) =>
      '$_libraryPrefix$userId';

  static String _activityKey(String userId) =>
      '$_activityPrefix$userId';

  static String _migratedKey(String authUserId) =>
      '$_cloudMigratedPrefix$authUserId';

  static String _dirtyKey(String authUserId) =>
      '$_cloudDirtyPrefix$authUserId';

  static String _pendingDeleteKey(String authUserId) =>
      '$_pendingDeletePrefix$authUserId';

  // ===========================================================================
  // BIBLIOTHÈQUE : CHARGEMENT
  // ===========================================================================

  static Future<List<GameLibraryEntry>>
      loadCurrentLibrary() async {
    final String? userId = await _currentUserId();

    if (userId == null || userId.isEmpty) {
      return <GameLibraryEntry>[];
    }

    final List<GameLibraryEntry> local =
        await _loadLocalLibrary(userId);

    return _resolveLibraryWithCloud(
      userId: userId,
      local: local,
    );
  }

  static Future<List<GameLibraryEntry>>
      _loadLocalLibrary(
    String userId,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    final String? raw =
        prefs.getString(_libraryKey(userId));

    if (raw == null || raw.isEmpty) {
      return <GameLibraryEntry>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <GameLibraryEntry>[];
      }

      final List<GameLibraryEntry> entries = decoded
          .whereType<Map>()
          .map(
            (item) => GameLibraryEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((entry) => entry.id.isNotEmpty)
          .toList();

      entries.sort(
        (a, b) =>
            b.updatedAt.compareTo(a.updatedAt),
      );
      return entries;
    } catch (_) {
      return <GameLibraryEntry>[];
    }
  }

  static Future<void> _saveLocalLibrary(
    String userId,
    List<GameLibraryEntry> entries,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _libraryKey(userId),
      jsonEncode(
        entries.map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  static Future<List<GameLibraryEntry>>
      _resolveLibraryWithCloud({
    required String userId,
    required List<GameLibraryEntry> local,
  }) async {
    final authUser =
        CloudDataService.permanentUser;

    if (authUser == null) {
      return local;
    }

    final CloudReadResult<List<GameLibraryEntry>> cloud =
        await CloudDataService.loadLibrary();

    if (!cloud.available) {
      return local;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final bool migrated =
        prefs.getBool(
              _migratedKey(authUser.id),
            ) ??
            false;

    final bool dirty =
        prefs.getBool(
              _dirtyKey(authUser.id),
            ) ??
            false;

    final Set<String> pendingDeletes =
        _readPendingDeletes(
      prefs,
      authUser.id,
    );

    if (!cloud.found || cloud.value == null) {
      final bool uploaded =
          await CloudDataService.replaceLibrary(
        local,
      );

      if (uploaded) {
        await _markLibraryCloudClean(
          prefs,
          authUser.id,
        );
      }

      return local;
    }

    final List<GameLibraryEntry> cloudEntries =
        List<GameLibraryEntry>.from(
      cloud.value!,
    )..removeWhere(
        (entry) => pendingDeletes.contains(entry.id),
      );

    if (!migrated || dirty) {
      final List<GameLibraryEntry> merged =
          _mergeLibraryEntries(
        local,
        cloudEntries,
      );

      final bool uploaded =
          await CloudDataService.replaceLibrary(
        merged,
      );

      if (uploaded) {
        await _saveLocalLibrary(
          userId,
          merged,
        );
        await _markLibraryCloudClean(
          prefs,
          authUser.id,
        );
      }

      return merged;
    }

    await _saveLocalLibrary(
      userId,
      cloudEntries,
    );

    return cloudEntries;
  }

  static List<GameLibraryEntry> _mergeLibraryEntries(
    List<GameLibraryEntry> local,
    List<GameLibraryEntry> cloud,
  ) {
    final Map<String, GameLibraryEntry> merged =
        <String, GameLibraryEntry>{};

    for (final GameLibraryEntry entry in cloud) {
      merged[entry.id] = entry;
    }

    for (final GameLibraryEntry entry in local) {
      final GameLibraryEntry? existing =
          merged[entry.id];

      if (existing == null ||
          entry.updatedAt.isAfter(
            existing.updatedAt,
          )) {
        merged[entry.id] = entry;
      }
    }

    final List<GameLibraryEntry> result =
        merged.values.toList()
          ..sort(
            (a, b) =>
                b.updatedAt.compareTo(a.updatedAt),
          );

    return result;
  }

  static Future<List<GameLibraryEntry>>
      loadCurrentLibraryConsolidated() async {
    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();

    final List<GameLibraryEntry> collapsed =
        _collapsePlatformDuplicates(entries);

    if (collapsed.length != entries.length) {
      collapsed.sort(
        (a, b) =>
            b.updatedAt.compareTo(a.updatedAt),
      );
      await saveCurrentLibrary(collapsed);
    }

    return collapsed;
  }

  // ===========================================================================
  // BIBLIOTHÈQUE : SAUVEGARDE
  // ===========================================================================

  static Future<void> saveCurrentLibrary(
    List<GameLibraryEntry> entries,
  ) async {
    final String? userId = await _currentUserId();

    if (userId == null || userId.isEmpty) {
      return;
    }

    final List<GameLibraryEntry> previous =
        await _loadLocalLibrary(userId);

    final Set<String> nextIds =
        entries.map((entry) => entry.id).toSet();

    final Set<String> removedIds = previous
        .map((entry) => entry.id)
        .where((id) => !nextIds.contains(id))
        .toSet();

    await _saveLocalLibrary(
      userId,
      entries,
    );

    final authUser =
        CloudDataService.permanentUser;

    if (authUser == null) {
      return;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(
      _dirtyKey(authUser.id),
      true,
    );

    if (removedIds.isNotEmpty) {
      final Set<String> pending =
          _readPendingDeletes(
        prefs,
        authUser.id,
      )..addAll(removedIds);

      await prefs.setString(
        _pendingDeleteKey(authUser.id),
        jsonEncode(pending.toList()),
      );
    }

    // Avant d'écrire, on récupère les éventuelles modifications arrivées d'un
    // autre appareil. La fusion se fait jeu par jeu grâce à updatedAt.
    final CloudReadResult<List<GameLibraryEntry>> cloud =
        await CloudDataService.loadLibrary();

    List<GameLibraryEntry> toUpload =
        List<GameLibraryEntry>.from(entries);

    if (cloud.available &&
        cloud.found &&
        cloud.value != null) {
      final Set<String> pending =
          _readPendingDeletes(
        prefs,
        authUser.id,
      );

      final List<GameLibraryEntry> remote =
          List<GameLibraryEntry>.from(
        cloud.value!,
      )..removeWhere(
          (entry) => pending.contains(entry.id),
        );

      toUpload = _mergeLibraryEntries(
        entries,
        remote,
      );
    }

    final bool uploaded =
        await CloudDataService.replaceLibrary(
      toUpload,
    );

    if (uploaded) {
      await _saveLocalLibrary(
        userId,
        toUpload,
      );
      await _markLibraryCloudClean(
        prefs,
        authUser.id,
      );
    }
  }

  static Set<String> _readPendingDeletes(
    SharedPreferences prefs,
    String authUserId,
  ) {
    final String? raw =
        prefs.getString(
      _pendingDeleteKey(authUserId),
    );

    if (raw == null || raw.isEmpty) {
      return <String>{};
    }

    try {
      final dynamic decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      // Ignore un cache de suppression corrompu.
    }

    return <String>{};
  }

  static Future<void> _markLibraryCloudClean(
    SharedPreferences prefs,
    String authUserId,
  ) async {
    await prefs.setBool(
      _migratedKey(authUserId),
      true,
    );
    await prefs.setBool(
      _dirtyKey(authUserId),
      false,
    );
    await prefs.remove(
      _pendingDeleteKey(authUserId),
    );
  }

  // ===========================================================================
  // OPÉRATIONS JEUX
  // ===========================================================================

  static Future<GameLibraryEntry> addManualGame({
    required String title,
    required GamePlatform platform,
    required GameStatus status,
    String? catalogId,
    String? coverUrl,
    String? summary,
    int? releaseYear,
    List<String> genres = const <String>[],
    List<String> catalogPlatforms = const <String>[],
  }) async {
    final DateTime now = DateTime.now();
    final GameLibraryEntry entry = GameLibraryEntry(
      id: 'manual_${now.microsecondsSinceEpoch}',
      title: title.trim(),
      platform: platform,
      status: status,
      favorite: false,
      progressPercent:
          status == GameStatus.completed ? 100 : 0,
      source: GameSource.manual,
      externalId: null,
      catalogId: catalogId,
      coverUrl: coverUrl,
      summary: summary,
      releaseYear: releaseYear,
      genres: genres,
      catalogPlatforms: catalogPlatforms,
      playtimeMinutes: 0,
      achievements:
          const GameAchievementSummary(),
      platformProfiles: <GamePlatformProfile>[
        GamePlatformProfile(
          platform: platform,
          source: GameSource.manual,
        ),
      ],
      addedAt: now,
      updatedAt: now,
    );

    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    entries.insert(0, entry);
    await saveCurrentLibrary(entries);

    return entry;
  }

  static Future<GameLibraryEntry> enrichFromCatalog({
    required GameLibraryEntry entry,
    required String catalogId,
    required String title,
    required String? coverUrl,
    required String? summary,
    required int? releaseYear,
    required List<String> genres,
    required List<String> catalogPlatforms,
  }) async {
    final GameLibraryEntry enriched =
        entry.copyWith(
      title: entry.hasOfficialPlatformConnection
          ? entry.title
          : title.trim().isEmpty
              ? entry.title
              : title.trim(),
      catalogId: catalogId,
      coverUrl: coverUrl,
      summary: summary,
      releaseYear: releaseYear,
      genres: genres,
      catalogPlatforms: catalogPlatforms,
      updatedAt: DateTime.now(),
    );

    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    final int index = entries.indexWhere(
      (game) => game.id == entry.id,
    );

    if (index == -1) {
      return enriched;
    }

    entries[index] = enriched;
    await saveCurrentLibrary(entries);
    return enriched;
  }

  static Future<void> updateGame(
    GameLibraryEntry updated, {
    bool announceAchievementUnlocks = true,
  }) async {
    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    final int index = entries.indexWhere(
      (entry) => entry.id == updated.id,
    );

    if (index == -1) {
      return;
    }

    final GameLibraryEntry previous =
        entries[index];

    // V1.10.2 : l'état personnel du jeu et la complétion des plateformes
    // sont deux notions différentes. Un 100 % de trophées/succès ne force
    // donc plus le statut « Terminé », et un jeu Terminé peut très bien
    // rester à 60 % de trophées.
    final GamePlatformProfile? primaryProfile =
        updated.platformProfile(updated.platform);

    final GameLibraryEntry normalized =
        updated.copyWith(
      title: previous.hasOfficialPlatformConnection
          ? previous.title
          : updated.title.trim(),
      coverUrl: previous.hasOfficialPlatformConnection
          ? previous.coverUrl
          : updated.coverUrl,
      coverFallbackUrls:
          previous.hasOfficialPlatformConnection
              ? previous.coverFallbackUrls
              : updated.coverFallbackUrls,
      progressPercent:
          updated.progressPercent.clamp(0, 100).toInt(),
      playtimeMinutes:
          primaryProfile?.playtimeMinutes ??
              updated.playtimeMinutes,
      achievements:
          primaryProfile?.computedAchievementSummary ??
              updated.computedAchievementSummary,
      achievementDetails:
          primaryProfile?.achievementDetails ??
              updated.achievementDetails,
      achievementCatalogInitialized:
          primaryProfile?.achievementCatalogInitialized ??
              updated.achievementCatalogInitialized,
      achievementsLastSyncedAt:
          primaryProfile?.achievementsLastSyncedAt ??
              updated.achievementsLastSyncedAt,
      updatedAt: DateTime.now(),
    );

    entries[index] = normalized;
    await saveCurrentLibrary(entries);

    if (previous.status != GameStatus.completed &&
        normalized.status ==
            GameStatus.completed) {
      await addActivity(
        title: '${normalized.title} terminé',
        detail:
            '${normalized.platformSummaryText} • Aventure accomplie',
      );
    } else if (previous.status ==
            GameStatus.abandoned &&
        normalized.status ==
            GameStatus.inProgress) {
      await addActivity(
        title:
            '${normalized.title} reprend son aventure',
        detail:
            '${normalized.platformSummaryText} • Retour après abandon',
      );
    }

    if (announceAchievementUnlocks) {
      for (final GamePlatformProfile currentProfile
          in normalized.resolvedPlatformProfiles) {
        final GamePlatformProfile? previousProfile =
            previous.platformProfile(
          currentProfile.platform,
        );

        final Map<String, GameAchievementDetail>
            previousDetails =
            <String, GameAchievementDetail>{
          for (final GameAchievementDetail achievement
              in previousProfile?.achievementDetails ??
                  const <GameAchievementDetail>[])
            achievement.id: achievement,
        };

        final List<GameAchievementDetail> newlyUnlocked =
            currentProfile.achievementDetails
                .where(
                  (achievement) =>
                      achievement.isUnlocked &&
                      !(previousDetails[achievement.id]
                              ?.isUnlocked ??
                          false),
                )
                .toList();

        for (final GameAchievementDetail achievement
            in newlyUnlocked.take(5)) {
          final String achievementType =
              currentProfile.platform ==
                      GamePlatform.playstation
                  ? 'Trophée'
                  : 'Succès';

          final String source =
              achievement.platformUnlocked
                  ? currentProfile.platform.label
                  : 'coché manuellement';

          await addActivity(
            title:
                '$achievementType « ${achievement.name} » obtenu',
            detail:
                '${normalized.title} • $source',
          );
        }

        if (newlyUnlocked.length > 5) {
          await addActivity(
            title:
                '${newlyUnlocked.length - 5} autres accomplissements sur ${normalized.title}',
            detail:
                currentProfile.progressText,
          );
        }

        // Compatibilité des anciennes fiches : si on ne dispose pas encore de
        // la liste détaillée, on peut au moins détecter une hausse du résumé.
        if (currentProfile.achievementDetails.isEmpty &&
            previousProfile != null) {
          final GameAchievementSummary before =
              previousProfile.computedAchievementSummary;
          final GameAchievementSummary after =
              currentProfile.computedAchievementSummary;

          if (after.platinumUnlocked >
              before.platinumUnlocked) {
            await addActivity(
              title:
                  'Platine obtenu sur ${normalized.title}',
              detail:
                  '${currentProfile.platform.label} • Trophée ultime débloqué',
            );
          } else {
            final int beforeCount =
                before.unlocked +
                    before.bronzeUnlocked +
                    before.silverUnlocked +
                    before.goldUnlocked +
                    before.platinumUnlocked;
            final int afterCount =
                after.unlocked +
                    after.bronzeUnlocked +
                    after.silverUnlocked +
                    after.goldUnlocked +
                    after.platinumUnlocked;

            if (afterCount > beforeCount) {
              await addActivity(
                title:
                    'Nouveaux ${currentProfile.platform.achievementLabel.toLowerCase()} '
                    'sur ${normalized.title}',
                detail:
                    currentProfile.progressText,
              );
            }
          }
        }
      }
    }
  }

  static Future<void> toggleFavorite(
    GameLibraryEntry entry,
  ) {
    return updateGame(
      entry.copyWith(
        favorite: !entry.favorite,
      ),
    );
  }

  static Future<void> removeGame(
    String id,
  ) async {
    final List<GameLibraryEntry> entries =
        await loadCurrentLibrary();
    entries.removeWhere(
      (entry) => entry.id == id,
    );
    await saveCurrentLibrary(entries);
  }

  static Future<({int added, int updated})>
      mergeSteamGames(
    List<GameLibraryEntry> imported,
  ) async {
    List<GameLibraryEntry> entries =
        await loadCurrentLibrary();

    // Nettoie d'abord les doublons créés par les anciennes versions :
    // ex. Rocket League PlayStation + Rocket League Steam.
    entries = _collapsePlatformDuplicates(entries);

    int added = 0;
    int updated = 0;

    for (final GameLibraryEntry incoming
        in imported) {
      final GamePlatformProfile? incomingSteam =
          incoming.platformProfile(GamePlatform.steam);

      if (incomingSteam == null ||
          (incomingSteam.externalId?.isEmpty ?? true)) {
        continue;
      }

      // 1. Correspondance officielle Steam : priorité absolue à l'AppID.
      int index = entries.indexWhere(
        (entry) {
          final GamePlatformProfile? steam =
              entry.platformProfile(GamePlatform.steam);
          return steam?.externalId ==
              incomingSteam.externalId;
        },
      );

      // 2. Pas encore lié : tentative de fusion stricte par titre.
      if (index == -1) {
        index = entries.indexWhere(
          (entry) =>
              _sameCanonicalTitle(
                entry.title,
                incoming.title,
              ) &&
              _releaseYearsCompatible(
                entry.releaseYear,
                incoming.releaseYear,
              ),
        );
      }

      if (index == -1) {
        entries.add(
          incoming.copyWith(
            platformProfiles:
                incoming.resolvedPlatformProfiles,
          ),
        );
        added += 1;
        continue;
      }

      final GameLibraryEntry existing =
          entries[index];

      entries[index] = _mergeDuplicateEntry(
        existing,
        incoming,
      ).copyWith(
        updatedAt: DateTime.now(),
      );

      updated += 1;
    }

    // Une seconde passe garantit qu'un ancien doublon restant avec le même
    // titre strict est regroupé après l'import.
    entries = _collapsePlatformDuplicates(entries);

    entries.sort(
      (a, b) =>
          b.updatedAt.compareTo(a.updatedAt),
    );

    await saveCurrentLibrary(entries);
    return (added: added, updated: updated);
  }

  static List<GameLibraryEntry>
      _collapsePlatformDuplicates(
    List<GameLibraryEntry> source,
  ) {
    final List<GameLibraryEntry> result =
        <GameLibraryEntry>[];

    for (final GameLibraryEntry entry in source) {
      final int index = result.indexWhere(
        (candidate) =>
            _sameCanonicalTitle(
              candidate.title,
              entry.title,
            ) &&
            _releaseYearsCompatible(
              candidate.releaseYear,
              entry.releaseYear,
            ) &&
            _canMergePlatformEntries(
              candidate,
              entry,
            ),
      );

      if (index == -1) {
        result.add(entry);
      } else {
        result[index] = _mergeDuplicateEntry(
          result[index],
          entry,
        );
      }
    }

    return result;
  }

  static bool _canMergePlatformEntries(
    GameLibraryEntry a,
    GameLibraryEntry b,
  ) {
    final Set<GamePlatform> aPlatforms =
        a.connectedPlatforms.toSet();
    final Set<GamePlatform> bPlatforms =
        b.connectedPlatforms.toSet();

    // On ne fusionne automatiquement que si au moins une des deux fiches
    // possède une connexion plateforme importée. Ça évite d'écraser deux
    // ajouts manuels volontairement distincts portant le même nom.
    final bool importedPlatform =
        a.resolvedPlatformProfiles.any(
              (profile) =>
                  profile.source != GameSource.manual,
            ) ||
            b.resolvedPlatformProfiles.any(
              (profile) =>
                  profile.source != GameSource.manual,
            );

    if (!importedPlatform) {
      return false;
    }

    // Deux profils de la même plateforme avec deux IDs officiels différents
    // ne doivent jamais être fusionnés automatiquement.
    for (final GamePlatform platform
        in aPlatforms.intersection(bPlatforms)) {
      final String? aId =
          a.platformProfile(platform)?.externalId;
      final String? bId =
          b.platformProfile(platform)?.externalId;

      if (aId != null &&
          bId != null &&
          aId.isNotEmpty &&
          bId.isNotEmpty &&
          aId != bId) {
        return false;
      }
    }

    return true;
  }

  static GameLibraryEntry _mergeDuplicateEntry(
    GameLibraryEntry a,
    GameLibraryEntry b,
  ) {
    final GameLibraryEntry preferred =
        _metadataScore(a) >= _metadataScore(b)
            ? a
            : b;
    final GameLibraryEntry other =
        identical(preferred, a) ? b : a;

    final Map<GamePlatform, GamePlatformProfile> profiles =
        <GamePlatform, GamePlatformProfile>{};

    for (final GamePlatformProfile profile
        in preferred.resolvedPlatformProfiles) {
      profiles[profile.platform] = profile;
    }

    for (final GamePlatformProfile profile
        in other.resolvedPlatformProfiles) {
      final GamePlatformProfile? current =
          profiles[profile.platform];
      profiles[profile.platform] = current == null
          ? profile
          : _mergePlatformProfile(
              current,
              profile,
            );
    }

    final List<GamePlatformProfile> mergedProfiles =
        profiles.values.toList()
          ..sort(
            (x, y) =>
                x.platform.index.compareTo(y.platform.index),
          );

    final GameStatus status =
        preferred.status != GameStatus.unclassified
            ? preferred.status
            : other.status;

    return preferred.copyWith(
      status: status,
      favorite: preferred.favorite || other.favorite,
      progressPercent:
          preferred.progressPercent >= other.progressPercent
              ? preferred.progressPercent
              : other.progressPercent,
      catalogId:
          preferred.catalogId ?? other.catalogId,
      coverUrl:
          _mergedCoverUrl(preferred, other),
      coverFallbackUrls:
          _mergedCoverFallbackUrls(
        preferred,
        other,
      ),
      summary:
          preferred.summary ?? other.summary,
      releaseYear:
          preferred.releaseYear ?? other.releaseYear,
      genres: preferred.genres.isNotEmpty
          ? preferred.genres
          : other.genres,
      catalogPlatforms:
          preferred.catalogPlatforms.isNotEmpty
              ? preferred.catalogPlatforms
              : other.catalogPlatforms,
      platformProfiles: mergedProfiles,
      updatedAt: preferred.updatedAt.isAfter(other.updatedAt)
          ? preferred.updatedAt
          : other.updatedAt,
    );
  }

  static GamePlatformProfile _mergePlatformProfile(
    GamePlatformProfile a,
    GamePlatformProfile b,
  ) {
    final bool bHasDetails =
        b.achievementDetails.isNotEmpty;
    final bool aHasDetails =
        a.achievementDetails.isNotEmpty;

    final GamePlatformProfile detailWinner =
        bHasDetails && !aHasDetails ? b : a;

    final String? externalId =
        (a.externalId?.isNotEmpty ?? false)
            ? a.externalId
            : b.externalId;

    return detailWinner.copyWith(
      source: a.source != GameSource.manual
          ? a.source
          : b.source,
      externalId: externalId,
      playtimeMinutes:
          a.playtimeMinutes >= b.playtimeMinutes
              ? a.playtimeMinutes
              : b.playtimeMinutes,
      achievements: bHasDetails && !aHasDetails
          ? b.computedAchievementSummary
          : a.computedAchievementSummary,
      achievementDetails:
          detailWinner.achievementDetails,
      achievementCatalogInitialized:
          a.achievementCatalogInitialized ||
              b.achievementCatalogInitialized,
      achievementsLastSyncedAt:
          _latestDate(
            a.achievementsLastSyncedAt,
            b.achievementsLastSyncedAt,
          ),
      lastPlayedAt:
          _latestDate(
            a.lastPlayedAt,
            b.lastPlayedAt,
          ),
    );
  }

  static DateTime? _latestDate(
    DateTime? a,
    DateTime? b,
  ) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a.isAfter(b) ? a : b;
  }

  static String? _mergedCoverUrl(
    GameLibraryEntry a,
    GameLibraryEntry b,
  ) {
    final String aUrl = a.coverUrl?.trim() ?? '';
    final String bUrl = b.coverUrl?.trim() ?? '';

    bool isSteamAsset(String value) =>
        value.contains('steamstatic.com/steam/apps/') ||
        value.contains('steampowered.com/steamcommunity/');

    bool isVerticalSteamAsset(String value) =>
        value.contains('library_600x900');

    // Une jaquette catalogue / manuelle déjà propre reste prioritaire face
    // aux assets techniques Steam.
    if (aUrl.isNotEmpty && !isSteamAsset(aUrl)) {
      return aUrl;
    }
    if (bUrl.isNotEmpty && !isSteamAsset(bUrl)) {
      return bUrl;
    }

    // Pour un jeu purement Steam, on privilégie la capsule verticale.
    if (aUrl.isNotEmpty && isVerticalSteamAsset(aUrl)) {
      return aUrl;
    }
    if (bUrl.isNotEmpty && isVerticalSteamAsset(bUrl)) {
      return bUrl;
    }

    if (aUrl.isNotEmpty) {
      return aUrl;
    }
    if (bUrl.isNotEmpty) {
      return bUrl;
    }
    return null;
  }

  static List<String> _mergedCoverFallbackUrls(
    GameLibraryEntry a,
    GameLibraryEntry b,
  ) {
    final String? primary = _mergedCoverUrl(a, b);
    final List<String> result = <String>[];

    void add(String? raw) {
      final String value = raw?.trim() ?? '';
      if (value.isEmpty ||
          value == primary ||
          result.contains(value)) {
        return;
      }
      result.add(value);
    }

    add(a.coverUrl);
    add(b.coverUrl);

    for (final String value in a.coverFallbackUrls) {
      add(value);
    }
    for (final String value in b.coverFallbackUrls) {
      add(value);
    }

    return result;
  }

  static int _metadataScore(
    GameLibraryEntry entry,
  ) {
    int score = 0;

    if (entry.catalogId?.isNotEmpty ?? false) {
      score += 8;
    }
    if (entry.summary?.isNotEmpty ?? false) {
      score += 4;
    }
    if (entry.coverUrl?.isNotEmpty ?? false) {
      score += 2;
    }
    if (entry.releaseYear != null) {
      score += 2;
    }
    if (entry.source == GameSource.manual) {
      score += 2;
    }
    if (entry.platform != GamePlatform.steam) {
      score += 1;
    }

    return score;
  }

  static bool _releaseYearsCompatible(
    int? a,
    int? b,
  ) {
    if (a == null || b == null) {
      return true;
    }

    return a == b;
  }

  static bool _sameCanonicalTitle(
    String a,
    String b,
  ) {
    return _canonicalTitle(a) ==
        _canonicalTitle(b);
  }

  static String _canonicalTitle(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll('™', '')
        .replaceAll('®', '')
        .replaceAll('©', '')
        .replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '',
        );
  }

  // ===========================================================================
  // FIL D'AVENTURE
  // ===========================================================================

  static Future<List<GamingActivityEvent>>
      loadCurrentActivity() async {
    final String? userId = await _currentUserId();

    if (userId == null || userId.isEmpty) {
      return <GamingActivityEvent>[];
    }

    final List<GamingActivityEvent> local =
        await _loadLocalActivity(userId);

    final CloudReadResult<List<GamingActivityEvent>> cloud =
        await CloudDataService.loadGamingActivity();

    if (!cloud.available) {
      return local;
    }

    final List<GamingActivityEvent> remote =
        cloud.found && cloud.value != null
            ? cloud.value!
            : <GamingActivityEvent>[];

    final Map<String, GamingActivityEvent> merged =
        <String, GamingActivityEvent>{};

    for (final GamingActivityEvent event
        in <GamingActivityEvent>[
      ...remote,
      ...local,
    ]) {
      if (_isLegacyLibraryJoinEvent(event)) {
        continue;
      }

      final GamingActivityEvent? existing =
          merged[event.id];

      if (existing == null ||
          event.createdAt.isAfter(
            existing.createdAt,
          )) {
        merged[event.id] = event;
      }
    }

    final List<GamingActivityEvent> result =
        merged.values.toList()
          ..sort(
            (a, b) =>
                b.createdAt.compareTo(a.createdAt),
          );

    final List<GamingActivityEvent> kept =
        result.take(_maxActivityEvents).toList();

    await _saveLocalActivity(
      userId,
      kept,
    );

    await CloudDataService.replaceGamingActivity(
      kept,
    );

    return kept;
  }

  static Future<List<GamingActivityEvent>>
      _loadLocalActivity(
    String userId,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();
    final String? raw =
        prefs.getString(_activityKey(userId));

    if (raw == null || raw.isEmpty) {
      return <GamingActivityEvent>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <GamingActivityEvent>[];
      }

      final List<GamingActivityEvent> events = decoded
          .whereType<Map>()
          .map(
            (item) => GamingActivityEvent.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (event) =>
                !_isLegacyLibraryJoinEvent(event),
          )
          .toList();

      events.sort(
        (a, b) =>
            b.createdAt.compareTo(a.createdAt),
      );

      return events;
    } catch (_) {
      return <GamingActivityEvent>[];
    }
  }

  static bool _isLegacyLibraryJoinEvent(
    GamingActivityEvent event,
  ) {
    return event.title
        .toLowerCase()
        .contains('rejoint ta bibliothèque');
  }

  static Future<void> _saveLocalActivity(
    String userId,
    List<GamingActivityEvent> events,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _activityKey(userId),
      jsonEncode(
        events.map((event) => event.toJson()).toList(),
      ),
    );
  }

  static Future<void> addActivity({
    required String title,
    required String detail,
  }) async {
    final String? userId = await _currentUserId();

    if (userId == null || userId.isEmpty) {
      return;
    }

    final List<GamingActivityEvent> events =
        await loadCurrentActivity();
    final DateTime now = DateTime.now();

    events.insert(
      0,
      GamingActivityEvent(
        id: 'activity_${now.microsecondsSinceEpoch}',
        title: title,
        detail: detail,
        createdAt: now,
      ),
    );

    final List<GamingActivityEvent> kept =
        events.take(_maxActivityEvents).toList();

    await _saveLocalActivity(
      userId,
      kept,
    );

    await CloudDataService.replaceGamingActivity(
      kept,
    );
  }

  // ===========================================================================
  // SYNCHRONISATION DE DÉMARRAGE
  // ===========================================================================

  static Future<void> syncCurrentDataWithCloud() async {
    await loadCurrentLibrary();
    await loadCurrentActivity();
  }
}
