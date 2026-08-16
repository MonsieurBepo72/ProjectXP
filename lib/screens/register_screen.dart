import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/session_service.dart';
import 'avatar/avatar_choice_screen.dart';

class RegisterScreen
    extends StatefulWidget {
  const RegisterScreen({
    super.key,
  });

  @override
  State<RegisterScreen> createState() =>
      _RegisterScreenState();
}

class _RegisterScreenState
    extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  final TextEditingController
      _usernameController =
      TextEditingController();

  final TextEditingController
      _emailController =
      TextEditingController();

  final TextEditingController
      _passwordController =
      TextEditingController();

  final TextEditingController
      _confirmPasswordController =
      TextEditingController();

  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
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
      final AuthRegisterResult result =
          await AuthService.register(
        username:
            _usernameController.text,
        email:
            _emailController.text,
        password:
            _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      switch (result) {
        case AuthRegisterResult.success:
          await SessionService
              .startNewSession();

          if (!mounted) {
            return;
          }

          await _offerBiometricActivation();

          if (!mounted) {
            return;
          }

          Navigator.of(context)
              .pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (context) =>
                  const AvatarChoiceScreen(),
            ),
            (route) => false,
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
            AuthService
                    .validatePassword(
                  _passwordController
                      .text,
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
          'Créer ton profil',
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
                  Icons.person_add_alt_1,
                  color:
                      Color(
                    0xffffc857,
                  ),
                  size: 70,
                ),

                const SizedBox(
                  height: 30,
                ),

                TextFormField(
                  controller:
                      _usernameController,
                  enabled:
                      !_loading,
                  textInputAction:
                      TextInputAction.next,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      _inputDecoration(
                    'Pseudo',
                    Icons.person,
                  ),
                  validator:
                      (value) {
                    if (value == null ||
                        value
                                .trim()
                                .length <
                            3) {
                      return 'Choisis un pseudo d’au moins 3 caractères.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 16,
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
                      TextInputAction.next,
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
                      icon:
                          Icon(
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
                    return AuthService
                        .validatePassword(
                      value ?? '',
                    );
                  },
                ),

                const SizedBox(
                  height: 16,
                ),

                TextFormField(
                  controller:
                      _confirmPasswordController,
                  enabled:
                      !_loading,
                  obscureText:
                      _hideConfirmPassword,
                  textInputAction:
                      TextInputAction.done,
                  onFieldSubmitted:
                      (_) {
                    _register();
                  },
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                  ),
                  decoration:
                      _inputDecoration(
                    'Confirmer le mot de passe',
                    Icons.lock_outline,
                  ).copyWith(
                    suffixIcon:
                        IconButton(
                      onPressed:
                          _loading
                              ? null
                              : () {
                                  setState(
                                    () {
                                      _hideConfirmPassword =
                                          !_hideConfirmPassword;
                                    },
                                  );
                                },
                      icon:
                          Icon(
                        _hideConfirmPassword
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
                        _passwordController
                            .text) {
                      return 'Les mots de passe ne correspondent pas.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 15,
                ),

                const _PasswordRules(),

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
                            : _register,
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
                            'CRÉER MON COMPTE',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
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
          0xff2b1b12,
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
            'Mot de passe :',
            style:
                TextStyle(
              color:
                  Color(
                0xffffc857,
              ),
              fontWeight:
                  FontWeight.bold,
              fontSize: 12,
            ),
          ),
          SizedBox(
            height: 6,
          ),
          Text(
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
        ],
      ),
    );
  }
}
