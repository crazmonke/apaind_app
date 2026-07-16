import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_config.dart';
import '../services/fcm_service.dart';
import 'webview_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onOpenUrl,
    required this.onClearWebCache,
    required this.refreshTick,
  });

  final Future<void> Function(String url) onOpenUrl;
  final Future<void> Function() onClearWebCache;
  final ValueListenable<int> refreshTick;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _pushEnabledKey = FcmService.pushEnabledKey;
  static const String _commentEnabledKey = FcmService.commentEnabledKey;
  static const String _noticeEnabledKey = FcmService.noticeEnabledKey;
  static const String _eventEnabledKey = FcmService.eventEnabledKey;

  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _pushEnabled = true;
  bool _commentEnabled = true;
  bool _noticeEnabled = true;
  bool _eventEnabled = true;
  String _appVersion = '-';
  String _fcmToken = '-';

  @override
  void initState() {
    super.initState();
    widget.refreshTick.addListener(_refreshLoginState);
    _loadSettings();
  }

  @override
  void dispose() {
    widget.refreshTick.removeListener(_refreshLoginState);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PackageInfo info = await PackageInfo.fromPlatform();

    setState(() {
      _pushEnabled = prefs.getBool(_pushEnabledKey) ?? true;
      _commentEnabled = prefs.getBool(_commentEnabledKey) ?? true;
      _noticeEnabled = prefs.getBool(_noticeEnabledKey) ?? true;
      _eventEnabled = prefs.getBool(_eventEnabledKey) ?? true;
      _appVersion = '${info.version}+${info.buildNumber}';
      _isLoggedIn = prefs.getBool('is_web_logged_in') ?? false;
      _isLoading = false;
    });

    try {
      final cached = prefs.getString('fcm.last.token');
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() => _fcmToken = cached);
      }
      final token = await _fetchFcmToken();
      if (mounted) setState(() => _fcmToken = token);
    } catch (e) {
      if (mounted) setState(() => _fcmToken = '오류: $e');
    }
  }

  Future<void> _refreshLoginState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = prefs.getBool('is_web_logged_in') ?? false;
    });
  }

  // iOS에서 APNS 토큰이 준비될 때까지 최대 10초 대기 후 FCM 토큰 반환
  Future<String> _fetchFcmToken() async {
    final messaging = FirebaseMessaging.instance;

    // 알림 권한 상태 확인
    final settings = await messaging.getNotificationSettings();
    final authStatus = settings.authorizationStatus;
    if (authStatus != AuthorizationStatus.authorized &&
        authStatus != AuthorizationStatus.provisional) {
      return '알림 권한 없음 (status: $authStatus)';
    }

    if (Platform.isIOS) {
      String? apnsToken;
      for (int i = 0; i < 15; i++) {
        try {
          apnsToken = await messaging.getAPNSToken();
        } catch (e) {
          if (i == 14) return 'APNS 오류: $e';
        }
        if (apnsToken != null && apnsToken.isNotEmpty) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (apnsToken == null || apnsToken.isEmpty) {
        return 'APNS 토큰 없음 (15초 대기 후에도 미발급)';
      }
    }

    final token = await messaging.getToken();
    return token ?? 'FCM 토큰 없음';
  }

  Future<void> _saveBool(String key, bool value) async {    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _togglePush(bool value) async {
    setState(() => _pushEnabled = value);
    await _saveBool(_pushEnabledKey, value);
    await FcmService.instance.applyPreferenceChanges(pushEnabled: value);
  }

  Future<void> _handleClearCache() async {
    await widget.onClearWebCache();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('현재 탭의 WebView 캐시를 초기화했습니다.')));
  }

  Future<void> _handleLogin() async {
    await widget.onOpenUrl('/login');
  }

  Future<void> _handleLogout() async {
    await FcmService.instance.logoutCurrentDevice();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.setBool('is_web_logged_in', false);

    final WebViewCookieManager cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();

    setState(() => _isLoggedIn = false);

    // 홈 탭을 메인 화면으로 이동 (로그인 화면이 아닌)
    await widget.onOpenUrl(kBaseWebUrl);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('로그아웃 되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          '푸시 알림',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('푸시 알림 수신'),
          value: _pushEnabled,
          onChanged: _togglePush,
        ),
        SwitchListTile(
          title: const Text('댓글 알림'),
          value: _commentEnabled,
          onChanged:
              _pushEnabled
                  ? (bool value) async {
                    setState(() => _commentEnabled = value);
                    await _saveBool(_commentEnabledKey, value);
                    await FcmService.instance.applyPreferenceChanges(
                      commentEnabled: value,
                    );
                  }
                  : null,
        ),
        SwitchListTile(
          title: const Text('공지 알림'),
          value: _noticeEnabled,
          onChanged:
              _pushEnabled
                  ? (bool value) async {
                    setState(() => _noticeEnabled = value);
                    await _saveBool(_noticeEnabledKey, value);
                    await FcmService.instance.applyPreferenceChanges(
                      noticeEnabled: value,
                    );
                  }
                  : null,
        ),
        SwitchListTile(
          title: const Text('새 글 알림'),
          value: _eventEnabled,
          onChanged:
              _pushEnabled
                  ? (bool value) async {
                    setState(() => _eventEnabled = value);
                    await _saveBool(_eventEnabledKey, value);
                    await FcmService.instance.applyPreferenceChanges(
                      eventEnabled: value,
                    );
                  }
                  : null,
        ),
        const Divider(height: 24),
        ListTile(
          title: const Text('계정설정'),
          leading: const Icon(Icons.manage_accounts_outlined),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WebViewScreen(
                  initialUrl: 'https://apaind.mycafe24.com/settings?apartment_id=1',
                  showAppBar: true,
                  title: '계정설정',
                ),
              ),
            );
          },
        ),
        ListTile(
          title: const Text('앱 버전'),
          subtitle: Text(_appVersion),
          leading: const Icon(Icons.info_outline),
        ),
        ListTile(
          title: const Text('FCM 토큰 복사'),
          subtitle: Text(
            _fcmToken,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: const Icon(Icons.copy_outlined),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => _fcmToken = '로딩 중...');
              try {
                final token = await _fetchFcmToken();
                if (mounted) setState(() => _fcmToken = token);
              } catch (e) {
                if (mounted) setState(() => _fcmToken = '오류: $e');
              }
            },
          ),
          onTap: () {
            if (_fcmToken == '-' || _fcmToken == '토큰 없음' || _fcmToken == '로딩 중...') return;
            Clipboard.setData(ClipboardData(text: _fcmToken));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('FCM 토큰이 복사되었습니다.')),
            );
          },
        ),
        ListTile(
          title: const Text('앱 캐시 초기화'),
          leading: const Icon(Icons.cleaning_services_outlined),
          onTap: _handleClearCache,
        ),
        ListTile(
          title: const Text('개인정보처리방침'),
          leading: const Icon(Icons.privacy_tip_outlined),
          onTap: () => widget.onOpenUrl('https://apaind.mycafe24.com/community/posts/13'),
        ),
        ListTile(
          title: const Text('이용약관'),
          leading: const Icon(Icons.description_outlined),
          onTap: () => widget.onOpenUrl('https://apaind.mycafe24.com/community/posts/14'),
        ),
        const SizedBox(height: 8),
        if (_isLoggedIn)
          FilledButton.tonalIcon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout),
            label: const Text('로그아웃'),
          )
        else
          FilledButton.icon(
            onPressed: _handleLogin,
            icon: const Icon(Icons.login),
            label: const Text('로그인'),
          ),
      ],
    );
  }
}
