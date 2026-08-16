import 'package:flutter/material.dart';

import 'package:project_xp/screens/profile_screen.dart';
import 'package:project_xp/screens/splash_screen.dart';
import 'package:project_xp/services/app_notification_service.dart';
import 'package:project_xp/services/auth_service.dart';
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
  // COMPTE
  // ==========================================================================

  void _openAccount() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          const Color(0xff21150e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
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
                  title: 'COMPTE',
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
                          'COMPTE',
                      subtitle:
                          'Informations du compte et déconnexion',
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
  final ValueChanged<bool> onChanged;

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
