import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'screens/home_shell_screen.dart';
import 'services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AptCommunityApp(initialUrl: kBaseWebUrl));
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) {
    return;
  }

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase 설정 파일(google-services.json / GoogleService-Info.plist)이
    // 아직 없을 수 있으므로 앱 시작 자체는 계속 진행한다.
  }
}

class AptCommunityApp extends StatefulWidget {
  const AptCommunityApp({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<AptCommunityApp> createState() => _AptCommunityAppState();
}

class _AptCommunityAppState extends State<AptCommunityApp>
    with WidgetsBindingObserver {
  static const String _ageConfirmedKey = 'compliance.age_confirmed';
  static const String _termsAcceptedKey = 'compliance.terms_accepted';

  final ValueNotifier<String?> _pendingOpenUrl = ValueNotifier<String?>(null);
  bool _isConsentReady = false;
  bool _isSafetyConsentAccepted = false;

  late final GoRouter _router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return HomeShellScreen(
            initialUrl: widget.initialUrl,
            pendingOpenUrl: _pendingOpenUrl,
          );
        },
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSafetyConsent();
    _bootstrapAppServices();
  }

  Future<void> _loadSafetyConsent() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool ageConfirmed = prefs.getBool(_ageConfirmedKey) ?? false;
    final bool termsAccepted = prefs.getBool(_termsAcceptedKey) ?? false;
    if (!mounted) return;
    setState(() {
      _isSafetyConsentAccepted = ageConfirmed && termsAccepted;
      _isConsentReady = true;
    });
  }

  Future<void> _acceptSafetyConsent() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ageConfirmedKey, true);
    await prefs.setBool(_termsAcceptedKey, true);
    if (!mounted) return;
    setState(() {
      _isSafetyConsentAccepted = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FcmService.instance.syncCurrentDeviceRegistration();
    }
  }

  Future<void> _bootstrapAppServices() async {
    try {
      await _ensureFirebaseInitialized().timeout(const Duration(seconds: 6));
    } on TimeoutException {
      debugPrint('Firebase initialization timed out.');
    }

    try {
      final String initialTargetUrl = await FcmService.getInitialTargetUrl(
        fallbackBaseUrl: kBaseWebUrl,
      ).timeout(const Duration(seconds: 3));

      if (mounted && initialTargetUrl.isNotEmpty && initialTargetUrl != kBaseWebUrl) {
        _pendingOpenUrl.value = initialTargetUrl;
      }
    } on TimeoutException {
      debugPrint('Initial FCM target URL fetch timed out.');
    } catch (error) {
      debugPrint('Initial FCM target URL fetch skipped: $error');
    }

    await FcmService.instance.initialize(
      fallbackBaseUrl: kBaseWebUrl,
      onOpenUrl: (String targetUrl) {
        _pendingOpenUrl.value = targetUrl;
        _router.go('/');
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingOpenUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConsentReady) {
      return MaterialApp(
        title: '아파인드',
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!_isSafetyConsentAccepted) {
      return MaterialApp(
        title: '아파인드',
        debugShowCheckedModeBanner: false,
        home: _SafetyConsentScreen(onAccepted: _acceptSafetyConsent),
      );
    }

    return MaterialApp.router(
      title: '아파인드',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

class _SafetyConsentScreen extends StatefulWidget {
  const _SafetyConsentScreen({required this.onAccepted});

  final Future<void> Function() onAccepted;

  @override
  State<_SafetyConsentScreen> createState() => _SafetyConsentScreenState();
}

class _SafetyConsentScreenState extends State<_SafetyConsentScreen> {
  bool _isAdultConfirmed = false;
  bool _isTermsAccepted = false;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (!_isAdultConfirmed || !_isTermsAccepted || _isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    await widget.onAccepted();
    if (!mounted) return;
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool canContinue =
        _isAdultConfirmed && _isTermsAccepted && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text('커뮤니티 이용 안내')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '아파인드는 사용자 생성 콘텐츠(UGC) 기반 서비스입니다.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '안전한 커뮤니티 운영을 위해 다음 사항에 동의해 주세요.\n'
                '- 만 18세 이상만 이용할 수 있습니다.\n'
                '- 불법, 혐오, 성적, 폭력, 괴롭힘, 사칭 등 부적절한 콘텐츠는 무관용 정책으로 즉시 제재됩니다.\n'
                '- 신고된 유해 콘텐츠는 최대 24시간 이내 검토 후 삭제 및 계정 제재가 진행될 수 있습니다.',
                style: TextStyle(height: 1.45),
              ),
              const SizedBox(height: 18),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isAdultConfirmed,
                onChanged: (bool? value) {
                  setState(() => _isAdultConfirmed = value ?? false);
                },
                title: const Text('만 18세 이상입니다.'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isTermsAccepted,
                onChanged: (bool? value) {
                  setState(() => _isTermsAccepted = value ?? false);
                },
                title: const Text('이용약관 및 커뮤니티 안전정책에 동의합니다.'),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '문의 및 신고 접수\n'
                  '- 앱 내 신고접수: 설정 > 커뮤니티 안전센터\n'
                  '- 웹 신고접수: /reports/new\n'
                  '- 이메일: support@apaind.com',
                  style: TextStyle(height: 1.4),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canContinue ? _submit : null,
                  child:
                      _isSubmitting
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('동의하고 시작하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
