import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_library_entry.dart';
import 'auth_service.dart';
import 'cloud_data_service.dart';

class GameLibraryService {
  GameLibraryService._();

  static const String _libraryPrefix = 'project_xp_game_library_v1_';
  static const String _activityPrefix = 'project_xp_gaming_activity_v1_';
  static const String _cloudMigratedPrefix =
      'project_xp_game_library_cloud_migrated_v1_';
  static const String _cloudDirtyPrefix =
      'project_xp_game_library_cloud_dirty_v1_';
  static const String _pendingDeletePrefix =
      'project_xp_game_library_pending_deletes_v1_';
  static const String _activityDirtyPrefix =
      'project_xp_gaming_activity_cloud_dirty_v1_';
  static const int _maxActivityEvents = 100;
  static const Duration _cloudRefreshCooldown = Duration(minutes: 1);

  static int _libraryRevision = 0;
  static int _activityRevision = 0;
  static Future<void>? _libraryPushTask;
  static Future<void>? _libraryRefreshTask;
  static Future<void>? _activityPushTask;
  static Future<void>? _activityRefreshTask;
  static DateTime? _lastLibraryRefreshAt;
  static DateTime? _lastActivityRefreshAt;
  static String? _libraryCacheUserId;
  static List<GameLibraryEntry>? _libraryCache;
  static String? _activityCacheUserId;
  static List<GamingActivityEvent>? _activityCache;

  static Future<String?> _currentUserId() => AuthService.getCurrentUserId();

  static String _libraryKey(String userId) => '$_libraryPrefix$userId';
  static String _activityKey(String userId) => '$_activityPrefix$userId';
  static String _migratedKey(String authUserId) =>
      '$_cloudMigratedPrefix$authUserId';
  static String _dirtyKey(String authUserId) => '$_cloudDirtyPrefix$authUserId';
  static String _pendingDeleteKey(String authUserId) =>
      '$_pendingDeletePrefix$authUserId';
  static String _activityDirtyKey(String authUserId) =>
      '$_activityDirtyPrefix$authUserId';

  // ===========================================================================
  // BIBLIOTHÈQUE : LOCAL D'ABORD
  // ===========================================================================

