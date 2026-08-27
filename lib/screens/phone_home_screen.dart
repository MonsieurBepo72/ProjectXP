import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_status_service.dart';
import '../services/friend_service.dart';
import '../services/private_message_service.dart';
import '../services/project_xp_communicator_ui_service.dart';
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
    with WidgetsBindingObserver, RouteAware {
  final Object _globalCommunicatorAlertToken =
      Object();

  PageRoute<dynamic>? _phoneRoute;
  bool _globalCommunicatorAlertSuppressed = false;

  void _suppressGlobalCommunicatorAlert() {
    if (_globalCommunicatorAlertSuppressed) {
      return;
    }

    _globalCommunicatorAlertSuppressed = true;

    ProjectXpCommunicatorUiService
        .suppressGlobalCommunicatorAlert(
      _globalCommunicatorAlertToken,
    );
  }

  void _releaseGlobalCommunicatorAlert() {
    if (!_globalCommunicatorAlertSuppressed) {
      return;
    }

    _globalCommunicatorAlertSuppressed = false;

    ProjectXpCommunicatorUiService
        .releaseGlobalCommunicatorAlert(
      _globalCommunicatorAlertToken,
    );
  }

  final Battery _battery =
      Battery();

  Timer? _clockTimer;

  Timer? _deviceStatusTimer;

  StreamSubscription<BatteryState>?
      _batteryStateSubscription;

  StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription;

  StreamSubscription<BluetoothAdapterState>?
      _bluetoothStateSubscription;

  DateTime _now =
      DateTime.now();

  int? _batteryLevel;

  BatteryState _batteryState =
      BatteryState.unknown;

  List<ConnectivityResult> _connectivity =
      const <ConnectivityResult>[];

  BluetoothAdapterState _bluetoothState =
      BluetoothAdapterState.unknown;

  DeviceStatusSnapshot _deviceStatus =
      DeviceStatusSnapshot.unsupported(
    platform: 'android',
  );

  @override
  void initState() {
    super.initState();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      true,
    );

    _suppressGlobalCommunicatorAlert();

    WidgetsBinding.instance.addObserver(
      this,
    );

    // Le Communicateur XP possède sa propre barre d'état.
    // On masque donc les barres système uniquement sur cet écran.
    unawaited(
      _enterCommunicatorMode(),
    );

    _startClock();
    _initializeBattery();
    _initializeConnectivity();
    _initializeBluetooth();
    _initializeDeviceStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final ModalRoute<dynamic>? modalRoute =
        ModalRoute.of(
      context,
    );

    if (modalRoute is! PageRoute<dynamic>) {
      return;
    }

    if (_phoneRoute != modalRoute) {
      if (_phoneRoute != null) {
        projectXpRouteObserver.unsubscribe(
          this,
        );
      }

      _phoneRoute = modalRoute;

      projectXpRouteObserver.subscribe(
        this,
        modalRoute,
      );
    }

    if (modalRoute.isCurrent) {
      _suppressGlobalCommunicatorAlert();

      ProjectXpCommunicatorUiService
          .setCommunicatorSessionActive(
        true,
      );
    }
  }

  @override
  void didPush() {
    _suppressGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      true,
    );
  }

  @override
  void didPopNext() {
    _suppressGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      true,
    );
  }

  @override
  void didPushNext() {
    _releaseGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      false,
    );
  }

  @override
  void didPop() {
    _releaseGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      false,
    );
  }

  @override
  void dispose() {
    projectXpRouteObserver.unsubscribe(
      this,
    );

    WidgetsBinding.instance.removeObserver(
      this,
    );

    _clockTimer?.cancel();
    _deviceStatusTimer?.cancel();

    _batteryStateSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _bluetoothStateSubscription?.cancel();

    // Dès que le Communicateur XP est rangé, Android/iOS reprend
    // immédiatement le contrôle de sa vraie barre système.
    unawaited(
      _restoreSystemBars(),
    );

    _releaseGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      false,
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
      _refreshConnectivity();
      _refreshBluetooth();
      _refreshDeviceStatus();

      final ModalRoute<dynamic>? route =
          ModalRoute.of(context);

      if (route?.isCurrent ?? false) {
        unawaited(
          _enterCommunicatorMode(),
        );
      }
    }
  }

  // ===========================================================================
  // BARRES SYSTÈME / MODE COMMUNICATEUR
  // ===========================================================================

  Future<void> _enterCommunicatorMode() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _restoreSystemBars() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  Future<void> _openPhoneApp(
    Widget screen,
  ) async {
    // Les applications ouvertes depuis le Communicateur ne sont plus
    // "dans le téléphone" visuellement : on rend donc la vraie barre
    // Android/iOS avant d'afficher l'écran.
    await _restoreSystemBars();

    if (!mounted) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          BuildContext context,
        ) {
          return screen;
        },
      ),
    );

    // Retour sur l'accueil du Communicateur :
    // on remasque immédiatement les barres système.
    if (!mounted) {
      return;
    }

    await _enterCommunicatorMode();
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

    if (_deviceStatus.powerSaveMode ==
        true) {
      return Icons.battery_saver_rounded;
    }

    return Icons.battery_full;
  }

  String get _batteryTooltip {
    if (_isCharging) {
      return 'Batterie en charge';
    }

    if (_deviceStatus.powerSaveMode ==
        true) {
      return 'Économie d’énergie activée';
    }

    return 'Batterie';
  }

  // ===========================================================================
  // RÉSEAU RÉEL
  // ===========================================================================

  Future<void> _initializeConnectivity() async {
    await _refreshConnectivity();

    _connectivitySubscription =
        Connectivity()
            .onConnectivityChanged
            .listen(
      (
        List<ConnectivityResult> results,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _connectivity = results;
        });
      },
    );
  }

  Future<void> _refreshConnectivity() async {
    try {
      final List<ConnectivityResult> results =
          await Connectivity().checkConnectivity();

      if (!mounted) {
        return;
      }

      setState(() {
        _connectivity = results;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connectivity =
            const <ConnectivityResult>[];
      });
    }
  }

  bool get _hasWifi {
    return _connectivity.contains(
      ConnectivityResult.wifi,
    );
  }

  bool get _hasMobile {
    return _connectivity.contains(
      ConnectivityResult.mobile,
    );
  }

  bool get _hasEthernet {
    return _connectivity.contains(
      ConnectivityResult.ethernet,
    );
  }

  bool get _hasNetwork {
    return _connectivity.any(
      (
        ConnectivityResult result,
      ) =>
          result !=
          ConnectivityResult.none,
    );
  }

  IconData get _networkIcon {
    if (_hasWifi) {
      return Icons.wifi_rounded;
    }

    if (_hasMobile) {
      return Icons.signal_cellular_alt_rounded;
    }

    if (_hasEthernet) {
      return Icons.settings_ethernet_rounded;
    }

    return Icons.signal_wifi_off_rounded;
  }

  String get _networkLabel {
    if (_hasWifi) {
      return 'Wi-Fi';
    }

    if (_hasMobile) {
      return 'Mobile';
    }

    if (_hasEthernet) {
      return 'Ethernet';
    }

    return 'Hors ligne';
  }

  // ===========================================================================
  // BLUETOOTH RÉEL
  // ===========================================================================

  Future<void> _initializeBluetooth() async {
    await _refreshBluetooth();

    _bluetoothStateSubscription =
        FlutterBluePlus.adapterState.listen(
      (
        BluetoothAdapterState state,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _bluetoothState = state;
        });
      },
      onError: (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _bluetoothState =
              BluetoothAdapterState.unknown;
        });
      },
    );
  }

  Future<void> _refreshBluetooth() async {
    try {
      final BluetoothAdapterState state =
          FlutterBluePlus.adapterStateNow;

      if (!mounted) {
        return;
      }

      setState(() {
        _bluetoothState = state;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _bluetoothState =
            BluetoothAdapterState.unknown;
      });
    }
  }

  bool get _bluetoothEnabled {
    return _bluetoothState ==
        BluetoothAdapterState.on;
  }

  // ===========================================================================
  // ÉTATS SYSTÈME RÉELS DU TÉLÉPHONE
  // ===========================================================================

  void _initializeDeviceStatus() {
    _refreshDeviceStatus();

    _deviceStatusTimer =
        Timer.periodic(
      const Duration(
        seconds: 2,
      ),
      (_) {
        _refreshDeviceStatus();
      },
    );
  }

  Future<void> _refreshDeviceStatus() async {
    final DeviceStatusSnapshot snapshot =
        await DeviceStatusService
            .instance
            .getSnapshot();

    if (!mounted) {
      return;
    }

    setState(() {
      _deviceStatus = snapshot;
    });
  }

  String _formatAlarmTime(
    DateTime alarm,
  ) {
    final String hour =
        alarm.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String minute =
        alarm.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$hour:$minute';
  }

  List<Widget> _buildNativeModeIcons() {
    final List<Widget> icons =
        <Widget>[];

    void addMode({
      required IconData icon,
      required String tooltip,
      Color color = Colors.white70,
    }) {
      if (icons.isNotEmpty) {
        icons.add(
          const SizedBox(
            width: 5,
          ),
        );
      }

      icons.add(
        Tooltip(
          message: tooltip,
          child: Icon(
            icon,
            color: color,
            size: 15,
          ),
        ),
      );
    }

    if (_deviceStatus
            .screenRecordingActive ==
        true) {
      addMode(
        icon:
            Icons.fiber_manual_record_rounded,
        tooltip:
            'Enregistrement d’écran actif',
        color:
            Colors.redAccent,
      );
    }

    if (_deviceStatus.airplaneMode ==
        true) {
      addMode(
        icon:
            Icons.flight_rounded,
        tooltip:
            'Mode avion activé',
      );
    }

    if (_deviceStatus.dndEnabled) {
      addMode(
        icon:
            Icons.do_not_disturb_on_rounded,
        tooltip:
            'Ne pas déranger activé',
      );
    }

    if (_deviceStatus.isSilent) {
      addMode(
        icon:
            Icons.volume_off_rounded,
        tooltip:
            'Téléphone en silencieux',
      );
    } else if (_deviceStatus.isVibrate) {
      addMode(
        icon:
            Icons.vibration_rounded,
        tooltip:
            'Téléphone en vibreur',
      );
    }

    if (_deviceStatus.dataSaverEnabled) {
      addMode(
        icon:
            Icons.data_saver_on_rounded,
        tooltip:
            'Économiseur de données activé',
      );
    }

    if (_deviceStatus.vpnActive ==
        true) {
      addMode(
        icon:
            Icons.vpn_key_rounded,
        tooltip:
            'VPN actif',
      );
    }

    if (_deviceStatus.nfcEnabled ==
        true) {
      addMode(
        icon:
            Icons.nfc_rounded,
        tooltip:
            'NFC activé',
      );
    }

    if (_deviceStatus.hotspotReadable &&
        _deviceStatus.hotspotActive ==
            true) {
      addMode(
        icon:
            Icons.wifi_tethering_rounded,
        tooltip:
            'Point d’accès personnel actif',
      );
    }

    // Comme sur beaucoup de téléphones Android, on n'affiche
    // rien quand la rotation automatique est active. En revanche,
    // si elle est désactivée, on montre clairement un verrouillage
    // d'orientation — pas une icône ambiguë de rotation.
    if (_deviceStatus.rotationLocked ==
        false) {
      addMode(
        icon:
            Icons.screen_lock_portrait_rounded,
        tooltip:
            'Rotation automatique désactivée',
      );
    }

    final DateTime? nextAlarm =
        _deviceStatus.nextAlarmAt;

    if (nextAlarm != null) {
      addMode(
        icon:
            Icons.alarm_rounded,
        tooltip:
            'Prochaine alarme : '
            '${_formatAlarmTime(nextAlarm)}',
      );
    }

    return icons;
  }

  // ===========================================================================
  // NAVIGATION DES "APPS"
  // ===========================================================================

  Future<void> _openFriends() async {
    await _openPhoneApp(
      const FriendsScreen(),
    );
  }

  Future<void> _openFriendRequests() async {
    await _openPhoneApp(
      const FriendRequestsScreen(),
    );
  }

  Future<void> _openMessages() async {
    await _openPhoneApp(
      const MessagesScreen(),
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
              _buildTopNavigation(),

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
  // BARRE D'ÉTAT DU COMMUNICATEUR
  //
  // Heure + batterie sont déjà réelles.
  // Les prochains indicateurs (réseau réel, Bluetooth, alarme, etc.)
  // seront branchés sur les états natifs du téléphone : aucun faux état.
  // ===========================================================================

  Widget _buildStatusBar() {
    final String batteryText =
        _batteryLevel == null
            ? '--%'
            : '${_batteryLevel!}%';

    final List<Widget> nativeIcons =
        _buildNativeModeIcons();

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        8,
        12,
        2,
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

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Align(
              alignment:
                  Alignment.centerRight,
              child: FittedBox(
                fit:
                    BoxFit.scaleDown,
                alignment:
                    Alignment.centerRight,
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    ...nativeIcons,

                    if (nativeIcons
                        .isNotEmpty)
                      const SizedBox(
                        width: 6,
                      ),

                    if (_bluetoothEnabled) ...[
                      const Tooltip(
                        message:
                            'Bluetooth activé',
                        child: Icon(
                          Icons
                              .bluetooth_rounded,
                          color:
                              Colors.white70,
                          size: 15,
                        ),
                      ),
                      const SizedBox(
                        width: 6,
                      ),
                    ],

                    Tooltip(
                      message:
                          _networkLabel,
                      child: Icon(
                        _networkIcon,
                        color: _hasNetwork
                            ? Colors.white70
                            : Colors.white38,
                        size: 16,
                      ),
                    ),

                    const SizedBox(
                      width: 7,
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

                    Tooltip(
                      message:
                          _batteryTooltip,
                      child: Icon(
                        _batteryIcon,
                        color: _isCharging ||
                                _deviceStatus
                                        .powerSaveMode ==
                                    true
                            ? const Color(
                                0xffffd27a,
                              )
                            : Colors.white70,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavigation() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        8,
        2,
        8,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip:
                'Retour',
            onPressed: () async {
              await _restoreSystemBars();

              if (!mounted) {
                return;
              }

              await Navigator.maybePop(
                context,
              );
            },
            icon: const Icon(
              Icons.arrow_back_rounded,
              color:
                  Colors.white70,
            ),
          ),

          const Spacer(),

          const Text(
            'Communicateur',
            style:
                TextStyle(
              color:
                  Colors.white54,
              fontSize: 12,
              fontWeight:
                  FontWeight.w600,
              letterSpacing: 0.4,
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
      child: Center(
        child: Container(
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
