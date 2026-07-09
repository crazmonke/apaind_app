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

## 알림 구조

클라이언트는 댓글/공지/새글을 직접 감지하지 않습니다. 사이트(서버)가 이벤트를 감지해 FCM을 발송해야 앱에 알림이 도착합니다.

- 클라이언트 역할: 토큰 생성, 토픽 구독, 푸시 표시, 딥링크 이동
- 서버 역할: 댓글/공지/새글 발생 시 FCM 발송, 토큰 저장/갱신, 사용자별 대상자 결정

현재 앱은 로그인 후 서버로 FCM 토큰을 전달하는 전제(`/api/v1/fcm-token`)로 설계되어 있습니다.

## 참고

루트 문서(../README.md)에 전체 진행 이력(환경 세팅/트러블슈팅/Firebase 등록 URL 포함)이 정리되어 있습니다.
