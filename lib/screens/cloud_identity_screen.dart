import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/cloud_identity_service.dart';

enum _CloudActivationFlow {
  none,
  currentPassword,
  forgottenPassword,
}

class CloudIdentityScreen extends StatefulWidget {
  const CloudIdentityScreen({super.key});

  @override
  State<CloudIdentityScreen> createState() =>
      _CloudIdentityScreenState();
}

class _CloudIdentityScreenState extends State<CloudIdentityScreen> {
  CloudIdentityStatus? _status;

  bool _loading = true;
  bool _busy = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  String _email = '';
  String _username = '';
  String _pendingPassword = '';

  _CloudActivationFlow _flow = _CloudActivationFlow.none;

  final TextEditingController _codeController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool get _codeSent => _flow != _CloudActivationFlow.none;
  bool get _forgottenPasswordFlow =>
      _flow == _CloudActivationFlow.forgottenPassword;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? email = await AuthService.getCurrentEmail();
    final String? username = await AuthService.getCurrentUsername();
    final CloudIdentityStatus status =
        await CloudIdentityService.loadStatus();

    if (!mounted) {
      return;
    }

    setState(() {
      _email = email?.trim() ?? '';
      _username = username?.trim().isNotEmpty == true
          ? username!.trim()
          : 'Aventurier';
      _status = status;
      _loading = false;
    });
  }

  Future<String?> _askPassword() {
    String value = '';
    bool obscure = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xff17121f),
              title: const Text(
                'CONFIRMER TON COMPTE',
                style: TextStyle(
                  color: Color(0xffffc857),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Entre ton mot de passe Project XP actuel. Il est vérifié localement avant la conversion Cloud.',
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    obscureText: obscure,
                    onChanged: (text) {
                      value = text;
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setDialogState(() {
                            obscure = !obscure;
                          });
                        },
                        icon: Icon(
                          obscure
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('ANNULER'),
                ),
                TextButton(
                  onPressed: () {
                    if (value.isEmpty) {
                      return;
                    }
                    Navigator.pop(dialogContext, value);
                  },
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
      },
    );
  }

  Future<void> _beginUpgrade() async {
    final String? password = await _askPassword();

    if (password == null || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    final CloudIdentityActionResult result =
        await CloudIdentityService.beginUpgrade(
      currentPassword: password,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _busy = false;
      if (result.success) {
        _pendingPassword = password;
        _flow = _CloudActivationFlow.currentPassword;
        _codeController.clear();
      }
    });

    _message(result.message);
  }

  Future<void> _beginForgottenPassword() async {
    if (_email.isEmpty) {
      _message(
        'Aucune adresse e-mail n’est associée à ce compte Project XP.',
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff17121f),
          title: const Text(
            'MOT DE PASSE OUBLIÉ',
            style: TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'On va envoyer un code à $_email. Ce code prouvera que tu contrôles bien l’adresse du compte avant de te laisser choisir un nouveau mot de passe.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('ANNULER'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                'ENVOYER LE CODE',
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

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    final CloudIdentityActionResult result =
        await CloudIdentityService.beginForgottenPasswordUpgrade();

    if (!mounted) {
      return;
    }

    setState(() {
      _busy = false;
      if (result.success) {
        _pendingPassword = '';
        _flow = _CloudActivationFlow.forgottenPassword;
        _codeController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
    });

    _message(result.message);
  }

  Future<void> _completeUpgrade() async {
    final String code = _codeController.text.trim();

    if (code.length != 6 && code.length != 8) {
      _message('Entre le code reçu par e-mail.');
      return;
    }

    CloudIdentityActionResult result;

    if (_forgottenPasswordFlow) {
      final String newPassword = _newPasswordController.text;
      final String confirmation = _confirmPasswordController.text;

      final String? passwordError =
          AuthService.validatePassword(newPassword);

      if (passwordError != null) {
        _message(passwordError);
        return;
      }

      if (newPassword != confirmation) {
        _message('Les deux mots de passe ne correspondent pas.');
        return;
      }

      setState(() {
        _busy = true;
      });

      result =
          await CloudIdentityService.completeForgottenPasswordUpgrade(
        otp: code,
        newPassword: newPassword,
      );
    } else {
      if (_pendingPassword.isEmpty) {
        _message('Relance l’activation du compte Cloud.');
        return;
      }

      setState(() {
        _busy = true;
      });

      result = await CloudIdentityService.completeUpgrade(
        otp: code,
        password: _pendingPassword,
      );
    }

    if (!mounted) {
      return;
    }

    if (result.success) {
      _resetFlow();
      setState(() {
        _busy = false;
      });
      await _load();
    } else {
      setState(() {
        _busy = false;
      });
    }

    if (!mounted) {
      return;
    }

    _message(result.message);
  }

  void _resetFlow() {
    _pendingPassword = '';
    _flow = _CloudActivationFlow.none;
    _codeController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  void _cancelFlow() {
    if (_busy) {
      return;
    }

    setState(() {
      _resetFlow();
    });
  }

  void _message(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility : Icons.visibility_off,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CloudIdentityStatus? status = _status;

    return Scaffold(
      backgroundColor: const Color(0xff0c0b12),
      appBar: AppBar(
        backgroundColor: const Color(0xff11101a),
        title: const Text(
          'COMPTE CLOUD',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xff7b5cff).withValues(alpha: 0.45),
                    ),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xff171429),
                        Color(0xff101019),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xff7b5cff)
                                  .withValues(alpha: 0.16),
                            ),
                            child: const Icon(
                              Icons.cloud_done_outlined,
                              color: Color(0xffb8a8ff),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _username,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _email,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _StatusPill(
                        permanent: status?.isPermanent == true,
                        mappingReady: status?.mappingReady == true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (status?.isPermanent == true) ...[
                  const _InfoCard(
                    icon: Icons.verified_user,
                    title: 'Compte Cloud actif',
                    text:
                        'Ton identité Project XP est maintenant récupérable sur d’autres appareils. Les futures connexions Steam, Xbox et autres plateformes pourront être liées à ce compte.',
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.fingerprint,
                    title: 'ID Project XP',
                    text: status?.projectXpUserId ??
                        'Synchronisation du mapping en attente.',
                  ),
                  const SizedBox(height: 12),
                  const _InfoCard(
                    icon: Icons.sync,
                    title: 'Prochaine étape',
                    text:
                        'Brancher cet identifiant Cloud à la Bibliothèque puis au bouton Connecter Steam.',
                  ),
                ] else ...[
                  const _InfoCard(
                    icon: Icons.phone_android,
                    title: 'Aujourd’hui',
                    text:
                        'Ton compte Project XP est encore principalement local. Ton identité sociale Supabase existe déjà, mais elle est anonyme et liée à cet appareil.',
                  ),
                  const SizedBox(height: 12),
                  const _InfoCard(
                    icon: Icons.cloud_outlined,
                    title: 'Après activation',
                    text:
                        'On transforme cette même identité Supabase en compte permanent : pas de nouvel UID social, donc on évite de casser la Taverne, les amis et la Compagnie.',
                  ),
                  const SizedBox(height: 18),
                  if (!_codeSent) ...[
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _beginUpgrade,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          _busy
                              ? 'PRÉPARATION...'
                              : 'ACTIVER MON COMPTE CLOUD',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff6c4dff),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    TextButton.icon(
                      onPressed: _busy ? null : _beginForgottenPassword,
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text(
                        'MOT DE PASSE OUBLIÉ ?',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  if (_codeSent) _buildVerificationCard(),
                  const SizedBox(height: 18),
                  const _InfoCard(
                    icon: Icons.lock_outline,
                    title: 'Sécurité',
                    text:
                        'Si tu connais ton mot de passe, il est vérifié localement. Si tu l’as oublié, Project XP exige d’abord le code reçu sur l’adresse e-mail du compte avant d’autoriser un nouveau mot de passe. L’ancien mot de passe n’est jamais récupéré ni affiché.',
                  ),
                ],
                if (status?.error != null) ...[
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.warning_amber,
                    title: 'Information technique',
                    text: status!.error!,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildVerificationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff15131d),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xffffc857).withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _forgottenPasswordFlow
                ? 'RÉINITIALISATION SÉCURISÉE'
                : 'VÉRIFICATION E-MAIL',
            style: const TextStyle(
              color: Color(0xffffc857),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _forgottenPasswordFlow
                ? 'Entre le code envoyé à $_email, puis choisis ton nouveau mot de passe.'
                : 'Entre le code envoyé à $_email.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 7,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '00000000',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (_forgottenPasswordFlow) ...[
            const SizedBox(height: 12),
            _passwordField(
              controller: _newPasswordController,
              label: 'Nouveau mot de passe',
              obscure: _obscureNewPassword,
              onToggle: () {
                setState(() {
                  _obscureNewPassword = !_obscureNewPassword;
                });
              },
            ),
            const SizedBox(height: 10),
            _passwordField(
              controller: _confirmPasswordController,
              label: 'Confirmer le mot de passe',
              obscure: _obscureConfirmPassword,
              onToggle: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
            ),
            const SizedBox(height: 9),
            const Text(
              'Minimum 10 caractères, avec au moins une lettre, un chiffre et un caractère spécial.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _busy ? null : _completeUpgrade,
              child: Text(
                _busy
                    ? 'VÉRIFICATION...'
                    : _forgottenPasswordFlow
                        ? 'RÉINITIALISER ET ACTIVER'
                        : 'VALIDER LE CODE',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : _cancelFlow,
            child: const Text('ANNULER'),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool permanent;
  final bool mappingReady;

  const _StatusPill({
    required this.permanent,
    required this.mappingReady,
  });

  @override
  Widget build(BuildContext context) {
    final String label;

    if (permanent && mappingReady) {
      label = '● COMPTE CLOUD ACTIF';
    } else if (permanent) {
      label = '● CLOUD ACTIF • MAPPING EN ATTENTE';
    } else {
      label = '○ COMPTE LOCAL / ANONYME';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: permanent
            ? const Color(0xff2e7d32).withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.06),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: permanent
              ? const Color(0xff8fe69a)
              : Colors.white60,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff15131d),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xffb8a8ff),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white60,
                    height: 1.4,
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
