import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'computer_settings_service.dart';

class AppNotificationService {
  AppNotificationService._();

  static final AppNotificationService instance =
      AppNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId =
      'project_xp_alerts';

  static const String _channelName =
      'Project XP';

  static const String _channelDescription =
      'Invitations, messages et événements de Project XP';

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings(
      'project_xp_notification',
    );

    const InitializationSettings settings =
        InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse:
          _onNotificationTapped,
    );

    final AndroidFlutterLocalNotificationsPlugin?
        androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      _channel,
    );

    _initialized = true;
  }

  void _onNotificationTapped(
    NotificationResponse response,
  ) {
    // Pour l'instant, toucher une notification ouvre
    // simplement Project XP.
    //
    // Plus tard, on pourra utiliser response.payload
    // pour ouvrir directement le Squad, la Taverne,
    // une invitation précise, etc.
  }

  Future<bool> areSystemNotificationsEnabled() async {
    await initialize();

    final AndroidFlutterLocalNotificationsPlugin?
        androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final bool? enabled =
        await androidPlugin?.areNotificationsEnabled();

    return enabled ?? true;
  }

  Future<bool> requestPermission() async {
    await initialize();

    final AndroidFlutterLocalNotificationsPlugin?
        androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      return false;
    }

    final bool alreadyEnabled =
        await areSystemNotificationsEnabled();

    if (alreadyEnabled) {
      return true;
    }

    final bool? granted =
        await androidPlugin
            .requestNotificationsPermission();

    if (granted == true) {
      return true;
    }

    return areSystemNotificationsEnabled();
  }

  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();

    if (!ComputerSettingsService
        .current.notificationsEnabled) {
      return;
    }

    final bool allowed =
        await areSystemNotificationsEnabled();

    if (!allowed) {
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      icon: 'project_xp_notification',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      channelShowBadge: true,
      visibility: NotificationVisibility.public,
    );

    const NotificationDetails details =
        NotificationDetails(
      android: androidDetails,
    );

    final int id =
        DateTime.now().millisecondsSinceEpoch %
            2147483647;

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> showTestNotification() async {
    await show(
      title: 'Project XP',
      body:
          'Les notifications Android sont activées ⚔️',
      payload: 'test',
    );
  }

  Future<void> showSquadInvitation(
    String playerName,
  ) async {
    await show(
      title: 'Invitation Squad',
      body:
          '$playerName veut rejoindre ton aventure.',
      payload: 'squad_invitation',
    );
  }

  Future<void> showMessage(
    String playerName,
  ) async {
    await show(
      title: 'Nouveau message',
      body:
          '$playerName t’a envoyé un message.',
      payload: 'message',
    );
  }
}
