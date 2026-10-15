import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/avatar_storage.dart';
import '../services/biometric_auth_service.dart';
import '../services/cloud_identity_service.dart';
import '../services/cloud_session_guard_service.dart';
import '../services/supabase_service.dart';
import '../services/session_service.dart';
import 'avatar/avatar_choice_screen.dart';
import 'hall_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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

  StreamSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<Uri>? _recoveryLinkSubscription;
  bool _recoveryFlowScheduled = false;
  bool _recoveryFlowBusy = false;
  String? _handledRecoveryUri;

  static const String _recoveryScheme = 'projectxp';
  static const String _recoveryHost = 'auth-reset';
  static const String _recoveryRedirect = 'projectxp://auth-reset';

  @override
  void initState() {
    super.initState();
    _refreshBiometricState();
    _initializePasswordRecovery();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _recoveryLinkSubscription?.cancel();
    super.dispose();
  }

  void _initializePasswordRecovery() {
    _authStateSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen(
      (AuthState state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _schedulePasswordRecoveryCompletion();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Une panne réseau Auth ne doit jamais faire planter l'écran de login.
      },
    );

    unawaited(_initializePasswordRecoveryLinks());
  }

  Future<void> _initializePasswordRecoveryLinks() async {
    try {
      final AppLinks appLinks = AppLinks();
      final Uri? initial = await appLinks.getInitialLink();
      if (initial != null) {
        unawaited(_handlePasswordRecoveryUri(initial));
      }

      _recoveryLinkSubscription = appLinks.uriLinkStream.listen(
        (Uri uri) {
          unawaited(_handlePasswordRecoveryUri(uri));
        },
        onError: (Object error) {
          // Un problème AppLinks ne doit jamais faire planter le login.
        },
      );
    } catch (_) {
      // Le lien pourra être redemandé si Android ne le livre pas correctement.
    }
  }

  Future<void> _handlePasswordRecoveryUri(Uri uri) async {
    if (uri.scheme != _recoveryScheme || uri.host != _recoveryHost) {
      return;
    }

    final String rawUri = uri.toString();
    if (_handledRecoveryUri == rawUri) {
      return;
    }
    _handledRecoveryUri = rawUri;

    try {
      // Supabase Flutter utilise PKCE par défaut. Comme la détection automatique
      // des callbacks est désactivée dans main.dart, Project XP échange lui-même
      // le code du lien. Cela évite la course observée au démarrage à froid où
      // le SDK consommait le callback avant que AuthScreen ne puisse l'utiliser.
      await SupabaseService.client.auth.getSessionFromUrl(uri);

      if (!mounted) {
        return;
      }

      _schedulePasswordRecoveryCompletion();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      final String message = error.message.toLowerCase();
      _showMessage(
        message.contains('code verifier') || message.contains('pkce')
            ? 'Ce lien doit être ouvert sur le même appareil que celui qui a demandé la récupération. Redemande un nouveau lien depuis ce téléphone.'
            : 'Le lien de récupération est invalide ou expiré. Redemande un nouveau lien.',
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Le lien de récupération n’a pas pu être validé. Redemande un nouveau lien.',
        );
      }
    }
  }

  void _schedulePasswordRecoveryCompletion() {
    if (_recoveryFlowScheduled || _recoveryFlowBusy || !mounted) {
      return;
    }

    _recoveryFlowScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _recoveryFlowScheduled = false;
        return;
      }

      unawaited(
        _completePasswordRecoveryFromSession().whenComplete(() {
          _recoveryFlowScheduled = false;
        }),
      );
    });
  }

  Future<void> _requestPasswordReset() async {
    if (_busy || _registerMode) {
      return;
    }

    final String email = _email.trim().toLowerCase();
    final String? emailError = _validateEmail(email);

    if (emailError != null) {
      _showMessage('Entre d’abord l’adresse e-mail du compte à récupérer.');
      return;
    }

    setState(() => _busy = true);

    try {
      await SupabaseService.client.auth.resetPasswordForEmail(
        email,
        redirectTo: _recoveryRedirect,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Si cette adresse possède un compte Cloud Project XP, un lien de récupération vient d’être envoyé. Ouvre-le sur cet appareil pour choisir un nouveau mot de passe.',
      );
    } on AuthException catch (_) {
      if (mounted) {
        _showMessage(
          'Impossible d’envoyer l’e-mail de récupération pour le moment. Réessaie dans un instant.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Impossible d’envoyer l’e-mail de récupération pour le moment. Vérifie ta connexion Internet.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _completePasswordRecoveryFromSession() async {
    if (_recoveryFlowBusy || !mounted) {
      return;
    }

    _recoveryFlowBusy = true;

    try {
      // Sur un retour navigateur à froid, Supabase peut finir de restaurer la
      // session quelques instants après la livraison du deep-link Android.
      User? user = SupabaseService.currentUser;

      for (int attempt = 0; attempt < 20 && user == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        user = SupabaseService.currentUser;
      }

      if (!mounted) {
        return;
      }

      if (user == null || user.isAnonymous) {
        _showMessage(
          'Le lien de récupération n’a pas pu ouvrir une session Cloud valide. Redemande un nouveau lien.',
        );
        return;
      }

      final String email = user.email?.trim().toLowerCase() ?? '';
      if (email.isEmpty) {
        await CloudSessionGuardService.signOutPermanentSession();
        if (mounted) {
          _showMessage('Le compte Cloud récupéré ne possède pas d’adresse e-mail valide.');
        }
        return;
      }

      final String? newPassword = await _askRecoveredPassword();

      if (newPassword == null || !mounted) {
        await CloudSessionGuardService.signOutPermanentSession();
        return;
      }

      setState(() => _busy = true);

      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      final CloudIdentityActionResult restored =
          await CloudIdentityService.signInCloudAndRestoreLocal(
        email: email,
        password: newPassword,
      );

      if (!mounted) {
        return;
      }

      if (!restored.success) {
        await CloudSessionGuardService.signOutPermanentSession();
        _showMessage(
          'Le mot de passe Cloud a été modifié, mais Project XP n’a pas pu restaurer le compte local. Reconnecte-toi avec le nouveau mot de passe.',
        );
        return;
      }

      // Pour un compte déjà présent sur l'appareil, la restauration Cloud
      // réactive l'ID historique mais ne remplace pas à elle seule le hash
      // Argon2id local. On aligne donc les deux mots de passe ici.
      final String localEmail =
          (await AuthService.getCurrentEmail())?.trim().toLowerCase() ?? email;

      final bool localPasswordSaved = await AuthService.setPasswordForEmail(
        email: localEmail,
        password: newPassword,
      );

      if (!localPasswordSaved) {
        await AuthService.logout();
        await CloudSessionGuardService.signOutPermanentSession();
        if (mounted) {
          _showMessage(
            'Le mot de passe Cloud a été modifié, mais sa copie locale n’a pas pu être sécurisée. Reconnecte-toi avec le nouveau mot de passe.',
          );
        }
        return;
      }

      await CloudSessionGuardService.rememberCurrentPermanentBinding();

      if (!mounted) {
        return;
      }

      _showMessage('Mot de passe réinitialisé. Ton compte Project XP est prêt.');
      await _finishAuthenticatedFlow(offerBiometrics: true);
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(
          error.message.toLowerCase().contains('same password')
              ? 'Choisis un mot de passe différent de l’ancien.'
              : 'Le nouveau mot de passe n’a pas pu être enregistré. Redemande un lien de récupération si nécessaire.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('La récupération du compte n’a pas pu être finalisée.');
      }
    } finally {
      _recoveryFlowBusy = false;
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _askRecoveredPassword() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    String password = '';
    String confirmation = '';
    bool hidePassword = true;
    bool hideConfirmation = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xff2b1a12),
              title: const Text(
                'NOUVEAU MOT DE PASSE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Le lien reçu par e-mail a validé ton identité Cloud. Choisis maintenant le nouveau mot de passe de ton compte Project XP.',
                        style: TextStyle(color: Colors.white70, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        autofocus: true,
                        obscureText: hidePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (value) => password = value,
                        validator: (value) =>
                            AuthService.validatePassword(value ?? ''),
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(
                          label: 'Nouveau mot de passe',
                          icon: Icons.lock_reset,
                          suffix: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                hidePassword = !hidePassword;
                              });
                            },
                            icon: Icon(
                              hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        obscureText: hideConfirmation,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (value) => confirmation = value,
                        validator: (value) {
                          if ((value ?? '') != password) {
                            return 'Les mots de passe ne correspondent pas.';
                          }
                          return null;
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(
                          label: 'Confirmer le mot de passe',
                          icon: Icons.verified_user_outlined,
                          suffix: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                hideConfirmation = !hideConfirmation;
                              });
                            },
                            icon: Icon(
                              hideConfirmation
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _PasswordRules(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'ANNULER',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false) ||
                        confirmation != password) {
                      return;
                    }
                    Navigator.pop(dialogContext, password);
                  },
                  child: const Text(
                    'ENREGISTRER',
                    style: TextStyle(
                      color: Color(0xffffc857),
                      fontWeight: FontWeight.bold,
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

  Future<void> _refreshBiometricState() async {
    final bool canUse =
        await BiometricAuthService.canUseBiometricLogin();

    final String? username = canUse
        ? await BiometricAuthService.getEnabledUsername()
        : null;

    if (!mounted) {
      return;
    }

    setState(() {
      _biometricLoginAvailable = canUse;
      _biometricUsername = username?.trim() ?? '';
    });
  }

  void _toggleMode() {
    if (_busy) {
      return;
    }

    setState(() {
      _registerMode = !_registerMode;
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

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    if (_registerMode && _password != _confirmPassword) {
      _showMessage('Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() => _busy = true);

    try {
      if (_registerMode) {
        await _register();
      } else {
        await _login();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _prepareNewLocalAccountSocialSession() async {
    final bool ready =
        await CloudSessionGuardService.prepareNewLocalAccountSocialSession();

    if (ready) {
      return true;
    }

    await AuthService.logout();

    if (mounted) {
      _showMessage(
        'Impossible d’ouvrir la session sociale Project XP. Réessaie dans un instant.',
      );
    }

    return false;
  }

  Future<bool> _alignCloudAfterPasswordLogin(String password) async {
    CloudSessionAlignmentResult alignment =
        await CloudSessionGuardService.alignAfterPasswordLogin(
      password: password,
    );

    if (alignment.success) {
      return true;
    }

    if (alignment.requiresLegacyDecision && mounted) {
      final bool? hadCloud = await _askLegacyCloudStatus();

      if (!mounted) {
        return false;
      }

      if (hadCloud == false) {
        final bool confirmed =
            await CloudSessionGuardService.confirmCurrentAccountLocalOnly();

        if (confirmed) {
          return true;
        }

        alignment = const CloudSessionAlignmentResult.fail(
          'Impossible de confirmer le mode local de ce compte.',
        );
      } else if (hadCloud == true) {
        final String? cloudPassword = await _askLegacyCloudPassword();

        if (!mounted) {
          return false;
        }

        if (cloudPassword == null || cloudPassword.isEmpty) {
          alignment = const CloudSessionAlignmentResult.fail(
            'La reconnexion Cloud a été annulée.',
          );
        } else {
          alignment = await CloudSessionGuardService.alignAfterPasswordLogin(
            password: cloudPassword,
            legacyDecisionOnInvalidCredentials: false,
          );

          if (alignment.success) {
            return true;
          }
        }
      } else {
        alignment = const CloudSessionAlignmentResult.fail(
          'Connexion annulée : le statut Cloud doit être confirmé avant d’ouvrir ce compte.',
        );
      }
    }

    // Le mot de passe local peut être correct alors que la session Cloud ne
    // l'est pas. Dans ce cas on reste sur l'écran de connexion : aucune tâche
    // personnelle ne doit démarrer avec une identité Supabase incertaine.
    await AuthService.logout();

    if (mounted) {
      _showMessage(alignment.message);
    }

    return false;
  }

  Future<bool?> _askLegacyCloudStatus() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: const Text(
            'STATUT CLOUD À CONFIRMER',
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Ton mot de passe Project XP local est correct, mais il ne permet pas de reconnaître ce compte côté Cloud.\n\n'
            'Avant cette mise à jour, un changement de mot de passe pouvait modifier uniquement la copie locale.\n\n'
            'Avais-tu déjà activé « Compte Cloud Project XP » pour ce compte ?',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'ANNULER',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('JAMAIS ACTIVÉ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'DÉJÀ ACTIVÉ',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _askLegacyCloudPassword() {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    String password = '';
    bool obscure = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xff2b1a12),
              title: const Text(
                'RECONNECTER LE CLOUD',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Entre le mot de passe utilisé par ton compte Cloud Project XP. Il sert uniquement à cette reconnexion et n’est pas enregistré.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      autofocus: true,
                      obscureText: obscure,
                      onChanged: (value) => password = value,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        label: 'Mot de passe Cloud',
                        icon: Icons.cloud_outlined,
                        suffix: IconButton(
                          onPressed: () {
                            setDialogState(() => obscure = !obscure);
                          },
                          icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if ((value ?? '').isEmpty) {
                          return 'Entre ton mot de passe Cloud.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'ANNULER',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) {
                      return;
                    }
                    Navigator.pop(dialogContext, password);
                  },
                  child: const Text(
                    'RECONNECTER',
                    style: TextStyle(
                      color: Color(0xffffc857),
                      fontWeight: FontWeight.bold,
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

  Future<void> _register() async {
    final AuthRegisterResult result = await AuthService.register(
      username: _username,
      email: _email,
      password: _password,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthRegisterResult.success:
        if (!await _prepareNewLocalAccountSocialSession() || !mounted) {
          return;
        }
        await _finishAuthenticatedFlow(offerBiometrics: true);
        return;

      case AuthRegisterResult.emailAlreadyUsed:
        _showMessage('Cette adresse e-mail est déjà utilisée.');
        return;

      case AuthRegisterResult.usernameAlreadyUsed:
        _showMessage('Ce pseudo est déjà utilisé.');
        return;

      case AuthRegisterResult.weakPassword:
        _showMessage(
          AuthService.validatePassword(_password) ??
              'Ce mot de passe ne respecte pas les règles de sécurité.',
        );
        return;

      case AuthRegisterResult.invalidData:
        _showMessage('Vérifie le pseudo et l’adresse e-mail.');
        return;
    }
  }

  Future<void> _login() async {
    final AuthLoginResult result = await AuthService.login(
      email: _email,
      password: _password,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case AuthLoginResult.success:
        if (!await _alignCloudAfterPasswordLogin(_password) || !mounted) {
          return;
        }
        await _finishAuthenticatedFlow(offerBiometrics: true);
        return;

      case AuthLoginResult.invalidCredentials:
        _showMessage('Adresse e-mail ou mot de passe incorrect.');
        return;

      case AuthLoginResult.passwordSetupRequired:
        await _upgradeLegacyAccount();
        return;
    }
  }

  Future<void> _upgradeLegacyAccount() async {
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: const Text(
            'SÉCURISER TON ANCIEN COMPTE',
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Ce compte a été créé avant l’ajout de la vraie vérification des mots de passe. '
            'L’ancien mot de passe n’a jamais été enregistré, il est donc impossible de le récupérer ou de le vérifier.\n\n'
            'Project XP va te demander de confirmer le propriétaire de cet appareil, puis de définir un nouveau mot de passe sécurisé.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'ANNULER',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'CONTINUER',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (accepted != true || !mounted) {
      return;
    }

    final bool deviceAuthAvailable =
        await BiometricAuthService.isDeviceAuthenticationAvailable();

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
        await BiometricAuthService.authenticateDeviceOwner();

    if (!mounted) {
      return;
    }

    if (!deviceOwnerConfirmed) {
      _showMessage('Confirmation de l’appareil annulée.');
      return;
    }

    final String? newPassword = await _askForNewPassword();

    if (newPassword == null || !mounted) {
      return;
    }

    final bool passwordSaved = await AuthService.setPasswordForEmail(
      email: _email,
      password: newPassword,
    );

    if (!mounted) {
      return;
    }

    if (!passwordSaved) {
      _showMessage('Impossible d’enregistrer le nouveau mot de passe.');
      return;
    }

    final AuthLoginResult result = await AuthService.login(
      email: _email,
      password: newPassword,
    );

    if (!mounted) {
      return;
    }

    if (result != AuthLoginResult.success) {
      _showMessage('Le compte a été sécurisé, mais la reconnexion a échoué.');
      return;
    }

    _password = newPassword;

    if (!await _alignCloudAfterPasswordLogin(newPassword) || !mounted) {
      return;
    }

    _showMessage(
      'Ton ancien compte est maintenant protégé par un vrai mot de passe.',
    );

    await _finishAuthenticatedFlow(offerBiometrics: true);
  }

  Future<String?> _askForNewPassword() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    String password = '';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: const Text(
            'NOUVEAU MOT DE PASSE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    obscureText: true,
                    onChanged: (value) => password = value,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      labelStyle: TextStyle(color: Color(0xffffc857)),
                    ),
                    validator: (value) =>
                        AuthService.validatePassword(value ?? ''),
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      labelStyle: TextStyle(color: Color(0xffffc857)),
                    ),
                    validator: (value) {
                      if ((value ?? '') != password) {
                        return 'Les mots de passe ne correspondent pas.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  const _PasswordRules(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'ANNULER',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                Navigator.pop(dialogContext, password);
              },
              child: const Text(
                'SÉCURISER',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
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

    final String? userId = await AuthService.getCurrentUserId();

    if (userId == null || userId.trim().isEmpty) {
      _showMessage('Impossible de charger le compte.');
      return;
    }

    final bool hasAvatar = await AvatarStorage.hasAvatar(userId);

    if (!mounted) {
      return;
    }

    final Widget destination =
        hasAvatar ? const HallScreen() : const AvatarChoiceScreen();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (context) => destination),
      (route) => false,
    );
  }

  Future<void> _offerBiometricActivation() async {
    final bool available = await BiometricAuthService.isBiometricAvailable();

    if (!available || !mounted) {
      return;
    }

    final String? currentUserId = await AuthService.getCurrentUserId();
    final String? enabledUserId = await BiometricAuthService.getEnabledUserId();

    if (!mounted || currentUserId == null || enabledUserId == currentUserId) {
      return;
    }

    final bool? activate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff2b1a12),
          title: const Text(
            'CONNEXION BIOMÉTRIQUE',
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Veux-tu utiliser ton empreinte ou la reconnaissance faciale pour tes prochaines connexions sur cet appareil ?\n\n'
            'Ton mot de passe reste obligatoire comme méthode principale et n’est jamais stocké en clair. '
            'Après une déconnexion complète d’un compte Cloud, le mot de passe sera de nouveau demandé pour rouvrir le Cloud.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'PLUS TARD',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'ACTIVER',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (activate != true || !mounted) {
      return;
    }

    final bool enabled =
        await BiometricAuthService.enableForCurrentAccount();

    if (!mounted) {
      return;
    }

    if (enabled) {
      _showMessage('Connexion biométrique activée.');
      await _refreshBiometricState();
    } else {
      _showMessage('La biométrie n’a pas pu être activée.');
    }
  }

  Future<void> _openAlternativeLoginMethods() async {
    if (_busy || !_biometricLoginAvailable || !mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff21150e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.key_outlined,
                      color: Color(0xffffc857),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AUTRE MÉTHODE DE CONNEXION',
                        style: TextStyle(
                          color: Color(0xffffc857),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(Future<void>.microtask(_loginWithBiometrics));
                    },
                    icon: const Icon(Icons.fingerprint),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BIOMÉTRIE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _biometricUsername.isNotEmpty
                                ? 'Empreinte ou visage • $_biometricUsername'
                                : 'Empreinte ou reconnaissance faciale',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xffffc857),
                      side: const BorderSide(color: Color(0xffffc857)),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    unawaited(Future<void>.microtask(_disableBiometrics));
                  },
                  child: const Text(
                    'Désactiver la connexion biométrique',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loginWithBiometrics() async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);

    try {
      final String? userId = await BiometricAuthService.getEnabledUserId();

      if (userId == null) {
        _showMessage('Aucun compte biométrique configuré.');
        return;
      }

      final bool authenticated =
          await BiometricAuthService.authenticateBiometricOnly(
        reason: 'Authentifie-toi pour te connecter à Project XP.',
      );

      if (!authenticated || !mounted) {
        return;
      }

      final bool activated = await AuthService.activateLocalAccountById(userId);

      if (!activated || !mounted) {
        _showMessage('Impossible de réactiver ce compte.');
        return;
      }

      // La biométrie réouvre le même compte lorsque Project XP a été verrouillé
      // localement. La session Cloud reste alors présente et le garde vérifie
      // qu'elle correspond exactement au même ID Project XP.
      final bool aligned =
          await CloudSessionGuardService.ensureAlignedSessionWithoutPassword();

      if (!aligned || !mounted) {
        final CloudLocalAccountKind accountKind =
            await CloudSessionGuardService.currentLocalAccountKind();

        await AuthService.logout();

        if (!mounted) {
          return;
        }

        _showMessage(
          accountKind == CloudLocalAccountKind.cloud
              ? 'Ce compte a été déconnecté complètement du Cloud. Utilise « Mot de passe oublié ? » si tu ne connais plus ton mot de passe.'
              : 'Sécurité Cloud : entre ton mot de passe une fois pour vérifier ce compte avant de réutiliser la biométrie.',
        );
        return;
      }

      await _finishAuthenticatedFlow(offerBiometrics: false);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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

    _showMessage('Connexion biométrique désactivée.');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateEmail(String? value) {
    final String email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Entre ton adresse e-mail.';
    }

    if (!email.contains('@') || !email.contains('.')) {
      return 'Adresse e-mail invalide.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff160e09),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 35, 22, 35),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Image.asset(
                    'assets/icon/app_icon.png',
                    width: 210,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text(
                        'PROJECT XP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xffffc857),
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 25),
                  Text(
                    _registerMode
                        ? 'CRÉER TON COMPTE'
                        : 'RETOUR À L’AVENTURE',
                    style: const TextStyle(
                      color: Color(0xffffc857),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _registerMode
                        ? 'Ton identité Project XP commence ici.'
                        : 'Connecte-toi à ton compte Project XP.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 25),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xff21150e),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xffffc857),
                        width: 1.5,
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        key: ValueKey(
                          'auth-form-$_formVersion-$_registerMode',
                        ),
                        children: [
                          if (_registerMode) ...[
                            TextFormField(
                              key: ValueKey('username-$_formVersion'),
                              enabled: !_busy,
                              textInputAction: TextInputAction.next,
                              onChanged: (value) => _username = value,
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Choisis un pseudo.';
                                }
                                return null;
                              },
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration(
                                label: 'Pseudo',
                                icon: Icons.person_outline,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            key: ValueKey('email-$_formVersion'),
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            onChanged: (value) => _email = value,
                            validator: _validateEmail,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              label: 'E-mail',
                              icon: Icons.mail_outline,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: ValueKey('password-$_formVersion'),
                            enabled: !_busy,
                            obscureText: _obscurePassword,
                            textInputAction: _registerMode
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!_registerMode) {
                                _submit();
                              }
                            },
                            onChanged: (value) => _password = value,
                            validator: (value) {
                              final String password = value ?? '';
                              if (password.isEmpty) {
                                return 'Entre ton mot de passe.';
                              }
                              if (_registerMode) {
                                return AuthService.validatePassword(password);
                              }
                              return null;
                            },
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              label: 'Mot de passe',
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        setState(() {
                                          _obscurePassword =
                                              !_obscurePassword;
                                        });
                                      },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          ),
                          if (_registerMode) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              key: ValueKey('confirm-$_formVersion'),
                              enabled: !_busy,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              onChanged: (value) => _confirmPassword = value,
                              validator: (value) {
                                if ((value ?? '').isEmpty) {
                                  return 'Confirme ton mot de passe.';
                                }
                                if ((value ?? '') != _password) {
                                  return 'Les mots de passe ne correspondent pas.';
                                }
                                return null;
                              },
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration(
                                label: 'Confirmer le mot de passe',
                                icon: Icons.lock_reset,
                                suffix: IconButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          setState(() {
                                            _obscureConfirm =
                                                !_obscureConfirm;
                                          });
                                        },
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            const _PasswordRules(),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xffffc857),
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_registerMode) ...[
                    const SizedBox(height: 7),
                    TextButton.icon(
                      onPressed: _busy ? null : _requestPasswordReset,
                      icon: const Icon(Icons.lock_reset_rounded, size: 18),
                      label: const Text(
                        'MOT DE PASSE OUBLIÉ ?',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xffffc857),
                      ),
                    ),
                    const Text(
                      'Disponible pour les comptes Cloud Project XP.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                  if (!_registerMode && _biometricLoginAvailable) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _busy ? null : _openAlternativeLoginMethods,
                      icon: const Icon(Icons.key_outlined, size: 19),
                      label: const Text(
                        'AUTRE MÉTHODE DE CONNEXION',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xffffc857),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _toggleMode,
                    child: Text(
                      _registerMode
                          ? 'J’ai déjà un compte'
                          : 'Créer un nouveau compte',
                      style: const TextStyle(
                        color: Color(0xffffc857),
                        fontWeight: FontWeight.w600,
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
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: const Color(0xffffc857)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xff160e09),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xffffc857),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.5,
        ),
      ),
    );
  }
}

class _PasswordRules extends StatelessWidget {
  const _PasswordRules();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff160e09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ton mot de passe doit contenir :',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 7),
          Text(
            '• au moins 10 caractères\n'
            '• au moins une lettre\n'
            '• au moins un chiffre\n'
            '• au moins un caractère spécial',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
