import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onOpenUrl,
    required this.onClearWebCache,
  });

  final Future<void> Function(String url) onOpenUrl;
  final Future<void> Function() onClearWebCache;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _pushEnabledKey = 'settings.push.enabled';
  static const String _commentEnabledKey = 'settings.push.comment';
  static const String _noticeEnabledKey = 'settings.push.notice';
  static const String _eventEnabledKey = 'settings.push.event';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isLoading = true;
  bool _pushEnabled = true;
  bool _commentEnabled = true;
  bool _noticeEnabled = true;
  bool _eventEnabled = true;
  String _appVersion = '-';

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
      _isLoading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _togglePush(bool value) async {
    setState(() {
      _pushEnabled = value;
    });
    await _saveBool(_pushEnabledKey, value);

    if (!value) {
      await _localNotifications.cancelAll();
    }
  }

  Future<void> _handleClearCache() async {
    await widget.onClearWebCache();
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('현재 탭의 WebView 캐시를 초기화했습니다.')));
  }

  Future<void> _handleLogout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');

    final WebViewCookieManager cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();

    await widget.onOpenUrl('/login');

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('로그아웃 되었습니다. 다시 로그인해 주세요.')));
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
                    setState(() {
                      _commentEnabled = value;
                    });
                    await _saveBool(_commentEnabledKey, value);
                  }
                  : null,
        ),
        SwitchListTile(
          title: const Text('공지 알림'),
          value: _noticeEnabled,
          onChanged:
              _pushEnabled
                  ? (bool value) async {
                    setState(() {
                      _noticeEnabled = value;
                    });
                    await _saveBool(_noticeEnabledKey, value);
                  }
                  : null,
        ),
        SwitchListTile(
          title: const Text('이벤트 알림'),
          value: _eventEnabled,
          onChanged:
              _pushEnabled
                  ? (bool value) async {
                    setState(() {
                      _eventEnabled = value;
                    });
                    await _saveBool(_eventEnabledKey, value);
                  }
                  : null,
        ),
        const Divider(height: 24),
        ListTile(
          title: const Text('앱 버전'),
          subtitle: Text(_appVersion),
          leading: const Icon(Icons.info_outline),
        ),
        ListTile(
          title: const Text('앱 캐시 초기화'),
          leading: const Icon(Icons.cleaning_services_outlined),
          onTap: _handleClearCache,
        ),
        ListTile(
          title: const Text('개인정보처리방침'),
          leading: const Icon(Icons.privacy_tip_outlined),
          onTap: () => widget.onOpenUrl('/privacy'),
        ),
        ListTile(
          title: const Text('이용약관'),
          leading: const Icon(Icons.description_outlined),
          onTap: () => widget.onOpenUrl('/terms'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _handleLogout,
          icon: const Icon(Icons.logout),
          label: const Text('로그아웃'),
        ),
      ],
    );
  }
}
