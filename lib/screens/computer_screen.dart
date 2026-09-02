import 'package:flutter/material.dart';

import 'package:project_xp/models/avatar_model.dart';
import 'package:project_xp/models/game_library_entry.dart';
import 'package:project_xp/screens/cloud_identity_screen.dart';
import 'package:project_xp/screens/game_library_screen.dart';
import 'package:project_xp/screens/profile_screen.dart';
import 'package:project_xp/screens/splash_screen.dart';
import 'package:project_xp/services/app_notification_service.dart';
import 'package:project_xp/services/auth_service.dart';
import 'package:project_xp/services/avatar_storage.dart';
import 'package:project_xp/services/biometric_auth_service.dart';
import 'package:project_xp/services/cloud_identity_service.dart';
import 'package:project_xp/services/computer_settings_service.dart';
import 'package:project_xp/services/game_library_service.dart';
import 'package:project_xp/services/session_service.dart';

import '../widgets/avatar_renderer.dart';
import '../widgets/hall_home_button.dart';

class ComputerScreen extends StatefulWidget {
  const ComputerScreen({
    super.key,
  });

  @override
  State<ComputerScreen> createState() =>
      _ComputerScreenState();
}

class _ComputerScreenState extends State<ComputerScreen> {
  ComputerSettings _settings =
      ComputerSettings.defaults();

  bool _loading = true;

  String _username = 'Aventurier';
  String _email = '';

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  CloudIdentityStatus? _cloudIdentityStatus;

  AvatarModel? _avatar;
  List<GameLibraryEntry> _games = <GameLibraryEntry>[];
  List<GamingActivityEvent> _activity = <GamingActivityEvent>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ==========================================================================
  // CHARGEMENT
  // ==========================================================================

  Future<void> _loadData() async {
    final ComputerSettings settings =
        await ComputerSettingsService.load();

    final String? username =
        await AuthService.getCurrentUsername();

    final String? email =
        await AuthService.getCurrentEmail();

    final bool biometricAvailable =
        await BiometricAuthService
            .isBiometricAvailable();

    final bool biometricEnabled =
        await BiometricAuthService
            .isEnabledForCurrentAccount();

    final CloudIdentityStatus cloudIdentityStatus =
        await CloudIdentityService.loadStatus();

    final AvatarModel? avatar =
        await AvatarStorage.loadCurrentAvatar();

    final List<GameLibraryEntry> games =
        await GameLibraryService.loadCurrentLibrary();

    final List<GamingActivityEvent> activity =
        await GameLibraryService.loadCurrentActivity();

    if (!mounted) {
      return;
    }

    setState(() {
      _settings = settings;

      _username =
          username?.trim().isNotEmpty == true
              ? username!.trim()
              : 'Aventurier';

      _email = email?.trim() ?? '';

      _biometricAvailable =
          biometricAvailable;

      _biometricEnabled =
          biometricEnabled;

      _cloudIdentityStatus =
          cloudIdentityStatus;

      _avatar = avatar;
      _games = games;
      _activity = activity;

      _loading = false;
    });
  }

  Future<void> _saveSettings(
    ComputerSettings settings,
  ) async {
    if (mounted) {
      setState(() {
        _settings = settings;
      });
    }

    await ComputerSettingsService.save(
      settings,
    );
  }

  // ==========================================================================
  // PROFIL
  // ==========================================================================

