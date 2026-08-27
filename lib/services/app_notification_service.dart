import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'computer_settings_service.dart';
import 'push_device_token_service.dart';

class ProjectXpInAppNotification {
  final String title;
  final String body;
  final String? payload;
  final Map<String, dynamic> data;

  const ProjectXpInAppNotification({
    required this.title,
    required this.body,
    required this.payload,
    this.data = const <String, dynamic>{},
  });
}

class ProjectXpNotificationTap {
  final String? payload;
  final Map<String, dynamic> data;
  final bool coldStart;

  const ProjectXpNotificationTap({
    required this.payload,
    this.data = const <String, dynamic>{},
    this.coldStart = false,
  });
}

class AppNotificationService with WidgetsBindingObserver {
  AppNotificationService._();

  static final AppNotificationService instance =
      AppNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  final StreamController<ProjectXpInAppNotification>
      _inAppNotificationController =
      StreamController<ProjectXpInAppNotification>.broadcast();

  final StreamController<ProjectXpNotificationTap>
      _notificationTapController =
      StreamController<ProjectXpNotificationTap>.broadcast();

  final List<ProjectXpNotificationTap>
      _pendingNotificationTaps =
      <ProjectXpNotificationTap>[];

  bool _initialized = false;
  bool _isAppInForeground = true;
  bool _notificationTapUiReady = false;

  Stream<ProjectXpInAppNotification>
      get inAppNotifications =>
          _inAppNotificationController.stream;

  Stream<ProjectXpNotificationTap>
      get notificationTaps =>
          _notificationTapController.stream;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  String? _lastKnownFcmToken;

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

    WidgetsBinding.instance.addObserver(this);
    _isAppInForeground = true;

    // =========================================================================
    // NOTIFICATIONS LOCALES ANDROID
    // =========================================================================

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

    try {
      final NotificationAppLaunchDetails?
          launchDetails =
          await _plugin
              .getNotificationAppLaunchDetails();

      final NotificationResponse? response =
          launchDetails?.notificationResponse;

      if (launchDetails?.didNotificationLaunchApp ==
              true &&
          response != null) {
        _emitNotificationTap(
          ProjectXpNotificationTap(
            payload: response.payload,
            coldStart: true,
          ),
        );
      }
    } catch (error) {
      debugPrint(
        'Lecture du lancement par notification locale impossible : $error',
      );
    }

