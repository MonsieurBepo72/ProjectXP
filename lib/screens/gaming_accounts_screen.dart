import 'package:flutter/material.dart';

import '../services/gaming_accounts_service.dart';
import '../services/steam_sync_service.dart';

class GamingAccountsScreen extends StatefulWidget {
  const GamingAccountsScreen({super.key});

  @override
  State<GamingAccountsScreen> createState() =>
      _GamingAccountsScreenState();
}

class _GamingAccountsScreenState extends State<GamingAccountsScreen> {
  bool _loading = true;
  bool _busy = false;
  List<GamingAccountLink> _accounts = <GamingAccountLink>[];
  String? _legacySteamId;

  @override
  void initState() {
    super.initState();
    GamingAccountsService.revision.addListener(_onRevision);
    GamingAccountsService.lastCallbackMessage.addListener(
      _onCallbackMessage,
    );
    _load();
  }

  @override
  void dispose() {
    GamingAccountsService.revision.removeListener(_onRevision);
    GamingAccountsService.lastCallbackMessage.removeListener(
      _onCallbackMessage,
    );
    super.dispose();
  }

  void _onRevision() {
    _load();
  }

  void _onCallbackMessage() {
    final String message =
        GamingAccountsService.lastCallbackMessage.value?.trim() ?? '';
    if (message.isEmpty || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    GamingAccountsService.lastCallbackMessage.value = null;
  }

  Future<void> _load() async {
    final List<GamingAccountLink> accounts =
        await GamingAccountsService.loadAccounts();
    final String legacySteamId =
        (await SteamSyncService.getLegacySavedSteamId() ?? '').trim();

    if (!mounted) {
      return;
    }

    setState(() {
      _accounts = accounts;
      _legacySteamId = legacySteamId.isEmpty ? null : legacySteamId;
      _loading = false;
    });
  }

  GamingAccountLink? _account(GamingPlatformProvider provider) {
    for (final GamingAccountLink account in _accounts) {
      if (account.provider == provider) {
        return account;
      }
    }
    return null;
  }

  Future<void> _connectSteam() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);

    try {
      await GamingAccountsService.startSteamLink();
      if (mounted) {
        _message(
          'Steam s’est ouvert. Connecte-toi sur Steam puis reviens dans Project XP.',
        );
      }
    } on GamingAccountsException catch (error) {
      if (mounted) {
        _message(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _unlinkSteam() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xff1b1e22),
            title: const Text(
              'Délier Steam ?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Tes jeux et succès déjà enregistrés restent dans Project XP. '
              'La synchronisation automatique Steam s’arrêtera jusqu’à une nouvelle connexion.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('ANNULER'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  'DÉLIER',
                  style: TextStyle(color: Color(0xffff9a9a)),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await GamingAccountsService.unlink(GamingPlatformProvider.steam);
      await SteamSyncService.clearSavedIdentity();
      await _load();
      if (mounted) {
        _message('Steam a été délié de ton compte Project XP.');
      }
    } on GamingAccountsException catch (error) {
      if (mounted) {
        _message(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GamingAccountLink? steam =
        _account(GamingPlatformProvider.steam);

    return Scaffold(
      backgroundColor: const Color(0xff0d0f11),
      appBar: AppBar(
        backgroundColor: const Color(0xff15181b),
        foregroundColor: Colors.white,
        title: const Text('COMPTES DE JEU'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: [
                const Text(
                  'Lie une plateforme une seule fois. Project XP peut ensuite '
                  'actualiser ta bibliothèque et tes accomplissements automatiquement, '
                  'quand la plateforme le permet.',
                  style: TextStyle(
                    color: Colors.white60,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _PlatformAccountCard(
                  provider: GamingPlatformProvider.steam,
                  account: steam,
                  busy: _busy,
                  legacyDetected:
                      steam == null && _legacySteamId != null,
                  available: true,
                  onConnect: _connectSteam,
                  onUnlink: _unlinkSteam,
                ),
                const SizedBox(height: 10),
                const _PlatformAccountCard(
                  provider: GamingPlatformProvider.playstation,
                  available: false,
                ),
                const SizedBox(height: 10),
                const _PlatformAccountCard(
                  provider: GamingPlatformProvider.xbox,
                  available: false,
                ),
                const SizedBox(height: 10),
                const _PlatformAccountCard(
                  provider: GamingPlatformProvider.nintendo,
                  available: false,
                ),
                const SizedBox(height: 10),
                const _PlatformAccountCard(
                  provider: GamingPlatformProvider.epic,
                  available: false,
                ),
              ],
            ),
    );
  }
}

class _PlatformAccountCard extends StatelessWidget {
  final GamingPlatformProvider provider;
  final GamingAccountLink? account;
  final bool busy;
  final bool legacyDetected;
  final bool available;
  final VoidCallback? onConnect;
  final VoidCallback? onUnlink;

  const _PlatformAccountCard({
    required this.provider,
    this.account,
    this.busy = false,
    this.legacyDetected = false,
    required this.available,
    this.onConnect,
    this.onUnlink,
  });

  IconData get _icon {
    switch (provider) {
      case GamingPlatformProvider.steam:
        return Icons.sports_esports_rounded;
      case GamingPlatformProvider.playstation:
        return Icons.gamepad_rounded;
      case GamingPlatformProvider.xbox:
        return Icons.videogame_asset_rounded;
      case GamingPlatformProvider.nintendo:
        return Icons.gamepad_outlined;
      case GamingPlatformProvider.epic:
        return Icons.storefront_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool linked = account != null;
    final String subtitle;

    if (linked) {
      final String name = account!.displayName.trim();
      subtitle = name.isEmpty
          ? 'Compte lié • ${account!.providerUserId}'
          : '$name • compte lié';
    } else if (legacyDetected) {
      subtitle =
          'Ancienne liaison locale détectée. Reconnecte Steam une fois pour sécuriser le lien.';
    } else if (!available) {
      subtitle = 'Connexion officielle à venir.';
    } else {
      subtitle = 'Non lié';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff181b1f),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: linked
              ? const Color(0xff315c83)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          _AvatarOrIcon(
            icon: _icon,
            avatarUrl: account?.avatarUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      provider.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (linked) ...[
                      const SizedBox(width: 7),
                      const Icon(
                        Icons.verified_rounded,
                        color: Color(0xff74d99f),
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: legacyDetected
                        ? const Color(0xffffcf73)
                        : Colors.white54,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (linked)
            TextButton(
              onPressed: busy ? null : onUnlink,
              child: const Text('DÉLIER'),
            )
          else if (available)
            FilledButton(
              onPressed: busy ? null : onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff315c83),
              ),
              child: const Text('CONNECTER'),
            )
          else
            const Icon(
              Icons.lock_clock_rounded,
              color: Colors.white24,
              size: 20,
            ),
        ],
      ),
    );
  }
}

class _AvatarOrIcon extends StatelessWidget {
  final IconData icon;
  final String? avatarUrl;

  const _AvatarOrIcon({
    required this.icon,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final String url = avatarUrl?.trim() ?? '';

    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.network(
          url,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => _iconBox(),
        ),
      );
    }

    return _iconBox();
  }

  Widget _iconBox() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xff252a30),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white70),
    );
  }
}
