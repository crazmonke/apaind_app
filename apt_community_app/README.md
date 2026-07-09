# apt_community_app

아파인드 WebView 기반 Flutter 앱입니다.

## 핵심 정보

- 기준 웹 URL: https://apaind.mycafe24.com/
- Android applicationId: com.example.apt_community_app
- iOS bundle identifier: com.example.aptCommunityApp

## Firebase 설정 파일 위치

- Android: android/app/google-services.json
- iOS: ios/Runner/GoogleService-Info.plist

## 실행

```bash
cd /Users/user/apaind_app/apt_community_app
flutter pub get
flutter analyze
flutter run -d "iPhone 17"
```

Android 실행:

```bash
cd /Users/user/apaind_app/apt_community_app
flutter run -d android
```

## 알림(FCM) 동작 요약

- 앱 시작 시 Firebase 초기화 후 FCM 서비스 초기화
- 설정 화면의 푸시/댓글/공지/이벤트 토글과 FCM 토픽 구독 상태가 동기화됨
- iOS foreground 알림 표시 옵션 활성화
- 푸시 OFF 시 로컬 알림 정리 + FCM 토큰 삭제

## 참고

루트 문서(../README.md)에 전체 진행 이력(환경 세팅/트러블슈팅/Firebase 등록 URL 포함)이 정리되어 있습니다.
