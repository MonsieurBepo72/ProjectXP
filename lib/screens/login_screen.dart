import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/session_service.dart';
import 'hall_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
  });

  @override
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  final TextEditingController _emailController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _loading = false;
  bool _hidePassword = true;

  bool _biometricLoginAvailable = false;
  String _biometricUsername = '';

  @override
  void initState() {
    super.initState();
    _refreshBiometricState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // BIOMÉTRIE
  // ===========================================================================

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

  Future<void> _loginWithBiometrics() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final String? userId =
          await BiometricAuthService
              .getEnabledUserId();

      if (userId == null ||
          userId.trim().isEmpty) {
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

      await _finishLogin(
        offerBiometrics: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
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
            'Veux-tu utiliser ton empreinte ou la reconnaissance faciale pour tes prochaines connexions sur cet appareil ?',
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

    _showMessage(
      enabled
          ? 'Connexion biométrique activée.'
          : 'La biométrie n’a pas pu être activée.',
    );

    await _refreshBiometricState();
  }

  // ===========================================================================
  // CONNEXION MOT DE PASSE
  // ===========================================================================

  Future<void> _login() async {
    if (_loading) {
      return;
    }

    if (!(_formKey.currentState
            ?.validate() ??
        false)) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final AuthLoginResult result =
          await AuthService.login(
        email:
            _emailController.text,
        password:
            _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      switch (result) {
        case AuthLoginResult.success:
          await _finishLogin(
            offerBiometrics: true,
          );
          return;

        case AuthLoginResult.invalidCredentials:
          _showMessage(
            'Adresse e-mail ou mot de passe incorrect.',
          );
          return;

        case AuthLoginResult.passwordSetupRequired:
          await _secureLegacyAccount();
          return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ===========================================================================
  // MIGRATION DES ANCIENS COMPTES
  // ===========================================================================

  Future<void> _secureLegacyAccount() async {
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
            'Ce compte a été créé avant que Project XP vérifie réellement les mots de passe.\n\n'
            'L’ancien mot de passe n’a jamais été enregistré et ne peut donc pas être récupéré. '
            'Confirme que cet appareil t’appartient puis choisis un nouveau mot de passe.',
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
        'Aucune authentification locale de l’appareil n’est disponible.',
      );
      return;
    }

    final bool ownerConfirmed =
        await BiometricAuthService
            .authenticateDeviceOwner();

    if (!mounted) {
      return;
    }

    if (!ownerConfirmed) {
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

    final bool saved =
        await AuthService
            .setPasswordForEmail(
      email:
          _emailController.text,
      password:
          newPassword,
    );

    if (!mounted) {
      return;
    }

    if (!saved) {
      _showMessage(
        'Impossible d’enregistrer le nouveau mot de passe.',
      );
      return;
    }

    final AuthLoginResult result =
        await AuthService.login(
      email:
          _emailController.text,
      password:
          newPassword,
    );

    if (!mounted) {
      return;
    }

    if (result !=
        AuthLoginResult.success) {
      _showMessage(
        'Le compte a été sécurisé mais la reconnexion a échoué.',
      );
      return;
    }

    _passwordController.text =
        newPassword;

    _showMessage(
      'Ton compte est maintenant protégé par un vrai mot de passe.',
    );

    await _finishLogin(
      offerBiometrics: true,
    );
  }

  Future<String?> _askForNewPassword() {
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
                        _inputDecoration(
                      'Nouveau mot de passe',
                      Icons.lock,
                    ),
                    validator: (value) {
                      return AuthService
                          .validatePassword(
                        value ?? '',
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
                        _inputDecoration(
                      'Confirmer le mot de passe',
                      Icons.lock_outline,
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

  // ===========================================================================
  // SESSION / NAVIGATION
  // ===========================================================================

  Future<void> _finishLogin({
    required bool offerBiometrics,
  }) async {
    await SessionService
        .startNewSession();

    if (!mounted) {
      return;
    }

    if (offerBiometrics) {
      await _offerBiometricActivation();
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) =>
            const HallScreen(),
      ),
      (route) => false,
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

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        foregroundColor:
            const Color(0xffffc857),
        elevation: 0,
        title:
            const Text(
          'Connexion',
        ),
      ),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            26,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Icon(
                  Icons.login,
                  color:
                      Color(
                    0xffffc857,
                  ),
                  size: 70,
                ),

                const SizedBox(
                  height: 35,
                ),

                TextFormField(
                  controller:
                      _emailController,
                  enabled:
                      !_loading,
                  keyboardType:
                      TextInputType
                          .emailAddress,
                  textInputAction:
                      TextInputAction.next,
                  autocorrect: false,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      _inputDecoration(
                    'Adresse e-mail',
                    Icons.email,
                  ),
                  validator:
                      (value) {
                    final String email =
                        value?.trim() ??
                            '';

                    if (email.isEmpty ||
                        !email
                            .contains(
                          '@',
                        )) {
                      return 'Entre une adresse e-mail valide.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 16,
                ),

                TextFormField(
                  controller:
                      _passwordController,
                  enabled:
                      !_loading,
                  obscureText:
                      _hidePassword,
                  textInputAction:
                      TextInputAction.done,
                  onFieldSubmitted:
                      (_) {
                    _login();
                  },
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      _inputDecoration(
                    'Mot de passe',
                    Icons.lock,
                  ).copyWith(
                    suffixIcon:
                        IconButton(
                      onPressed:
                          _loading
                              ? null
                              : () {
                                  setState(
                                    () {
                                      _hidePassword =
                                          !_hidePassword;
                                    },
                                  );
                                },
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color:
                            Colors.white54,
                      ),
                    ),
                  ),
                  validator:
                      (value) {
                    if (value == null ||
                        value.isEmpty) {
                      return 'Entre ton mot de passe.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 30,
                ),

                SizedBox(
                  width:
                      double.infinity,
                  height: 55,
                  child:
                      ElevatedButton(
                    onPressed:
                        _loading
                            ? null
                            : _login,
                    style:
                        ElevatedButton
                            .styleFrom(
                      backgroundColor:
                          const Color(
                        0xffffc857,
                      ),
                      foregroundColor:
                          const Color(
                        0xff21150e,
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  3,
                            ),
                          )
                        : const Text(
                            'ENTRER',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                if (_biometricLoginAvailable) ...[
                  const SizedBox(
                    height: 16,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height: 52,
                    child:
                        OutlinedButton.icon(
                      onPressed:
                          _loading
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
                            TextOverflow
                                .ellipsis,
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
                ],

                const SizedBox(
                  height: 15,
                ),

                const Text(
                  'Le mot de passe est vérifié localement et n’est jamais stocké en clair.',
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    color:
                        Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
  ) {
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
      filled: true,
      fillColor:
          const Color(
        0xff2b1b12,
      ),
      border:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        borderSide:
            BorderSide.none,
      ),
      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        borderSide:
            const BorderSide(
          color:
              Color(
            0xffffc857,
          ),
          width: 2,
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
