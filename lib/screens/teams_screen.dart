import 'dart:io';

import 'package:flutter/material.dart';

import '../models/team_model.dart';
import '../services/auth_service.dart';
import '../services/profile_storage.dart';
import '../services/team_storage.dart';
import 'create_team_screen.dart';
import 'team_details_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({
    super.key,
  });

  @override
  State<TeamsScreen> createState() =>
      _TeamsScreenState();
}

class _TeamsScreenState
    extends State<TeamsScreen> {
  List<TeamModel> _teams =
      <TeamModel>[];

  String _currentUserId = '';
  String _currentUsername =
      'Joueur';

  bool _isLoading = true;

  // ===========================================================================
  // INITIALISATION
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final Map<String, dynamic> profile =
          await ProfileStorage
              .loadProfile();

      final String? authUserId =
          await AuthService
              .getCurrentUserId();

      final String? authUsername =
          await AuthService
              .getCurrentUsername();

      final List<TeamModel> allTeams =
          await TeamStorage
              .loadTeams();

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

      final List<TeamModel>
          myTeams =
          allTeams.where(
        (team) {
          return team.ownerId ==
                  userId ||
              team.memberIds
                  .contains(
                userId,
              );
        },
      ).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUserId =
            userId;

        _currentUsername =
            username;

        _teams =
            myTeams;

        _isLoading =
            false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading =
            false;
      });

      _showMessage(
        'Impossible de charger tes équipes.',
      );
    }
  }

  // ===========================================================================
  // CRÉATION
  // ===========================================================================

  Future<void> _createTeam() async {
    final TeamModel? created =
        await Navigator.push<
            TeamModel>(
      context,
      MaterialPageRoute<
          TeamModel>(
        builder: (context) =>
            const CreateTeamScreen(),
      ),
    );

    if (created == null ||
        !mounted) {
      return;
    }

    await _loadData();

    if (!mounted) {
      return;
    }

    _showMessage(
      '${created.name} a été créée.',
    );
  }

  // ===========================================================================
  // OUVRIR UNE ÉQUIPE
  // ===========================================================================

  Future<void> _openTeam(
    TeamModel team,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            TeamDetailsScreen(
          teamId: team.id,
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

    await _loadData();
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
          const Color(
        0xff1b120d,
      ),
      appBar: AppBar(
        backgroundColor:
            const Color(
          0xff5c3317,
        ),
        foregroundColor:
            Colors.amber,
        centerTitle:
            true,
        title:
            const Text(
          'MES ÉQUIPES',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child:
            _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(
                      color:
                          Colors.amber,
                    ),
                  )
                : RefreshIndicator(
                    color:
                        Colors.amber,
                    backgroundColor:
                        const Color(
                      0xff2b1a12,
                    ),
                    onRefresh:
                        _loadData,
                    child:
                        _teams.isEmpty
                            ? _buildEmptyState()
                            : _buildTeamsList(),
                  ),
      ),
    );
  }

  Widget _buildTeamsList() {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        16,
        20,
        16,
        30,
      ),
      children: [
        const Text(
          'Tes Compagnies',
          textAlign:
              TextAlign.center,
          style:
              TextStyle(
            color:
                Colors.amber,
            fontSize: 27,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(
          height: 7,
        ),

        const Text(
          'Retrouve tes équipes et gère-les depuis ici.',
          textAlign:
              TextAlign.center,
          style:
              TextStyle(
            color:
                Colors.white70,
            fontSize: 14,
          ),
        ),

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
                _createTeam,
            icon:
                const Icon(
              Icons.add,
            ),
            label:
                const Text(
              'CRÉER UNE ÉQUIPE',
              style:
                  TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            style:
                ElevatedButton
                    .styleFrom(
              backgroundColor:
                  Colors.amber,
              foregroundColor:
                  Colors.black,
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
          height: 24,
        ),

        ..._teams.map(
          _buildTeamCard,
        ),
      ],
    );
  }

  // ===========================================================================
  // CARTE ÉQUIPE
  // ===========================================================================

  Widget _buildTeamCard(
    TeamModel team,
  ) {
    final String role =
        team.roleLabelFor(
      _currentUserId,
    );

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 16,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff2b1a12,
        ),
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border:
            Border.all(
          color: role == 'CHEF'
              ? Colors.amber
              : Colors.white24,
          width: role == 'CHEF'
              ? 1.7
              : 1,
        ),
        boxShadow:
            const [
          BoxShadow(
            color:
                Colors.black38,
            blurRadius: 8,
            offset:
                Offset(
              0,
              4,
            ),
          ),
        ],
      ),
      child:
          Material(
        color:
            Colors.transparent,
        child:
            InkWell(
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          onTap: () {
            _openTeam(
              team,
            );
          },
          child:
              Padding(
            padding:
                const EdgeInsets.all(
              14,
            ),
            child:
                Column(
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _TeamImage(
                      imagePath:
                          team.imagePath,
                      size: 82,
                    ),

                    const SizedBox(
                      width: 13,
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
                                2,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontSize:
                                  19,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const SizedBox(
                            height: 6,
                          ),

                          _RoleLine(
                            role:
                                role,
                          ),

                          const SizedBox(
                            height: 7,
                          ),

                          Row(
                            children: [
                              const Icon(
                                Icons.people,
                                color:
                                    Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(
                                width: 5,
                              ),
                              Text(
                                '${team.memberIds.length}/${team.maxMembers} membres',
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

                          const SizedBox(
                            height: 5,
                          ),

                          Row(
                            children: [
                              Icon(
                                team.recruitmentOpen
                                    ? Icons.lock_open
                                    : Icons.lock_outline,
                                color: team.recruitmentOpen
                                    ? Colors.greenAccent
                                    : Colors.white38,
                                size: 15,
                              ),
                              const SizedBox(
                                width: 5,
                              ),
                              Text(
                                team.recruitmentOpen
                                    ? 'Recrutement ouvert'
                                    : 'Recrutement fermé',
                                style:
                                    TextStyle(
                                  color: team.recruitmentOpen
                                      ? Colors.greenAccent
                                      : Colors.white38,
                                  fontSize:
                                      11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Icon(
                      Icons.chevron_right,
                      color:
                          Colors.amber,
                    ),
                  ],
                ),

                if (team.description
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 13,
                  ),
                  Align(
                    alignment:
                        Alignment.centerLeft,
                    child:
                        Text(
                      team.description,
                      maxLines:
                          2,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          const TextStyle(
                        color:
                            Colors.white60,
                        fontSize:
                            12,
                        height:
                            1.4,
                      ),
                    ),
                  ),
                ],

                if (team.games
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 12,
                  ),
                  Align(
                    alignment:
                        Alignment.centerLeft,
                    child:
                        Wrap(
                      spacing:
                          6,
                      runSpacing:
                          6,
                      children:
                          team.games
                              .take(
                                3,
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
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ÉTAT VIDE
  // ===========================================================================

  Widget _buildEmptyState() {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.all(
        28,
      ),
      children: [
        SizedBox(
          height:
              MediaQuery.of(
                    context,
                  ).size.height *
                  0.20,
        ),

        const Icon(
          Icons.groups_outlined,
          color:
              Colors.amber,
          size: 72,
        ),

        const SizedBox(
          height: 18,
        ),

        const Text(
          'Aucune équipe',
          textAlign:
              TextAlign.center,
          style:
              TextStyle(
            color:
                Colors.white,
            fontSize: 24,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(
          height: 8,
        ),

        const Text(
          'Crée ton premier Compagnie ou rejoins une équipe depuis « Trouver une équipe ».',
          textAlign:
              TextAlign.center,
          style:
              TextStyle(
            color:
                Colors.white70,
            height: 1.4,
          ),
        ),

        const SizedBox(
          height: 24,
        ),

        SizedBox(
          height: 52,
          child:
              ElevatedButton.icon(
            onPressed:
                _createTeam,
            icon:
                const Icon(
              Icons.add,
            ),
            label:
                const Text(
              'CRÉER UNE ÉQUIPE',
              style:
                  TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            style:
                ElevatedButton
                    .styleFrom(
              backgroundColor:
                  Colors.amber,
              foregroundColor:
                  Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }
}

// =============================================================================
// WIDGETS
// =============================================================================

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
              Colors.amber,
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
            Colors.amber,
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
                Colors.amber,
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
          Colors.amber,
      size:
          size * 0.45,
    );
  }
}

class _RoleLine
    extends StatelessWidget {
  final String role;

  const _RoleLine({
    required this.role,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final IconData icon =
        role == 'CHEF'
            ? Icons.workspace_premium
            : role == 'ADMIN'
                ? Icons.shield
                : Icons.person;

    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Icon(
          icon,
          color:
              Colors.amber,
          size: 15,
        ),
        const SizedBox(
          width: 5,
        ),
        Text(
          role,
          style:
              const TextStyle(
            color:
                Colors.amber,
            fontSize:
                10,
            fontWeight:
                FontWeight.bold,
            letterSpacing:
                0.7,
          ),
        ),
      ],
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
        horizontal: 8,
        vertical: 5,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff6B4226,
        ),
        borderRadius:
            BorderRadius.circular(
          9,
        ),
        border:
            Border.all(
          color:
              Colors.amber.withValues(
            alpha: 0.4,
          ),
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
              11,
        ),
      ),
    );
  }
}
