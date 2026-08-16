import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';


enum AuthLoginResult {
  success,
  invalidCredentials,
  passwordSetupRequired,
}

enum AuthRegisterResult {
  success,
  invalidData,
  emailAlreadyUsed,
  usernameAlreadyUsed,
  weakPassword,
}

class AuthService {
  // ===========================================================================
  // CLÉS DE COMPATIBILITÉ
  //
  // On les conserve afin de ne casser aucun écran existant.
  // Elles représentent TOUJOURS le compte actif.
  // ===========================================================================

  static const String _isLoggedInKey =
      'project_xp_is_logged_in';

  static const String _userIdKey =
      'project_xp_user_id';

  static const String _usernameKey =
      'project_xp_username';

  static const String _emailKey =
      'project_xp_email';

  // ===========================================================================
  // NOUVEAU REGISTRE MULTI-COMPTES
  // ===========================================================================

  static const String _accountsKey =
      'project_xp_accounts_v2';

  static const String _migrationDoneKey =
      'project_xp_accounts_v2_migrated';

  static Future<void>? _initializationFuture;

  // ===========================================================================
  // MOT DE PASSE
  //
  // Argon2id avec un sel aléatoire différent pour chaque compte.
  // Seuls le hash + le sel + les paramètres sont stockés.
  // Le mot de passe en clair n'est jamais sauvegardé.
  // ===========================================================================

  static const int passwordMinLength = 10;
  static const int passwordMaxLength = 128;

  static const int _argonMemory = 19456; // 19 MiB en blocs de 1 KiB.
  static const int _argonIterations = 2;
  static const int _argonParallelism = 1;
  static const int _argonHashLength = 32;
  static const int _passwordSaltLength = 16;

  static final Random _secureRandom =
      Random.secure();

  // ===========================================================================
  // INITIALISATION / MIGRATION
  // ===========================================================================

  static Future<void> initialize() {
    return _initializationFuture ??=
        _migrateLegacyStorage();
  }

  static Future<void> _migrateLegacyStorage() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    // -------------------------------------------------------------------------
    // 1. Compte actuellement enregistré par l'ancien AuthService.
    // -------------------------------------------------------------------------

    String? currentUserId =
        prefs.getString(_userIdKey);

    final String currentUsername =
        prefs.getString(_usernameKey)?.trim() ?? '';

    final String currentEmail =
        prefs.getString(_emailKey)?.trim().toLowerCase() ?? '';

    if ((currentUserId == null ||
            currentUserId.trim().isEmpty) &&
        currentEmail.isNotEmpty) {
      currentUserId = DateTime.now()
          .millisecondsSinceEpoch
          .toString();

      await prefs.setString(
        _userIdKey,
        currentUserId,
      );
    }

    if (currentUserId != null &&
        currentUserId.trim().isNotEmpty) {
      accounts = _addOrMergeAccount(
        accounts,
        id: currentUserId.trim(),
        username: currentUsername,
        email: currentEmail,
        legacy: false,
      );

      // Verrouille le propriétaire de l'ancien profil global AVANT qu'un
      // nouveau compte puisse être créé. Ainsi, le profil historique ne sera
      // jamais attribué par erreur au prochain compte inscrit.
      final String? legacyProfile =
          prefs.getString('profile_data');

      final String? legacyProfileTarget =
          prefs.getString(
        'project_xp_profile_legacy_migrated_to',
      );

      if (legacyProfile != null &&
          legacyProfile.isNotEmpty &&
          (legacyProfileTarget == null ||
              legacyProfileTarget.isEmpty)) {
        await prefs.setString(
          'project_xp_profile_legacy_migrated_to',
          currentUserId.trim(),
        );
      }
    }

    // -------------------------------------------------------------------------
    // 2. Comptes encore présents dans les équipes.
    //
    // On NE MODIFIE PAS les IDs des équipes :
    // chaque équipe reste liée au compte qui l'a réellement créée.
    // Cela évite de fusionner accidentellement deux comptes de test.
    // -------------------------------------------------------------------------