  Future<void> _openProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const ProfileScreen(),
      ),
    );
  }

  Future<void> _openLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const GameLibraryScreen(),
      ),
    );

    await _loadData();
  }

  Future<void> _openCloudIdentity() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            const CloudIdentityScreen(),
      ),
    );

    await _loadData();
  }

  // ==========================================================================
  // DÉCONNEXION
  // ==========================================================================

  Future<void> _logout() async {
    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff21150e),
          title: const Text(
            'Déconnexion',
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Tu veux vraiment te déconnecter de Project XP ?',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(
                  color: Colors.white54,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'SE DÉCONNECTER',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await CloudIdentityService
        .signOutPermanentCloudUser();

    await SessionService.logout();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) =>
            const SplashScreen(),
      ),
      (route) => false,
    );
  }

  // ==========================================================================
  // PARAMÈTRES
  // ==========================================================================

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          const Color(0xff21150e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            Future<void> update(
              ComputerSettings settings,
            ) async {
              setSheetState(() {
                _settings = settings;
              });

              await _saveSettings(
                settings,
              );
            }

            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  28,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    _buildSheetHandle(),

                    const SizedBox(
                      height: 15,
                    ),

                    const _SheetTitle(
                      icon: Icons.settings,
                      title: 'PARAMÈTRES',
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _TerminalSwitch(
                      icon: Icons.music_note,
                      title: 'Musique',
                      subtitle:
                          'Musique d’ambiance de Project XP',
                      value:
                          _settings.musicEnabled,
                      onChanged: (value) async {
                        await update(
                          _settings.copyWith(
                            musicEnabled: value,
                          ),
                        );
                      },
                    ),

                    _TerminalSwitch(
                      icon: Icons.volume_up,
                      title: 'Effets sonores',
                      subtitle:
                          'Portails, boutons et interactions',
                      value:
                          _settings.soundEffectsEnabled,
                      onChanged: (value) async {
                        await update(
                          _settings.copyWith(
                            soundEffectsEnabled:
                                value,
                          ),
                        );
                      },
                    ),

                    _TerminalSwitch(
                      icon: Icons.vibration,
                      title: 'Vibrations',
                      subtitle:
                          'Retour haptique pendant les actions',
                      value:
                          _settings.vibrationEnabled,
                      onChanged: (value) async {
                        await update(
                          _settings.copyWith(
                            vibrationEnabled:
                                value,
                          ),
                        );
                      },
                    ),

                    _TerminalSwitch(
                      icon: Icons.notifications,
                      title: 'Notifications',
                      subtitle:
                          'Autoriser les notifications Android de Project XP',
                      value:
                          _settings.notificationsEnabled,
                      onChanged: (value) async {
                        // --------------------------------------------------
                        // DÉSACTIVATION
                        // --------------------------------------------------

                        if (!value) {
                          await update(
                            _settings.copyWith(
                              notificationsEnabled:
                                  false,
                            ),
                          );

                          return;
                        }

                        // --------------------------------------------------
                        // ACTIVATION + PERMISSION ANDROID
                        // --------------------------------------------------

                        final bool granted =
                            await AppNotificationService
                                .instance
                                .requestPermission();

                        if (!granted) {
                          await update(
                            _settings.copyWith(
                              notificationsEnabled:
                                  false,
                            ),
                          );

                          if (!context.mounted) {
                            return;
                          }

                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Permission de notifications refusée dans Android.',
                              ),
                            ),
                          );

                          return;
                        }

                        await update(
                          _settings.copyWith(
                            notificationsEnabled:
                                true,
                          ),
                        );

                        await AppNotificationService
                            .instance
                            .showTestNotification();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // OPTIONS
  // ==========================================================================

  void _openOptions() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          const Color(0xff21150e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            Future<void> update(
              ComputerSettings settings,
            ) async {
              setSheetState(() {
                _settings = settings;
              });

              await _saveSettings(
                settings,
              );
            }

            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  28,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    _buildSheetHandle(),

                    const SizedBox(
                      height: 15,
                    ),

                    const _SheetTitle(
                      icon: Icons.tune,
                      title: 'OPTIONS',
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    _TerminalSwitch(
                      icon: Icons.animation,
                      title:
                          'Réduire les animations',
                      subtitle:
                          'Prépare un mode plus léger et plus rapide',
                      value:
                          _settings.reducedAnimations,
                      onChanged: (value) async {
                        await update(
                          _settings.copyWith(
                            reducedAnimations:
                                value,
                          ),
                        );
                      },
                    ),

                    _TerminalSwitch(
                      icon:
                          Icons.verified_user_outlined,
                      title: 'Confirmations',
                      subtitle:
                          'Demander confirmation avant les actions sensibles',
                      value:
                          _settings.confirmationsEnabled,
                      onChanged: (value) async {
                        await update(
                          _settings.copyWith(
                            confirmationsEnabled:
                                value,
                          ),
                        );
                      },
                    ),

                    _TerminalSwitch(
                      icon: Icons.auto_awesome,
                      title: 'Conseils de Bjorn',
                      subtitle:
                          'Afficher les aides et conseils du guide',
                      value:
                          _settings.bjornTipsEnabled,
                      onChanged: (value) async {
                        await update(
                          _settings.copyWith(
                            bjornTipsEnabled:
                                value,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // COMPTE & SÉCURITÉ
  // ==========================================================================

  Future<void> _refreshSecurityState() async {
    final bool biometricAvailable =
        await BiometricAuthService
            .isBiometricAvailable();

    final bool biometricEnabled =
        await BiometricAuthService
            .isEnabledForCurrentAccount();

    if (!mounted) {
      return;
    }

    setState(() {
      _biometricAvailable =
          biometricAvailable;

      _biometricEnabled =
          biometricEnabled;
    });
  }

  Future<void> _openAccount() async {
    await _refreshSecurityState();

    if (!mounted) {
      return;
    }

    bool biometricEnabled =
        _biometricEnabled;

    bool biometricBusy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          const Color(0xff21150e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            Future<void> disableBiometrics() async {
              if (biometricBusy) {
                return;
              }

              setSheetState(() {
                biometricBusy = true;
              });

              await BiometricAuthService
                  .disableForCurrentAccount();

              final bool enabled =
                  await BiometricAuthService
                      .isEnabledForCurrentAccount();

              if (!mounted ||
                  !sheetContext.mounted) {
                return;
              }

              setState(() {
                _biometricEnabled =
                    enabled;
              });

              setSheetState(() {
                biometricEnabled =
                    enabled;

                biometricBusy = false;
              });

              _showMessage(
                'Connexion biométrique désactivée.',
              );
            }

            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  28,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    _buildSheetHandle(),

                    const SizedBox(
                      height: 15,
                    ),

                    const _SheetTitle(
                      icon:
                          Icons.manage_accounts,
                      title:
                          'COMPTE & SÉCURITÉ',
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    _AccountLine(
                      icon: Icons.person_outline,
                      label: 'Pseudo',
                      value: _username,
                    ),

                    if (_email.isNotEmpty) ...[
                      const SizedBox(
                        height: 10,
                      ),
                      _AccountLine(
                        icon:
                            Icons.email_outlined,
                        label: 'E-mail',
                        value: _email,
                      ),
                    ],

                    const SizedBox(
                      height: 18,
                    ),

                    const _SecuritySectionLabel(
                      label: 'SÉCURITÉ',
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    _AccountActionButton(
                      icon:
                          Icons.cloud_outlined,
                      title:
                          'Compte Cloud Project XP',
                      subtitle:
                          _cloudIdentityStatus?.isPermanent == true
                              ? 'Actif • identité récupérable sur plusieurs appareils'
                              : 'Local • activer la sauvegarde d’identité Cloud',
                      onTap: () {
                        Navigator.pop(
                          sheetContext,
                        );

                        _openCloudIdentity();
                      },
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    _BiometricSecurityTile(
                      available:
                          _biometricAvailable,
                      enabled:
                          biometricEnabled,
                      busy:
                          biometricBusy,
                      onChanged:
                          !_biometricAvailable ||
                                  biometricBusy
                              ? null
                              : (value) async {
                                  if (value) {
                                    Navigator.pop(
                                      sheetContext,
                                    );

                                    await _enableBiometricsFromAccount();
                                    return;
                                  }

                                  await disableBiometrics();
                                },
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    _AccountActionButton(
                      icon:
                          Icons.password,
                      title:
                          'Changer le mot de passe',
                      subtitle:
                          'Le mot de passe actuel sera demandé',
                      onTap: () {
                        Navigator.pop(
                          sheetContext,
                        );

                        _changePassword();
                      },
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    _AccountActionButton(
                      icon:
                          Icons.alternate_email,
                      title:
                          'Changer l’adresse e-mail',
                      subtitle:
                          'Le mot de passe actuel sera demandé',
                      onTap: () {
                        Navigator.pop(
                          sheetContext,
                        );

                        _changeEmail();
                      },
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child:
                          OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(
                            sheetContext,
                          );

                          _logout();
                        },
                        icon: const Icon(
                          Icons.logout,
                        ),
                        label: const Text(
                          'SE DÉCONNECTER',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        style:
                            OutlinedButton
                                .styleFrom(
                          foregroundColor:
                              Colors.redAccent,
                          side:
                              const BorderSide(
                            color:
                                Colors.redAccent,
                          ),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _enableBiometricsFromAccount() async {
    if (!_biometricAvailable) {
      _showMessage(
        'Aucune empreinte ou reconnaissance faciale n’est configurée sur cet appareil.',
      );
      return;
    }

    final String? currentPassword =
        await _askCurrentPassword(
      title:
          'ACTIVER LA BIOMÉTRIE',
      message:
          'Entre ton mot de passe Project XP avant d’autoriser la biométrie sur cet appareil.',
    );

    if (currentPassword == null ||
        !mounted) {
      return;
    }

    final bool passwordValid =
        await AuthService
            .verifyCurrentPassword(
      currentPassword,
    );

    if (!mounted) {
      return;
    }

    if (!passwordValid) {
      _showMessage(
        'Mot de passe incorrect.',
      );
      return;
    }

    final bool enabled =
        await BiometricAuthService
            .enableForCurrentAccount();

    if (!mounted) {
      return;
    }

    await _refreshSecurityState();

    if (!mounted) {
      return;
    }

    _showMessage(
      enabled
          ? 'Connexion biométrique activée.'
          : 'La biométrie n’a pas pu être activée.',
    );
  }

  Future<void> _changePassword() async {
    final _PasswordChangeInput? input =
        await _askPasswordChange();

    if (input == null ||
        !mounted) {
      return;
    }

    final AuthPasswordChangeResult result =
        await AuthService
            .changeCurrentPassword(
      currentPassword:
          input.currentPassword,
      newPassword:
          input.newPassword,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthPasswordChangeResult.success:
        _showMessage(
          'Mot de passe modifié avec succès.',
        );
        return;

      case AuthPasswordChangeResult.invalidCurrentPassword:
        _showMessage(
          'Le mot de passe actuel est incorrect.',
        );
        return;

      case AuthPasswordChangeResult.weakNewPassword:
        _showMessage(
          AuthService.validatePassword(
                input.newPassword,
              ) ??
              'Le nouveau mot de passe ne respecte pas les règles de sécurité.',
        );
        return;

      case AuthPasswordChangeResult.sameAsCurrentPassword:
        _showMessage(
          'Choisis un nouveau mot de passe différent de l’actuel.',
        );
        return;

      case AuthPasswordChangeResult.accountNotFound:
        _showMessage(
          'Impossible de retrouver le compte actif.',
        );
        return;
    }
  }

  Future<void> _changeEmail() async {
    final _EmailChangeInput? input =
        await _askEmailChange();

    if (input == null ||
        !mounted) {
      return;
    }

    final AuthEmailChangeResult result =
        await AuthService
            .changeCurrentEmail(
      currentPassword:
          input.currentPassword,
      newEmail:
          input.newEmail,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthEmailChangeResult.success:
        final String? email =
            await AuthService
                .getCurrentEmail();

        if (!mounted) {
          return;
        }

        setState(() {
          _email =
              email?.trim() ?? '';
        });

        _showMessage(
          'Adresse e-mail modifiée avec succès.',
        );
        return;

      case AuthEmailChangeResult.invalidCurrentPassword:
        _showMessage(
          'Le mot de passe actuel est incorrect.',
        );
        return;

      case AuthEmailChangeResult.invalidEmail:
        _showMessage(
          'Entre une adresse e-mail valide.',
        );
        return;

      case AuthEmailChangeResult.emailAlreadyUsed:
        _showMessage(
          'Cette adresse e-mail est déjà utilisée.',
        );
        return;

      case AuthEmailChangeResult.accountNotFound:
        _showMessage(
          'Impossible de retrouver le compte actif.',
        );
        return;
    }
  }

  Future<String?> _askCurrentPassword({
    required String title,
    required String message,
  }) {
    final GlobalKey<FormState> formKey =
        GlobalKey<FormState>();

    String password = '';
    bool hidePassword = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(0xff21150e),
              title: Text(
                title,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Color(
                    0xffffc857,
                  ),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: Form(
                key: formKey,
                child:
                    SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Text(
                        message,
                        style:
                            const TextStyle(
                          color:
                              Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      TextFormField(
                        autofocus: true,
                        obscureText:
                            hidePassword,
                        onChanged:
                            (value) {
                          password =
                              value;
                        },
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            _securityInputDecoration(
                          label:
                              'Mot de passe actuel',
                          icon:
                              Icons.lock_outline,
                          suffix:
                              IconButton(
                            onPressed: () {
                              setDialogState(
                                () {
                                  hidePassword =
                                      !hidePassword;
                                },
                              );
                            },
                            icon: Icon(
                              hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color:
                                  Colors.white54,
                            ),
                          ),
                        ),
                        validator:
                            (value) {
                          if ((value ?? '')
                              .isEmpty) {
                            return 'Entre ton mot de passe actuel.';
                          }

                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white54,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (!(formKey
                            .currentState
                            ?.validate() ??
                        false)) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      password,
                    );
                  },
                  child: const Text(
                    'CONFIRMER',
                    style:
                        TextStyle(
                      color:
                          Color(
                        0xffffc857,
                      ),
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_PasswordChangeInput?>
      _askPasswordChange() {
    final GlobalKey<FormState> formKey =
        GlobalKey<FormState>();

    String currentPassword = '';
    String newPassword = '';

    bool hideCurrent = true;
    bool hideNew = true;
    bool hideConfirmation = true;

    return showDialog<
        _PasswordChangeInput>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(0xff21150e),
              title: const Text(
                'CHANGER LE MOT DE PASSE',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Color(
                    0xffffc857,
                  ),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: Form(
                key: formKey,
                child:
                    SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      TextFormField(
                        obscureText:
                            hideCurrent,
                        onChanged:
                            (value) {
                          currentPassword =
                              value;
                        },
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            _securityInputDecoration(
                          label:
                              'Mot de passe actuel',
                          icon:
                              Icons.lock_outline,
                          suffix:
                              IconButton(
                            onPressed: () {
                              setDialogState(
                                () {
                                  hideCurrent =
                                      !hideCurrent;
                                },
                              );
                            },
                            icon:
                                Icon(
                              hideCurrent
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color:
                                  Colors.white54,
                            ),
                          ),
                        ),
                        validator:
                            (value) {
                          if ((value ?? '')
                              .isEmpty) {
                            return 'Entre ton mot de passe actuel.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      TextFormField(
                        obscureText:
                            hideNew,
                        onChanged:
                            (value) {
                          newPassword =
                              value;
                        },
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            _securityInputDecoration(
                          label:
                              'Nouveau mot de passe',
                          icon:
                              Icons.password,
                          suffix:
                              IconButton(
                            onPressed: () {
                              setDialogState(
                                () {
                                  hideNew =
                                      !hideNew;
                                },
                              );
                            },
                            icon:
                                Icon(
                              hideNew
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color:
                                  Colors.white54,
                            ),
                          ),
                        ),
                        validator:
                            (value) {
                          return AuthService
                              .validatePassword(
                            value ?? '',
                          );
                        },
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      TextFormField(
                        obscureText:
                            hideConfirmation,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            _securityInputDecoration(
                          label:
                              'Confirmer le nouveau mot de passe',
                          icon:
                              Icons.lock_reset,
                          suffix:
                              IconButton(
                            onPressed: () {
                              setDialogState(
                                () {
                                  hideConfirmation =
                                      !hideConfirmation;
                                },
                              );
                            },
                            icon:
                                Icon(
                              hideConfirmation
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color:
                                  Colors.white54,
                            ),
                          ),
                        ),
                        validator:
                            (value) {
                          if ((value ?? '') !=
                              newPassword) {
                            return 'Les mots de passe ne correspondent pas.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      const _PasswordRulesCard(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white54,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (!(formKey
                            .currentState
                            ?.validate() ??
                        false)) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _PasswordChangeInput(
                        currentPassword:
                            currentPassword,
                        newPassword:
                            newPassword,
                      ),
                    );
                  },
                  child: const Text(
                    'MODIFIER',
                    style:
                        TextStyle(
                      color:
                          Color(
                        0xffffc857,
                      ),
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_EmailChangeInput?>
      _askEmailChange() {
    final GlobalKey<FormState> formKey =
        GlobalKey<FormState>();

    String newEmail = _email;
    String currentPassword = '';
    bool hidePassword = true;

    return showDialog<_EmailChangeInput>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor:
                  const Color(0xff21150e),
              title: const Text(
                'CHANGER L’ADRESSE E-MAIL',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      Color(
                    0xffffc857,
                  ),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: Form(
                key: formKey,
                child:
                    SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue:
                            _email,
                        keyboardType:
                            TextInputType
                                .emailAddress,
                        autocorrect:
                            false,
                        onChanged:
                            (value) {
                          newEmail =
                              value;
                        },
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            _securityInputDecoration(
                          label:
                              'Nouvelle adresse e-mail',
                          icon:
                              Icons.alternate_email,
                        ),
                        validator:
                            (value) {
                          final String email =
                              value
                                      ?.trim() ??
                                  '';

                          if (!RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(
                            email,
                          )) {
                            return 'Entre une adresse e-mail valide.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      TextFormField(
                        obscureText:
                            hidePassword,
                        onChanged:
                            (value) {
                          currentPassword =
                              value;
                        },
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            _securityInputDecoration(
                          label:
                              'Mot de passe actuel',
                          icon:
                              Icons.lock_outline,
                          suffix:
                              IconButton(
                            onPressed: () {
                              setDialogState(
                                () {
                                  hidePassword =
                                      !hidePassword;
                                },
                              );
                            },
                            icon:
                                Icon(
                              hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color:
                                  Colors.white54,
                            ),
                          ),
                        ),
                        validator:
                            (value) {
                          if ((value ?? '')
                              .isEmpty) {
                            return 'Entre ton mot de passe actuel.';
                          }

                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'ANNULER',
                    style:
                        TextStyle(
                      color:
                          Colors.white54,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (!(formKey
                            .currentState
                            ?.validate() ??
                        false)) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _EmailChangeInput(
                        newEmail:
                            newEmail,
                        currentPassword:
                            currentPassword,
                      ),
                    );
                  },
                  child: const Text(
                    'MODIFIER',
                    style:
                        TextStyle(
                      color:
                          Color(
                        0xffffc857,
                      ),
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  InputDecoration
      _securityInputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(
        color:
            Colors.white60,
      ),
      prefixIcon:
          Icon(
        icon,
        color:
            const Color(
          0xffffc857,
        ),
      ),
      suffixIcon:
          suffix,
      filled: true,
      fillColor:
          const Color(
        0xff160e09,
      ),
      enabledBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        borderSide:
            const BorderSide(
          color:
              Colors.white12,
        ),
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        borderSide:
            const BorderSide(
          color:
              Color(
            0xffffc857,
          ),
          width: 1.5,
        ),
      ),
      errorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        borderSide:
            const BorderSide(
          color:
              Colors.redAccent,
        ),
      ),
      focusedErrorBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        borderSide:
            const BorderSide(
          color:
              Colors.redAccent,
          width: 1.5,
        ),
      ),
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  Widget _buildSheetHandle() {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius:
            BorderRadius.circular(
          10,
        ),
      ),
    );
  }

  // ==========================================================================
  // CENTRE DE CONFIGURATION DU PORTAIL
  // ==========================================================================

  void _openControlCenter() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          const Color(0xff17120f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        void openAfterClose(
          VoidCallback action,
        ) {
          Navigator.pop(sheetContext);
          Future<void>.microtask(action);
        }

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              16,
              18,
              28,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                _buildSheetHandle(),

                const SizedBox(
                  height: 14,
                ),

                const _SheetTitle(
                  icon:
                      Icons.settings_suggest,
                  title:
                      'CENTRE DE CONFIGURATION',
                ),

                const SizedBox(
                  height: 14,
                ),

                _SettingsHubTile(
                  icon:
                      Icons.settings,
                  title:
                      'PARAMÈTRES',
                  subtitle:
                      'Musique, sons, vibrations et notifications',
                  onTap: () {
                    openAfterClose(
                      _openSettings,
                    );
                  },
                ),

                const SizedBox(
                  height: 10,
                ),

                _SettingsHubTile(
                  icon:
                      Icons.tune,
                  title:
                      'OPTIONS',
                  subtitle:
                      'Animations, confirmations et conseils de Bjorn',
                  onTap: () {
                    openAfterClose(
                      _openOptions,
                    );
                  },
                ),

                const SizedBox(
                  height: 10,
                ),

                _SettingsHubTile(
                  icon:
                      Icons.manage_accounts,
                  title:
                      'COMPTE & SÉCURITÉ',
                  subtitle:
                      'E-mail, mot de passe, biométrie et déconnexion',
                  onTap: () {
                    openAfterClose(
                      _openAccount,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPortalComingSoon(
    String feature,
  ) {
    _showMessage(
      '$feature sera branché au portail quand cette partie de Project XP sera développée.',
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff0d0b0a),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff21150e),
        foregroundColor:
            const Color(0xffffc857),
        automaticallyImplyLeading: false,
        leadingWidth: 58,
        leading: const Center(
          child: HallHomeButton(
            width: 44,
            height: 40,
          ),
        ),
        centerTitle: true,
        title: const Text(
          'TERMINAL XP',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(
                color:
                    Color(0xffffc857),
              ),
            )
          : SafeArea(
              child:
                  SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  24,
                ),
                child: _PortalBrowser(
                  username:
                      _username,
                  avatar:
                      _avatar,
                  games:
                      _games,
                  activity:
                      _activity,
                  onProfile:
                      _openProfile,
                  onSettings:
                      _openControlCenter,
                  onReload:
                      _loadData,
                  onLibrary:
                      _openLibrary,
                  onQuestTap: () {
                    _showPortalComingSoon(
                      'Les quêtes',
                    );
                  },
                ),
              ),
            ),
    );
  }
}

// =============================================================================
// NAVIGATEUR PROJECT XP
// =============================================================================

class _PortalBrowser extends StatelessWidget {
  final String username;
  final AvatarModel? avatar;
  final List<GameLibraryEntry> games;
  final List<GamingActivityEvent> activity;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onReload;
  final VoidCallback onLibrary;
  final VoidCallback onQuestTap;

  const _PortalBrowser({
    required this.username,
    required this.avatar,
    required this.games,
    required this.activity,
    required this.onProfile,
    required this.onSettings,
    required this.onReload,
    required this.onLibrary,
    required this.onQuestTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff111315),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xff4b3a25),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _BrowserBar(
            onSettings: onSettings,
            onReload: onReload,
          ),
          _PortalPage(
            username: username,
            avatar: avatar,
            games: games,
            activity: activity,
            onProfile: onProfile,
            onLibrary: onLibrary,
            onQuestTap: onQuestTap,
          ),
        ],
      ),
    );
  }
}

class _BrowserBar extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onReload;

  const _BrowserBar({
    required this.onSettings,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xff202326),
        border: Border(
          bottom: BorderSide(color: Colors.white10),
        ),
      ),
      child: Row(
        children: [
          const _BrowserIcon(
            icon: Icons.arrow_back_ios_new,
            enabled: false,
          ),
          const _BrowserIcon(
            icon: Icons.arrow_forward_ios,
            enabled: false,
          ),
          _BrowserIcon(
            icon: Icons.refresh,
            onTap: onReload,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xff151719),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock,
                    color: Color(0xff7fd18b),
                    size: 14,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'portal.projectxp.gg',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Paramètres Project XP',
            onPressed: onSettings,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.settings,
              color: Color(0xffffc857),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowserIcon extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _BrowserIcon({
    required this.icon,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = enabled ? Colors.white60 : Colors.white24;

    return SizedBox(
      width: 32,
      height: 38,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onTap : null,
        icon: Icon(
          icon,
          color: color,
          size: 17,
        ),
      ),
    );
  }
}

class _PortalPage extends StatelessWidget {
  final String username;
  final AvatarModel? avatar;
  final List<GameLibraryEntry> games;
  final List<GamingActivityEvent> activity;
  final VoidCallback onProfile;
  final VoidCallback onLibrary;
  final VoidCallback onQuestTap;

  const _PortalPage({
    required this.username,
    required this.avatar,
    required this.games,
    required this.activity,
    required this.onProfile,
    required this.onLibrary,
    required this.onQuestTap,
  });

  @override
  Widget build(BuildContext context) {
    GameLibraryEntry? currentGame;
    for (final GameLibraryEntry game in games) {
      if (game.status == GameStatus.inProgress) {
        currentGame = game;
        break;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xff171312),
            Color(0xff101214),
          ],
        ),
      ),
      child: Column(
        children: [
          const Text(
            'PORTAIL DES AVENTURIERS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xffffc857),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 20),
          _PortalIdentityCard(
            username: username,
            avatar: avatar,
            onProfile: onProfile,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 145,
                  child: _PortalInfoCard(
                    icon: Icons.sports_esports,
                    title: 'EN COURS',
                    value: currentGame?.title ?? 'Aucun jeu en cours',
                    subtitle: currentGame == null
                        ? 'Choisis une aventure dans ta Bibliothèque'
                        : '${currentGame.platform.label} • ${currentGame.progressPercent} %',
                    onTap: onLibrary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 145,
                  child: _PortalInfoCard(
                    icon: Icons.auto_awesome,
                    title: 'QUÊTE ACTIVE',
                    value: 'Aucune quête',
                    subtitle: 'Le Maître des Quêtes arrive bientôt',
                    onTap: onQuestTap,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PortalLibraryCard(
            games: games,
            onTap: onLibrary,
          ),
          const SizedBox(height: 18),
          _PortalAdventureFeed(activity: activity),
        ],
      ),
    );
  }
}

class _PortalIdentityCard extends StatelessWidget {
  final String username;
  final AvatarModel? avatar;
  final VoidCallback onProfile;

  const _PortalIdentityCard({
    required this.username,
    required this.avatar,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final AvatarModel? currentAvatar = avatar;

    return Material(
      color: const Color(0xff1d1f22),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onProfile,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xffffc857).withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xff141618),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xffffc857),
                    width: 1.5,
                  ),
                ),
                child: currentAvatar == null
                    ? const Icon(
                        Icons.person,
                        color: Color(0xffffc857),
                      )
                    : ClipOval(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          child: AvatarRenderer(
                            avatar: currentAvatar,
                            size: 54,
                            showFrame: false,
                            compactHeadCrop: true,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bonjour $username 👋',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Niveau --  •  XP -- / --',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Progression RPG en préparation',
                      style: TextStyle(
                        color: Color(0xffb69bdc),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xffffc857),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback onTap;

  const _PortalInfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff1d1f22),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: const Color(0xffffc857),
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffffc857),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0x75FFFFFF),
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalLibraryCard extends StatelessWidget {
  final List<GameLibraryEntry> games;
  final VoidCallback onTap;

  const _PortalLibraryCard({
    required this.games,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final int inProgress =
        games.where((game) => game.status == GameStatus.inProgress).length;
    final int completed =
        games.where((game) => game.status == GameStatus.completed).length;
    final List<GameLibraryEntry> preview = games.take(4).toList();

    return Material(
      color: const Color(0xff1a1c1f),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xffffc857),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'MA BIBLIOTHÈQUE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                games.isEmpty
                    ? 'Aucun jeu ajouté pour le moment.'
                    : '${games.length} jeux • $inProgress en cours • $completed terminés',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
                ),
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (int i = 0; i < preview.length; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      Expanded(
                        child: _PortalGameMini(game: preview[i]),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalGameMini extends StatelessWidget {
  final GameLibraryEntry game;

  const _PortalGameMini({required this.game});

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: const Color(0xff111315),
      alignment: Alignment.center,
      child: const Icon(
        Icons.sports_esports,
        color: Colors.white24,
        size: 18,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
            aspectRatio: 0.72,
            child: game.coverUrl == null || game.coverUrl!.isEmpty
                ? fallback
                : Image.network(
                    game.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => fallback,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          game.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 8.5,
          ),
        ),
      ],
    );
  }
}

class _PortalAdventureFeed extends StatelessWidget {
  final List<GamingActivityEvent> activity;

  const _PortalAdventureFeed({required this.activity});

  String _date(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  @override
  Widget build(BuildContext context) {
    final List<GamingActivityEvent> preview = activity.take(4).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: const Color(0xff1a1c1f),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                color: Color(0xffffc857),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'FIL D’AVENTURE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (preview.isEmpty)
            const Text(
              'Tes trophées, succès, jeux terminés et autres accomplissements apparaîtront ici au fil de ton aventure.',
              style: TextStyle(
                color: Color(0x75FFFFFF),
                fontSize: 11.5,
                height: 1.35,
              ),
            )
          else
            for (final GamingActivityEvent event in preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.circle,
                        color: Color(0xffb69bdc),
                        size: 5,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (event.detail.isNotEmpty)
                            Text(
                              event.detail,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _date(event.createdAt),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 2),
          const Text(
            'L’activité de tes amis rejoindra bientôt ce fil.',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 9.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}


class _SettingsHubTile
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsHubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color:
          const Color(0xff120d0a),
      borderRadius:
          BorderRadius.circular(
        14,
      ),
      child: InkWell(
        onTap:
            onTap,
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.all(
            14,
          ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              14,
            ),
            border: Border.all(
              color:
                  Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      const Color(0xff21150e),
                  borderRadius:
                      BorderRadius.circular(
                    11,
                  ),
                  border: Border.all(
                    color:
                        const Color(0xffffc857)
                            .withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
                child: Icon(
                  icon,
                  color:
                      const Color(0xffffc857),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color:
                            Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right,
                color:
                    Color(0xffffc857),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TITRE DES FENÊTRES
// =============================================================================

class _SheetTitle
    extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SheetTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color:
              const Color(
            0xffffc857,
          ),
        ),
        const SizedBox(
          width: 9,
        ),
        Text(
          title,
          style:
              const TextStyle(
            color:
                Color(
              0xffffc857,
            ),
            fontSize: 20,
            fontWeight:
                FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SWITCH PARAMÈTRE
// =============================================================================

class _TerminalSwitch
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _TerminalSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xff160e09),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
              Colors.white12,
        ),
      ),
      child: SwitchListTile(
        secondary: Icon(
          icon,
          color:
              const Color(
            0xffffc857,
          ),
        ),
        title: Text(
          title,
          style:
              const TextStyle(
            color:
                Colors.white,
            fontWeight:
                FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style:
              const TextStyle(
            color:
                Colors.white54,
            fontSize: 12,
          ),
        ),
        value: value,
        activeThumbColor:
            const Color(
          0xffffc857,
        ),
        onChanged:
            onChanged,
      ),
    );
  }
}

// =============================================================================
// INFO COMPTE
// =============================================================================

class _AccountLine
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AccountLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xff160e09),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
              Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color:
                const Color(
              0xffffc857,
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      const TextStyle(
                    color:
                        Colors.white38,
                    fontSize: 11,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  value,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SÉCURITÉ DU COMPTE
// =============================================================================

class _SecuritySectionLabel
    extends StatelessWidget {
  final String label;

  const _SecuritySectionLabel({
    required this.label,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Align(
      alignment:
          Alignment.centerLeft,
      child: Text(
        label,
        style:
            const TextStyle(
          color:
              Color(
            0xffffc857,
          ),
          fontSize: 12,
          fontWeight:
              FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _BiometricSecurityTile
    extends StatelessWidget {
  final bool available;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool>?
      onChanged;

  const _BiometricSecurityTile({
    required this.available,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final String subtitle;

    if (!available) {
      subtitle =
          'Aucune biométrie configurée sur cet appareil';
    } else if (enabled) {
      subtitle =
          'Activée pour ce compte sur cet appareil';
    } else {
      subtitle =
          'Disponible : empreinte ou reconnaissance faciale';
    }

    return Container(
      decoration: BoxDecoration(
        color:
            const Color(
          0xff160e09,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
              enabled
                  ? const Color(
                      0xffffc857,
                    )
                  : Colors.white12,
        ),
      ),
      child: SwitchListTile(
        secondary: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                      Color(
                    0xffffc857,
                  ),
                ),
              )
            : const Icon(
                Icons.fingerprint,
                color:
                    Color(
                  0xffffc857,
                ),
              ),
        title: const Text(
          'Connexion biométrique',
          style:
              TextStyle(
            color:
                Colors.white,
            fontWeight:
                FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style:
              const TextStyle(
            color:
                Colors.white54,
            fontSize: 12,
          ),
        ),
        value: enabled,
        activeThumbColor:
            const Color(
          0xffffc857,
        ),
        onChanged:
            onChanged,
      ),
    );
  }
}

class _AccountActionButton
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color:
          const Color(
        0xff160e09,
      ),
      borderRadius:
          BorderRadius.circular(
        14,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        child: Container(
          width:
              double.infinity,
          padding:
              const EdgeInsets.all(
            14,
          ),
          decoration:
              BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              14,
            ),
            border:
                Border.all(
              color:
                  Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color:
                    const Color(
                  0xffffc857,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(
                        color:
                            Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color:
                    Color(
                  0xffffc857,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordRulesCard
    extends StatelessWidget {
  const _PasswordRulesCard();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        12,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff160e09,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        border:
            Border.all(
          color:
              Colors.white12,
        ),
      ),
      child:
          const Text(
        '• 10 caractères minimum\n'
        '• au moins une lettre\n'
        '• au moins un chiffre\n'
        '• au moins un caractère spécial',
        style:
            TextStyle(
          color:
              Colors.white54,
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }
}

class _PasswordChangeInput {
  final String currentPassword;
  final String newPassword;

  const _PasswordChangeInput({
    required this.currentPassword,
    required this.newPassword,
  });
}

class _EmailChangeInput {
  final String newEmail;
  final String currentPassword;

  const _EmailChangeInput({
    required this.newEmail,
    required this.currentPassword,
  });
}

