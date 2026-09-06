import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/gaming_accounts_service.dart';
import '../services/playstation_sync_service.dart';
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

  Future<void> _connectPlayStation() async {
    if (_busy) {
      return;
    }

    final _PlayStationCredentials? credentials =
        await _askPlayStationCredentials();

    if (credentials == null || !mounted) {
      return;
    }

    setState(() => _busy = true);

    try {
      final GamingAccountLink account =
          await GamingAccountsService.linkPlayStation(
        onlineId: credentials.onlineId,
        npsso: credentials.npsso,
      );

      await _load();

      if (!mounted) {
        return;
      }

      _message(
        'PlayStation lié à ${account.displayName.isEmpty ? credentials.onlineId : account.displayName}. '
        'Import de la bibliothèque en cours…',
      );

      try {
        final PlayStationSyncResult result =
            await PlayStationSyncService.syncEverything();

        if (mounted) {
          _message(_playStationSyncMessage(result));
        }
      } on PlayStationSyncException catch (error) {
        if (mounted) {
          _message(
            'Compte PlayStation lié, mais la première synchro a échoué : '
            '${error.message}',
          );
        }
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

  Future<void> _syncPlayStation() async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);

    try {
      final PlayStationSyncResult result =
          await PlayStationSyncService.syncEverything();

      if (mounted) {
        _message(_playStationSyncMessage(result));
      }
    } on PlayStationSyncException catch (error) {
      if (mounted) {
        _message(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _unlinkPlayStation() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xff1b1e22),
            title: const Text(
              'Délier PlayStation ?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Tes jeux et trophées déjà enregistrés restent dans Project XP. '
              'Le jeton de synchronisation PlayStation chiffré sera supprimé.',
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
      await GamingAccountsService.unlink(
        GamingPlatformProvider.playstation,
      );
      await _load();

      if (mounted) {
        _message('PlayStation a été délié de ton compte Project XP.');
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

  Future<_PlayStationCredentials?> _askPlayStationCredentials() async {
    final TextEditingController onlineIdController =
        TextEditingController();
    final TextEditingController npssoController =
        TextEditingController();
    bool hideNpsso = true;

    final _PlayStationCredentials? result =
        await showDialog<_PlayStationCredentials>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> openTokenPage() async {
              try {
                await GamingAccountsService.openPlayStationTokenPage();
              } on GamingAccountsException catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.message)),
                  );
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xff15181b),
              title: const Row(
                children: [
                  Icon(
                    Icons.gamepad_rounded,
                    color: Color(0xff6aa9ff),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'LIER PLAYSTATION',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sony ne propose pas de connexion développeur publique '
                      'équivalente à Steam. Project XP utilise donc le jeton '
                      'de session NPSSO pour créer une liaison sécurisée.',
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xff202832),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xff6aa9ff)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        'Le NPSSO n’est jamais conservé. Il est envoyé au '
                        'serveur Project XP, échangé contre un jeton de '
                        'renouvellement puis immédiatement abandonné. '
                        'Le jeton conservé est chiffré et inaccessible à l’app.',
                        style: TextStyle(
                          color: Color(0xffb9d7ff),
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: onlineIdController,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Identifiant en ligne PSN',
                        hintText: 'Ton pseudo PlayStation',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: npssoController,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: hideNpsso,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Jeton NPSSO / JSON PlayStation',
                        hintText: 'Colle le jeton ou le JSON complet',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() {
                              hideNpsso = !hideNpsso;
                            });
                          },
                          icon: Icon(
                            hideNpsso
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: openTokenPage,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text(
                        'OUVRIR LA PAGE DU JETON PLAYSTATION',
                      ),
                    ),
                    const Text(
                      'Connecte-toi d’abord à PlayStation dans ce navigateur. '
                      'La page affiche ensuite un JSON contenant "npsso". '
                      'Tu peux maintenant coller le JSON complet : Project XP '
                      'extrait automatiquement le jeton.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('ANNULER'),
                ),
                FilledButton(
                  onPressed: () {
                    final String onlineId =
                        onlineIdController.text.trim();
                    final String npsso = _normalizeNpssoInput(
                      npssoController.text,
                    );

                    if (onlineId.length < 3 || npsso.length < 32) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Renseigne ton identifiant PSN et un NPSSO valide.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _PlayStationCredentials(
                        onlineId: onlineId,
                        npsso: npsso,
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff315c83),
                  ),
                  child: const Text('LIER'),
                ),
              ],
            );
          },
        );
      },
    );

    onlineIdController.dispose();
    npssoController.dispose();

    return result;
  }

  String _playStationSyncMessage(PlayStationSyncResult result) {
    final List<String> details = <String>[
      if (result.added > 0) '${result.added} ajoutés',
      if (result.updated > 0) '${result.updated} actualisés',
      if (result.unchanged > 0) '${result.unchanged} déjà à jour',
    ];

    return details.isEmpty
        ? 'PlayStation est déjà à jour.'
        : 'PlayStation synchronisé : ${details.join(', ')}.';
  }

  String _normalizeNpssoInput(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return '';
    }

    if (value.startsWith('{')) {
      try {
        final dynamic decoded = jsonDecode(value);
        if (decoded is Map) {
          final String token = decoded['npsso']?.toString().trim() ?? '';
          if (token.isNotEmpty) {
            return token;
          }
        }
      } catch (_) {
        // On essaie ensuite le format texte brut / partiel.
      }
    }

    final int marker = value.toLowerCase().indexOf('npsso');
    if (marker >= 0) {
      final String tail = value.substring(marker + 'npsso'.length);
      final String token = tail
          .replaceFirst(RegExp(r'^[^a-zA-Z0-9]+'), '')
          .split(RegExp(r'[^a-zA-Z0-9_-]+'))
          .first
          .trim();
      if (token.length >= 32) {
        return token;
      }
    }

    return value
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();
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
    final GamingAccountLink? playStation =
        _account(GamingPlatformProvider.playstation);

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
                _PlatformAccountCard(
                  provider: GamingPlatformProvider.playstation,
                  account: playStation,
                  busy: _busy,
                  available: true,
                  onConnect: _connectPlayStation,
                  onUnlink: _unlinkPlayStation,
                  onSync: _syncPlayStation,
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

class _PlayStationCredentials {
  final String onlineId;
  final String npsso;

  const _PlayStationCredentials({
    required this.onlineId,
    required this.npsso,
  });
}

class _PlatformAccountCard extends StatelessWidget {
  final GamingPlatformProvider provider;
  final GamingAccountLink? account;
  final bool busy;
  final bool legacyDetected;
  final bool available;
  final VoidCallback? onConnect;
  final VoidCallback? onUnlink;
  final VoidCallback? onSync;

  const _PlatformAccountCard({
    required this.provider,
    this.account,
    this.busy = false,
    this.legacyDetected = false,
    required this.available,
    this.onConnect,
    this.onUnlink,
    this.onSync,
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
          : provider == GamingPlatformProvider.playstation
          ? '$name • jeux + trophées'
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
          if (linked) ...[
            if (onSync != null)
              IconButton(
                tooltip: 'Synchroniser',
                onPressed: busy ? null : onSync,
                icon: busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            TextButton(
              onPressed: busy ? null : onUnlink,
              child: const Text('DÉLIER'),
            ),
          ] else if (available)
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
