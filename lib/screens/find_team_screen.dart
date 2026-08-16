import 'dart:io';

import 'package:flutter/material.dart';

import '../models/team_model.dart';
import '../services/auth_service.dart';
import '../services/profile_storage.dart';
import '../services/squad_invitation_storage.dart';
import '../services/squad_request_storage.dart';
import '../services/team_storage.dart';

class FindTeamScreen extends StatefulWidget {
  const FindTeamScreen({
    super.key,
  });

  @override
  State<FindTeamScreen> createState() =>
      _FindTeamScreenState();
}

class _FindTeamScreenState
    extends State<FindTeamScreen> {
  final TextEditingController
      _searchController =
      TextEditingController();

  List<TeamModel> _allTeams =
      <TeamModel>[];

  String _currentUserId = '';
  String _currentUsername = 'Joueur';

  String _selectedGame = 'Tous';
  String _selectedPlatform = 'Toutes';

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _refresh,
    );

    _load();
  }

  @override
  void dispose() {
    _searchController
        .removeListener(
      _refresh,
    );

    _searchController.dispose();

    super.dispose();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _load() async {
    final List<TeamModel> teams =
        await TeamStorage.loadTeams();

    final Map<String, dynamic> profile =
        await ProfileStorage.loadProfile();

    final String? authUserId =
        await AuthService
            .getCurrentUserId();

    final String? authUsername =
        await AuthService
            .getCurrentUsername();

    final String userId =
        authUserId?.trim().isNotEmpty ==
                true
            ? authUserId!.trim()
            : profile['id']
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? profile['id']
                    .toString()
                    .trim()
                : '';

    final String username =
        profile['pseudo']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? profile['pseudo']
                .toString()
                .trim()
            : authUsername
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? authUsername!.trim()
                : 'Joueur';

    if (!mounted) {
      return;
    }

    setState(() {
      _allTeams = teams;
      _currentUserId = userId;
      _currentUsername = username;
      _loading = false;
    });
  }

  List<TeamModel> get _visibleTeams {
    final String query =
        _searchController.text
            .trim()
            .toLowerCase();

    return _allTeams.where(
      (team) {
        final bool alreadyMember =
            team.ownerId ==
                    _currentUserId ||
                team.memberIds.contains(
                  _currentUserId,
                );

        if (alreadyMember) {
          return false;
        }

        if (!team.recruitmentOpen) {
          return false;
        }

        if (team.memberIds.length >=
            team.maxMembers) {
          return false;
        }

        if (_selectedGame !=
                'Tous' &&
            !team.games.contains(
              _selectedGame,
            )) {
          return false;
        }

        if (_selectedPlatform !=
                'Toutes' &&
            !team.platforms.contains(
              _selectedPlatform,
            )) {
          return false;
        }

        if (query.isEmpty) {
          return true;
        }

        final String haystack =
            '${team.name} '
                    '${team.description} '
                    '${team.ownerName} '
                    '${team.games.join(' ')} '
                    '${team.platforms.join(' ')}'
                .toLowerCase();

        return haystack.contains(
          query,
        );
      },
    ).toList();
  }

  List<String> get _games {
    final Set<String> values =
        <String>{};

    for (final TeamModel team
        in _allTeams) {
      values.addAll(
        team.games,
      );
    }

    final List<String> result =
        values.toList()..sort();

    return <String>[
      'Tous',
      ...result,
    ];
  }

  List<String> get _platforms {
    final Set<String> values =
        <String>{};

    for (final TeamModel team
        in _allTeams) {
      values.addAll(
        team.platforms,
      );
    }

    final List<String> result =
        values.toList()..sort();

    return <String>[
      'Toutes',
      ...result,
    ];
  }

  Future<void> _openTeam(
    TeamModel team,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            PublicTeamScreen(
          team: team,
          currentUserId:
              _currentUserId,
          currentUsername:
              _currentUsername,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _load();
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
          'TROUVER UNE ÉQUIPE',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
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
                onRefresh:
                    _load,
                child:
                    ListView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(
                    18,
                    18,
                    18,
                    30,
                  ),
                  children: [
                    TextField(
                      controller:
                          _searchController,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                      ),
                      decoration:
                          InputDecoration(
                        hintText:
                            'Nom, jeu, Chef...',
                        hintStyle:
                            const TextStyle(
                          color:
                              Colors.white38,
                        ),
                        prefixIcon:
                            const Icon(
                          Icons.search,
                          color:
                              Color(
                            0xffffc857,
                          ),
                        ),
                        filled:
                            true,
                        fillColor:
                            const Color(
                          0xff21150e,
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
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    Row(
                      children: [
                        Expanded(
                          child:
                              _FilterDropdown(
                            label:
                                'Jeu',
                            value:
                                _selectedGame,
                            values:
                                _games,
                            onChanged:
                                (value) {
                              setState(() {
                                _selectedGame =
                                    value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                              _FilterDropdown(
                            label:
                                'Plateforme',
                            value:
                                _selectedPlatform,
                            values:
                                _platforms,
                            onChanged:
                                (value) {
                              setState(() {
                                _selectedPlatform =
                                    value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 22,
                    ),

                    Text(
                      '${_visibleTeams.length} équipe(s) disponible(s)',
                      style:
                          const TextStyle(
                        color:
                            Colors.white54,
                        fontSize:
                            12,
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    if (_visibleTeams
                        .isEmpty)
                      const _EmptyState()
                    else
                      ..._visibleTeams
                          .map(
                            (team) =>
                                _TeamCard(
                              team:
                                  team,
                              onTap: () {
                                _openTeam(
                                  team,
                                );
                              },
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
// FICHE PUBLIQUE ÉQUIPE
// =============================================================================

class PublicTeamScreen
    extends StatefulWidget {
  final TeamModel team;
  final String currentUserId;
  final String currentUsername;

  const PublicTeamScreen({
    super.key,
    required this.team,
    required this.currentUserId,
    required this.currentUsername,
  });

  @override
  State<PublicTeamScreen> createState() =>
      _PublicTeamScreenState();
}

class _PublicTeamScreenState
    extends State<PublicTeamScreen> {
  bool _checking = true;
  bool _requestPending = false;
  bool _invitationPending = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _checkRequest();
  }

  Future<void> _checkRequest() async {
    final bool pending =
        await SquadRequestStorage
            .hasPendingRequest(
      teamId: widget.team.id,
      requesterId:
          widget.currentUserId,
    );

    final bool invitationPending =
        await SquadInvitationStorage
            .hasPendingInvitation(
      teamId: widget.team.id,
      inviteeId:
          widget.currentUserId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _requestPending = pending;
      _invitationPending =
          invitationPending;
      _checking = false;
    });
  }

  Future<void> _requestToJoin() async {
    if (_requestPending ||
        _sending) {
      return;
    }

    if (_invitationPending) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Tu as déjà une invitation pour cette équipe. Ouvre le Communicateur XP pour la traiter.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    final bool success =
        await SquadRequestStorage
            .createRequest(
      team: widget.team,
      requesterId:
          widget.currentUserId,
      requesterName:
          widget.currentUsername,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _sending = false;

      if (success) {
        _requestPending = true;
      }
    });

    if (!success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’envoyer cette demande.',
          ),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          'Demande envoyée à ${widget.team.name}.',
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final TeamModel team =
        widget.team;

    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff21150e),
        foregroundColor:
            const Color(0xffffc857),
        title: Text(
          team.name,
          overflow:
              TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(
            18,
            20,
            18,
            30,
          ),
          children: [
            Center(
              child:
                  _TeamImage(
                imagePath:
                    team.imagePath,
                size: 170,
              ),
            ),

            const SizedBox(
              height: 18,
            ),

            Text(
              team.name,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Color(
                  0xffffc857,
                ),
                fontSize: 27,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              team.description.isEmpty
                  ? 'Aucune description.'
                  : team.description,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white70,
                height: 1.45,
              ),
            ),

            const SizedBox(
              height: 22,
            ),

            _InfoRow(
              icon:
                  Icons.workspace_premium,
              label:
                  'Chef',
              value:
                  team.ownerName,
            ),

            const SizedBox(
              height: 9,
            ),

            _InfoRow(
              icon:
                  Icons.people,
              label:
                  'Membres',
              value:
                  '${team.memberIds.length}/${team.maxMembers}',
            ),

            const SizedBox(
              height: 9,
            ),

            const _InfoRow(
              icon:
                  Icons.lock_open,
              label:
                  'Recrutement',
              value:
                  'OUVERT',
            ),

            const SizedBox(
              height: 25,
            ),

            const _SectionTitle(
              icon:
                  Icons.sports_esports,
              title:
                  'JEUX',
            ),

            const SizedBox(
              height: 10,
            ),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: team.games
                  .map(
                    (game) =>
                        _Tag(
                      icon:
                          Icons.games,
                      text:
                          game,
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(
              height: 25,
            ),

            const _SectionTitle(
              icon:
                  Icons.devices,
              title:
                  'PLATEFORMES',
            ),

            const SizedBox(
              height: 10,
            ),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: team.platforms
                  .map(
                    (platform) =>
                        _Tag(
                      icon:
                          Icons.devices,
                      text:
                          platform,
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(
              height: 28,
            ),

            SizedBox(
              width:
                  double.infinity,
              height: 54,
              child:
                  ElevatedButton.icon(
                onPressed:
                    _checking ||
                            _sending ||
                            _requestPending ||
                            _invitationPending
                        ? null
                        : _requestToJoin,
                icon:
                    _sending
                        ? const SizedBox(
                            width:
                                20,
                            height:
                                20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2,
                              color:
                                  Colors.black,
                            ),
                          )
                        : Icon(
                            _invitationPending
                                ? Icons.mail_outline
                                : _requestPending
                                    ? Icons.hourglass_top
                                    : Icons.group_add,
                          ),
                label:
                    Text(
                  _invitationPending
                      ? 'INVITATION REÇUE'
                      : _requestPending
                          ? 'DEMANDE EN ATTENTE'
                          : _sending
                              ? 'ENVOI...'
                              : 'DEMANDER À REJOINDRE',
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
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
                  disabledBackgroundColor:
                      Colors.white12,
                  disabledForegroundColor:
                      Colors.white38,
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

            const SizedBox(
              height: 14,
            ),

            Text(
              _invitationPending
                  ? 'Cette équipe t’a déjà invité. Retrouve l’invitation dans le Communicateur XP du Hall.'
                  : 'La demande sera envoyée au Chef et à l’Admin de l’équipe. Ils la retrouveront dans le téléphone du Hall.',
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white38,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// WIDGETS
// =============================================================================

class _TeamCard
    extends StatelessWidget {
  final TeamModel team;
  final VoidCallback onTap;

  const _TeamCard({
    required this.team,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child:
          Material(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          17,
        ),
        child:
            InkWell(
          onTap:
              onTap,
          borderRadius:
              BorderRadius.circular(
            17,
          ),
          child:
              Container(
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                17,
              ),
              border:
                  Border.all(
                color:
                    Colors.white12,
              ),
            ),
            child:
                Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _TeamImage(
                  imagePath:
                      team.imagePath,
                  size: 76,
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.name,
                        maxLines:
                            1,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize:
                              17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      Text(
                        'Chef : ${team.ownerName}',
                        maxLines:
                            1,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Colors.white54,
                          fontSize:
                              11,
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      Text(
                        '${team.memberIds.length}/${team.maxMembers} membres',
                        style:
                            const TextStyle(
                          color:
                              Color(
                            0xffffc857,
                          ),
                          fontSize:
                              12,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),

                      const SizedBox(
                        height: 7,
                      ),

                      Wrap(
                        spacing:
                            5,
                        runSpacing:
                            5,
                        children:
                            team.games
                                .take(
                                  2,
                                )
                                .map(
                                  (game) =>
                                      _MiniTag(
                                    text:
                                        game,
                                  ),
                                )
                                .toList(),
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
      ),
    );
  }
}

class _FilterDropdown
    extends StatelessWidget {
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String>
      onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return DropdownButtonFormField<
        String>(
      initialValue:
          values.contains(value)
              ? value
              : values.first,
      dropdownColor:
          const Color(
        0xff21150e,
      ),
      decoration:
          InputDecoration(
        labelText:
            label,
        labelStyle:
            const TextStyle(
          color:
              Colors.white54,
        ),
        filled:
            true,
        fillColor:
            const Color(
          0xff21150e,
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
      ),
      style:
          const TextStyle(
        color:
            Colors.white,
      ),
      iconEnabledColor:
          const Color(
        0xffffc857,
      ),
      items:
          values
              .map(
                (item) =>
                    DropdownMenuItem<
                        String>(
                  value:
                      item,
                  child:
                      Text(
                    item,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
      onChanged:
          (newValue) {
        if (newValue ==
            null) {
          return;
        }

        onChanged(
          newValue,
        );
      },
    );
  }
}

class _TeamImage
    extends StatelessWidget {
  final String? imagePath;
  final double size;

  const _TeamImage({
    required this.imagePath,
    required this.size,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          size,
      height:
          size,
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff6B4226,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              const Color(
            0xffffc857,
          ),
          width:
              1.5,
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      child:
          _content(),
    );
  }

  Widget _content() {
    final String? path =
        imagePath;

    if (path == null ||
        path.isEmpty) {
      return Icon(
        Icons.groups,
        color:
            const Color(
          0xffffc857,
        ),
        size:
            size * 0.45,
      );
    }

    if (path.startsWith(
          'http://',
        ) ||
        path.startsWith(
          'https://',
        )) {
      return Image.network(
        path,
        fit:
            BoxFit.cover,
        errorBuilder:
            (
          context,
          error,
          stackTrace,
        ) {
          return Icon(
            Icons.groups,
            color:
                const Color(
              0xffffc857,
            ),
            size:
                size * 0.45,
          );
        },
      );
    }

    final File file =
        File(path);

    if (file.existsSync()) {
      return Image.file(
        file,
        fit:
            BoxFit.cover,
      );
    }

    return Icon(
      Icons.groups,
      color:
          const Color(
        0xffffc857,
      ),
      size:
          size * 0.45,
    );
  }
}

class _InfoRow
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        13,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          13,
        ),
        border:
            Border.all(
          color:
              Colors.white12,
        ),
      ),
      child:
          Row(
        children: [
          Icon(
            icon,
            color:
                const Color(
              0xffffc857,
            ),
            size:
                20,
          ),
          const SizedBox(
            width:
                10,
          ),
          Text(
            '$label : ',
            style:
                const TextStyle(
              color:
                  Colors.white54,
            ),
          ),
          Expanded(
            child:
                Text(
              value,
              textAlign:
                  TextAlign.right,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle
    extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color:
              const Color(
            0xffffc857,
          ),
          size:
              20,
        ),
        const SizedBox(
          width:
              8,
        ),
        Text(
          title,
          style:
              const TextStyle(
            color:
                Color(
              0xffffc857,
            ),
            fontSize:
                16,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _Tag
    extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Tag({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal:
            10,
        vertical:
            7,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff3d291e,
        ),
        borderRadius:
            BorderRadius.circular(
          10,
        ),
        border:
            Border.all(
          color:
              Colors.white24,
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                const Color(
              0xffffc857,
            ),
            size:
                15,
          ),
          const SizedBox(
            width:
                5,
          ),
          Text(
            text,
            style:
                const TextStyle(
              color:
                  Colors.white70,
              fontSize:
                  12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag
    extends StatelessWidget {
  final String text;

  const _MiniTag({
    required this.text,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal:
            7,
        vertical:
            4,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff6B4226,
        ),
        borderRadius:
            BorderRadius.circular(
          8,
        ),
      ),
      child:
          Text(
        text,
        style:
            const TextStyle(
          color:
              Colors.white70,
          fontSize:
              10,
        ),
      ),
    );
  }
}

class _EmptyState
    extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        24,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border:
            Border.all(
          color:
              Colors.white12,
        ),
      ),
      child:
          const Column(
        children: [
          Icon(
            Icons.search_off,
            color:
                Color(
              0xffffc857,
            ),
            size:
                44,
          ),
          SizedBox(
            height:
                12,
          ),
          Text(
            'Aucune équipe disponible',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Colors.white,
              fontSize:
                  18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          SizedBox(
            height:
                7,
          ),
          Text(
            'Essaie de modifier les filtres ou reviens plus tard.',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Colors.white54,
              height:
                  1.4,
            ),
          ),
        ],
      ),
    );
  }
}
