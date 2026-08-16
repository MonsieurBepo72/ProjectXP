import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Réparation ponctuelle des données locales créées AVANT le passage
/// au stockage multi-comptes.
///
/// Cette migration ne supprime rien :
/// - elle sauvegarde l'ancien profile_data ;
/// - elle rattache l'ancien profil Vieti au bon compte historique ;
/// - elle rattache l'ancien e-mail au bon ID ;
/// - elle crée un profil propre pour le compte Isto uniquement s'il n'en a pas ;
/// - elle ne touche PAS aux avatars, équipes ou demandes Squad.
///
/// Une fois exécutée avec succès, elle ne se relance plus.
class LocalAccountRepairService {
  const LocalAccountRepairService._();

  static const String _doneKey =
      'project_xp_identity_repair_20260816_done';

  static const String _accountsKey =
      'project_xp_accounts_v2';

  static const String _legacyProfileKey =
      'profile_data';

  static const String _legacyProfileUserIdKey =
      'profile_user_id';

  static const String _legacyMigrationTargetKey =
      'project_xp_profile_legacy_migrated_to';

  static const String _backupLegacyProfileKey =
      'project_xp_legacy_profile_backup_20260816';

  // ---------------------------------------------------------------------------
  // Données identifiées dans TON stockage local.
  // ---------------------------------------------------------------------------

  static const String _vietiId =
      '1786908432042';

  static const String _vietiUsername =
      'Vieti';

  static const String _vietiEmail =
      'yaiitsu72@gmail.com';

  static const String _istoId =
      '1786911022322';

  static const String _istoUsername =
      'Isto';

  static const String _istoEmail =
      'test@test.fr';

  static Future<void> runOnce() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    if (prefs.getBool(_doneKey) == true) {
      return;
    }

    // =========================================================================
    // 1. Sauvegarde de l'ancien profil global AVANT toute modification.
    // =========================================================================

    final String? legacyProfileRaw =
        prefs.getString(_legacyProfileKey);

    if (legacyProfileRaw != null &&
        legacyProfileRaw.isNotEmpty &&
        !prefs.containsKey(
          _backupLegacyProfileKey,
        )) {
      await prefs.setString(
        _backupLegacyProfileKey,
        legacyProfileRaw,
      );
    }

    // =========================================================================
    // 2. Réparation du registre de comptes.
    // =========================================================================

    final List<Map<String, dynamic>> accounts =
        _readAccounts(
      prefs.getString(_accountsKey),
    );

    _upsertAccount(
      accounts,
      id: _vietiId,
      username: _vietiUsername,
      email: _vietiEmail,
      legacy: false,
    );

    _upsertAccount(
      accounts,
      id: _istoId,
      username: _istoUsername,
      email: _istoEmail,
      legacy: false,
    );

    await prefs.setString(
      _accountsKey,
      jsonEncode(accounts),
    );

    // =========================================================================
    // 3. L'ancien profile_data appartient à Vieti.
    // =========================================================================

    if (legacyProfileRaw != null &&
        legacyProfileRaw.isNotEmpty) {
      final Map<String, dynamic> legacyProfile =
          _decodeMap(
        legacyProfileRaw,
      );

      if (legacyProfile.isNotEmpty) {
        final String vietiProfileKey =
            'project_xp_profile_$_vietiId';

        // Si une donnée par compte existait déjà, on la sauvegarde également.
        final String? existingVietiProfile =
            prefs.getString(
          vietiProfileKey,
        );

        if (existingVietiProfile != null &&
            existingVietiProfile.isNotEmpty) {
          await prefs.setString(
            '${vietiProfileKey}_backup_20260816',
            existingVietiProfile,
          );
        }

        final Map<String, dynamic> vietiProfile = {
          ...legacyProfile,
          'id': _vietiId,
          'userId': _vietiId,
          'pseudo': _vietiUsername,
          'email': _vietiEmail,
        };

        await prefs.setString(
          vietiProfileKey,
          jsonEncode(vietiProfile),
        );
      }
    }

    // =========================================================================
    // 4. Profil du compte Isto.
    //
    // On ne remplace JAMAIS un profil Isto déjà présent.
    // S'il n'existe pas, on crée seulement une base propre.
    // =========================================================================

    final String istoProfileKey =
        'project_xp_profile_$_istoId';

    String? istoProfileRaw =
        prefs.getString(
      istoProfileKey,
    );

    if (istoProfileRaw == null ||
        istoProfileRaw.isEmpty) {
      final Map<String, dynamic> istoProfile = {
        'id': _istoId,
        'userId': _istoId,
        'email': _istoEmail,
        'pseudo': _istoUsername,
        'description':
            "Je cherche des compagnons pour partir à l'aventure !",
        'games': <String>[],
        'platforms':
            <Map<String, String>>[],
        'availability':
            <String, List<String>>{
          'Lundi': <String>[],
          'Mardi': <String>[],
          'Mercredi': <String>[],
          'Jeudi': <String>[],
          'Vendredi': <String>[],
          'Samedi': <String>[],
          'Dimanche': <String>[],
        },
        'networks':
            <Map<String, String>>[],
      };

      istoProfileRaw =
          jsonEncode(istoProfile);

      await prefs.setString(
        istoProfileKey,
        istoProfileRaw,
      );
    }

    // =========================================================================
    // 5. Le profil historique était bien celui de Vieti.
    // =========================================================================

    await prefs.setString(
      _legacyMigrationTargetKey,
      _vietiId,
    );

    // =========================================================================
    // 6. Le vieux profile_data reste un miroir du COMPTE ACTIF.
    //
    // Cela garde la compatibilité avec les anciens morceaux de l'application.
    // =========================================================================

    final String? activeUserId =
        prefs.getString(
      'project_xp_user_id',
    );

    if (activeUserId != null &&
        activeUserId.isNotEmpty) {
      final String? activeProfileRaw =
          prefs.getString(
        'project_xp_profile_$activeUserId',
      );

      if (activeProfileRaw != null &&
          activeProfileRaw.isNotEmpty) {
        await prefs.setString(
          _legacyProfileKey,
          activeProfileRaw,
        );

        await prefs.setString(
          _legacyProfileUserIdKey,
          activeUserId,
        );
      }
    }

    // =========================================================================
    // 7. Terminé.
    // =========================================================================

    await prefs.setBool(
      _doneKey,
      true,
    );
  }

  static List<Map<String, dynamic>>
      _readAccounts(
    String? raw,
  ) {
    if (raw == null ||
        raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                Map<String, dynamic>.from(
              item,
            ),
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Map<String, dynamic> _decodeMap(
    String raw,
  ) {
    try {
      final dynamic decoded =
          jsonDecode(raw);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (_) {
      // Rien n'est supprimé en cas d'erreur.
    }

    return <String, dynamic>{};
  }

  static void _upsertAccount(
    List<Map<String, dynamic>> accounts, {
    required String id,
    required String username,
    required String email,
    required bool legacy,
  }) {
    final int index =
        accounts.indexWhere(
      (account) =>
          account['id']?.toString() ==
          id,
    );

    final Map<String, dynamic> value = {
      'id': id,
      'username': username,
      'email': email.trim().toLowerCase(),
      'legacy': legacy,
      'createdAt': index == -1
          ? DateTime.now().toIso8601String()
          : accounts[index]['createdAt'] ??
              DateTime.now().toIso8601String(),
    };

    if (index == -1) {
      accounts.add(value);
    } else {
      accounts[index] = {
        ...accounts[index],
        ...value,
      };
    }
  }
}
