import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/fcm_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.initialUrl,
    this.showAppBar = true,
    this.title = '아파인드',
    this.onOpenUrl,
  });

  final String initialUrl;
  final bool showAppBar;
  final String title;
  final void Function(String url)? onOpenUrl;

  @override
  State<WebViewScreen> createState() => WebViewScreenState();
}

class WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isSlowLoading = false;
  bool _isInitialLoad = true;
  bool _isPullRefreshing = false;
  double _pullProgress = 0.0;
  String? _errorMessage;
  late String _currentUrl;
  int _loadCycle = 0;

  @override
  void initState() {
    super.initState();
    final Uri? parsedInitial = Uri.tryParse(widget.initialUrl);
    if (parsedInitial == null || !parsedInitial.hasScheme) {
      _currentUrl = widget.initialUrl;
      _isLoading = false;
      _isInitialLoad = false;
      _errorMessage = '잘못된 초기 주소입니다.\n앱 설정을 확인해 주세요.';
    } else {
      _currentUrl = parsedInitial.toString();
    }
    _controller = _buildController(widget.initialUrl);
  }

  @override
  void didUpdateWidget(covariant WebViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl) {
      openUrl(widget.initialUrl);
    }
  }

  Future<void> openUrl(String url) async {
    debugPrint('WebView openUrl: $url');
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) {
      if (!mounted) return;
      setState(() {
        _currentUrl = url;
        _isLoading = false;
        _isSlowLoading = false;
        _isInitialLoad = false;
        _errorMessage = '잘못된 주소입니다.\n설정에서 기본 주소를 확인해 주세요.';
      });
      return;
    }

    _currentUrl = parsed.toString();
    _errorMessage = null;
    await _controller.loadRequest(parsed);
  }

  Future<void> clearCache() async {
    await _controller.clearCache();
    await _controller.clearLocalStorage();
  }

  void _handleJsBridge(String message) {
    if (!mounted) return;
    if (message == 'refresh') {
      _pullRefresh();
    } else if (message == 'cancel') {
      setState(() => _pullProgress = 0.0);
    } else if (message.startsWith('pull:')) {
      final double delta = double.tryParse(message.substring(5)) ?? 0.0;
      setState(() => _pullProgress = (delta / 80.0).clamp(0.0, 1.0));
    }
  }

  Future<void> _pullRefresh() async {
    final Uri? parsed = Uri.tryParse(_currentUrl);
    if (parsed == null || !parsed.hasScheme) return;

    setState(() {
      _isPullRefreshing = true;
      _pullProgress = 0.0;
      _errorMessage = null;
    });

    await _controller.loadRequest(parsed);
  }

  Future<void> _captureAuthTokenIfPresent() async {
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        "window.localStorage.getItem('auth_token')",
      );

      final String? token = _normalizeJavaScriptString(result);
      if (token == null || token.isEmpty) return;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? currentToken = prefs.getString('auth_token');
      if (currentToken == token) return;

      await prefs.setString('auth_token', token);
      await FcmService.instance.syncCurrentDeviceRegistration();
    } catch (_) {}
  }

  /// 사이트-nav DOM의 "계정" 링크 href를 읽어 로그인 상태를 SharedPreferences에 저장
  Future<void> syncAuthToken() async {
    try {
      final Object result = await _controller.runJavaScriptReturningResult(r'''
        (function() {
          var el = document.querySelector('a[aria-label="계정"]');
          if (!el) return 'unknown';
          var href = el.getAttribute('href') || '';
          return href.indexOf('/settings') === 0 ? 'logged_in' : 'logged_out';
        })()
      ''');
      final String raw = result.toString().replaceAll('"', '');
      if (raw == 'unknown') return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_web_logged_in', raw == 'logged_in');
    } catch (_) {}
  }

  Future<void> _handleLoginState(String state) async {
    if (state != 'logged_in' && state != 'logged_out') return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_web_logged_in', state == 'logged_in');
    } catch (_) {}
  }

  Future<void> _handleAppToken(String token) async {
    if (token.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await FcmService.instance.syncCurrentDeviceRegistration();
      debugPrint('AppTokenBridge: FCM token sync triggered');
    } catch (_) {}
  }

  Future<void> _handleGeoRequest(String message) async {
    // message format: "get:callbackId"
    final List<String> parts = message.split(':');
    if (parts.length < 2) return;
    final String callbackId = parts[1];

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _controller.runJavaScript(
          "window['_geoError_$callbackId'](1,'Permission denied')",
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;
      await _controller.runJavaScript(
        "window['_geoCallback_$callbackId'](${position.latitude},${position.longitude},${position.accuracy})",
      );
    } catch (_) {
      await _controller.runJavaScript(
        "window['_geoError_$callbackId'](2,'Position unavailable')",
      );
    }
  }

  void _handleNavigation(String url) {
    widget.onOpenUrl?.call(url);
  }

  String? _normalizeJavaScriptString(Object? result) {
    if (result == null) return null;
    final String raw = result.toString();
    if (raw == 'null' || raw == 'undefined') return null;
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  Future<void> _showJavaScriptAlertDialog(
    JavaScriptAlertDialogRequest request,
  ) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: Text(request.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showJavaScriptConfirmDialog(
    JavaScriptConfirmDialogRequest request,
  ) async {
    if (!mounted) return false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: Text(request.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  WebViewController _buildController(String initialUrl) {
    final Uri initialUri = Uri.tryParse(initialUrl) ?? Uri.parse('about:blank');
    final WebViewController controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setOnJavaScriptAlertDialog(_showJavaScriptAlertDialog)
          ..setOnJavaScriptConfirmDialog(_showJavaScriptConfirmDialog)
          ..addJavaScriptChannel(
            'AppRefreshBridge',
            onMessageReceived: (JavaScriptMessage message) {
              _handleJsBridge(message.message);
            },
          )
          ..addJavaScriptChannel(
            'AppLoginBridge',
            onMessageReceived: (JavaScriptMessage message) {
              _handleLoginState(message.message);
            },
          )
          ..addJavaScriptChannel(
            'AppTokenBridge',
            onMessageReceived: (JavaScriptMessage message) {
              _handleAppToken(message.message);
            },
          )
          ..addJavaScriptChannel(
            'AppGeoBridge',
            onMessageReceived: (JavaScriptMessage message) {
              _handleGeoRequest(message.message);
            },
          )
          ..addJavaScriptChannel(
            'AppNavigationBridge',
            onMessageReceived: (JavaScriptMessage message) {
              _handleNavigation(message.message);
            },
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (_) {
                if (!mounted) return;
                _loadCycle += 1;
                final int thisCycle = _loadCycle;
                debugPrint('WebView onPageStarted: $_currentUrl');
                setState(() {
                  _isLoading = true;
                  _isSlowLoading = false;
                  _errorMessage = null;
                });

                Future<void>.delayed(const Duration(seconds: 12), () {
                  if (!mounted || _loadCycle != thisCycle) return;
                  if (_isLoading && _errorMessage == null) {
                    setState(() => _isSlowLoading = true);
                    debugPrint('WebView slow loading detected: $_currentUrl');
                  }
                });
              },
              onPageFinished: (_) {
                if (!mounted) return;
                debugPrint('WebView onPageFinished: $_currentUrl');
                setState(() {
                  _isLoading = false;
                  _isSlowLoading = false;
                  _isPullRefreshing = false;
                  if (_isInitialLoad) _isInitialLoad = false;
                });
                _logPageSnapshot();
                _captureAuthTokenIfPresent();
                _injectAppBehaviors();
              },
              onWebResourceError: (WebResourceError error) {
                if (!mounted) return;
                final bool isMainFrame = error.isForMainFrame ?? true;
                if (!isMainFrame) return;

                debugPrint(
                  'WebView onWebResourceError: '
                  'code=${error.errorCode}, '
                  'type=${error.errorType}, '
                  'description=${error.description}, '
                  'url=$_currentUrl',
                );

                setState(() {
                  _isLoading = false;
                  _isSlowLoading = false;
                  _isInitialLoad = false;
                  _isPullRefreshing = false;
                  _pullProgress = 0.0;
                  _errorMessage = _toFriendlyError(error);
                });
              },
            ),
          )
          ..loadRequest(initialUri);

    return controller;
  }

  Future<void> _injectAppBehaviors() async {
    try {
      await _controller.runJavaScript(r'''
        (function() {
          if (window._appBehaviorsInjected) return;
          window._appBehaviorsInjected = true;

          var style = document.createElement('style');
          style.textContent = 'header.site-nav, .site-nav { display: none !important; }';
          document.head.appendChild(style);

          // 로그인 상태 감지 - "계정" 링크 href 기반 (서버 렌더링)
          (function detectLogin() {
            var el = document.querySelector('a[aria-label="계정"]');
            if (!el) return;
            var href = el.getAttribute('href') || '';
            var isLoggedIn = href.indexOf('/settings') === 0;
            if (typeof AppLoginBridge !== 'undefined') {
              AppLoginBridge.postMessage(isLoggedIn ? 'logged_in' : 'logged_out');
            }
            if (isLoggedIn && typeof AppTokenBridge !== 'undefined') {
              fetch('/api/app-token', {credentials: 'include'})
                .then(function(r) { return r.ok ? r.json() : null; })
                .then(function(data) {
                  if (data && data.token) AppTokenBridge.postMessage(data.token);
                })
                .catch(function() {});
            }
          })();

          var _prStartY = 0, _prActive = false;

          document.addEventListener('touchstart', function(e) {
            _prStartY = e.touches[0].clientY;
            _prActive = (window.scrollY <= 0);
          }, {passive: true});

          document.addEventListener('touchmove', function(e) {
            if (!_prActive) return;
            var delta = e.touches[0].clientY - _prStartY;
            if (delta <= 0) { _prActive = false; return; }
            if (typeof AppRefreshBridge !== 'undefined') {
              AppRefreshBridge.postMessage('pull:' + Math.min(delta, 100));
            }
            if (delta > 80) {
              _prActive = false;
              if (typeof AppRefreshBridge !== 'undefined') {
                AppRefreshBridge.postMessage('refresh');
              }
            }
          }, {passive: true});

          document.addEventListener('touchend', function() {
            if (_prActive) {
              _prActive = false;
              if (typeof AppRefreshBridge !== 'undefined') {
                AppRefreshBridge.postMessage('cancel');
              }
            }
          }, {passive: true});

          // 알림 페이지에서 링크 클릭 시 탭 라우팅
          if (window.location.pathname.startsWith('/notifications')) {
            document.addEventListener('click', function(e) {
              var a = e.target.closest('a[href]');
              if (!a) return;
              var href = a.getAttribute('href');
              if (!href || href.startsWith('#') || href.startsWith('javascript:') || href.startsWith('mailto:')) return;
              try {
                var fullUrl = new URL(href, window.location.href).href;
                if (typeof AppNavigationBridge !== 'undefined') {
                  e.preventDefault();
                  AppNavigationBridge.postMessage(fullUrl);
                }
              } catch(err) {}
            }, true);
          }
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _logPageSnapshot() async {
    try {
      final Object readyState = await _controller.runJavaScriptReturningResult(
        'document.readyState',
      );
      final Object title = await _controller.runJavaScriptReturningResult(
        'document.title',
      );
      final Object bodyLength = await _controller.runJavaScriptReturningResult(
        'document.body && document.body.innerText ? document.body.innerText.length : -1',
      );

      debugPrint(
        'WebView snapshot: readyState=$readyState, title=$title, bodyLength=$bodyLength, url=$_currentUrl',
      );
    } catch (error) {
      debugPrint('WebView snapshot skipped: $error');
    }
  }

  String _toFriendlyError(WebResourceError error) {
    if (error.errorType == WebResourceErrorType.connect ||
        error.errorType == WebResourceErrorType.timeout ||
        error.errorType == WebResourceErrorType.hostLookup) {
      return '네트워크에 연결할 수 없습니다.\n인터넷 연결을 확인해 주세요.';
    }
    return '페이지를 불러오는 중 오류가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
  }

  Future<bool> _handleWillPop() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  Future<void> _reload() async {
    final Uri? parsed = Uri.tryParse(_currentUrl);
    if (parsed == null || !parsed.hasScheme) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSlowLoading = false;
        _errorMessage = '잘못된 주소입니다.\n설정에서 기본 주소를 확인해 주세요.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _controller.loadRequest(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body =
        _errorMessage != null
            ? _OfflineErrorView(message: _errorMessage!, onRetry: _reload)
            : Stack(
              children: <Widget>[
                WebViewWidget(controller: _controller),
                // 초기 로드 또는 당겨서 새로고침 중: 브랜드 스플래시
                if (_isInitialLoad || _isPullRefreshing) const _ApaindSplash(),
                // 일반 페이지 이동 중 로딩 스피너
                if (_isLoading && !_isInitialLoad && !_isPullRefreshing)
                  const Center(child: CircularProgressIndicator()),
                // 당기는 중 진행 표시줄
                if (_pullProgress > 0 && !_isPullRefreshing)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: _pullProgress,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                      color: const Color(0xFF0f6f67),
                    ),
                  ),
                if (_isSlowLoading)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Material(
                      elevation: 1,
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFFF9FAFB),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                '페이지 로딩이 지연되고 있습니다. 네트워크 상태를 확인해 주세요.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: _reload,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );

    final Widget content = PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final NavigatorState navigator = Navigator.of(context);
        final bool canPopNow = await _handleWillPop();
        if (canPopNow && mounted) navigator.pop();
      },
      child: body,
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: '새로고침',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: content,
    );
  }
}

class _ApaindSplash extends StatelessWidget {
  const _ApaindSplash();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF2e4fb8), Color(0xFF0f6f67)],
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x4D104378),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '아파인드',
              style: TextStyle(
                color: Color(0xFF0f6f67),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF0f6f67),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineErrorView extends StatelessWidget {
  const _OfflineErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wifi_off, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
            if (Platform.isIOS)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'iOS 환경에서는 네트워크 전환 후 앱을 다시 열어 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
