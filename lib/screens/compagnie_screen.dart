import 'package:flutter/material.dart';

import '../widgets/hall_home_button.dart';
import 'find_players_screen.dart';
import 'find_team_screen.dart';
import 'teams_screen.dart';

class CompagnieScreen extends StatelessWidget {
  const CompagnieScreen({
    super.key,
  });

  static const Color _background =
      Color(0xff160e09);

  static const Color _panel =
      Color(0xff21150e);

  static const Color _panelDark =
      Color(0xff120c08);

  static const Color _gold =
      Color(0xffffc857);

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _panel,
        foregroundColor: _gold,
        automaticallyImplyLeading: false,
        leadingWidth: 58,
        leading: const Center(
          child: HallHomeButton(
            width: 44,
            height: 40,
          ),
        ),
        centerTitle: true,
        title: const Text(
          'COMPAGNIE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            20,
            24,
            20,
            30,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(
                  22,
                ),
                decoration:
                    BoxDecoration(
                  color: _panel,
                  borderRadius:
                      BorderRadius.circular(
                    22,
                  ),
                  border: Border.all(
                    color: _gold,
                    width: 2,
                  ),
                  boxShadow:
                      const [
                    BoxShadow(
                      color:
                          Colors.black45,
                      blurRadius: 16,
                      offset:
                          Offset(
                        0,
                        8,
                      ),
                    ),
                  ],
                ),
                child:
                    const Column(
                  children: [
                    Icon(
                      Icons.shield,
                      color: _gold,
                      size: 48,
                    ),
                    SizedBox(
                      height: 12,
                    ),
                    Text(
                      'PORTAIL COMPAGNIE',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color: _gold,
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                        letterSpacing:
                            1.5,
                      ),
                    ),
                    SizedBox(
                      height: 8,
                    ),
                    Text(
                      'Trouve une équipe, gère tes Compagnies ou rencontre de nouveaux joueurs.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white60,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 26,
              ),

              _CompagnieMenuCard(
                icon: Icons.search,
                title:
                    'TROUVER UNE ÉQUIPE',
                subtitle:
                    'Recherche un Compagnie qui recrute selon tes jeux et plateformes.',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder:
                          (context) =>
                              const FindTeamScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(
                height: 14,
              ),

              _CompagnieMenuCard(
                icon:
                    Icons.shield_outlined,
                title:
                    'MES ÉQUIPES',
                subtitle:
                    'Crée une équipe et gère les Compagnies dont tu fais partie.',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder:
                          (context) =>
                              const TeamsScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(
                height: 14,
              ),

              _CompagnieMenuCard(
                icon:
                    Icons.people_alt_outlined,
                title:
                    'TROUVER DES JOUEURS',
                subtitle:
                    'Découvre des joueurs compatibles selon leurs profils.',
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder:
                          (context) =>
                              const FindPlayersScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(
                height: 28,
              ),

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                decoration:
                    BoxDecoration(
                  color: _panelDark,
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                  border: Border.all(
                    color:
                        Colors.white12,
                  ),
                ),
                child:
                    const Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.smartphone,
                      color: _gold,
                      size: 21,
                    ),
                    SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: Text(
                        'Les demandes et invitations reçues sont centralisées dans le téléphone du Hall.',
                        style:
                            TextStyle(
                          color:
                              Colors.white54,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompagnieMenuCard
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CompagnieMenuCard({
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
          const Color(
        0xff21150e,
      ),
      borderRadius:
          BorderRadius.circular(
        18,
      ),
      child: InkWell(
        onTap:
            onTap,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        child: Container(
          width:
              double.infinity,
          padding:
              const EdgeInsets.all(
            18,
          ),
          decoration:
              BoxDecoration(
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
              Row(
            children: [
              Container(
                width:
                    56,
                height:
                    56,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xff120c08,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                  border:
                      Border.all(
                    color:
                        const Color(
                      0xffffc857,
                    ),
                  ),
                ),
                child:
                    Icon(
                  icon,
                  color:
                      const Color(
                    0xffffc857,
                  ),
                  size:
                      28,
                ),
              ),
              const SizedBox(
                width:
                    15,
              ),
              Expanded(
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize:
                            16,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height:
                          5,
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(
                        color:
                            Colors.white54,
                        fontSize:
                            12,
                        height:
                            1.35,
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