  static Future<List<GameLibraryEntry>> loadCurrentLibrary() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return <GameLibraryEntry>[];
    }

    final List<GameLibraryEntry> local = await _loadLocalLibrary(userId);
    _scheduleLibraryMaintenance(userId);
    return local;
  }

  static Future<List<GameLibraryEntry>> loadCurrentLibraryConsolidated() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return <GameLibraryEntry>[];
    }

    final List<GameLibraryEntry> local = await _loadLocalLibrary(userId);
    final List<GameLibraryEntry> collapsed = _collapsePlatformDuplicates(local);

    if (collapsed.length != local.length) {
      await saveCurrentLibrary(collapsed);
    } else {
      _scheduleLibraryMaintenance(userId);
    }

    return collapsed;
  }

  static Future<List<GameLibraryEntry>> _loadCurrentLibraryForWrite() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return <GameLibraryEntry>[];
    }
    return _loadLocalLibrary(userId);
  }

  static Future<List<GameLibraryEntry>> _loadLocalLibrary(String userId) async {
    if (_libraryCacheUserId == userId && _libraryCache != null) {
      return List<GameLibraryEntry>.from(_libraryCache!);
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_libraryKey(userId));
    if (raw == null || raw.isEmpty) {
      _libraryCacheUserId = userId;
      _libraryCache = <GameLibraryEntry>[];
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
            (item) =>
                GameLibraryEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((entry) => entry.id.isNotEmpty)
          .toList();

      entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _libraryCacheUserId = userId;
      _libraryCache = List<GameLibraryEntry>.from(entries);
      return entries;
    } catch (_) {
      return <GameLibraryEntry>[];
    }
  }

  static Future<void> _saveLocalLibrary(
    String userId,
    List<GameLibraryEntry> entries,
  ) async {
    _libraryCacheUserId = userId;
    _libraryCache = List<GameLibraryEntry>.from(entries);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _libraryKey(userId),
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    _libraryRevision += 1;
  }

  static void _scheduleLibraryMaintenance(String userId) {
    if (CloudDataService.permanentUser == null) {
      return;
    }

    unawaited(() async {
      final authUser = CloudDataService.permanentUser;
      if (authUser == null) {
        return;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool dirty = prefs.getBool(_dirtyKey(authUser.id)) ?? false;
      if (dirty) {
        _scheduleLibraryPush(userId);
      } else {
        _scheduleLibraryRefresh(userId);
      }
    }());
  }

  static void _scheduleLibraryRefresh(String userId) {
    if (_libraryRefreshTask != null || CloudDataService.permanentUser == null) {
      return;
    }

    final DateTime now = DateTime.now();
    if (_lastLibraryRefreshAt != null &&
        now.difference(_lastLibraryRefreshAt!) < _cloudRefreshCooldown) {
      return;
    }

    final int revision = _libraryRevision;
    final Future<void> task = _refreshLibraryFromCloud(userId, revision);
    _libraryRefreshTask = task;
    unawaited(task);
  }

  static Future<void> _refreshLibraryFromCloud(
    String userId,
    int revision,
  ) async {
    try {
      final authUser = CloudDataService.permanentUser;
      if (authUser == null) {
        return;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_dirtyKey(authUser.id)) ?? false) {
        return;
      }

      final CloudReadResult<List<GameLibraryEntry>> cloud =
          await CloudDataService.loadLibrary();

      if (!cloud.available || _libraryRevision != revision) {
        return;
      }

      if (!cloud.found || cloud.value == null) {
        final List<GameLibraryEntry> local = await _loadLocalLibrary(userId);
        if (local.isNotEmpty) {
          await prefs.setBool(_dirtyKey(authUser.id), true);
          _scheduleLibraryPush(userId);
        }
        return;
      }

      if (prefs.getBool(_dirtyKey(authUser.id)) ?? false) {
        return;
      }

      final Set<String> pending = _readPendingDeletes(prefs, authUser.id);
      final List<GameLibraryEntry> remote = List<GameLibraryEntry>.from(
        cloud.value!,
      )..removeWhere((entry) => pending.contains(entry.id));

      if (_libraryRevision == revision) {
        await _saveLocalLibrary(userId, remote);
      }
    } catch (_) {
      // Le cache local reste toujours utilisable.
    } finally {
      _lastLibraryRefreshAt = DateTime.now();
      _libraryRefreshTask = null;
    }
  }

  // ===========================================================================
  // BIBLIOTHÈQUE : SAUVEGARDE LOCALE IMMÉDIATE + CLOUD EN ARRIÈRE-PLAN
  // ===========================================================================

  static Future<void> saveCurrentLibrary(List<GameLibraryEntry> entries) async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final List<GameLibraryEntry> previous = await _loadLocalLibrary(userId);
    final Set<String> nextIds = entries.map((entry) => entry.id).toSet();
    final Set<String> removedIds = previous
        .map((entry) => entry.id)
        .where((id) => !nextIds.contains(id))
        .toSet();

    await _saveLocalLibrary(userId, entries);

    final authUser = CloudDataService.permanentUser;
    if (authUser == null) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dirtyKey(authUser.id), true);

    if (removedIds.isNotEmpty) {
      final Set<String> pending = _readPendingDeletes(prefs, authUser.id)
        ..addAll(removedIds);
      await prefs.setString(
        _pendingDeleteKey(authUser.id),
        jsonEncode(pending.toList()),
      );
    }

    _scheduleLibraryPush(userId);
  }

  static void _scheduleLibraryPush(String userId) {
    if (_libraryPushTask != null || CloudDataService.permanentUser == null) {
      return;
    }

    final Future<void> task = _pushLibraryToCloud(userId);
    _libraryPushTask = task;
    unawaited(task);
  }

  static Future<void> _pushLibraryToCloud(String userId) async {
    try {
      while (true) {
        final authUser = CloudDataService.permanentUser;
        if (authUser == null) {
          return;
        }

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final bool dirty = prefs.getBool(_dirtyKey(authUser.id)) ?? false;
        if (!dirty) {
          return;
        }

        final int revision = _libraryRevision;
        final List<GameLibraryEntry> local = await _loadLocalLibrary(userId);
        final Set<String> pending = _readPendingDeletes(prefs, authUser.id);

        List<GameLibraryEntry> toUpload = List<GameLibraryEntry>.from(local);

        final CloudReadResult<List<GameLibraryEntry>> cloud =
            await CloudDataService.loadLibrary();

        if (cloud.available && cloud.found && cloud.value != null) {
          final Map<String, GameLibraryEntry> merged =
              <String, GameLibraryEntry>{};

          for (final GameLibraryEntry remote in cloud.value!) {
            if (!pending.contains(remote.id)) {
              merged[remote.id] = remote;
            }
          }

          // Les jeux présents uniquement sur l'autre appareil sont conservés.
          // Pour une même fiche, les favoris et actions personnelles restent
          // protégés, tandis qu'un état Steam peut être recalculé lorsque la
          // plateforme possède une donnée de progression réellement exploitable.
          for (final GameLibraryEntry localEntry in local) {
            final GameLibraryEntry? remoteEntry = merged[localEntry.id];
            merged[localEntry.id] = remoteEntry == null
                ? localEntry
                : _mergeDuplicateEntry(remoteEntry, localEntry);
          }

          toUpload = merged.values.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        }

        final bool uploaded = await CloudDataService.replaceLibrary(toUpload);
        if (!uploaded) {
          return;
        }

        if (_libraryRevision == revision) {
          await _markLibraryCloudClean(prefs, authUser.id);
          return;
        }

        // Une autre action locale a eu lieu pendant l'envoi : on repart avec
        // la toute dernière version au lieu de déclarer le cache propre trop tôt.
      }
    } catch (_) {
      // Le flag dirty reste en place : une prochaine ouverture / sauvegarde
      // retentera automatiquement l'envoi.
    } finally {
      _libraryPushTask = null;
    }
  }

  static Set<String> _readPendingDeletes(
    SharedPreferences prefs,
    String authUserId,
  ) {
    final String? raw = prefs.getString(_pendingDeleteKey(authUserId));
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
      // Cache de suppression corrompu : on ne détruit rien.
    }

    return <String>{};
  }

  static Future<void> _markLibraryCloudClean(
    SharedPreferences prefs,
    String authUserId,
  ) async {
    await prefs.setBool(_migratedKey(authUserId), true);
    await prefs.setBool(_dirtyKey(authUserId), false);
    await prefs.remove(_pendingDeleteKey(authUserId));
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
      statusAutomatic: false,
      favorite: false,
      progressPercent: status == GameStatus.completed ? 100 : 0,
      source: GameSource.manual,
      externalId: null,
      catalogId: catalogId,
      coverUrl: coverUrl,
      summary: summary,
      releaseYear: releaseYear,
      genres: genres,
      catalogPlatforms: catalogPlatforms,
      playtimeMinutes: 0,
      achievements: const GameAchievementSummary(),
      platformProfiles: <GamePlatformProfile>[
        GamePlatformProfile(platform: platform, source: GameSource.manual),
      ],
      addedAt: now,
      personalUpdatedAt: now,
      updatedAt: now,
    );

    final List<GameLibraryEntry> entries = await _loadCurrentLibraryForWrite();
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
    final DateTime now = DateTime.now();
    final GameLibraryEntry enriched = entry.copyWith(
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
      personalUpdatedAt: now,
      updatedAt: now,
    );

    final List<GameLibraryEntry> entries = await _loadCurrentLibraryForWrite();
    final int index = entries.indexWhere((game) => game.id == entry.id);
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
    bool technicalUpdate = false,
  }) async {
    final List<GameLibraryEntry> entries = await _loadCurrentLibraryForWrite();
    final int index = entries.indexWhere((entry) => entry.id == updated.id);
    if (index == -1) {
      return;
    }

    final GameLibraryEntry previous = entries[index];
    final DateTime now = DateTime.now();
    final bool statusChanged = previous.status != updated.status;
    final bool personalStateChanged =
        !technicalUpdate &&
        (statusChanged ||
            previous.favorite != updated.favorite ||
            previous.progressPercent != updated.progressPercent ||
            _manualAchievementStateChanged(previous, updated));

    final GamePlatformProfile? primaryProfile = updated.platformProfile(
      updated.platform,
    );

    final GameLibraryEntry normalized = updated.copyWith(
      title: previous.hasOfficialPlatformConnection
          ? previous.title
          : updated.title.trim(),
      coverUrl: previous.hasOfficialPlatformConnection
          ? previous.coverUrl
          : updated.coverUrl,
      coverFallbackUrls: previous.hasOfficialPlatformConnection
          ? previous.coverFallbackUrls
          : updated.coverFallbackUrls,
      progressPercent: updated.progressPercent.clamp(0, 100).toInt(),
      playtimeMinutes:
          primaryProfile?.playtimeMinutes ?? updated.playtimeMinutes,
      achievements:
          primaryProfile?.computedAchievementSummary ??
          updated.computedAchievementSummary,
      achievementDetails:
          primaryProfile?.achievementDetails ?? updated.achievementDetails,
      achievementCatalogInitialized:
          primaryProfile?.achievementCatalogInitialized ??
          updated.achievementCatalogInitialized,
      achievementsLastSyncedAt:
          primaryProfile?.achievementsLastSyncedAt ??
          updated.achievementsLastSyncedAt,
      statusAutomatic: technicalUpdate
          ? updated.statusAutomatic
          : (statusChanged ? false : updated.statusAutomatic),
      personalUpdatedAt: personalStateChanged
          ? now
          : previous.personalUpdatedAt,
      updatedAt: technicalUpdate ? updated.updatedAt : now,
    );

    entries[index] = normalized;
    await saveCurrentLibrary(entries);

    if (technicalUpdate) {
      return;
    }

    if (previous.status != GameStatus.completed &&
        normalized.status == GameStatus.completed) {
      await addActivity(
        title: '${normalized.title} terminé',
        detail: '${normalized.platformSummaryText} • Aventure accomplie',
      );
    } else if (previous.status == GameStatus.abandoned &&
        normalized.status == GameStatus.inProgress) {
      await addActivity(
        title: '${normalized.title} reprend son aventure',
        detail: '${normalized.platformSummaryText} • Retour après abandon',
      );
    }

    if (announceAchievementUnlocks) {
      await _announceManualAchievementChanges(previous, normalized);
    }
  }

  static bool _manualAchievementStateChanged(
    GameLibraryEntry previous,
    GameLibraryEntry updated,
  ) {
    for (final GamePlatformProfile current
        in updated.resolvedPlatformProfiles) {
      final GamePlatformProfile? before = previous.platformProfile(
        current.platform,
      );
      final Map<String, GameAchievementDetail> beforeById =
          <String, GameAchievementDetail>{
            for (final GameAchievementDetail item
                in before?.achievementDetails ??
                    const <GameAchievementDetail>[])
              item.id: item,
          };

      for (final GameAchievementDetail item in current.achievementDetails) {
        final GameAchievementDetail? old = beforeById[item.id];
        if ((old?.manuallyUnlocked ?? false) != item.manuallyUnlocked) {
          return true;
        }
      }
    }
    return false;
  }

  static Future<void> _announceManualAchievementChanges(
    GameLibraryEntry previous,
    GameLibraryEntry normalized,
  ) async {
    for (final GamePlatformProfile currentProfile
        in normalized.resolvedPlatformProfiles) {
      final GamePlatformProfile? previousProfile = previous.platformProfile(
        currentProfile.platform,
      );
      final Map<String, GameAchievementDetail> previousDetails =
          <String, GameAchievementDetail>{
            for (final GameAchievementDetail achievement
                in previousProfile?.achievementDetails ??
                    const <GameAchievementDetail>[])
              achievement.id: achievement,
          };

      final List<GameAchievementDetail> newlyUnlocked = currentProfile
          .achievementDetails
          .where(
            (achievement) =>
                achievement.isUnlocked &&
                !(previousDetails[achievement.id]?.isUnlocked ?? false),
          )
          .toList();

      for (final GameAchievementDetail achievement in newlyUnlocked.take(5)) {
        final String achievementType =
            currentProfile.platform == GamePlatform.playstation
            ? 'Trophée'
            : 'Succès';
        final String source = achievement.platformUnlocked
            ? currentProfile.platform.label
            : 'coché manuellement';

        await addActivity(
          title: '$achievementType « ${achievement.name} » obtenu',
          detail: '${normalized.title} • $source',
          createdAt:
              achievement.platformUnlockedAt ?? achievement.manuallyUnlockedAt,
        );
      }

      if (newlyUnlocked.length > 5) {
        await addActivity(
          title:
              '${newlyUnlocked.length - 5} autres accomplissements sur ${normalized.title}',
          detail: currentProfile.progressText,
        );
      }

      if (currentProfile.achievementDetails.isEmpty &&
          previousProfile != null) {
        final GameAchievementSummary before =
            previousProfile.computedAchievementSummary;
        final GameAchievementSummary after =
            currentProfile.computedAchievementSummary;

        if (after.platinumUnlocked > before.platinumUnlocked) {
          await addActivity(
            title: 'Platine obtenu sur ${normalized.title}',
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
              detail: currentProfile.progressText,
            );
          }
        }
      }
    }
  }

  static Future<void> toggleFavorite(GameLibraryEntry entry) {
    return updateGame(entry.copyWith(favorite: !entry.favorite));
  }

  static Future<void> removeGame(String id) async {
    final List<GameLibraryEntry> entries = await _loadCurrentLibraryForWrite();
    entries.removeWhere((entry) => entry.id == id);
    await saveCurrentLibrary(entries);
  }

  static Future<({int added, int updated})> mergeSteamGames(
    List<GameLibraryEntry> imported,
  ) async {
    List<GameLibraryEntry> entries = await _loadCurrentLibraryForWrite();
    entries = _collapsePlatformDuplicates(entries);

    int added = 0;
    int updated = 0;

    for (final GameLibraryEntry incoming in imported) {
      final GamePlatformProfile? incomingSteam = incoming.platformProfile(
        GamePlatform.steam,
      );
      if (incomingSteam == null ||
          (incomingSteam.externalId?.isEmpty ?? true)) {
        continue;
      }

      int index = entries.indexWhere((entry) {
        final GamePlatformProfile? steam = entry.platformProfile(
          GamePlatform.steam,
        );
        return steam?.externalId == incomingSteam.externalId;
      });

      if (index == -1) {
        index = entries.indexWhere(
          (entry) =>
              _sameCanonicalTitle(entry.title, incoming.title) &&
              _releaseYearsCompatible(entry.releaseYear, incoming.releaseYear),
        );
      }

      if (index == -1) {
        entries.add(
          incoming.copyWith(
            platformProfiles: incoming.resolvedPlatformProfiles,
          ),
        );
        added += 1;
        continue;
      }

      final GameLibraryEntry existing = entries[index];
      final GameLibraryEntry merged = _mergeDuplicateEntry(existing, incoming);

      DateTime recentAt = existing.updatedAt;
      final DateTime? playedAt = incomingSteam.lastPlayedAt;
      if (playedAt != null && playedAt.isAfter(recentAt)) {
        recentAt = playedAt;
      }

      final bool mayAutoClassify =
          existing.statusAutomatic ||
          existing.status == GameStatus.unclassified;

      entries[index] = merged.copyWith(
        status: mayAutoClassify ? incoming.status : existing.status,
        statusAutomatic: mayAutoClassify ? true : existing.statusAutomatic,
        favorite: existing.favorite,
        progressPercent: existing.progressPercent,
        personalUpdatedAt: existing.personalUpdatedAt,
        updatedAt: recentAt,
      );

      updated += 1;
    }

    entries = _collapsePlatformDuplicates(entries);
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveCurrentLibrary(entries);
    return (added: added, updated: updated);
  }

  static List<GameLibraryEntry> _collapsePlatformDuplicates(
    List<GameLibraryEntry> source,
  ) {
    final List<GameLibraryEntry> result = <GameLibraryEntry>[];

    for (final GameLibraryEntry entry in source) {
      final int index = result.indexWhere(
        (candidate) =>
            _sameCanonicalTitle(candidate.title, entry.title) &&
            _releaseYearsCompatible(candidate.releaseYear, entry.releaseYear) &&
            _canMergePlatformEntries(candidate, entry),
      );

      if (index == -1) {
        result.add(entry);
      } else {
        result[index] = _mergeDuplicateEntry(result[index], entry);
      }
    }

    return result;
  }

  static bool _canMergePlatformEntries(GameLibraryEntry a, GameLibraryEntry b) {
    final Set<GamePlatform> aPlatforms = a.connectedPlatforms.toSet();
    final Set<GamePlatform> bPlatforms = b.connectedPlatforms.toSet();

    final bool importedPlatform =
        a.resolvedPlatformProfiles.any(
          (profile) => profile.source != GameSource.manual,
        ) ||
        b.resolvedPlatformProfiles.any(
          (profile) => profile.source != GameSource.manual,
        );

    if (!importedPlatform) {
      return false;
    }

    for (final GamePlatform platform in aPlatforms.intersection(bPlatforms)) {
      final String? aId = a.platformProfile(platform)?.externalId;
      final String? bId = b.platformProfile(platform)?.externalId;
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
    final GameLibraryEntry preferred = _metadataScore(a) >= _metadataScore(b)
        ? a
        : b;
    final GameLibraryEntry other = identical(preferred, a) ? b : a;

    bool hasPersonalState(GameLibraryEntry entry) {
      // Compatibilité des anciennes sauvegardes : avant personalUpdatedAt, un
      // favori ou une progression manuelle était déjà une intention joueur.
      return entry.personalUpdatedAt != null ||
          !entry.statusAutomatic ||
          entry.favorite ||
          entry.progressPercent > 0;
    }

    final bool aPersonal = hasPersonalState(a);
    final bool bPersonal = hasPersonalState(b);
    final GameLibraryEntry personal;

    if (aPersonal != bPersonal) {
      personal = aPersonal ? a : b;
    } else {
      personal =
          a.effectivePersonalUpdatedAt.isAfter(b.effectivePersonalUpdatedAt)
          ? a
          : b;
    }

    final Map<GamePlatform, GamePlatformProfile> profiles =
        <GamePlatform, GamePlatformProfile>{};

    for (final GamePlatformProfile profile
        in preferred.resolvedPlatformProfiles) {
      profiles[profile.platform] = profile;
    }

    for (final GamePlatformProfile profile in other.resolvedPlatformProfiles) {
      final GamePlatformProfile? current = profiles[profile.platform];
      profiles[profile.platform] = current == null
          ? profile
          : _mergePlatformProfile(current, profile);
    }

    final List<GamePlatformProfile> mergedProfiles = profiles.values.toList()
      ..sort((x, y) => x.platform.index.compareTo(y.platform.index));

    GameStatus mergedStatus = personal.status;
    bool mergedStatusAutomatic = personal.statusAutomatic;

    GamePlatformProfile? mergedSteam;
    for (final GamePlatformProfile profile in mergedProfiles) {
      if (profile.platform == GamePlatform.steam) {
        mergedSteam = profile;
        break;
      }
    }

    if (mergedSteam != null) {
      final GameAchievementSummary steamSummary =
          mergedSteam.computedAchievementSummary;
      final int platformUnlocked = mergedSteam.achievementDetails.isNotEmpty
          ? mergedSteam.achievementDetails
                .where((achievement) => achievement.platformUnlocked)
                .length
          : steamSummary.unlocked;
      final int achievementTotal = mergedSteam.achievementDetails.isNotEmpty
          ? mergedSteam.achievementDetails.length
          : steamSummary.total;
      final bool hasKnownAchievementProgress = achievementTotal > 0;
      final bool hasStarted =
          mergedSteam.playtimeMinutes > 0 || platformUnlocked > 0;

      final bool preserveManualOutcome =
          !hasKnownAchievementProgress &&
          !personal.statusAutomatic &&
          (personal.status == GameStatus.completed ||
              personal.status == GameStatus.abandoned);

      if (!preserveManualOutcome) {
        if (hasKnownAchievementProgress &&
            platformUnlocked >= achievementTotal) {
          mergedStatus = GameStatus.completed;
        } else if (hasStarted) {
          mergedStatus = GameStatus.inProgress;
        } else {
          mergedStatus = GameStatus.backlog;
        }
        mergedStatusAutomatic = true;
      }
    }

    return preferred.copyWith(
      status: mergedStatus,
      statusAutomatic: mergedStatusAutomatic,
      favorite: personal.favorite,
      progressPercent: personal.progressPercent,
      catalogId: preferred.catalogId ?? other.catalogId,
      coverUrl: _mergedCoverUrl(preferred, other),
      coverFallbackUrls: _mergedCoverFallbackUrls(preferred, other),
      summary: preferred.summary ?? other.summary,
      releaseYear: preferred.releaseYear ?? other.releaseYear,
      genres: preferred.genres.isNotEmpty ? preferred.genres : other.genres,
      catalogPlatforms: preferred.catalogPlatforms.isNotEmpty
          ? preferred.catalogPlatforms
          : other.catalogPlatforms,
      platformProfiles: mergedProfiles,
      personalUpdatedAt: _latestDate(a.personalUpdatedAt, b.personalUpdatedAt),
      updatedAt: preferred.updatedAt.isAfter(other.updatedAt)
          ? preferred.updatedAt
          : other.updatedAt,
    );
  }

  static GamePlatformProfile _mergePlatformProfile(
    GamePlatformProfile a,
    GamePlatformProfile b,
  ) {
    final String? externalId = (a.externalId?.isNotEmpty ?? false)
        ? a.externalId
        : b.externalId;

    GamePlatformProfile achievementWinner = a;
    final DateTime? aSync = a.achievementsLastSyncedAt;
    final DateTime? bSync = b.achievementsLastSyncedAt;

    if (aSync == null && bSync != null) {
      achievementWinner = b;
    } else if (aSync != null && bSync != null && bSync.isAfter(aSync)) {
      achievementWinner = b;
    } else if (aSync == null &&
        bSync == null &&
        b.achievementDetails.length > a.achievementDetails.length) {
      achievementWinner = b;
    }

    final Map<String, GameAchievementDetail> mergedDetails =
        <String, GameAchievementDetail>{};

    void absorb(List<GameAchievementDetail> details) {
      for (final GameAchievementDetail incoming in details) {
        final GameAchievementDetail? current = mergedDetails[incoming.id];
        if (current == null) {
          mergedDetails[incoming.id] = incoming;
          continue;
        }

        final bool platformUnlocked =
            current.platformUnlocked || incoming.platformUnlocked;
        final bool manuallyUnlocked = platformUnlocked
            ? false
            : (current.manuallyUnlocked || incoming.manuallyUnlocked);

        mergedDetails[incoming.id] = current.copyWith(
          platformUnlocked: platformUnlocked,
          manuallyUnlocked: manuallyUnlocked,
          platformUnlockedAt: _latestDate(
            current.platformUnlockedAt,
            incoming.platformUnlockedAt,
          ),
          manuallyUnlockedAt: manuallyUnlocked
              ? _latestDate(
                  current.manuallyUnlockedAt,
                  incoming.manuallyUnlockedAt,
                )
              : null,
          clearManuallyUnlockedAt: !manuallyUnlocked,
        );
      }
    }

    // Le snapshot le plus récent fournit le catalogue de référence ; l'autre
    // snapshot complète seulement les états déjà connus afin de ne pas perdre
    // une coche manuelle ou un succès officiel pendant une fusion Cloud.
    absorb(achievementWinner.achievementDetails);
    absorb(
      identical(achievementWinner, a)
          ? b.achievementDetails
          : a.achievementDetails,
    );

    final List<GameAchievementDetail> details = mergedDetails.values.toList()
      ..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));

    GamePlatformProfile merged = achievementWinner.copyWith(
      source: a.source != GameSource.manual ? a.source : b.source,
      externalId: externalId,
      playtimeMinutes: a.playtimeMinutes >= b.playtimeMinutes
          ? a.playtimeMinutes
          : b.playtimeMinutes,
      achievementDetails: details,
      achievementCatalogInitialized:
          a.achievementCatalogInitialized || b.achievementCatalogInitialized,
      achievementsLastSyncedAt: _latestDate(
        a.achievementsLastSyncedAt,
        b.achievementsLastSyncedAt,
      ),
      lastPlayedAt: _latestDate(a.lastPlayedAt, b.lastPlayedAt),
    );

    merged = merged.copyWith(
      achievements: details.isNotEmpty
          ? merged.computedAchievementSummary
          : achievementWinner.computedAchievementSummary,
    );

    return merged;
  }

  static DateTime? _latestDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static String? _mergedCoverUrl(GameLibraryEntry a, GameLibraryEntry b) {
    final String aUrl = a.coverUrl?.trim() ?? '';
    final String bUrl = b.coverUrl?.trim() ?? '';

    bool isSteamAsset(String value) =>
        value.contains('steamstatic.com/steam/apps/') ||
        value.contains('steampowered.com/steamcommunity/');
    bool isVerticalSteamAsset(String value) =>
        value.contains('library_600x900');

    if (aUrl.isNotEmpty && !isSteamAsset(aUrl)) return aUrl;
    if (bUrl.isNotEmpty && !isSteamAsset(bUrl)) return bUrl;
    if (aUrl.isNotEmpty && isVerticalSteamAsset(aUrl)) return aUrl;
    if (bUrl.isNotEmpty && isVerticalSteamAsset(bUrl)) return bUrl;
    if (aUrl.isNotEmpty) return aUrl;
    if (bUrl.isNotEmpty) return bUrl;
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
      if (value.isEmpty || value == primary || result.contains(value)) return;
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

  static int _metadataScore(GameLibraryEntry entry) {
    int score = 0;
    if (entry.catalogId?.isNotEmpty ?? false) score += 8;
    if (entry.summary?.isNotEmpty ?? false) score += 4;
    if (entry.coverUrl?.isNotEmpty ?? false) score += 2;
    if (entry.releaseYear != null) score += 2;
    if (entry.source == GameSource.manual) score += 2;
    if (entry.platform != GamePlatform.steam) score += 1;
    return score;
  }

  static bool _releaseYearsCompatible(int? a, int? b) {
    if (a == null || b == null) return true;
    return a == b;
  }

  static bool _sameCanonicalTitle(String a, String b) =>
      _canonicalTitle(a) == _canonicalTitle(b);

  static String _canonicalTitle(String value) => value
      .toLowerCase()
      .replaceAll('™', '')
      .replaceAll('®', '')
      .replaceAll('©', '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  // ===========================================================================
  // FIL D'AVENTURE : LOCAL D'ABORD
  // ===========================================================================

  static Future<List<GamingActivityEvent>> loadCurrentActivity() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return <GamingActivityEvent>[];
    }

    final List<GamingActivityEvent> local = await _loadLocalActivity(userId);
    _scheduleActivityMaintenance(userId, local);
    return local;
  }

  static Future<List<GamingActivityEvent>> _loadLocalActivity(
    String userId,
  ) async {
    if (_activityCacheUserId == userId && _activityCache != null) {
      return List<GamingActivityEvent>.from(_activityCache!);
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_activityKey(userId));
    if (raw == null || raw.isEmpty) {
      _activityCacheUserId = userId;
      _activityCache = <GamingActivityEvent>[];
      return <GamingActivityEvent>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <GamingActivityEvent>[];

      final List<GamingActivityEvent> events =
          decoded
              .whereType<Map>()
              .map(
                (item) => GamingActivityEvent.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((event) => !_isLegacyLibraryJoinEvent(event))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _activityCacheUserId = userId;
      _activityCache = List<GamingActivityEvent>.from(events);
      return events;
    } catch (_) {
      return <GamingActivityEvent>[];
    }
  }

  static Future<void> _saveLocalActivity(
    String userId,
    List<GamingActivityEvent> events, {
    bool markCloudDirty = true,
  }) async {
    _activityCacheUserId = userId;
    _activityCache = List<GamingActivityEvent>.from(events);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _activityKey(userId),
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );

    final authUser = CloudDataService.permanentUser;
    if (markCloudDirty && authUser != null) {
      await prefs.setBool(_activityDirtyKey(authUser.id), true);
    }

    _activityRevision += 1;
  }

  static bool _isLegacyLibraryJoinEvent(GamingActivityEvent event) =>
      event.title.toLowerCase().contains('rejoint ta bibliothèque');

  static Future<void> addActivity({
    required String title,
    required String detail,
    DateTime? createdAt,
  }) async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final List<GamingActivityEvent> events = await _loadLocalActivity(userId);
    final DateTime now = DateTime.now();
    final DateTime eventDate = createdAt ?? now;

    events.add(
      GamingActivityEvent(
        id: 'activity_${now.microsecondsSinceEpoch}',
        title: title,
        detail: detail,
        createdAt: eventDate,
      ),
    );

    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final List<GamingActivityEvent> kept = events
        .take(_maxActivityEvents)
        .toList();
    await _saveLocalActivity(userId, kept);
    _scheduleActivityPush(userId);
  }

  static void _scheduleActivityMaintenance(
    String userId,
    List<GamingActivityEvent> local,
  ) {
    if (CloudDataService.permanentUser == null) {
      return;
    }

    unawaited(() async {
      final authUser = CloudDataService.permanentUser;
      if (authUser == null) return;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool dirty = prefs.getBool(_activityDirtyKey(authUser.id)) ?? false;

      if (dirty) {
        _scheduleActivityPush(userId);
      } else {
        _scheduleActivityRefresh(userId, local);
      }
    }());
  }

  static void _scheduleActivityPush(String userId) {
    if (_activityPushTask != null || CloudDataService.permanentUser == null) {
      return;
    }
    final Future<void> task = _pushActivityToCloud(userId);
    _activityPushTask = task;
    unawaited(task);
  }

  static Future<void> _pushActivityToCloud(String userId) async {
    try {
      while (true) {
        final authUser = CloudDataService.permanentUser;
        if (authUser == null) return;

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final bool dirty =
            prefs.getBool(_activityDirtyKey(authUser.id)) ?? false;
        if (!dirty) return;

        final int revision = _activityRevision;
        final List<GamingActivityEvent> local = await _loadLocalActivity(
          userId,
        );
        final CloudReadResult<List<GamingActivityEvent>> cloud =
            await CloudDataService.loadGamingActivity();

        final Map<String, GamingActivityEvent> merged =
            <String, GamingActivityEvent>{};

        if (cloud.available && cloud.found && cloud.value != null) {
          for (final GamingActivityEvent event in cloud.value!) {
            if (!_isLegacyLibraryJoinEvent(event)) merged[event.id] = event;
          }
        }
        for (final GamingActivityEvent event in local) {
          merged[event.id] = event;
        }

        final List<GamingActivityEvent> toUpload = merged.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final bool uploaded = await CloudDataService.replaceGamingActivity(
          toUpload.take(_maxActivityEvents).toList(),
        );
        if (!uploaded) {
          return;
        }
        if (_activityRevision == revision) {
          await prefs.setBool(_activityDirtyKey(authUser.id), false);
          return;
        }
      }
    } catch (_) {
      // L'activité reste sauvegardée localement.
    } finally {
      _activityPushTask = null;
    }
  }

  static void _scheduleActivityRefresh(
    String userId,
    List<GamingActivityEvent> local,
  ) {
    if (_activityRefreshTask != null ||
        _activityPushTask != null ||
        CloudDataService.permanentUser == null) {
      return;
    }

    final DateTime now = DateTime.now();
    if (_lastActivityRefreshAt != null &&
        now.difference(_lastActivityRefreshAt!) < _cloudRefreshCooldown) {
      return;
    }

    final int revision = _activityRevision;
    final Future<void> task = _refreshActivityFromCloud(
      userId,
      local,
      revision,
    );
    _activityRefreshTask = task;
    unawaited(task);
  }

  static Future<void> _refreshActivityFromCloud(
    String userId,
    List<GamingActivityEvent> local,
    int revision,
  ) async {
    try {
      final authUser = CloudDataService.permanentUser;
      if (authUser == null) return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_activityDirtyKey(authUser.id)) ?? false) {
        _scheduleActivityPush(userId);
        return;
      }

      final CloudReadResult<List<GamingActivityEvent>> cloud =
          await CloudDataService.loadGamingActivity();
      if (!cloud.available || !cloud.found || cloud.value == null) return;
      if (_activityRevision != revision) return;

      final Map<String, GamingActivityEvent> merged =
          <String, GamingActivityEvent>{};
      for (final GamingActivityEvent event in <GamingActivityEvent>[
        ...cloud.value!,
        ...local,
      ]) {
        if (_isLegacyLibraryJoinEvent(event)) continue;
        final GamingActivityEvent? existing = merged[event.id];
        if (existing == null || event.createdAt.isAfter(existing.createdAt)) {
          merged[event.id] = event;
        }
      }

      final List<GamingActivityEvent> result = merged.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (_activityRevision == revision) {
        await _saveLocalActivity(
          userId,
          result.take(_maxActivityEvents).toList(),
          markCloudDirty: false,
        );
      }
    } catch (_) {
      // Aucun blocage d'écran si Supabase est lent ou indisponible.
    } finally {
      _lastActivityRefreshAt = DateTime.now();
      _activityRefreshTask = null;
    }
  }

  // ===========================================================================
  // SYNCHRONISATION EXPLICITE
  // ===========================================================================

  static Future<void> syncCurrentDataWithCloud() async {
    final String? userId = await _currentUserId();
    if (userId == null || userId.isEmpty) return;

    final authUser = CloudDataService.permanentUser;
    if (authUser == null) return;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_dirtyKey(authUser.id)) ?? false) {
      await _pushLibraryToCloud(userId);
    } else {
      await _refreshLibraryFromCloud(userId, _libraryRevision);
    }

    await _pushActivityToCloud(userId);
    final List<GamingActivityEvent> localActivity = await _loadLocalActivity(
      userId,
    );
    await _refreshActivityFromCloud(userId, localActivity, _activityRevision);
  }
}
