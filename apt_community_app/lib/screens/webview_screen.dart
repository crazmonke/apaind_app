import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  String? _errorMessage;
  late String _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
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
    _currentUrl = url;
    _errorMessage = null;
    await _controller.loadRequest(Uri.parse(url));
  }

  Future<void> clearCache() async {
    await _controller.clearCache();
    await _controller.clearLocalStorage();
  }

  WebViewController _buildController(String initialUrl) {
    final WebViewController controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (_) {
                if (!mounted) return;
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
              },
              onPageFinished: (_) {
                if (!mounted) return;
                setState(() {
                  _isLoading = false;
                });
              },
              onWebResourceError: (WebResourceError error) {
                if (!mounted) return;
                final bool isMainFrame = error.isForMainFrame ?? true;
                if (!isMainFrame) {
                  return;
                }

                setState(() {
                  _isLoading = false;
                  _errorMessage = _toFriendlyError(error);
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(initialUrl));

    return controller;
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _controller.loadRequest(Uri.parse(_currentUrl));
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
