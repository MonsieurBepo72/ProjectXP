import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_status_service.dart';
import '../services/friend_service.dart';
import '../services/notification_center_service.dart';
import '../services/phone_wallpaper_service.dart';
import '../services/private_message_service.dart';
import '../services/project_xp_communicator_ui_service.dart';
import 'friend_requests_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'notification_center_screen.dart';

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

  StreamSubscription<int>?
      _notificationCenterCountSubscription;

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

  int _notificationCenterUnreadCount = 0;

  String? _wallpaperPath;
  bool _wallpaperActionInProgress = false;
  _WallpaperPalette _wallpaperPalette =
      _WallpaperPalette.projectXp;

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
    unawaited(
      _refreshNotificationCenterCount(),
    );

    _bindNotificationCenterCounter();

    unawaited(
      _loadWallpaper(),
    );
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

    unawaited(
      _refreshNotificationCenterCount(),
    );
  }

  @override
  void didPushNext() {
    // Les écrans Messages / Amis / Demandes / Notifications font toujours
    // partie du Communicateur XP. On garde donc le téléphone global masqué :
    // afficher un autre téléphone au-dessus du téléphone serait redondant.
    _suppressGlobalCommunicatorAlert();

    ProjectXpCommunicatorUiService
        .setCommunicatorSessionActive(
      true,
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
    _notificationCenterCountSubscription?.cancel();

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
      unawaited(
        _refreshNotificationCenterCount(),
      );

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

  Future<void> _openNotifications() async {
    await _openPhoneApp(
      const NotificationCenterScreen(),
    );

    if (!mounted) {
      return;
    }

    await _refreshNotificationCenterCount();
  }

  Future<void> _refreshNotificationCenterCount() async {
    final int count =
        await NotificationCenterService.unreadCount();

    if (!mounted) {
      return;
    }

    setState(() {
      _notificationCenterUnreadCount =
          count < 0 ? 0 : count;
    });
  }

  void _bindNotificationCenterCounter() {
    _notificationCenterCountSubscription?.cancel();

    _notificationCenterCountSubscription =
        NotificationCenterService
            .unreadCountStream()
            .listen(
      (int count) {
        if (!mounted) {
          return;
        }

        setState(() {
          _notificationCenterUnreadCount =
              count < 0 ? 0 : count;
        });
      },
      onError: (Object error) {
        debugPrint(
          'Compteur Notifications du Communicateur indisponible : $error',
        );
      },
    );
  }

  Future<void> _loadWallpaper() async {
    final String? path =
        await PhoneWallpaperService
            .loadCurrentWallpaperPath();

    final _WallpaperPalette palette =
        await _deriveWallpaperPalette(path);

    if (!mounted) {
      return;
    }

    setState(() {
      _wallpaperPath = path;
      _wallpaperPalette = palette;
    });
  }

  Future<_WallpaperPalette> _deriveWallpaperPalette(
    String? path,
  ) async {
    if (path == null || path.isEmpty) {
      return _WallpaperPalette.projectXp;
    }

    try {
      final File file = File(path);

      if (!await file.exists()) {
        return _WallpaperPalette.projectXp;
      }

      final ui.Codec codec =
          await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 48,
        targetHeight: 48,
      );

      final ui.FrameInfo frame =
          await codec.getNextFrame();

      final ByteData? data =
          await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      frame.image.dispose();
      codec.dispose();

      if (data == null) {
        return _WallpaperPalette.projectXp;
      }

      final Uint8List bytes =
          data.buffer.asUint8List();

      int red = 0;
      int green = 0;
      int blue = 0;
      int samples = 0;

      for (int index = 0;
          index + 3 < bytes.length;
          index += 4) {
        final int alpha = bytes[index + 3];

        if (alpha < 40) {
          continue;
        }

        red += bytes[index];
        green += bytes[index + 1];
        blue += bytes[index + 2];
        samples++;
      }

      if (samples == 0) {
        return _WallpaperPalette.projectXp;
      }

      final Color average = Color.fromARGB(
        255,
        red ~/ samples,
        green ~/ samples,
        blue ~/ samples,
      );

      return _WallpaperPalette.fromAverage(
        average,
      );
    } catch (_) {
      return _WallpaperPalette.projectXp;
    }
  }

  Future<void> _openWallpaperSettings() async {
    if (_wallpaperActionInProgress) {
      return;
    }

    final String? action =
        await showModalBottomSheet<String>(
      context: context,
      backgroundColor:
          const Color(0xff21150e),
      shape:
          const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              18,
              14,
              18,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FOND D’ÉCRAN',
                  style: TextStyle(
                    color: Color(0xffffd27a),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Personnalise ton Communicateur XP avec une image de ta galerie.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(0xffffd27a),
                  ),
                  title: const Text(
                    'Choisir une image',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Galerie du téléphone',
                    style: TextStyle(
                      color: Colors.white38,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      'pick',
                    );
                  },
                ),
                if (_wallpaperPath != null)
                  ListTile(
                    leading: const Icon(
                      Icons.restart_alt_rounded,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Fond Project XP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Revenir au fond par défaut',
                      style: TextStyle(
                        color: Colors.white38,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(
                        sheetContext,
                        'reset',
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }

    setState(() {
      _wallpaperActionInProgress = true;
    });

    try {
      if (action == 'pick') {
        final String? path =
            await PhoneWallpaperService
                .pickAndSaveCurrentWallpaper();

        if (!mounted || path == null) {
          return;
        }

        final _WallpaperPalette palette =
            await _deriveWallpaperPalette(path);

        if (!mounted) {
          return;
        }

        setState(() {
          _wallpaperPath = path;
          _wallpaperPalette = palette;
        });

        _showWallpaperMessage(
          'Fond d’écran du Communicateur mis à jour.',
        );
      } else if (action == 'reset') {
        await PhoneWallpaperService
            .clearCurrentWallpaper();

        if (!mounted) {
          return;
        }

        setState(() {
          _wallpaperPath = null;
          _wallpaperPalette =
              _WallpaperPalette.projectXp;
        });

        _showWallpaperMessage(
          'Fond Project XP restauré.',
        );
      }
    } catch (_) {
      _showWallpaperMessage(
        'Impossible de modifier le fond d’écran pour le moment.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _wallpaperActionInProgress = false;
        });
      }
    }
  }

  void _showWallpaperMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Widget _buildPhoneBackground() {
    final String? path =
        _wallpaperPath;

    if (path == null || path.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xff21150e),
              Color(0xff130c08),
              Color(0xff090605),
            ],
          ),
        ),
      );
    }

    final File file = File(path);

    if (!file.existsSync()) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xff21150e),
              Color(0xff130c08),
              Color(0xff090605),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          file,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0x99000000),
                Color(0x66000000),
                Color(0xaa000000),
              ],
            ),
          ),
        ),
      ],
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPhoneBackground(),
          SafeArea(
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
        ],
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

          IconButton(
            tooltip: 'Fond d’écran',
            onPressed: _wallpaperActionInProgress
                ? null
                : _openWallpaperSettings,
            icon: const Icon(
              Icons.wallpaper_rounded,
              color: Colors.white70,
            ),
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
              palette:
                  _wallpaperPalette,
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
              palette:
                  _wallpaperPalette,
            );
          },
        ),

        _PhoneAppIcon(
          label: 'Amis',
          icon:
              Icons.people_alt_rounded,
          onTap:
              _openFriends,
          palette:
              _wallpaperPalette,
        ),

        _PhoneAppIcon(
          label: 'Notifications',
          icon:
              Icons.notifications_rounded,
          badgeCount:
              _notificationCenterUnreadCount,
          onTap:
              _openNotifications,
          palette:
              _wallpaperPalette,
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

class _WallpaperPalette {
  const _WallpaperPalette({
    required this.tileColor,
    required this.borderColor,
    required this.iconColor,
    required this.labelColor,
    required this.badgeBorderColor,
  });

  final Color tileColor;
  final Color borderColor;
  final Color iconColor;
  final Color labelColor;
  final Color badgeBorderColor;

  static const _WallpaperPalette projectXp =
      _WallpaperPalette(
    tileColor: Color(0xff2c1c13),
    borderColor: Color(0xff6a4327),
    iconColor: Color(0xffffd27a),
    labelColor: Colors.white,
    badgeBorderColor: Color(0xff130c08),
  );

  factory _WallpaperPalette.fromAverage(
    Color average,
  ) {
    final bool isLight =
        average.computeLuminance() >= 0.52;

    final Color tile = Color.lerp(
          average,
          isLight ? Colors.white : Colors.black,
          isLight ? 0.66 : 0.52,
        ) ??
        average;

    final Color icon = Color.lerp(
          average,
          isLight ? Colors.black : Colors.white,
          isLight ? 0.78 : 0.82,
        ) ??
        (isLight ? Colors.black : Colors.white);

    final Color border = Color.lerp(
          average,
          isLight ? Colors.black : Colors.white,
          isLight ? 0.28 : 0.34,
        ) ??
        icon;

    return _WallpaperPalette(
      tileColor: tile.withValues(alpha: 0.86),
      borderColor: border.withValues(alpha: 0.72),
      iconColor: icon,
      labelColor: Colors.white,
      badgeBorderColor:
          isLight ? Colors.white : Colors.black,
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
    required this.palette,
    this.badgeCount = 0,
  });

  final String label;

  final IconData icon;

  final VoidCallback onTap;

  final _WallpaperPalette palette;

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
                        palette.tileColor,
                    borderRadius:
                        BorderRadius.circular(
                      22,
                    ),
                    border:
                        Border.all(
                      color:
                          palette.borderColor,
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
                        palette.iconColor,
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
                              palette.badgeBorderColor,
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
                  TextStyle(
                color:
                    palette.labelColor,
                fontSize: 12,
                fontWeight:
                    FontWeight.w700,
                shadows:
                    const <Shadow>[
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
