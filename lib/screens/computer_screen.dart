import 'package:flutter/material.dart';

import 'package:project_xp/screens/profile_screen.dart';
import 'package:project_xp/screens/splash_screen.dart';
import 'package:project_xp/services/app_notification_service.dart';
import 'package:project_xp/services/auth_service.dart';
import 'package:project_xp/services/biometric_auth_service.dart';
import 'package:project_xp/services/computer_settings_service.dart';
import 'package:project_xp/services/session_service.dart';

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
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff120c08),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff21150e),
        foregroundColor:
            const Color(0xffffc857),
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
                    const EdgeInsets.all(
                  20,
                ),
                child: Column(
                  children: [
                    _TerminalHeader(
                      username:
                          _username,
                    ),

                    const SizedBox(
                      height: 26,
                    ),

                    _TerminalMenuCard(
                      icon:
                          Icons.person,
                      title:
                          'MON PROFIL',
                      subtitle:
                          'Profil, avatar, jeux, plateformes et réseaux',
                      onTap:
                          _openProfile,
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    _TerminalMenuCard(
                      icon:
                          Icons.settings,
                      title:
                          'PARAMÈTRES',
                      subtitle:
                          'Musique, sons, vibrations et notifications',
                      onTap:
                          _openSettings,
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    _TerminalMenuCard(
                      icon:
                          Icons.tune,
                      title:
                          'OPTIONS',
                      subtitle:
                          'Animations, confirmations et conseils de Bjorn',
                      onTap:
                          _openOptions,
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    _TerminalMenuCard(
                      icon:
                          Icons.manage_accounts,
                      title:
                          'COMPTE & SÉCURITÉ',
                      subtitle:
                          'E-mail, mot de passe, biométrie et déconnexion',
                      onTap:
                          _openAccount,
                    ),

                    const SizedBox(
                      height: 28,
                    ),

                    const Text(
                      'PROJECT XP // TERMINAL DU HALL',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            Colors.white24,
                        fontSize: 10,
                        fontWeight:
                            FontWeight.bold,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// =============================================================================
// EN-TÊTE DU TERMINAL
// =============================================================================

class _TerminalHeader
    extends StatelessWidget {
  final String username;

  const _TerminalHeader({
    required this.username,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(
        22,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xff21150e),
        borderRadius:
            BorderRadius.circular(
          22,
        ),
        border: Border.all(
          color:
              const Color(0xffffc857),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color:
                Colors.black45,
            blurRadius: 16,
            offset:
                Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration:
                BoxDecoration(
              shape:
                  BoxShape.circle,
              color:
                  const Color(
                0xff160e09,
              ),
              border:
                  Border.all(
                color:
                    const Color(
                  0xffffc857,
                ),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.computer,
              color:
                  Color(
                0xffffc857,
              ),
              size: 38,
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          const Text(
            'BIENVENUE SUR LE TERMINAL',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  Color(
                0xffffc857,
              ),
              fontWeight:
                  FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),

          const SizedBox(
            height: 7,
          ),

          Text(
            username,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontSize: 24,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CARTE DU MENU
// =============================================================================

class _TerminalMenuCard
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TerminalMenuCard({
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
          const Color(0xff21150e),
      borderRadius:
          BorderRadius.circular(
        16,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.all(
            17,
          ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              16,
            ),
            border: Border.all(
              color:
                  Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
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
                        const Color(
                      0xffffc857,
                    ),
                  ),
                ),
                child: Icon(
                  icon,
                  color:
                      const Color(
                    0xffffc857,
                  ),
                ),
              ),

              const SizedBox(
                width: 14,
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
                            FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
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

