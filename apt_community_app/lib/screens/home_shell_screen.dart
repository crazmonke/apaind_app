import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/unread_message_service.dart';
import 'search_screen.dart';
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

class _HomeShellScreenState extends State<HomeShellScreen>
    with WidgetsBindingObserver {
  final GlobalKey<WebViewScreenState> _homeKey =
      GlobalKey<WebViewScreenState>();
  final GlobalKey<WebViewScreenState> _communityKey =
      GlobalKey<WebViewScreenState>();
  final GlobalKey<SearchScreenState> _searchKey =
      GlobalKey<SearchScreenState>();
  final GlobalKey<WebViewScreenState> _messageKey =
      GlobalKey<WebViewScreenState>();
  final GlobalKey<WebViewScreenState> _notificationKey =
      GlobalKey<WebViewScreenState>();
  final ValueNotifier<int> _settingsRefreshTick = ValueNotifier<int>(0);

  late final Uri _baseUri = Uri.parse(kBaseWebUrl);
  late String _homeUrl = kBaseWebUrl;
  late String _communityUrl = _baseUri.resolve('/community').toString();
  late String _searchUrl = _baseUri.resolve('/community').toString();
  late String _messageUrl = _baseUri.resolve('/messages').toString();
  late String _notificationUrl = _baseUri.resolve('/notifications').toString();

  int _currentIndex = 0;
  int _unreadMessageCount = 0;
  Timer? _unreadPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pendingOpenUrl.addListener(_handlePendingUrl);
    _applyTargetUrl(widget.initialUrl, isInitial: true);
    _refreshUnreadCount();
    _unreadPollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshUnreadCount(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadPollTimer?.cancel();
    widget.pendingOpenUrl.removeListener(_handlePendingUrl);
    _settingsRefreshTick.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshUnreadCount();
    }
  }

  Future<void> _refreshUnreadCount() async {
    final int? count = await UnreadMessageService.instance.fetchUnreadCount();
    if (!mounted || count == null || count == _unreadMessageCount) {
      return;
    }

    setState(() {
      _unreadMessageCount = count;
    });
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
    switch (_currentIndex) {
      case 0:
        await _homeKey.currentState?.syncAuthToken();
        break;
      case 1:
        await _communityKey.currentState?.syncAuthToken();
        break;
      case 2:
        await _searchKey.currentState?.syncAuthToken();
        break;
      case 3:
        await _messageKey.currentState?.syncAuthToken();
        break;
      case 4:
        await _notificationKey.currentState?.syncAuthToken();
        break;
      default:
        break;
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
        await _searchKey.currentState?.clearCache();
        break;
      case 3:
        await _messageKey.currentState?.clearCache();
        break;
      case 4:
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
        _searchUrl = normalized;
      } else if (nextTabIndex == 3) {
        _messageUrl = normalized;
      } else if (nextTabIndex == 4) {
        _notificationUrl = normalized;
      }
    });

    if (!isInitial) {
      if (nextTabIndex == 0) {
        _homeKey.currentState?.openUrl(normalized);
      } else if (nextTabIndex == 1) {
        _communityKey.currentState?.openUrl(normalized);
      } else if (nextTabIndex == 2) {
        _searchKey.currentState?.openUrl(normalized);
      } else if (nextTabIndex == 3) {
        _messageKey.currentState?.openUrl(normalized);
      } else if (nextTabIndex == 4) {
        _notificationKey.currentState?.openUrl(normalized);
      }
    }

    if (nextTabIndex == 3) {
      _scheduleUnreadRefreshAfterMessagesVisit();
    }
  }

  /// 쪽지함 진입 후 읽음 처리가 반영되도록 잠시 뒤 배지를 갱신한다.
  void _scheduleUnreadRefreshAfterMessagesVisit() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _refreshUnreadCount();
      }
    });
  }

  int _inferTabIndex(Uri uri) {
    final String path = uri.path.toLowerCase();
    if (path.startsWith('/notifications')) {
      return 4;
    }

    if (path.startsWith('/messages')) {
      return 3;
    }

    if (path.startsWith('/community')) {
      final String? query = uri.queryParameters['q'];
      if (query != null && query.trim().isNotEmpty) {
        return 2;
      }
      return 1;
    }

    if (path.startsWith('/board') ||
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

  Widget _messageTabIcon() {
    return Badge(
      isLabelVisible: _unreadMessageCount > 0,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      label: Text(
        _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount',
      ),
      child: const Icon(Icons.mail_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 5 ? AppBar(title: const Text('설정')) : null,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentIndex,
          children: <Widget>[
            WebViewScreen(
              key: _homeKey,
              initialUrl: _homeUrl,
              showAppBar: false,
              onOpenUrl: _applyTargetUrl,
            ),
            WebViewScreen(
              key: _communityKey,
              initialUrl: _communityUrl,
              showAppBar: false,
              onOpenUrl: _applyTargetUrl,
            ),
            SearchScreen(
              key: _searchKey,
              initialUrl: _searchUrl,
              onOpenUrl: _applyTargetUrl,
            ),
            WebViewScreen(
              key: _messageKey,
              initialUrl: _messageUrl,
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
            final String communityBase =
                _baseUri.resolve('/community').toString();
            _communityUrl = communityBase;
            _communityKey.currentState?.openUrl(communityBase);
          } else if (index == 3) {
            final String messageBase = _baseUri.resolve('/messages').toString();
            _messageUrl = messageBase;
            _messageKey.currentState?.openUrl(messageBase);
            _scheduleUnreadRefreshAfterMessagesVisit();
          } else if (index == 4) {
            final String notifBase =
                _baseUri.resolve('/notifications').toString();
            _notificationUrl = notifBase;
            _notificationKey.currentState?.openUrl(notifBase);
          } else if (index == 5) {
            _syncAndRefreshSettings();
          }
        },
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: '홈',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            label: '커뮤니티',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            label: '검색',
          ),
          BottomNavigationBarItem(icon: _messageTabIcon(), label: '쪽지'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            label: '알림',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
