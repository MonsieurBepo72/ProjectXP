import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/friend_service.dart';
import '../services/private_message_service.dart';
import 'friend_requests_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';

class PhoneHomeScreen extends StatefulWidget {
  const PhoneHomeScreen({
    super.key,
  });

  @override
  State<PhoneHomeScreen> createState() =>
      _PhoneHomeScreenState();
}

class _PhoneHomeScreenState
    extends State<PhoneHomeScreen>
    with WidgetsBindingObserver {
  final Battery _battery =
      Battery();

  Timer? _clockTimer;

  StreamSubscription<BatteryState>?
      _batteryStateSubscription;

  DateTime _now =
      DateTime.now();

  int? _batteryLevel;

  BatteryState _batteryState =
      BatteryState.unknown;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(
      this,
    );

    // Le Communicateur XP se comporte comme un vrai téléphone plein écran :
    // on masque temporairement les barres système Android/iOS pour éviter
    // d'afficher deux fois l'heure et la batterie.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );

    _startClock();
    _initializeBattery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    );

    _clockTimer?.cancel();

    _batteryStateSubscription?.cancel();

    // On rend les barres système au Hall dès que l'utilisateur range
    // le Communicateur XP.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      _refreshTime();
      _refreshBatteryLevel();
    }
  }

  // ===========================================================================
  // HEURE RÉELLE
  // ===========================================================================

  void _startClock() {
    _refreshTime();

    _clockTimer =
        Timer.periodic(
      const Duration(
        seconds: 15,
      ),
      (_) {
        _refreshTime();
      },
    );
  }

  void _refreshTime() {
    if (!mounted) {
      return;
    }

    setState(() {
      _now = DateTime.now();
    });
  }

  String get _formattedTime {
    final String hour =
        _now.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String minute =
        _now.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$hour:$minute';
  }

  String get _formattedDate {
    const List<String> days =
        <String>[
      'Lun.',
      'Mar.',
      'Mer.',
      'Jeu.',
      'Ven.',
      'Sam.',
      'Dim.',
    ];

    const List<String> months =
        <String>[
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];

    final String day =
        days[_now.weekday - 1];

    final String month =
        months[_now.month - 1];

    return '$day ${_now.day} $month';
  }

  // ===========================================================================
  // BATTERIE RÉELLE DU TÉLÉPHONE
  // ===========================================================================

  Future<void> _initializeBattery() async {
    await _refreshBatteryLevel();

    try {
      _batteryState =
          await _battery.batteryState;

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Le niveau reste affiché si disponible.
    }

    _batteryStateSubscription =
        _battery.onBatteryStateChanged.listen(
      (
        BatteryState state,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _batteryState = state;
        });

        _refreshBatteryLevel();
      },
    );
  }

  Future<void> _refreshBatteryLevel() async {
    try {
      final int level =
          await _battery.batteryLevel;

      if (!mounted) {
        return;
      }

      setState(() {
        _batteryLevel = level;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _batteryLevel = null;
      });
    }
  }

  bool get _isCharging {
    return _batteryState ==
            BatteryState.charging ||
        _batteryState ==
            BatteryState.full;
  }

  IconData get _batteryIcon {
    if (_isCharging) {
      return Icons.battery_charging_full;
    }

    return Icons.battery_full;
  }

  // ===========================================================================
  // NAVIGATION DES "APPS"
  // ===========================================================================

  Future<void> _openFriends() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          BuildContext context,
        ) {
          return const FriendsScreen();
        },
      ),
    );
  }

  Future<void> _openFriendRequests() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          BuildContext context,
        ) {
          return const FriendRequestsScreen();
        },
      ),
    );
  }

  Future<void> _openMessages() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          BuildContext context,
        ) {
          return const MessagesScreen();
        },
      ),
    );
  }

  void _openNotifications() {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Le centre de notifications arrive à l’étape suivante.',
        ),
      ),
    );
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
        0xff100a07,
      ),
      body: Container(
        decoration:
            const BoxDecoration(
          gradient:
              LinearGradient(
            begin:
                Alignment.topCenter,
            end:
                Alignment.bottomCenter,
            colors: <Color>[
              Color(
                0xff21150e,
              ),
              Color(
                0xff130c08,
              ),
              Color(
                0xff090605,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildStatusBar(),

              Expanded(
                child:
                    LayoutBuilder(
                  builder: (
                    BuildContext context,
                    BoxConstraints constraints,
                  ) {
                    final bool compact =
                        constraints.maxHeight <
                            580;

                    return SingleChildScrollView(
                      physics:
                          const BouncingScrollPhysics(),
                      padding:
                          EdgeInsets.fromLTRB(
                        22,
                        compact ? 12 : 24,
                        22,
                        18,
                      ),
                      child: Column(
                        children: [
                          _buildPhoneHeader(
                            compact:
                                compact,
                          ),

                          SizedBox(
                            height:
                                compact
                                    ? 22
                                    : 34,
                          ),

                          _buildAppGrid(),

                          SizedBox(
                            height:
                                compact
                                    ? 22
                                    : 36,
                          ),

                          _buildHint(),
                        ],
                      ),
                    );
                  },
                ),
              ),

              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BARRE D'ÉTAT
  // ===========================================================================

  Widget _buildStatusBar() {
    final String batteryText =
        _batteryLevel == null
            ? '--%'
            : '${_batteryLevel!}%';

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        8,
        12,
        4,
      ),
      child: Row(
        children: [
          Text(
            _formattedTime,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontSize: 13,
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const Spacer(),

          const Icon(
            Icons.wifi,
            color:
                Colors.white70,
            size: 16,
          ),

          const SizedBox(
            width: 6,
          ),

          Text(
            batteryText,
            style:
                const TextStyle(
              color:
                  Colors.white70,
              fontSize: 12,
              fontWeight:
                  FontWeight.w600,
            ),
          ),

          const SizedBox(
            width: 3,
          ),

          Icon(
            _batteryIcon,
            color: _isCharging
                ? const Color(
                    0xffffd27a,
                  )
                : Colors.white70,
            size: 19,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // EN-TÊTE
  // ===========================================================================

  Widget _buildPhoneHeader({
    required bool compact,
  }) {
    return Column(
      children: [
        Text(
          _formattedTime,
          style: TextStyle(
            color:
                Colors.white,
            fontSize:
                compact ? 42 : 50,
            fontWeight:
                FontWeight.w300,
            letterSpacing:
                -1.4,
          ),
        ),

        const SizedBox(
          height: 2,
        ),

        Text(
          _formattedDate,
          style:
              const TextStyle(
            color:
                Colors.white60,
            fontSize: 13,
          ),
        ),

        SizedBox(
          height:
              compact ? 10 : 16,
        ),

        const Text(
          'COMMUNICATEUR XP',
          style: TextStyle(
            color: Color(
              0xffffd27a,
            ),
            fontSize: 11,
            fontWeight:
                FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // GRILLE D'APPLICATIONS
  // ===========================================================================

  Widget _buildAppGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 24,
      crossAxisSpacing: 24,
      childAspectRatio: 1.05,
      children: [
        StreamBuilder<int>(
          stream: PrivateMessageService
              .unreadCountStream(),
          initialData: 0,
          builder: (
            BuildContext context,
            AsyncSnapshot<int>
                snapshot,
          ) {
            return _PhoneAppIcon(
              label: 'Messages',
              icon:
                  Icons.chat_bubble_rounded,
              badgeCount:
                  snapshot.data ?? 0,
              onTap:
                  _openMessages,
            );
          },
        ),

        StreamBuilder<int>(
          stream: FriendService
              .incomingRequestCountStream(),
          initialData: 0,
          builder: (
            BuildContext context,
            AsyncSnapshot<int>
                snapshot,
          ) {
            return _PhoneAppIcon(
              label: 'Demandes',
              icon:
                  Icons.person_add_alt_1_rounded,
              badgeCount:
                  snapshot.data ?? 0,
              onTap:
                  _openFriendRequests,
            );
          },
        ),

        _PhoneAppIcon(
          label: 'Amis',
          icon:
              Icons.people_alt_rounded,
          onTap:
              _openFriends,
        ),

        _PhoneAppIcon(
          label: 'Notifications',
          icon:
              Icons.notifications_rounded,
          onTap:
              _openNotifications,
        ),
      ],
    );
  }

  Widget _buildHint() {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white
                .withValues(
          alpha: 0.045,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color:
              Colors.white
                  .withValues(
            alpha: 0.07,
          ),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.lock_outline,
            color:
                Colors.white38,
            size: 17,
          ),

          SizedBox(
            width: 9,
          ),

          Expanded(
            child: Text(
              'Tes messages privés, tes amis et tes notifications vivent ici.',
              style:
                  TextStyle(
                color:
                    Colors.white54,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BARRE BASSE
  // ===========================================================================

  Widget _buildBottomBar() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        14,
        6,
        14,
        10,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip:
                'Retour',
            onPressed: () {
              Navigator.maybePop(
                context,
              );
            },
            icon: const Icon(
              Icons.arrow_back_rounded,
              color:
                  Colors.white54,
            ),
          ),

          const Spacer(),

          Container(
            width: 84,
            height: 4,
            decoration:
                BoxDecoration(
              color:
                  Colors.white24,
              borderRadius:
                  BorderRadius.circular(
                999,
              ),
            ),
          ),

          const Spacer(),

          const SizedBox(
            width: 48,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ICÔNE D'APPLICATION
// =============================================================================

class _PhoneAppIcon extends StatelessWidget {
  const _PhoneAppIcon({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;

  final IconData icon;

  final VoidCallback onTap;

  final int badgeCount;

  @override
  Widget build(
    BuildContext context,
  ) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(
        24,
      ),
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.all(
          6,
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior:
                  Clip.none,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xff2c1c13,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      22,
                    ),
                    border:
                        Border.all(
                      color:
                          const Color(
                        0xff6a4327,
                      ),
                    ),
                    boxShadow:
                        const <BoxShadow>[
                      BoxShadow(
                        color:
                            Colors.black26,
                        blurRadius:
                            12,
                        offset:
                            Offset(
                          0,
                          6,
                        ),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color:
                        const Color(
                      0xffffd27a,
                    ),
                    size: 35,
                  ),
                ),

                if (badgeCount >
                    0)
                  Positioned(
                    right: -8,
                    top: -7,
                    child:
                        Container(
                      constraints:
                          const BoxConstraints(
                        minWidth:
                            23,
                        minHeight:
                            23,
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal:
                            6,
                      ),
                      alignment:
                          Alignment.center,
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.redAccent,
                        shape:
                            BoxShape.circle,
                        border:
                            Border.all(
                          color:
                              const Color(
                            0xff130c08,
                          ),
                          width: 2,
                        ),
                      ),
                      child:
                          Text(
                        badgeCount >
                                99
                            ? '99+'
                            : badgeCount
                                .toString(),
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize:
                              10,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(
              height: 9,
            ),

            Text(
              label,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize: 12,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
