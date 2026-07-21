import 'package:flutter/material.dart';

import '../app_config.dart';
import 'webview_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.initialUrl, this.onOpenUrl});

  final String initialUrl;
  final void Function(String url)? onOpenUrl;

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final GlobalKey<WebViewScreenState> _webViewKey =
      GlobalKey<WebViewScreenState>();
  late final TextEditingController _searchController;
  late final Uri _baseUri = Uri.parse(kBaseWebUrl);
  late String _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    final String initialQuery =
        Uri.tryParse(widget.initialUrl)?.queryParameters['q'] ?? '';
    _searchController = TextEditingController(text: initialQuery);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl == widget.initialUrl ||
        _currentUrl == widget.initialUrl) {
      return;
    }

    _currentUrl = widget.initialUrl;
    _searchController.text =
        Uri.tryParse(widget.initialUrl)?.queryParameters['q'] ?? '';
    _webViewKey.currentState?.openUrl(widget.initialUrl);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> syncAuthToken() async {
    await _webViewKey.currentState?.syncAuthToken();
  }

  Future<void> clearCache() async {
    await _webViewKey.currentState?.clearCache();
  }

  Future<void> openUrl(String url) async {
    _currentUrl = url;
    final String query = Uri.tryParse(url)?.queryParameters['q'] ?? '';
    _searchController.value = _searchController.value.copyWith(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
      composing: TextRange.empty,
    );
    if (!mounted) return;
    setState(() {});
    await _webViewKey.currentState?.openUrl(url);
  }

  void _submitSearch([String? raw]) {
    final String query = (raw ?? _searchController.text).trim();
    final Uri communityUri = _baseUri.resolve('/community');
    final Uri targetUri =
        query.isEmpty
            ? communityUri
            : communityUri.replace(
              queryParameters: <String, String>{'q': query},
            );
    final String targetUrl = targetUri.toString();

    FocusScope.of(context).unfocus();
    _searchController.value = _searchController.value.copyWith(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
      composing: TextRange.empty,
    );
    setState(() {
      _currentUrl = targetUrl;
    });
    _webViewKey.currentState?.openUrl(targetUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 12,
                backgroundColor: Color(0xFF2E4FB8),
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submitSearch,
                  decoration: InputDecoration(
                    hintText: '검색어를 입력하세요',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _submitSearch,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFF2E4FB8)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: WebViewScreen(
            key: _webViewKey,
            initialUrl: _currentUrl,
            showAppBar: false,
            onOpenUrl: widget.onOpenUrl,
          ),
        ),
      ],
    );
  }
}
