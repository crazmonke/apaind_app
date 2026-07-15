import 'package:flutter/material.dart';

import '../app_config.dart';
import 'settings_screen.dart';
import 'webview_screen.dart';

class HomeShellScreen extends StatefulWidget {
  const HomeShellScreen({
    super.key,
    required this.initialUrl,
    required this.pendingOpenUrl,
  });

  final String initialUrl;
  final ValueNotifier<String?> pendingOpenUrl;

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen> {
  final GlobalKey<WebViewScreenState> _homeKey =
      GlobalKey<WebViewScreenState>();
  final GlobalKey<WebViewScreenState> _communityKey =
      GlobalKey<WebViewScreenState>();
  final GlobalKey<WebViewScreenState> _notificationKey =
      GlobalKey<WebViewScreenState>();
  final ValueNotifier<int> _settingsRefreshTick = ValueNotifier<int>(0);

  late final Uri _baseUri = Uri.parse(kBaseWebUrl);
  late String _homeUrl = kBaseWebUrl;
  late String _communityUrl = _baseUri.resolve('/community').toString();
  late String _notificationUrl = _baseUri.resolve('/notifications').toString();

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.pendingOpenUrl.addListener(_handlePendingUrl);
    _applyTargetUrl(widget.initialUrl, isInitial: true);
  }

  @override
  void dispose() {
    widget.pendingOpenUrl.removeListener(_handlePendingUrl);
    _settingsRefreshTick.dispose();
    super.dispose();
  }

  void _handlePendingUrl() {
    final String? target = widget.pendingOpenUrl.value;
    if (target == null || target.isEmpty) {
      return;
    }

    _applyTargetUrl(target);
  }

  Future<void> _syncAndRefreshSettings() async {
    // 활성 WebView(같은 도메인)의 localStorage에서 auth_token 상태를 SharedPreferences에 동기화
    final WebViewScreenState? webView =
        _homeKey.currentState ??
        _communityKey.currentState ??
        _notificationKey.currentState;
    if (webView != null) {
      await webView.syncAuthToken();
    }
    _settingsRefreshTick.value++;
  }

  Future<void> _openFromSettings(String target) async {
    _applyTargetUrl(target);
  }

  Future<void> _clearCurrentWebCache() async {
    switch (_currentIndex) {
      case 0:
        await _homeKey.currentState?.clearCache();
        break;
      case 1:
        await _communityKey.currentState?.clearCache();
        break;
      case 2:
        await _notificationKey.currentState?.clearCache();
        break;
      default:
        break;
    }
  }

  void _applyTargetUrl(String rawUrl, {bool isInitial = false}) {
    final String normalized = _normalizeUrl(rawUrl);
    final Uri uri = Uri.parse(normalized);
    final int nextTabIndex = _inferTabIndex(uri);

    setState(() {
      _currentIndex = nextTabIndex;
      if (nextTabIndex == 0) {
        _homeUrl = normalized;
      } else if (nextTabIndex == 1) {
        _communityUrl = normalized;
      } else if (nextTabIndex == 2) {
        _notificationUrl = normalized;
      }
    });

    if (!isInitial) {
      if (nextTabIndex == 0) {
        _homeKey.currentState?.openUrl(normalized);
      } else if (nextTabIndex == 1) {
        _communityKey.currentState?.openUrl(normalized);
      } else if (nextTabIndex == 2) {
        _notificationKey.currentState?.openUrl(normalized);
      }
    }
  }

  int _inferTabIndex(Uri uri) {
    final String path = uri.path.toLowerCase();
    if (path.startsWith('/notifications')) {
      return 2;
    }

    if (path.startsWith('/community') ||
        path.startsWith('/board') ||
        path.startsWith('/posts') ||
        path.startsWith('/post')) {
      return 1;
    }

    return 0;
  }

  String _normalizeUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null) {
      return kBaseWebUrl;
    }

    if (uri.hasScheme && uri.scheme != 'aptcommunity') {
      return uri.toString();
    }

    if (uri.scheme == 'aptcommunity') {
      final List<String> segments = <String>[
        if (uri.host.isNotEmpty) uri.host,
        ...uri.pathSegments.where((String segment) => segment.isNotEmpty),
      ];

      if (segments.isEmpty) {
        return kBaseWebUrl;
      }

      if (segments.first == 'post' && segments.length > 1) {
        return _baseUri.resolve('/posts/${segments[1]}').toString();
      }

      if (segments.first == 'notice' && segments.length > 1) {
        return _baseUri.resolve('/notices/${segments[1]}').toString();
      }

      final String joined = segments.join('/');
      return _baseUri.resolve('/$joined').toString();
    }

    return _baseUri.resolveUri(uri).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 3 ? AppBar(title: const Text('설정')) : null,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentIndex,
          children: <Widget>[
            WebViewScreen(key: _homeKey, initialUrl: _homeUrl, showAppBar: false, onOpenUrl: _applyTargetUrl),
            WebViewScreen(
              key: _communityKey,
              initialUrl: _communityUrl,
              showAppBar: false,
              onOpenUrl: _applyTargetUrl,
            ),
            WebViewScreen(
              key: _notificationKey,
              initialUrl: _notificationUrl,
              showAppBar: false,
              onOpenUrl: _applyTargetUrl,
            ),
            SettingsScreen(
              onOpenUrl: _openFromSettings,
              onClearWebCache: _clearCurrentWebCache,
              refreshTick: _settingsRefreshTick,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (int index) {
          setState(() {
            _currentIndex = index;
          });
          if (index == 0) {
            _homeUrl = kBaseWebUrl;
            _homeKey.currentState?.openUrl(kBaseWebUrl);
          } else if (index == 1) {
            final String communityBase = _baseUri.resolve('/community').toString();
            _communityUrl = communityBase;
            _communityKey.currentState?.openUrl(communityBase);
          } else if (index == 2) {
            final String notifBase = _baseUri.resolve('/notifications').toString();
            _notificationUrl = notifBase;
            _notificationKey.currentState?.openUrl(notifBase);
          } else if (index == 3) {
            _syncAndRefreshSettings();
          }
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            label: '커뮤니티',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            label: '알림',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
