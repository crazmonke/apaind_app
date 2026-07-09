import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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

  static const String registerEndpointPath = '/api/v1/fcm-token';
  static const String logoutEndpointPath = '/api/auth/logout';
  static const String pushEnabledKey = 'settings.push.enabled';
  static const String commentEnabledKey = 'settings.push.comment';
  static const String noticeEnabledKey = 'settings.push.notice';
  static const String eventEnabledKey = 'settings.push.event';

  static const String _authTokenKey = 'auth_token';
  static const String _deviceIdKey = 'device.id';
  static const String _lastFcmTokenKey = 'fcm.last.token';

  static const String _commentTopic = 'comment';
  static const String _noticeTopic = 'notice';
  static const String _newPostTopic = 'new_post';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _messaging;
  Uri? _registerEndpoint;
  Uri? _logoutEndpoint;
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
    _registerEndpoint = _resolveEndpoint(fallbackBaseUrl, registerEndpointPath);
    _logoutEndpoint = _resolveEndpoint(fallbackBaseUrl, logoutEndpointPath);

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

    await syncCurrentDeviceRegistration();

    messaging.onTokenRefresh.listen((String refreshedToken) {
      syncCurrentDeviceRegistration(token: refreshedToken);
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
      await syncCurrentDeviceRegistration();
      return;
    }

    await logoutCurrentDevice();
  }

  Future<void> syncCurrentDeviceRegistration({String? token}) async {
    if (!_isInitialized || !_pushEnabled) {
      return;
    }

    final FirebaseMessaging? messaging = _messaging;
    if (messaging == null) {
      return;
    }

    final String? authToken = await _readAuthToken();
    if (authToken == null || authToken.isEmpty) {
      debugPrint('FCM registration skipped: auth token not found');
      return;
    }

    String? currentToken = token;
    try {
      currentToken ??= await messaging.getToken();
    } catch (error) {
      debugPrint('FCM token fetch skipped: $error');
      return;
    }

    if (currentToken == null || currentToken.isEmpty) {
      return;
    }

    final _DeviceMetadata deviceMetadata = await _resolveDeviceMetadata();
    final String appVersion = await _resolveAppVersion();

    await _registerTokenWithBackend(
      authToken: authToken,
      token: currentToken,
      deviceId: deviceMetadata.deviceId,
      deviceName: deviceMetadata.deviceName,
      appVersion: appVersion,
    );
  }

  Future<void> logoutCurrentDevice() async {
    final FirebaseMessaging? messaging = _messaging;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? authToken = prefs.getString(_authTokenKey);

    if (authToken != null && authToken.isNotEmpty) {
      final Uri? endpoint = _logoutEndpoint;
      if (endpoint != null) {
        String? currentToken;
        if (messaging != null) {
          try {
            currentToken = await messaging.getToken();
          } catch (error) {
            debugPrint('FCM logout token fetch skipped: $error');
          }
        }

        final _DeviceMetadata deviceMetadata = await _resolveDeviceMetadata();
        final Map<String, dynamic> body = <String, dynamic>{
          if (currentToken != null && currentToken.isNotEmpty)
            'fcm_token': currentToken,
          'device_id': deviceMetadata.deviceId,
          'device_name': deviceMetadata.deviceName,
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
            debugPrint('FCM backend delete success: ${response.statusCode}');
          } else {
            debugPrint(
              'FCM backend delete failed: ${response.statusCode} ${response.body}',
            );
          }
        } catch (error) {
          debugPrint('FCM backend delete error: $error');
        }
      }
    } else {
      debugPrint('FCM delete skipped: auth token not found');
    }

    if (messaging != null) {
      try {
        await messaging.deleteToken();
      } catch (error) {
        debugPrint('FCM local token delete failed: $error');
      }
    }

    await prefs.remove(_lastFcmTokenKey);
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
      _newPostTopic: _pushEnabled && _eventEnabled,
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

  Uri _resolveEndpoint(String fallbackBaseUrl, String path) {
    final Uri baseUri = Uri.parse(fallbackBaseUrl);
    return baseUri.resolve(path);
  }

  Future<void> _registerTokenWithBackend({
    required String authToken,
    required String token,
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final Uri? endpoint = _registerEndpoint;
    if (endpoint == null) {
      return;
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'token': token,
      'platform': _platformName(),
      'device_id': deviceId,
      'device_name': deviceName,
      'app_version': appVersion,
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
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastFcmTokenKey, token);
        debugPrint('FCM backend register success: ${response.statusCode}');
        return;
      }

      debugPrint(
        'FCM backend register failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      debugPrint('FCM backend register error: $error');
    }
  }

  Future<String?> _readAuthToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  Future<String> _resolveAppVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<_DeviceMetadata> _resolveDeviceMetadata() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String deviceId = prefs.getString(_deviceIdKey) ?? '';
    String deviceName = _fallbackDeviceName();

    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        deviceName = '${androidInfo.brand} ${androidInfo.model}'.trim();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? deviceId;
        deviceName = iosInfo.name.isNotEmpty ? iosInfo.name : 'iPhone';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
        deviceId = macInfo.systemGUID ?? deviceId;
        deviceName =
            macInfo.computerName.isNotEmpty ? macInfo.computerName : 'macOS';
      }
    } catch (error) {
      debugPrint('FCM device metadata fallback used: $error');
    }

    if (deviceId.isEmpty) {
      deviceId = _fallbackDeviceId();
    }

    await prefs.setString(_deviceIdKey, deviceId);
    return _DeviceMetadata(deviceId: deviceId, deviceName: deviceName);
  }

  String _fallbackDeviceId() {
    return 'device-${defaultTargetPlatform.name}-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _fallbackDeviceName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
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
    };

    return _extractTargetUrlFromMap(mergedData, fallbackBaseUrl);
  }

  static String _extractTargetUrlFromMap(
    Map<String, dynamic> data,
    String fallbackBaseUrl,
  ) {
    final String? notificationType =
        data['type']?.toString() ?? data['notificationType']?.toString();
    final String? postId = data['post_id']?.toString();
    final String? rawUrl =
        data['url']?.toString() ??
        data['deep_link']?.toString() ??
        data['link']?.toString();

    final String? routedUrl = _buildRoutedUrl(
      notificationType: notificationType,
      postId: postId,
      fallbackBaseUrl: fallbackBaseUrl,
    );

    if (routedUrl != null) {
      return routedUrl;
    }

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

  static String? _buildRoutedUrl({
    required String? notificationType,
    required String? postId,
    required String fallbackBaseUrl,
  }) {
    if (notificationType == null || notificationType.isEmpty) {
      return null;
    }

    final String normalizedType = notificationType.toLowerCase();
    final bool hasPostId = postId != null && postId.isNotEmpty;
    if (!hasPostId) {
      return null;
    }

    if (normalizedType.contains('notice')) {
      return Uri.parse(fallbackBaseUrl).resolve('/notices/$postId').toString();
    }

    if (normalizedType.contains('new_post') ||
        normalizedType.contains('comment') ||
        normalizedType.contains('post')) {
      return Uri.parse(fallbackBaseUrl).resolve('/posts/$postId').toString();
    }

    return null;
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
    if (category.contains('new_post') || category.contains('post')) {
      return _eventEnabled;
    }
    return true;
  }
}

class _DeviceMetadata {
  const _DeviceMetadata({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;
}
