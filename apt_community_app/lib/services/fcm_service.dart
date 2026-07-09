import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 메시지 수신 시 isolate에서 호출된다.
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // 설정 파일 누락 등으로 초기화 실패 시 백그라운드 처리를 생략한다.
    }
  }
}

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  static const String pushEnabledKey = 'settings.push.enabled';
  static const String commentEnabledKey = 'settings.push.comment';
  static const String noticeEnabledKey = 'settings.push.notice';
  static const String eventEnabledKey = 'settings.push.event';

  static const String _commentTopic = 'apt_comment';
  static const String _noticeTopic = 'apt_notice';
  static const String _eventTopic = 'apt_event';
  static const String _authTokenKey = 'auth_token';
  static const String _lastFcmTokenKey = 'fcm.last.token';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _messaging;
  Uri? _fcmTokenEndpoint;
  bool _isInitialized = false;
  bool _pushEnabled = true;
  bool _commentEnabled = true;
  bool _noticeEnabled = true;
  bool _eventEnabled = true;

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

    _messaging = messaging;
    _fcmTokenEndpoint = _resolveFcmTokenEndpoint(fallbackBaseUrl);

    await _loadPreferenceCache();

    if (_pushEnabled) {
      await _requestPermission();
    }
    await _initializeLocalNotifications(onOpenUrl, fallbackBaseUrl);
    await _syncTopicSubscriptions();

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (!_pushEnabled) {
        return;
      }
      final String targetUrl = _extractTargetUrl(message, fallbackBaseUrl);
      onOpenUrl(targetUrl);
    });

    await _printCurrentToken();

    messaging.onTokenRefresh.listen((String refreshedToken) {
      if (_pushEnabled) {
        debugPrint('FCM token refreshed: $refreshedToken');
        _syncTokenWithBackend(token: refreshedToken, pushEnabled: true);
      }
    });

    _isInitialized = true;
  }

  Future<void> applyPreferenceChanges({
    bool? pushEnabled,
    bool? commentEnabled,
    bool? noticeEnabled,
    bool? eventEnabled,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (pushEnabled != null) {
      _pushEnabled = pushEnabled;
      await prefs.setBool(pushEnabledKey, pushEnabled);
    }
    if (commentEnabled != null) {
      _commentEnabled = commentEnabled;
      await prefs.setBool(commentEnabledKey, commentEnabled);
    }
    if (noticeEnabled != null) {
      _noticeEnabled = noticeEnabled;
      await prefs.setBool(noticeEnabledKey, noticeEnabled);
    }
    if (eventEnabled != null) {
      _eventEnabled = eventEnabled;
      await prefs.setBool(eventEnabledKey, eventEnabled);
    }

    await _syncTopicSubscriptions();

    if (_pushEnabled) {
      await _requestPermission();
      await _printCurrentToken();
      return;
    }

    final String? currentToken = await _messaging?.getToken();
    await _syncTokenWithBackend(token: currentToken, pushEnabled: false);

    await _localNotifications.cancelAll();
    final FirebaseMessaging? messaging = _messaging;
    if (messaging != null) {
      await messaging.deleteToken();
      debugPrint('FCM token deleted: push disabled');
    }
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
    final FirebaseMessaging? messaging = _messaging ?? _safeMessagingInstance();
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

  Future<void> _loadPreferenceCache() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _pushEnabled = prefs.getBool(pushEnabledKey) ?? true;
    _commentEnabled = prefs.getBool(commentEnabledKey) ?? true;
    _noticeEnabled = prefs.getBool(noticeEnabledKey) ?? true;
    _eventEnabled = prefs.getBool(eventEnabledKey) ?? true;
  }

  Future<void> _syncTopicSubscriptions() async {
    final FirebaseMessaging? messaging = _messaging;
    if (messaging == null) {
      return;
    }

    if (!await _canSyncTopics(messaging)) {
      return;
    }

    final Map<String, bool> topicStates = <String, bool>{
      _commentTopic: _pushEnabled && _commentEnabled,
      _noticeTopic: _pushEnabled && _noticeEnabled,
      _eventTopic: _pushEnabled && _eventEnabled,
    };

    for (final MapEntry<String, bool> entry in topicStates.entries) {
      try {
        if (entry.value) {
          await messaging.subscribeToTopic(entry.key);
        } else {
          await messaging.unsubscribeFromTopic(entry.key);
        }
      } catch (error) {
        debugPrint('FCM topic sync skipped for ${entry.key}: $error');
      }
    }
  }

  Future<void> _printCurrentToken() async {
    if (!_pushEnabled) {
      return;
    }

    final FirebaseMessaging? messaging = _messaging;
    if (messaging == null) {
      return;
    }

    String? token;
    try {
      token = await messaging.getToken();
    } catch (error) {
      debugPrint('FCM token fetch skipped: $error');
      return;
    }

    if (token != null) {
      debugPrint('FCM token: $token');
      await _syncTokenWithBackend(token: token, pushEnabled: true);
    }
  }

  Future<bool> _canSyncTopics(FirebaseMessaging messaging) async {
    final bool isApplePlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (!isApplePlatform) {
      return true;
    }

    try {
      final String? apnsToken = await messaging.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        debugPrint('FCM topic sync deferred: APNS token is not ready yet.');
        return false;
      }
      return true;
    } catch (error) {
      debugPrint('FCM topic sync deferred: $error');
      return false;
    }
  }

  Uri _resolveFcmTokenEndpoint(String fallbackBaseUrl) {
    final Uri baseUri = Uri.parse(fallbackBaseUrl);
    return baseUri.resolve('/api/v1/fcm-token');
  }

  Future<void> _syncTokenWithBackend({
    required String? token,
    required bool pushEnabled,
  }) async {
    final Uri? endpoint = _fcmTokenEndpoint;
    if (endpoint == null) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? authToken = prefs.getString(_authTokenKey);

    if (authToken == null || authToken.isEmpty) {
      debugPrint('FCM backend sync skipped: auth token not found');
      return;
    }

    final String? effectiveToken = token ?? prefs.getString(_lastFcmTokenKey);

    final Map<String, dynamic> body = <String, dynamic>{
      'token': effectiveToken,
      'push_enabled': pushEnabled,
      'platform': _platformName(),
      'topics': _enabledTopics(),
    };

    try {
      final http.Response response = await http.post(
        endpoint,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (effectiveToken != null && effectiveToken.isNotEmpty) {
          await prefs.setString(_lastFcmTokenKey, effectiveToken);
        }
        debugPrint('FCM backend sync success: ${response.statusCode}');
        return;
      }

      debugPrint(
        'FCM backend sync failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      debugPrint('FCM backend sync error: $error');
    }
  }

  List<String> _enabledTopics() {
    if (!_pushEnabled) {
      return <String>[];
    }

    return <String>[
      if (_commentEnabled) _commentTopic,
      if (_noticeEnabled) _noticeTopic,
      if (_eventEnabled) _eventTopic,
    ];
  }

  String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
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
    if (!_pushEnabled) {
      return;
    }

    if (!_isMessageAllowedByCategory(message.data)) {
      return;
    }

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
    final Map<String, dynamic> mergedData = <String, dynamic>{
      ...message.data,
      if (message.notification?.android?.link != null)
        'url': message.notification!.android!.link.toString(),
      if (message.notification?.apple?.imageUrl != null)
        'image_url': message.notification!.apple!.imageUrl,
    };

    return _extractTargetUrlFromMap(mergedData, fallbackBaseUrl);
  }

  static String _extractTargetUrlFromMap(
    Map<String, dynamic> data,
    String fallbackBaseUrl,
  ) {
    final String? rawUrl =
        data['url']?.toString() ??
        data['deep_link']?.toString() ??
        data['link']?.toString();

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

  bool _isMessageAllowedByCategory(Map<String, dynamic> data) {
    final String category =
        (data['type'] ?? data['category'] ?? data['notificationType'] ?? '')
            .toString()
            .toLowerCase();

    if (category.contains('comment')) {
      return _commentEnabled;
    }
    if (category.contains('notice')) {
      return _noticeEnabled;
    }
    if (category.contains('event')) {
      return _eventEnabled;
    }
    return true;
  }
}
