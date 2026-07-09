# apaind_app

아파인드(apaind) 하이브리드 WebView Flutter 앱 저장소입니다.

## 1) 프로젝트 구조

- Flutter 앱 경로: `apt_community_app`
- 기준 웹 URL: `https://apaind.mycafe24.com/`

## 2) 개발 환경/기반 설정

- OS: macOS
- Flutter: 3.29.1
- Dart: 3.7.0
- Xcode: 26.6

### iOS/macOS 타깃 조정

- iOS Deployment Target: `13.0`
- macOS Deployment Target: `10.15`
- iOS Runner의 시뮬레이터 대상 빌드를 위해 `SUPPORTED_PLATFORMS`에 `iphonesimulator` 포함

## 3) Firebase 등록 정보

### Firebase Console URL

- 콘솔 진입: https://console.firebase.google.com/
- 프로젝트 설정(일반): https://console.firebase.google.com/project/apaind/settings/general

### Firebase 프로젝트

- 프로젝트 이름/ID: `apaind`

### 등록된 앱 식별자

- Android applicationId: `com.example.apt_community_app`
- iOS bundle identifier: `com.example.aptCommunityApp`

### 다운로드/적용한 설정 파일

- Android 설정 파일: `android/app/google-services.json`
- iOS 설정 파일: `ios/Runner/GoogleService-Info.plist`

## 4) 코드 반영 사항(이번 세션)

### Android Firebase 연동

- `android/settings.gradle.kts`
  - `com.google.gms.google-services` 플러그인 버전 선언 추가
- `android/app/build.gradle.kts`
  - `com.google.gms.google-services` 플러그인 적용 추가

### iOS Firebase 연동

- `ios/Runner.xcodeproj/project.pbxproj`
  - `GoogleService-Info.plist` 파일 레퍼런스 및 Runner Resources 포함 처리

### FCM/알림 로직 강화

- `lib/services/fcm_service.dart`
  - 백그라운드 핸들러에서 Firebase 초기화 보강
  - iOS foreground 알림 표시 옵션 설정
  - 알림 설정값(푸시/댓글/공지/이벤트) 기반 토픽 구독/해제 동기화
  - 푸시 OFF 시 로컬 알림 취소 및 FCM 토큰 삭제 처리
  - 토글 변경 시 런타임 반영 API(`applyPreferenceChanges`) 추가
  - 카테고리(type/category/notificationType) 기반 필터링 적용
  - 딥링크 키 확장(`url`, `deep_link`, `link`)

- `lib/screens/settings_screen.dart`
  - 설정 토글이 `FcmService`와 직접 연결되도록 수정
  - 푸시/댓글/공지/이벤트 토글 변경 시 FCM 동기화 즉시 반영

## 5) 실행/검증 명령어

앱 루트로 이동 후 실행:

```bash
cd /Users/user/apaind_app/apt_community_app
flutter pub get
flutter analyze
flutter run -d "iPhone 17"
```

Android 실행 예시:

```bash
cd /Users/user/apaind_app/apt_community_app
flutter run -d android
```

## 6) 참고 및 주의사항

- 현재 식별자(`com.example...`)는 기본값입니다. 실제 배포 전 고유 식별자로 변경 권장
- 식별자 변경 시 Firebase 콘솔에도 동일 값으로 앱을 재등록해야 설정 파일이 일치합니다.
- 실기기 iOS 푸시 수신까지 완료하려면 Apple Developer(APNs 인증키/권한) 설정이 추가로 필요합니다.
