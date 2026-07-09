import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 메시지 수신 시 isolate에서 호출된다.
}

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize({
    required String fallbackBaseUrl,
    required ValueChanged<String> onOpenUrl,
  }) async {
    if (_isInitialized) {
      return;
    }

    if (Firebase.apps.isEmpty) {
      debugPrint('FCM 비활성화: Firebase 앱이 초기화되지 않았습니다.');
      _isInitialized = true;
      return;
    }

    final FirebaseMessaging? messaging = _safeMessagingInstance();
    if (messaging == null) {
      debugPrint('FCM 비활성화: FirebaseMessaging 인스턴스를 생성할 수 없습니다.');
      _isInitialized = true;
      return;
    }

    await _requestPermission();
    await _initializeLocalNotifications(onOpenUrl, fallbackBaseUrl);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final String targetUrl = _extractTargetUrl(message, fallbackBaseUrl);
      onOpenUrl(targetUrl);
    });

    final String? token = await messaging.getToken();
    if (token != null) {
      debugPrint('FCM token: $token');
      // TODO: Laravel API(/api/v1/fcm-token) 연동 시 서버로 토큰 전송.
    }

    messaging.onTokenRefresh.listen((String refreshedToken) {
      debugPrint('FCM token refreshed: $refreshedToken');
      // TODO: 토큰 갱신 시 서버 갱신 호출.
    });

    _isInitialized = true;
  }

  static Future<String> getInitialTargetUrl({
    required String fallbackBaseUrl,
  }) async {
    if (Firebase.apps.isEmpty) {
      return fallbackBaseUrl;
    }

    RemoteMessage? initialMessage;
    try {
      initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    } catch (_) {
      return fallbackBaseUrl;
    }

    if (initialMessage == null) {
      return fallbackBaseUrl;
    }

    return _extractTargetUrl(initialMessage, fallbackBaseUrl);
  }

  Future<void> _requestPermission() async {
    final FirebaseMessaging? messaging = _safeMessagingInstance();
    if (messaging == null) {
      return;
    }

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  FirebaseMessaging? _safeMessagingInstance() {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> _initializeLocalNotifications(
    ValueChanged<String> onOpenUrl,
    String fallbackBaseUrl,
  ) async {
    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInitSettings =
        DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload == null || payload.isEmpty) {
          onOpenUrl(fallbackBaseUrl);
          return;
        }

        try {
          final Map<String, dynamic> data =
              jsonDecode(payload) as Map<String, dynamic>;
          final String targetUrl = _extractTargetUrlFromMap(
            data,
            fallbackBaseUrl,
          );
          onOpenUrl(targetUrl);
        } catch (_) {
          onOpenUrl(fallbackBaseUrl);
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'apt_community_channel',
      '아파인드 알림',
      description: '커뮤니티 앱 기본 알림 채널',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    if (notification == null) {
      return;
    }

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'apt_community_channel',
        '아파인드 알림',
        channelDescription: '커뮤니티 앱 기본 알림 채널',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  static String _extractTargetUrl(
    RemoteMessage message,
    String fallbackBaseUrl,
  ) {
    return _extractTargetUrlFromMap(message.data, fallbackBaseUrl);
  }

  static String _extractTargetUrlFromMap(
    Map<String, dynamic> data,
    String fallbackBaseUrl,
  ) {
    final String? rawUrl = data['url']?.toString();

    if (rawUrl == null || rawUrl.isEmpty) {
      return fallbackBaseUrl;
    }

    final Uri? parsed = Uri.tryParse(rawUrl);
    if (parsed == null) {
      return fallbackBaseUrl;
    }

    if (parsed.hasScheme) {
      return rawUrl;
    }

    final Uri baseUri = Uri.parse(fallbackBaseUrl);
    return baseUri.resolveUri(parsed).toString();
  }
}