    final AndroidFlutterLocalNotificationsPlugin?
        androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      _channel,
    );

    // =========================================================================
    // FIREBASE CLOUD MESSAGING
    // =========================================================================

    await _initializeFirebaseMessaging();

    _initialized = true;
  }

  Future<void> _initializeFirebaseMessaging() async {
    // Android 13+ demande une autorisation explicite.
    // Sur les anciennes versions Android, cette demande ne bloque pas.
    final NotificationSettings permission =
        await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    debugPrint(
      'FCM autorisation : ${permission.authorizationStatus}',
    );

    // Le token identifie cette installation de Project XP auprès de FCM.
    // On l'enregistre automatiquement dans Supabase pour l'utilisateur
    // actuellement connecté.
    try {
      final String? token =
          await _messaging.getToken();

      _lastKnownFcmToken =
          token?.trim();

      debugPrint(
        'FCM TOKEN PROJECT XP : $token',
      );

      if (_lastKnownFcmToken != null &&
          _lastKnownFcmToken!.isNotEmpty) {
        await PushDeviceTokenService.saveToken(
          token: _lastKnownFcmToken!,
        );
      }
    } catch (error) {
      debugPrint(
        'Impossible de récupérer le token FCM : $error',
      );
    }

    // Le token peut changer (réinstallation, restauration, rotation FCM...).
    await _tokenRefreshSubscription?.cancel();

    _tokenRefreshSubscription =
        _messaging.onTokenRefresh.listen(
      (String token) async {
        final String cleanToken =
            token.trim();

        debugPrint(
          'FCM TOKEN RAFRAÎCHI : $cleanToken',
        );

        if (cleanToken.isEmpty) {
          return;
        }

        final String oldToken =
            _lastKnownFcmToken ?? '';

        final bool saved =
            await PushDeviceTokenService.replaceToken(
          oldToken: oldToken,
          newToken: cleanToken,
        );

        if (saved) {
          _lastKnownFcmToken =
              cleanToken;
        }
      },
      onError: (Object error) {
        debugPrint(
          'Erreur rafraîchissement token FCM : $error',
        );
      },
    );

    // Quand Project XP est déjà ouvert, on NE crée plus de notification
    // Android locale. Le message devient un événement interne à Project XP.
    //
    // Plus tard, l'interface globale écoutera ce flux pour faire apparaître
    // le petit Communicateur vibrant en haut des écrans concernés.
    await _foregroundMessageSubscription?.cancel();

    _foregroundMessageSubscription =
        FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
      onError: (Object error) {
        debugPrint(
          'Erreur message FCM au premier plan : $error',
        );
      },
    );

    await _openedAppSubscription?.cancel();

    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(
      (
        RemoteMessage message,
      ) {
        _handleRemoteNotificationTap(
          message,
          coldStart: false,
        );
      },
      onError: (Object error) {
        debugPrint(
          'Erreur ouverture notification FCM : $error',
        );
      },
    );

    try {
      final RemoteMessage? initialMessage =
          await _messaging.getInitialMessage();

      if (initialMessage != null) {
        _handleRemoteNotificationTap(
          initialMessage,
          coldStart: true,
        );
      }
    } catch (error) {
      debugPrint(
        'Lecture de la notification FCM initiale impossible : $error',
      );
    }
  }

  Future<void> _handleForegroundMessage(
    RemoteMessage message,
  ) async {
    debugPrint(
      'FCM reçu au premier plan : ${message.messageId}',
    );

    final RemoteNotification? notification =
        message.notification;

    final String title =
        notification?.title?.trim().isNotEmpty == true
            ? notification!.title!.trim()
            : 'Project XP';

    final String body =
        notification?.body?.trim().isNotEmpty == true
            ? notification!.body!.trim()
            : _bodyFromData(
                message.data,
              );

    if (body.isEmpty ||
        !ComputerSettingsService
            .current.notificationsEnabled) {
      return;
    }

    _emitInAppNotification(
      title: title,
      body: body,
      payload: _payloadFromMessage(
        message,
      ),
      data: message.data,
    );
  }

  void _emitInAppNotification({
    required String title,
    required String body,
    String? payload,
    Map<String, dynamic> data =
        const <String, dynamic>{},
  }) {
    if (_inAppNotificationController.isClosed) {
      return;
    }

    _inAppNotificationController.add(
      ProjectXpInAppNotification(
        title: title,
        body: body,
        payload: payload,
        data: Map<String, dynamic>.unmodifiable(
          data,
        ),
      ),
    );

    debugPrint(
      'Notification Project XP gérée dans l’app : $payload',
    );
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    _isAppInForeground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  String _bodyFromData(
    Map<String, dynamic> data,
  ) {
    final String body =
        data['body']?.toString().trim() ?? '';

    if (body.isNotEmpty) {
      return body;
    }

    final String senderName =
        data['sender_name']?.toString().trim() ?? '';

    if (senderName.isNotEmpty) {
      return '$senderName t’a envoyé un message.';
    }

    return '';
  }

  String? _payloadFromMessage(
    RemoteMessage message,
  ) {
    final String conversationId =
        message.data['conversation_id']
                ?.toString()
                .trim() ??
            '';

    if (conversationId.isNotEmpty) {
      return 'private_message:$conversationId';
    }

    final String type =
        message.data['type']?.toString().trim() ?? '';

    if (type.isNotEmpty) {
      return type;
    }

    return null;
  }

  void _handleRemoteNotificationTap(
    RemoteMessage message, {
    required bool coldStart,
  }) {
    final String? payload =
        _payloadFromMessage(
      message,
    );

    debugPrint(
      'Notification FCM Project XP touchée : $payload',
    );

    _emitNotificationTap(
      ProjectXpNotificationTap(
        payload: payload,
        data:
            Map<String, dynamic>.unmodifiable(
          message.data,
        ),
        coldStart: coldStart,
      ),
    );
  }

  void _onNotificationTapped(
    NotificationResponse response,
  ) {
    debugPrint(
      'Notification Project XP touchée : ${response.payload}',
    );

    _emitNotificationTap(
      ProjectXpNotificationTap(
        payload: response.payload,
      ),
    );
  }

  void _emitNotificationTap(
    ProjectXpNotificationTap event,
  ) {
    if (_notificationTapUiReady) {
      _notificationTapController.add(
        event,
      );

      return;
    }

    _pendingNotificationTaps.add(
      event,
    );
  }

  void markNotificationTapUiReady() {
    _notificationTapUiReady = true;
  }

  List<ProjectXpNotificationTap>
      takePendingNotificationTaps() {
    final List<ProjectXpNotificationTap> pending =
        List<ProjectXpNotificationTap>.from(
      _pendingNotificationTaps,
    );

    _pendingNotificationTaps.clear();

    return pending;
  }

  Future<String?> getFcmToken() async {
    await initialize();

    try {
      return await _messaging.getToken();
    } catch (error) {
      debugPrint(
        'Impossible de lire le token FCM : $error',
      );

      return null;
    }
  }

  Future<bool> areSystemNotificationsEnabled() async {
    final AndroidFlutterLocalNotificationsPlugin?
        androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      return true;
    }

    final bool? enabled =
        await androidPlugin.areNotificationsEnabled();

    return enabled ?? true;
  }

  Future<bool> requestPermission() async {
    await initialize();

    final NotificationSettings fcmPermission =
        await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin?
        androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      return fcmPermission.authorizationStatus ==
              AuthorizationStatus.authorized ||
          fcmPermission.authorizationStatus ==
              AuthorizationStatus.provisional;
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

    if (_isAppInForeground) {
      _emitInAppNotification(
        title: title,
        body: body,
        payload: payload,
      );

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

  Future<void> showCompagnieInvitation(
    String playerName,
  ) async {
    await show(
      title: 'Invitation Compagnie',
      body:
          '$playerName veut rejoindre ton aventure.',
      payload: 'compagnie_invitation',
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

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);

    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _openedAppSubscription?.cancel();

    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    _openedAppSubscription = null;
    _lastKnownFcmToken = null;
    _notificationTapUiReady = false;
    _pendingNotificationTaps.clear();

    _initialized = false;
  }
}
