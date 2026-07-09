import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_config.dart';
import 'screens/home_shell_screen.dart';
import 'services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  final String initialUrl = await FcmService.getInitialTargetUrl(
    fallbackBaseUrl: kBaseWebUrl,
  );

  runApp(AptCommunityApp(initialUrl: initialUrl));
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

class _AptCommunityAppState extends State<AptCommunityApp> {
  final ValueNotifier<String?> _pendingOpenUrl = ValueNotifier<String?>(null);

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
    _initializeFcm();
  }

  Future<void> _initializeFcm() async {
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
    _pendingOpenUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '아파인드',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
