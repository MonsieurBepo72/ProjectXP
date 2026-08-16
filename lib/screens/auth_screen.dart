import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/avatar_storage.dart';
import '../services/biometric_auth_service.dart';
import '../services/session_service.dart';
import 'avatar/avatar_choice_screen.dart';
import 'hall_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
  });

  @override
  State<AuthScreen> createState() =>
      _AuthScreenState();
}

class _AuthScreenState
    extends State<AuthScreen> {
  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  bool _registerMode = false;
  bool _busy = false;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  int _formVersion = 0;

  String _username = '';
  String _email = '';
  String _password = '';
  String _confirmPassword = '';

  bool _biometricLoginAvailable = false;
  String _biometricUsername = '';

  @override
  void initState() {
    super.initState();
    _refreshBiometricState();
  }

  Future<void> _refreshBiometricState() async {
    final bool canUse =
        await BiometricAuthService
            .canUseBiometricLogin();

    final String? username =
        canUse
            ? await BiometricAuthService
                .getEnabledUsername()
            : null;

    if (!mounted) {
      return;
    }

    setState(() {
      _biometricLoginAvailable =
          canUse;

      _biometricUsername =
          username?.trim() ?? '';
    });
  }

  void _toggleMode() {
    if (_busy) {
      return;
    }

    setState(() {
      _registerMode =
          !_registerMode;

      _username = '';
      _email = '';
      _password = '';
      _confirmPassword = '';

      _obscurePassword = true;
      _obscureConfirm = true;

      _formVersion++;
    });
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }

    final bool valid =
        _formKey.currentState
                ?.validate() ??
            false;

    if (!valid) {
      return;
    }

    if (_registerMode &&
        _password !=
            _confirmPassword) {
      _showMessage(
        'Les deux mots de passe ne correspondent pas.',
      );
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      if (_registerMode) {
        await _register();
      } else {
        await _login();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _register() async {
    final AuthRegisterResult result =
        await AuthService.register(
      username: _username,
      email: _email,
      password: _password,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthRegisterResult.success:
        await _finishAuthenticatedFlow(
          offerBiometrics: true,
        );
        return;

      case AuthRegisterResult.emailAlreadyUsed:
        _showMessage(
          'Cette adresse e-mail est déjà utilisée.',
        );
        return;

      case AuthRegisterResult.usernameAlreadyUsed:
        _showMessage(
          'Ce pseudo est déjà utilisé.',
        );
        return;

      case AuthRegisterResult.weakPassword:
        _showMessage(
          AuthService.validatePassword(
                _password,
              ) ??
              'Ce mot de passe ne respecte pas les règles de sécurité.',
        );
        return;

      case AuthRegisterResult.invalidData:
        _showMessage(
          'Vérifie le pseudo et l’adresse e-mail.',
        );
        return;
    }
  }

  Future<void> _login() async {
    final AuthLoginResult result =
        await AuthService.login(
      email: _email,
      password: _password,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthLoginResult.success:
        await _finishAuthenticatedFlow(
          offerBiometrics: true,
        );
        return;

      case AuthLoginResult.invalidCredentials:
        _showMessage(
          'Adresse e-mail ou mot de passe incorrect.',
        );
        return;

      case AuthLoginResult.passwordSetupRequired:
        await _upgradeLegacyAccount();
        return;
    }
  }

  Future<void> _upgradeLegacyAccount() async {
    final bool? accepted =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: const Text(
            'SÉCURISER TON ANCIEN COMPTE',
            style: TextStyle(
              color:
                  Color(0xffffc857),
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: const Text(
            'Ce compte a été créé avant l’ajout de la vraie vérification des mots de passe. '
            'L’ancien mot de passe n’a jamais été enregistré, il est donc impossible de le récupérer ou de le vérifier.\n\n'
            'Project XP va te demander de confirmer le propriétaire de cet appareil, puis de définir un nouveau mot de passe sécurisé.',
            style: TextStyle(
              color:
                  Colors.white70,
              height: 1.4,
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
                  color:
                      Colors.white54,
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
                'CONTINUER',
                style: TextStyle(
                  color:
                      Color(0xffffc857),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (accepted != true ||
        !mounted) {
      return;
    }

    final bool deviceAuthAvailable =
        await BiometricAuthService
            .isDeviceAuthenticationAvailable();

    if (!mounted) {
      return;
    }

    if (!deviceAuthAvailable) {
      _showMessage(
        'Impossible de sécuriser cet ancien compte : aucune authentification locale de l’appareil n’est disponible.',
      );
      return;
    }

    final bool deviceOwnerConfirmed =
        await BiometricAuthService
            .authenticateDeviceOwner();

    if (!mounted) {
      return;
    }

    if (!deviceOwnerConfirmed) {
      _showMessage(
        'Confirmation de l’appareil annulée.',
      );
      return;
    }

    final String? newPassword =
        await _askForNewPassword();

    if (newPassword == null ||
        !mounted) {
      return;
    }

    final bool passwordSaved =
        await AuthService
            .setPasswordForEmail(
      email: _email,
      password: newPassword,
    );

    if (!mounted) {
      return;
    }

    if (!passwordSaved) {
      _showMessage(
        'Impossible d’enregistrer le nouveau mot de passe.',
      );
      return;
    }

    final AuthLoginResult result =
        await AuthService.login(
      email: _email,
      password: newPassword,
    );

    if (!mounted) {
      return;
    }

    if (result !=
        AuthLoginResult.success) {
      _showMessage(
        'Le compte a été sécurisé, mais la reconnexion a échoué.',
      );
      return;
    }

    _password = newPassword;

    _showMessage(
      'Ton ancien compte est maintenant protégé par un vrai mot de passe.',
    );

    await _finishAuthenticatedFlow(
      offerBiometrics: true,
    );
  }

  Future<String?> _askForNewPassword() async {
    final GlobalKey<FormState> formKey =
        GlobalKey<FormState>();

    String password = '';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: const Text(
            'NOUVEAU MOT DE PASSE',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  Color(0xffffc857),
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
                    obscureText: true,
                    onChanged: (value) {
                      password = value;
                    },
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                    ),
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Nouveau mot de passe',
                      labelStyle:
                          TextStyle(
                        color:
                            Color(
                          0xffffc857,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final String candidate =
                          value ?? '';

                      return AuthService
                          .validatePassword(
                        candidate,
                      );
                    },
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  TextFormField(
                    obscureText: true,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                    ),
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Confirmer le mot de passe',
                      labelStyle:
                          TextStyle(
                        color:
                            Color(
                          0xffffc857,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '') !=
                          password) {
                        return 'Les mots de passe ne correspondent pas.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  const _PasswordRules(),
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
                style: TextStyle(
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
                'SÉCURISER',
                style: TextStyle(
                  color:
                      Color(0xffffc857),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _finishAuthenticatedFlow({
    required bool offerBiometrics,
  }) async {
    await SessionService.startNewSession();

    if (!mounted) {
      return;
    }

    if (offerBiometrics) {
      await _offerBiometricActivation();
    }

    if (!mounted) {
      return;
    }

    final String? userId =
        await AuthService.getCurrentUserId();

    if (userId == null ||
        userId.trim().isEmpty) {
      _showMessage(
        'Impossible de charger le compte.',
      );
      return;
    }

    final bool hasAvatar =
        await AvatarStorage.hasAvatar(
      userId,
    );

    if (!mounted) {
      return;
    }

    final Widget destination =
        hasAvatar
            ? const HallScreen()
            : const AvatarChoiceScreen();

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) =>
            destination,
      ),
      (route) => false,
    );
  }

  Future<void> _offerBiometricActivation() async {
    final bool available =
        await BiometricAuthService
            .isBiometricAvailable();

    if (!available ||
        !mounted) {
      return;
    }

    final String? currentUserId =
        await AuthService
            .getCurrentUserId();

    final String? enabledUserId =
        await BiometricAuthService
            .getEnabledUserId();

    if (!mounted ||
        currentUserId == null ||
        enabledUserId ==
            currentUserId) {
      return;
    }

    final bool? activate =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: const Text(
            'CONNEXION BIOMÉTRIQUE',
            style: TextStyle(
              color:
                  Color(0xffffc857),
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: const Text(
            'Veux-tu utiliser ton empreinte ou la reconnaissance faciale pour tes prochaines connexions sur cet appareil ?\n\n'
            'Ton mot de passe reste obligatoire comme méthode principale et n’est jamais stocké en clair.',
            style: TextStyle(
              color:
                  Colors.white70,
              height: 1.4,
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
                'PLUS TARD',
                style: TextStyle(
                  color:
                      Colors.white54,
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
                'ACTIVER',
                style: TextStyle(
                  color:
                      Color(0xffffc857),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (activate != true ||
        !mounted) {
      return;
    }

    final bool enabled =
        await BiometricAuthService
            .enableForCurrentAccount();

    if (!mounted) {
      return;
    }

    if (enabled) {
      _showMessage(
        'Connexion biométrique activée.',
      );

      await _refreshBiometricState();
    } else {
      _showMessage(
        'La biométrie n’a pas pu être activée.',
      );
    }
  }

  Future<void> _loginWithBiometrics() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final String? userId =
          await BiometricAuthService
              .getEnabledUserId();

      if (userId == null) {
        _showMessage(
          'Aucun compte biométrique configuré.',
        );
        return;
      }

      final bool authenticated =
          await BiometricAuthService
              .authenticateBiometricOnly(
        reason:
            'Authentifie-toi pour te connecter à Project XP.',
      );

      if (!authenticated ||
          !mounted) {
        return;
      }

      final bool activated =
          await AuthService
              .activateLocalAccountById(
        userId,
      );

      if (!activated ||
          !mounted) {
        _showMessage(
          'Impossible de réactiver ce compte.',
        );
        return;
      }

      await _finishAuthenticatedFlow(
        offerBiometrics: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _disableBiometrics() async {
    await BiometricAuthService.disable();

    if (!mounted) {
      return;
    }

    await _refreshBiometricState();

    if (!mounted) {
      return;
    }

    _showMessage(
      'Connexion biométrique désactivée.',
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
        content: Text(
          message,
        ),
      ),
    );
  }

  String? _validateEmail(
    String? value,
  ) {
    final String email =
        value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Entre ton adresse e-mail.';
    }

    if (!email.contains('@') ||
        !email.contains('.')) {
      return 'Adresse e-mail invalide.';
    }

    return null;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            22,
            35,
            22,
            35,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 520,
              ),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/logo_project_xp.png',
                    width: 210,
                    fit:
                        BoxFit.contain,
                    errorBuilder: (
                      context,
                      error,
                      stackTrace,
                    ) {
                      return const Text(
                        'PROJECT XP',
                        textAlign:
                            TextAlign.center,
                        style:
                            TextStyle(
                          color:
                              Color(
                            0xffffc857,
                          ),
                          fontSize: 34,
                          fontWeight:
                              FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      );
                    },
                  ),

                  const SizedBox(
                    height: 25,
                  ),

                  Text(
                    _registerMode
                        ? 'CRÉER TON COMPTE'
                        : 'RETOUR À L’AVENTURE',
                    style:
                        const TextStyle(
                      color:
                          Color(
                        0xffffc857,
                      ),
                      fontSize: 22,
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Text(
                    _registerMode
                        ? 'Ton identité Project XP commence ici.'
                        : 'Connecte-toi à ton compte Project XP.',
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      color:
                          Colors.white54,
                    ),
                  ),

                  const SizedBox(
                    height: 25,
                  ),

                  Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets.all(
                      18,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xff21150e,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        18,
                      ),
                      border:
                          Border.all(
                        color:
                            const Color(
                          0xffffc857,
                        ),
                        width: 1.5,
                      ),
                    ),
                    child: Form(
                      key:
                          _formKey,
                      child: Column(
                        key: ValueKey(
                          'auth-form-$_formVersion-$_registerMode',
                        ),
                        children: [
                          if (_registerMode) ...[
                            TextFormField(
                              key: ValueKey(
                                'username-$_formVersion',
                              ),
                              enabled:
                                  !_busy,
                              textInputAction:
                                  TextInputAction.next,
                              onChanged:
                                  (value) {
                                _username =
                                    value;
                              },
                              validator:
                                  (value) {
                                if ((value ?? '')
                                    .trim()
                                    .isEmpty) {
                                  return 'Choisis un pseudo.';
                                }

                                return null;
                              },
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  _inputDecoration(
                                label:
                                    'Pseudo',
                                icon:
                                    Icons.person_outline,
                              ),
                            ),
                            const SizedBox(
                              height: 14,
                            ),
                          ],

                          TextFormField(
                            key: ValueKey(
                              'email-$_formVersion',
                            ),
                            enabled:
                                !_busy,
                            keyboardType:
                                TextInputType
                                    .emailAddress,
                            textInputAction:
                                TextInputAction.next,
                            autocorrect:
                                false,
                            onChanged:
                                (value) {
                              _email =
                                  value;
                            },
                            validator:
                                _validateEmail,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                            ),
                            decoration:
                                _inputDecoration(
                              label:
                                  'E-mail',
                              icon:
                                  Icons.mail_outline,
                            ),
                          ),

                          const SizedBox(
                            height: 14,
                          ),

                          TextFormField(
                            key: ValueKey(
                              'password-$_formVersion',
                            ),
                            enabled:
                                !_busy,
                            obscureText:
                                _obscurePassword,
                            textInputAction:
                                _registerMode
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                            onFieldSubmitted:
                                (_) {
                              if (!_registerMode) {
                                _submit();
                              }
                            },
                            onChanged:
                                (value) {
                              _password =
                                  value;
                            },
                            validator:
                                (value) {
                              final String password =
                                  value ??
                                      '';

                              if (password
                                  .isEmpty) {
                                return 'Entre ton mot de passe.';
                              }

                              if (_registerMode) {
                                return AuthService
                                    .validatePassword(
                                  password,
                                );
                              }

                              return null;
                            },
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                            ),
                            decoration:
                                _inputDecoration(
                              label:
                                  'Mot de passe',
                              icon:
                                  Icons.lock_outline,
                              suffix:
                                  IconButton(
                                onPressed:
                                    _busy
                                        ? null
                                        : () {
                                            setState(
                                              () {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              },
                                            );
                                          },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color:
                                      Colors.white54,
                                ),
                              ),
                            ),
                          ),

                          if (_registerMode) ...[
                            const SizedBox(
                              height: 14,
                            ),

                            TextFormField(
                              key: ValueKey(
                                'confirm-$_formVersion',
                              ),
                              enabled:
                                  !_busy,
                              obscureText:
                                  _obscureConfirm,
                              textInputAction:
                                  TextInputAction.done,
                              onFieldSubmitted:
                                  (_) {
                                _submit();
                              },
                              onChanged:
                                  (value) {
                                _confirmPassword =
                                    value;
                              },
                              validator:
                                  (value) {
                                if ((value ?? '')
                                        .isEmpty) {
                                  return 'Confirme ton mot de passe.';
                                }

                                if ((value ?? '') !=
                                    _password) {
                                  return 'Les mots de passe ne correspondent pas.';
                                }

                                return null;
                              },
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  _inputDecoration(
                                label:
                                    'Confirmer le mot de passe',
                                icon:
                                    Icons.lock_reset,
                                suffix:
                                    IconButton(
                                  onPressed:
                                      _busy
                                          ? null
                                          : () {
                                              setState(
                                                () {
                                                  _obscureConfirm =
                                                      !_obscureConfirm;
                                                },
                                              );
                                            },
                                  icon:
                                      Icon(
                                    _obscureConfirm
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color:
                                        Colors.white54,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: 15,
                            ),

                            const _PasswordRules(),
                          ],

                          const SizedBox(
                            height: 22,
                          ),

                          SizedBox(
                            width:
                                double.infinity,
                            height: 52,
                            child:
                                ElevatedButton.icon(
                              onPressed:
                                  _busy
                                      ? null
                                      : _submit,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            Colors.black,
                                      ),
                                    )
                                  : Icon(
                                      _registerMode
                                          ? Icons.person_add_alt_1
                                          : Icons.login,
                                    ),
                              label: Text(
                                _busy
                                    ? 'PATIENTE...'
                                    : (_registerMode
                                        ? 'CRÉER MON COMPTE'
                                        : 'SE CONNECTER'),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              style:
                                  ElevatedButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color(
                                  0xffffc857,
                                ),
                                foregroundColor:
                                    Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!_registerMode &&
                      _biometricLoginAvailable) ...[
                    const SizedBox(
                      height: 16,
                    ),

                    SizedBox(
                      width:
                          double.infinity,
                      height: 50,
                      child:
                          OutlinedButton.icon(
                        onPressed:
                            _busy
                                ? null
                                : _loginWithBiometrics,
                        icon:
                            const Icon(
                          Icons.fingerprint,
                        ),
                        label: Text(
                          _biometricUsername
                                  .isNotEmpty
                              ? 'SE CONNECTER EN TANT QUE $_biometricUsername'
                              : 'CONNEXION BIOMÉTRIQUE',
                          overflow:
                              TextOverflow.ellipsis,
                        ),
                        style:
                            OutlinedButton
                                .styleFrom(
                          foregroundColor:
                              const Color(
                            0xffffc857,
                          ),
                          side:
                              const BorderSide(
                            color:
                                Color(
                              0xffffc857,
                            ),
                          ),
                        ),
                      ),
                    ),

                    TextButton(
                      onPressed:
                          _busy
                              ? null
                              : _disableBiometrics,
                      child:
                          const Text(
                        'Désactiver la connexion biométrique',
                        style:
                            TextStyle(
                          color:
                              Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(
                    height: 10,
                  ),

                  TextButton(
                    onPressed:
                        _busy
                            ? null
                            : _toggleMode,
                    child: Text(
                      _registerMode
                          ? 'J’ai déjà un compte'
                          : 'Créer un nouveau compte',
                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xffffc857,
                        ),
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
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
}

class _PasswordRules
    extends StatelessWidget {
  const _PasswordRules();

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
          const Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            'Ton mot de passe doit contenir :',
            style:
                TextStyle(
              color:
                  Colors.white70,
              fontWeight:
                  FontWeight.bold,
              fontSize: 12,
            ),
          ),
          SizedBox(
            height: 7,
          ),
          Text(
            '• au moins 10 caractères\n'
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
        ],
      ),
    );
  }
}
