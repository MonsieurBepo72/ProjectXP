import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../services/avatar_storage.dart';
import '../services/profile_storage.dart';
import '../widgets/avatar_renderer.dart';
import '../widgets/brand_icon.dart';

class PublicProfileScreen
    extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState
    extends State<PublicProfileScreen> {
  bool _loading = true;

  Map<String, dynamic> _profile =
      <String, dynamic>{};

  AvatarModel? _avatar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Map<String, dynamic> profile =
        await ProfileStorage
            .loadProfileForUser(
      widget.userId,
    );

    final AvatarModel? avatar =
        await AvatarStorage.loadAvatar(
      widget.userId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _profile = profile;
      _avatar = avatar;
      _loading = false;
    });
  }

  String get _pseudo {
    final String value =
        _profile['pseudo']
                ?.toString()
                .trim() ??
            '';

    return value.isEmpty
        ? 'Joueur'
        : value;
  }

  String get _description {
    final String value =
        _profile['description']
                ?.toString()
                .trim() ??
            '';

    return value.isEmpty
        ? 'Aucune description.'
        : value;
  }

  List<String> get _games {
    final dynamic raw =
        _profile['games'];

    if (raw is! List) {
      return <String>[];
    }

    return raw
        .map(
          (item) =>
              item.toString().trim(),
        )
        .where(
          (item) => item.isNotEmpty,
        )
        .toList();
  }

  List<Map<String, String>>
      get _platforms {
    final dynamic raw =
        _profile['platforms'];

    if (raw is! List) {
      return <Map<String, String>>[];
    }

    final List<Map<String, String>> result =
        <Map<String, String>>[];

    for (final dynamic item in raw) {
      if (item is! Map) {
        continue;
      }

      result.add(
        item.map(
          (key, value) => MapEntry(
            key.toString(),
            value.toString(),
          ),
        ),
      );
    }

    return result;
  }

  Map<String, List<String>>
      get _availability {
    final dynamic raw =
        _profile['availability'];

    if (raw is! Map) {
      return <String, List<String>>{};
    }

    final Map<String, List<String>> result =
        <String, List<String>>{};

    for (final MapEntry<dynamic, dynamic> entry
        in raw.entries) {
      if (entry.value is! List) {
        continue;
      }

      final List<String> values =
          (entry.value as List)
              .map(
                (item) =>
                    item.toString().trim(),
              )
              .where(
                (item) => item.isNotEmpty,
              )
              .toList();

      if (values.isEmpty) {
        continue;
      }

      result[entry.key.toString()] =
          values;
    }

    return result;
  }

  List<Map<String, String>>
      get _visibleNetworks {
    final dynamic raw =
        _profile['networks'];

    if (raw is! List) {
      return <Map<String, String>>[];
    }

    final List<Map<String, String>> result =
        <Map<String, String>>[];

    for (final dynamic item in raw) {
      if (item is! Map) {
        continue;
      }

      final Map<String, String> network =
          item.map(
        (key, value) => MapEntry(
          key.toString(),
          value.toString(),
        ),
      );

      final String visibility =
          network['visibilite']
                  ?.trim()
                  .toLowerCase() ??
              '';

      if (visibility != 'visible') {
        continue;
      }

      result.add(network);
    }

    return result;
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
            const Color(0xff21150e),
        foregroundColor:
            const Color(0xffffc857),
        centerTitle: true,
        title: const Text(
          'PROFIL AVENTURIER',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
            letterSpacing:
                1.1,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(
                  color:
                      Color(
                    0xffffc857,
                  ),
                ),
              )
            : RefreshIndicator(
                color:
                    const Color(
                  0xffffc857,
                ),
                onRefresh: _load,
                child:
                    ListView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(
                    18,
                    22,
                    18,
                    32,
                  ),
                  children: [
                    _buildIdentity(),
                    const SizedBox(height: 22),
                    _PublicSection(
                      title: 'À PROPOS',
                      icon: Icons.person_outline,
                      child: Text(
                        _description,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PublicSection(
                      title: 'JEUX',
                      icon: Icons.sports_esports,
                      child: _buildGames(),
                    ),
                    const SizedBox(height: 14),
                    _PublicSection(
                      title: 'PLATEFORMES',
                      icon: Icons.devices,
                      child: _buildPlatforms(),
                    ),
                    const SizedBox(height: 14),
                    _PublicSection(
                      title: 'DISPONIBILITÉS',
                      icon: Icons.schedule,
                      child: _buildAvailability(),
                    ),
                    const SizedBox(height: 14),
                    _PublicSection(
                      title: 'RÉSEAUX VISIBLES',
                      icon: Icons.link,
                      child: _buildNetworks(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildIdentity() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff21150e),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xffffc857),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          if (_avatar != null)
            AvatarRenderer(
              avatar: _avatar!,
              size: 120,
            )
          else
            Container(
              width: 120,
              height: 150,
              decoration: BoxDecoration(
                color: const Color(0xff2b1a12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xffffc857),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.person,
                color: Color(0xffffc857),
                size: 58,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _pseudo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xffffc857),
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Niveau 1 - Aventurier',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.visibility,
                color: Colors.white38,
                size: 15,
              ),
              SizedBox(width: 5),
              Text(
                'Profil public',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGames() {
    final List<String> games = _games;

    if (games.isEmpty) {
      return const _EmptyPublicValue(
        text: 'Aucun jeu renseigné.',
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: games.map(
        (game) {
          return _PublicChip(
            label: game,
            leading: BrandIcon(
              brand: game,
              size: 18,
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildPlatforms() {
    final List<Map<String, String>>
        platforms = _platforms;

    if (platforms.isEmpty) {
      return const _EmptyPublicValue(
        text: 'Aucune plateforme renseignée.',
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: platforms.map(
        (platform) {
          final String name =
              platform['nom'] ?? 'Plateforme';

          return _PublicChip(
            label: name,
            leading: BrandIcon(
              brand: name,
              size: 18,
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildAvailability() {
    final Map<String, List<String>>
        availability = _availability;

    if (availability.isEmpty) {
      return const _EmptyPublicValue(
        text: 'Aucune disponibilité renseignée.',
      );
    }

    return Column(
      children: availability.entries.map(
        (entry) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xff160e09),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: Colors.white12,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      color: Color(0xffffc857),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value.join(' • '),
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildNetworks() {
    final List<Map<String, String>>
        networks = _visibleNetworks;

    if (networks.isEmpty) {
      return const _EmptyPublicValue(
        text: 'Aucun réseau public.',
      );
    }

    return Column(
      children: networks.map(
        (network) {
          final String name =
              network['nom'] ?? 'Réseau';

          final String username =
              network['pseudo'] ?? '';

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xff160e09),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: Colors.white12,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: BrandIcon(
                      brand: name,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xffffc857),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (username.trim().isNotEmpty)
                        Text(
                          username,
                          style: const TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.visibility,
                  color: Colors.white38,
                  size: 18,
                ),
              ],
            ),
          );
        },
      ).toList(),
    );
  }
}

class _PublicSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PublicSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xff21150e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xffffc857),
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xffffc857),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PublicChip extends StatelessWidget {
  final String label;
  final Widget leading;

  const _PublicChip({
    required this.label,
    required this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff160e09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPublicValue extends StatelessWidget {
  final String text;

  const _EmptyPublicValue({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 12,
      ),
    );
  }
}
