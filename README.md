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

## 7) 알림 구조와 서버 역할

클라이언트만으로는 댓글, 공지, 새글 발생을 자동으로 알 수 없습니다. 앱은 FCM 토큰을 등록하고, 수신한 푸시를 화면에 보여주는 역할을 담당합니다. 실제로 “알림이 와야 하는 순간”은 사이트/서버가 판단해서 FCM을 발송해야 합니다.

### 클라이언트가 하는 일

- Firebase 초기화 및 FCM 토큰 생성
- 사용자 설정(푸시/댓글/공지/이벤트)에 따라 토픽 구독/해제
- 푸시 수신 시 WebView 화면으로 딥링크 이동
- 설정 화면에서 알림 수신 여부를 즉시 반영

### 서버가 해야 하는 일

- 댓글 작성, 공지 등록, 새글 생성 같은 이벤트 발생 시 FCM 발송
- 사용자별 토큰 저장 및 갱신 처리
- 카테고리별 토픽 발송 또는 개별 토큰 발송
- 로그인/로그아웃/토큰 폐기 시 서버 저장값 정리

### 권장 백엔드 연동 방식

- 앱 로그인 시 서버에 FCM 토큰 전송: `POST /api/v1/fcm-token`
- 서버는 사용자 ID와 토큰을 저장하고, 이벤트 발생 시 Firebase Admin SDK로 발송
- 서버 토픽은 `comment`, `notice`, `new_post`를 사용
- payload는 `type`, `notificationType`, `post_id`, `url`, `deep_link`, `link` 순서로 해석
- payload 예시:

```json
{
  "type": "comment",
  "title": "새 댓글이 달렸습니다",
  "body": "게시글에 새 댓글이 도착했습니다.",
  "url": "/community/123"
}
```

### 현재 상태 기준으로 아직 필요한 것

- 서버에서 FCM 발송 로직 구현
- APNs 실기기 테스트
- 로그인 시 `auth_token`이 앱에 저장되는 흐름과 `/api/v1/fcm-token` 실제 응답 스펙 확정