    final String? teamsRaw =
        prefs.getString('teams_data');

    if (teamsRaw != null &&
        teamsRaw.isNotEmpty) {
      try {
        final dynamic decoded =
            jsonDecode(teamsRaw);

        if (decoded is List) {
          for (final dynamic item in decoded) {
            if (item is! Map) {
              continue;
            }

            final Map<String, dynamic> team =
                Map<String, dynamic>.from(item);

            final String ownerId =
                team['ownerId']?.toString().trim() ?? '';

            final String ownerName =
                team['ownerName']?.toString().trim() ?? '';

            if (ownerId.isNotEmpty) {
              accounts = _addOrMergeAccount(
                accounts,
                id: ownerId,
                username: ownerName,
                email: '',
                legacy:
                    ownerId != currentUserId,
              );
            }

            final String leaderId =
                team['leaderId']?.toString().trim() ?? '';

            final String leaderName =
                team['leaderName']?.toString().trim() ?? '';

            if (leaderId.isNotEmpty) {
              accounts = _addOrMergeAccount(
                accounts,
                id: leaderId,
                username: leaderName,
                email: '',
                legacy:
                    leaderId != currentUserId,
              );
            }

            final dynamic memberIds =
                team['memberIds'];

            if (memberIds is List) {
              for (final dynamic member in memberIds) {
                final String memberId =
                    member.toString().trim();

                if (memberId.isEmpty) {
                  continue;
                }

                accounts = _addOrMergeAccount(
                  accounts,
                  id: memberId,
                  username: '',
                  email: '',
                  legacy:
                      memberId != currentUserId,
                );
              }
            }
          }
        }
      } catch (_) {
        // Les anciennes données restent intactes même si elles sont illisibles.
      }
    }

    // -------------------------------------------------------------------------
    // 3. Comptes encore présents dans les avatars.
    //
    // Les avatars étaient déjà enregistrés avec :
    // project_xp_avatar_<userId>
    // On récupère donc les anciens IDs sans supprimer les avatars.
    // -------------------------------------------------------------------------

    for (final String key in prefs.getKeys()) {
      const String avatarPrefix =
          'project_xp_avatar_';

      if (!key.startsWith(avatarPrefix)) {
        continue;
      }

      final String avatarUserId =
          key.substring(
        avatarPrefix.length,
      );

      if (avatarUserId.isEmpty) {
        continue;
      }

      accounts = _addOrMergeAccount(
        accounts,
        id: avatarUserId,
        username: '',
        email: '',
        legacy:
            avatarUserId != currentUserId,
      );
    }

    await _saveAccountsToPrefs(
      prefs,
      accounts,
    );

