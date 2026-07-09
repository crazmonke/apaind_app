import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/fcm_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.initialUrl,
    this.showAppBar = true,
    this.title = '아파인드',
  });

  final String initialUrl;
  final bool showAppBar;
  final String title;

  @override
  State<WebViewScreen> createState() => WebViewScreenState();
}

class WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isSlowLoading = false;
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
      if (!mounted) {
        return;
      }

      setState(() {
        _currentUrl = url;
        _isLoading = false;
        _isSlowLoading = false;
        _errorMessage = '잘못된 주소입니다.\n설정에서 기본 주소를 확인해 주세요.';
      });
      debugPrint('WebView openUrl ignored (invalid URL): $url');
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

  Future<void> _captureAuthTokenIfPresent() async {
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        "window.localStorage.getItem('auth_token')",
      );

      final String? token = _normalizeJavaScriptString(result);
      if (token == null || token.isEmpty) {
        return;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? currentToken = prefs.getString('auth_token');
      if (currentToken == token) {
        return;
      }

      await prefs.setString('auth_token', token);
      await FcmService.instance.syncCurrentDeviceRegistration();
    } catch (_) {
      // 로그인 상태를 읽을 수 없으면 조용히 무시한다.
    }
  }

  String? _normalizeJavaScriptString(Object? result) {
    if (result == null) {
      return null;
    }

    final String raw = result.toString();
    if (raw == 'null' || raw == 'undefined') {
      return null;
    }

    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }

    return raw;
  }

  WebViewController _buildController(String initialUrl) {
    final Uri initialUri = Uri.tryParse(initialUrl) ?? Uri.parse('about:blank');
    final WebViewController controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
                  if (!mounted) {
                    return;
                  }

                  if (_loadCycle != thisCycle) {
                    return;
                  }

                  if (_isLoading && _errorMessage == null) {
                    setState(() {
                      _isSlowLoading = true;
                    });
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
                });
                _logPageSnapshot();
                _captureAuthTokenIfPresent();
              },
              onWebResourceError: (WebResourceError error) {
                if (!mounted) return;
                final bool isMainFrame = error.isForMainFrame ?? true;
                if (!isMainFrame) {
                  return;
                }

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
                  _errorMessage = _toFriendlyError(error);
                });
              },
            ),
          )
          ..loadRequest(initialUri);

    return controller;
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
      if (!mounted) {
        return;
      }

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
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
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
        if (canPopNow && mounted) {
          navigator.pop();
        }
      },
      child: body,
    );

    if (!widget.showAppBar) {
      return content;
    }

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