    await prefs.setBool(
      _migrationDoneKey,
      true,
    );
  }

  // ===========================================================================
  // SESSION
  // ===========================================================================

  static Future<bool> isLoggedIn() async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.getBool(
          _isLoggedInKey,
        ) ??
        false;
  }

  // ===========================================================================
  // INSCRIPTION
  //
  // Une nouvelle inscription n'écrase plus les anciens comptes.
  // ===========================================================================

  static Future<AuthRegisterResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String normalizedEmail =
        email.trim().toLowerCase();

    final String normalizedUsername =
        username.trim();

    if (normalizedEmail.isEmpty ||
        normalizedUsername.isEmpty ||
        !normalizedEmail.contains('@')) {
      return AuthRegisterResult.invalidData;
    }

    final String? passwordError =
        validatePassword(password);

    if (passwordError != null) {
      return AuthRegisterResult.weakPassword;
    }

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    final bool emailAlreadyExists =
        accounts.any(
      (account) =>
          account['email']
              ?.toString()
              .trim()
              .toLowerCase() ==
          normalizedEmail,
    );

    if (emailAlreadyExists) {
      return AuthRegisterResult.emailAlreadyUsed;
    }

    final bool usernameAvailable =
        _isUsernameAvailableInAccounts(
      normalizedUsername,
      accounts,
    );

    if (!usernameAvailable) {
      return AuthRegisterResult.usernameAlreadyUsed;
    }

    final String userId =
        DateTime.now()
            .microsecondsSinceEpoch
            .toString();

    final Map<String, dynamic> passwordFields =
        await _createPasswordFields(
      password,
    );

    final Map<String, dynamic> account = {
      'id': userId,
      'username': normalizedUsername,
      'email': normalizedEmail,
      'legacy': false,
      'createdAt':
          DateTime.now().toIso8601String(),
      ...passwordFields,
    };

    accounts.add(account);

    await _saveAccountsToPrefs(
      prefs,
      accounts,
    );

    await _activateAccount(
      prefs,
      account,
      loggedIn: true,
    );

    return AuthRegisterResult.success;
  }

  // ===========================================================================
  // CONNEXION
  //
  // La connexion recherche maintenant l'e-mail dans le registre local.
  // ===========================================================================

  static Future<AuthLoginResult> login({
    required String email,
    required String password,
  }) async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String normalizedEmail =
        email.trim().toLowerCase();

    if (normalizedEmail.isEmpty ||
        password.isEmpty) {
      return AuthLoginResult.invalidCredentials;
    }

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    final int index =
        accounts.indexWhere(
      (account) =>
          account['email']
              ?.toString()
              .trim()
              .toLowerCase() ==
          normalizedEmail,
    );

    if (index == -1) {
      return AuthLoginResult.invalidCredentials;
    }

    final Map<String, dynamic> account =
        accounts[index];

    if (!_accountHasPassword(account)) {
      // Les anciens comptes Project XP n'avaient aucun mot de passe réellement
      // enregistré. On ne peut donc pas vérifier l'ancien mot de passe :
      // un nouveau mot de passe doit être défini une seule fois.
      return AuthLoginResult.passwordSetupRequired;
    }

    final bool validPassword =
        await _verifyPassword(
      password: password,
      account: account,
    );

    if (!validPassword) {
      return AuthLoginResult.invalidCredentials;
    }

    await _activateAccount(
      prefs,
      account,
      loggedIn: true,
    );

    return AuthLoginResult.success;
  }

  static Future<void> logout() async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    // On conserve l'ID actif et toutes les données du compte.
    await prefs.setBool(
      _isLoggedInKey,
      false,
    );
  }

  // ===========================================================================
  // SÉCURITÉ DU MOT DE PASSE
  // ===========================================================================

  static String? validatePassword(
    String password,
  ) {
    if (password.length <
        passwordMinLength) {
      return 'Le mot de passe doit contenir au moins '
          '$passwordMinLength caractères.';
    }

    if (password.length >
        passwordMaxLength) {
      return 'Le mot de passe est trop long.';
    }

    if (!RegExp(
      r'[A-Za-zÀ-ÖØ-öø-ÿ]',
    ).hasMatch(password)) {
      return 'Ajoute au moins une lettre.';
    }

    if (!RegExp(
      r'[0-9]',
    ).hasMatch(password)) {
      return 'Ajoute au moins un chiffre.';
    }

    if (!RegExp(
      r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9\s]',
    ).hasMatch(password)) {
      return 'Ajoute au moins un caractère spécial.';
    }

    return null;
  }

  static Future<bool> accountHasPasswordForEmail(
    String email,
  ) async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String normalizedEmail =
        email.trim().toLowerCase();

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    for (final Map<String, dynamic> account
        in accounts) {
      if (account['email']
              ?.toString()
              .trim()
              .toLowerCase() !=
          normalizedEmail) {
        continue;
      }

      return _accountHasPassword(
        account,
      );
    }

    return false;
  }

  /// Migration des comptes créés avant l'ajout des vrais mots de passe.
  ///
  /// IMPORTANT :
  /// Cette méthode doit être appelée uniquement après une authentification
  /// locale du propriétaire de l'appareil (PIN/biométrie) dans l'interface.
  static Future<bool> setPasswordForEmail({
    required String email,
    required String password,
  }) async {
    await initialize();

    if (validatePassword(password) !=
        null) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String normalizedEmail =
        email.trim().toLowerCase();

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    final int index =
        accounts.indexWhere(
      (account) =>
          account['email']
              ?.toString()
              .trim()
              .toLowerCase() ==
          normalizedEmail,
    );

    if (index == -1) {
      return false;
    }

    final Map<String, dynamic> passwordFields =
        await _createPasswordFields(
      password,
    );

    accounts[index] = {
      ...accounts[index],
      ...passwordFields,
    };

    await _saveAccountsToPrefs(
      prefs,
      accounts,
    );

    return true;
  }

  // ===========================================================================
  // COMPTE ACTIF
  // ===========================================================================

  static Future<String?> getCurrentUserId() async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? value =
        prefs.getString(_userIdKey);

    if (value == null ||
        value.trim().isEmpty) {
      return null;
    }

    return value.trim();
  }

  static Future<String?> getCurrentUsername() async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _usernameKey,
    );
  }

  static Future<String?> getCurrentEmail() async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _emailKey,
    );
  }

  // ===========================================================================
  // MISE À JOUR DU PSEUDO
  //
  // Le pseudo du Profil PC et celui du compte restent synchronisés.
  // ===========================================================================

  static Future<bool> updateCurrentUsername(
    String username,
  ) async {
    await initialize();

    final String newUsername =
        username.trim();

    if (newUsername.isEmpty) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String? userId =
        prefs.getString(_userIdKey);

    if (userId == null ||
        userId.isEmpty) {
      return false;
    }

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    final bool usernameAvailable =
        _isUsernameAvailableInAccounts(
      newUsername,
      accounts,
      excludeUserId: userId,
    );

    if (!usernameAvailable) {
      return false;
    }

    final int index =
        accounts.indexWhere(
      (account) =>
          account['id']?.toString() ==
          userId,
    );

    if (index == -1) {
      return false;
    }

    accounts[index] = {
      ...accounts[index],
      'username': newUsername,
    };

    await _saveAccountsToPrefs(
      prefs,
      accounts,
    );

    await prefs.setString(
      _usernameKey,
      newUsername,
    );

    return true;
  }

  // ===========================================================================
  // PSEUDOS
  //
  // Comparaison insensible à la casse :
  // Vieti / vieti / VIETI = le même pseudo.
  //
  // Les anciens "stubs" legacy sans e-mail sont ignorés afin de ne pas bloquer
  // un vrai compte à cause de doublons créés avant la migration multi-comptes.
  // ===========================================================================

  static Future<bool> isUsernameAvailable(
    String username, {
    String? excludeUserId,
  }) async {
    await initialize();

    final String cleanUsername =
        username.trim();

    if (cleanUsername.isEmpty) {
      return false;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    return _isUsernameAvailableInAccounts(
      cleanUsername,
      accounts,
      excludeUserId: excludeUserId,
    );
  }

  static Future<String?> getUsernameForUserId(
    String userId,
  ) async {
    await initialize();

    final String cleanUserId =
        userId.trim();

    if (cleanUserId.isEmpty) {
      return null;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    for (final Map<String, dynamic> account
        in accounts) {
      if (account['id']?.toString().trim() !=
          cleanUserId) {
        continue;
      }

      final String username =
          account['username']
                  ?.toString()
                  .trim() ??
              '';

      return username.isEmpty
          ? null
          : username;
    }

    return null;
  }

  // ===========================================================================
  // COMPTES LOCAUX
  //
  // Utile plus tard pour un sélecteur de comptes.
  // Les comptes legacy sans e-mail restent conservés.
  // ===========================================================================

  static Future<List<Map<String, dynamic>>>
      getLocalAccounts() async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return _readAccountsFromPrefs(
      prefs,
    )
        .map(
          (account) =>
              Map<String, dynamic>.from(
            account,
          ),
        )
        .toList();
  }

  /// Permet de réactiver plus tard un ancien compte local par ID,
  /// même s'il n'avait pas d'e-mail enregistré dans l'ancien système.
  ///
  /// Aucun écran n'utilise encore cette méthode automatiquement.
  static Future<bool> activateLocalAccountById(
    String userId,
  ) async {
    await initialize();

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> accounts =
        _readAccountsFromPrefs(prefs);

    Map<String, dynamic>? account;

    for (final Map<String, dynamic> item
        in accounts) {
      if (item['id']?.toString() ==
          userId) {
        account = item;
        break;
      }
    }

    if (account == null) {
      return false;
    }

    await _activateAccount(
      prefs,
      account,
      loggedIn: true,
    );

    return true;
  }

  // ===========================================================================
  // OUTILS INTERNES
  // ===========================================================================

  static bool _accountHasPassword(
    Map<String, dynamic> account,
  ) {
    final String hash =
        account['passwordHash']
                ?.toString()
                .trim() ??
            '';

    final String salt =
        account['passwordSalt']
                ?.toString()
                .trim() ??
            '';

    return hash.isNotEmpty &&
        salt.isNotEmpty;
  }

  static Future<Map<String, dynamic>>
      _createPasswordFields(
    String password,
  ) async {
    final List<int> salt =
        List<int>.generate(
      _passwordSaltLength,
      (_) => _secureRandom.nextInt(
        256,
      ),
      growable: false,
    );

    final Argon2id algorithm =
        Argon2id(
      memory: _argonMemory,
      parallelism:
          _argonParallelism,
      iterations:
          _argonIterations,
      hashLength:
          _argonHashLength,
    );

    final SecretKey derivedKey =
        await algorithm
            .deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );

    final List<int> hash =
        await derivedKey.extractBytes();

    return <String, dynamic>{
      'passwordAlgorithm':
          'argon2id-v1',
      'passwordSalt':
          base64Encode(salt),
      'passwordHash':
          base64Encode(hash),
      'passwordMemory':
          _argonMemory,
      'passwordIterations':
          _argonIterations,
      'passwordParallelism':
          _argonParallelism,
      'passwordHashLength':
          _argonHashLength,
    };
  }

  static Future<bool> _verifyPassword({
    required String password,
    required Map<String, dynamic> account,
  }) async {
    try {
      final String algorithmName =
          account['passwordAlgorithm']
                  ?.toString()
                  .trim() ??
              '';

      if (algorithmName !=
          'argon2id-v1') {
        return false;
      }

      final List<int> salt =
          base64Decode(
        account['passwordSalt']
            .toString(),
      );

      final List<int> expectedHash =
          base64Decode(
        account['passwordHash']
            .toString(),
      );

      final int memory =
          _asPositiveInt(
            account['passwordMemory'],
          ) ??
          _argonMemory;

      final int iterations =
          _asPositiveInt(
            account[
                'passwordIterations'],
          ) ??
          _argonIterations;

      final int parallelism =
          _asPositiveInt(
            account[
                'passwordParallelism'],
          ) ??
          _argonParallelism;

      final int hashLength =
          _asPositiveInt(
            account[
                'passwordHashLength'],
          ) ??
          expectedHash.length;

      final Argon2id algorithm =
          Argon2id(
        memory: memory,
        parallelism:
            parallelism,
        iterations:
            iterations,
        hashLength:
            hashLength,
      );

      final SecretKey derivedKey =
          await algorithm
              .deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

      final List<int> actualHash =
          await derivedKey.extractBytes();

      return _constantTimeEquals(
        actualHash,
        expectedHash,
      );
    } catch (_) {
      return false;
    }
  }

  static int? _asPositiveInt(
    dynamic value,
  ) {
    if (value is int &&
        value > 0) {
      return value;
    }

    final int? parsed =
        int.tryParse(
      value?.toString() ?? '',
    );

    if (parsed == null ||
        parsed <= 0) {
      return null;
    }

    return parsed;
  }

  static bool _constantTimeEquals(
    List<int> a,
    List<int> b,
  ) {
    int difference =
        a.length ^ b.length;

    final int maxLength =
        a.length > b.length
            ? a.length
            : b.length;

    for (int i = 0;
        i < maxLength;
        i++) {
      final int aValue =
          i < a.length
              ? a[i]
              : 0;

      final int bValue =
          i < b.length
              ? b[i]
              : 0;

      difference |=
          aValue ^ bValue;
    }

    return difference == 0;
  }

  static String _usernameKeyForComparison(
    String username,
  ) {
    return username
        .trim()
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .toLowerCase();
  }

  static bool _isLegacyPlaceholderAccount(
    Map<String, dynamic> account,
  ) {
    final bool legacy =
        account['legacy'] == true;

    final String email =
        account['email']
                ?.toString()
                .trim() ??
            '';

    return legacy &&
        email.isEmpty;
  }

  static bool _isUsernameAvailableInAccounts(
    String username,
    List<Map<String, dynamic>> accounts, {
    String? excludeUserId,
  }) {
    final String wanted =
        _usernameKeyForComparison(
      username,
    );

    if (wanted.isEmpty) {
      return false;
    }

    final String excludedId =
        excludeUserId?.trim() ?? '';

    for (final Map<String, dynamic> account
        in accounts) {
      final String accountId =
          account['id']?.toString().trim() ??
              '';

      if (excludedId.isNotEmpty &&
          accountId == excludedId) {
        continue;
      }

      if (_isLegacyPlaceholderAccount(
        account,
      )) {
        continue;
      }

      final String existingUsername =
          account['username']
                  ?.toString()
                  .trim() ??
              '';

      if (existingUsername.isEmpty) {
        continue;
      }

      if (_usernameKeyForComparison(
            existingUsername,
          ) ==
          wanted) {
        return false;
      }
    }

    return true;
  }

  static Future<void> _activateAccount(
    SharedPreferences prefs,
    Map<String, dynamic> account, {
    required bool loggedIn,
  }) async {
    final String id =
        account['id']?.toString() ?? '';

    if (id.isEmpty) {
      return;
    }

    final String username =
        account['username']
                ?.toString()
                .trim() ??
            '';

    final String email =
        account['email']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

    await prefs.setString(
      _userIdKey,
      id,
    );

    await prefs.setString(
      _usernameKey,
      username,
    );

    await prefs.setString(
      _emailKey,
      email,
    );

    await prefs.setBool(
      _isLoggedInKey,
      loggedIn,
    );
  }

  static List<Map<String, dynamic>>
      _readAccountsFromPrefs(
    SharedPreferences prefs,
  ) {
    final String? raw =
        prefs.getString(
      _accountsKey,
    );

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
          .where(
            (account) =>
                account['id']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true,
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _saveAccountsToPrefs(
    SharedPreferences prefs,
    List<Map<String, dynamic>> accounts,
  ) async {
    await prefs.setString(
      _accountsKey,
      jsonEncode(accounts),
    );
  }

  static List<Map<String, dynamic>>
      _addOrMergeAccount(
    List<Map<String, dynamic>> accounts, {
    required String id,
    required String username,
    required String email,
    required bool legacy,
  }) {
    final List<Map<String, dynamic>> result =
        accounts
            .map(
              (item) =>
                  Map<String, dynamic>.from(
                item,
              ),
            )
            .toList();

    final int index =
        result.indexWhere(
      (account) =>
          account['id']?.toString() ==
          id,
    );

    if (index == -1) {
      result.add({
        'id': id,
        'username': username,
        'email': email,
        'legacy': legacy,
        'createdAt':
            DateTime.now().toIso8601String(),
      });

      return result;
    }

    final Map<String, dynamic> existing =
        result[index];

    final String oldUsername =
        existing['username']
                ?.toString()
                .trim() ??
            '';

    final String oldEmail =
        existing['email']
                ?.toString()
                .trim() ??
            '';

    result[index] = {
      ...existing,
      'username': oldUsername.isNotEmpty
          ? oldUsername
          : username,
      'email': oldEmail.isNotEmpty
          ? oldEmail
          : email,
      'legacy':
          existing['legacy'] == false
              ? false
              : legacy,
    };

    return result;
  }
}
