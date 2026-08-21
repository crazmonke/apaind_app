# apaind_app

아파인드(apaind) 하이브리드 WebView Flutter 앱 저장소입니다.

이 문서는 "수정사항 저장 + main 브랜치 push 완료" 이후부터, 로컬 검증과 TestFlight 배포를 처음 해보는 사람도 따라할 수 있도록 정리한 운영 가이드입니다.

## 1. 프로젝트/환경 기준

- 앱 경로: apt_community_app
- 기준 웹 URL: https://apaind.cloud/
- OS: macOS
- Flutter: 3.44.5 (stable)
- Dart: 3.12.2
- Xcode: 26.6
- CocoaPods: 1.16.2

## 2. 현재 배포 식별자/설정

- iOS Bundle ID: com.apaind.app
- Android Application ID: com.apaind.app
- iOS Deployment Target: 13.0
- macOS Deployment Target: 10.15

## 3. 시작 조건 (여기서부터 진행)

아래 조건을 만족했다고 가정하고 시작합니다.

- 수정사항 저장 완료
- main 브랜치 push 완료

예시:

```bash
git add .
git commit -m "feat: ..."
git push origin main
```

## 4. 로컬 테스트 (배포 전 필수)

프로젝트 이동:

```bash
cd /Users/mac_al03256479/apaind_app/apt_community_app
```

### 4-1. 의존성 동기화

```bash
flutter pub get
```

### 4-2. 단위 테스트

```bash
flutter test
```

### 4-3. 정적 분석 (권장)

```bash
flutter analyze
```

### 4-4. iOS 릴리즈 빌드 점검 (코드사인 없이)

```bash
flutter build ios --release --no-codesign
```

목적: 코드/리소스/플러그인 레벨 빌드 오류를 먼저 잡기 위함입니다.

### 4-5. macOS 빌드 점검 (선택)

```bash
flutter build macos
```

## 5. TestFlight 배포 준비 (버전 올리기)

TestFlight는 동일 버전을 중복 업로드할 수 없으므로, 배포 전 버전/빌드 번호를 반드시 증가시킵니다.

파일:

- apt_community_app/pubspec.yaml

예시:

- 기존: version: 1.0.1+12
- 다음: version: 1.0.2+13

규칙:

- 사용자에게 보이는 앱 버전: 1.0.2
- 내부 업로드 번호(빌드): 13
- 최소한 빌드 번호(+N)는 매 배포마다 증가해야 함

버전 수정 후:

```bash
flutter pub get
```

## 6. TestFlight 업로드용 산출물 생성

아래 명령 1개로 Archive + IPA를 생성합니다.

```bash
flutter build ipa --release
```

생성 결과:

- Archive: build/ios/archive/Runner.xcarchive
- IPA: build/ios/ipa/*.ipa

버전 확인(선택):

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist
```

## 7. Xcode에서 TestFlight 업로드 (메뉴 단계)

중요: 반드시 ios/Runner.xcworkspace 를 사용합니다.

1. Xcode 실행
2. File > Open... > apt_community_app/ios/Runner.xcworkspace 선택
3. 상단 스킴이 Runner인지 확인
4. Product > Archive 실행
5. Archive 완료 후 Organizer 창에서 최신 Archive 선택
6. Distribute App 클릭
7. App Store Connect 선택
8. Upload 선택
9. Signing/심사 옵션은 기본 권장값으로 Next 진행
10. Upload 클릭

업로드 직전 체크 포인트:

- Version/Build가 방금 올린 값과 일치하는지
- Bundle ID가 com.apaind.app 인지
- Team/Signing이 정상인지

## 8. 업로드 후 App Store Connect 처리

1. App Store Connect > My Apps > Apaind 진입
2. TestFlight 탭에서 빌드 처리 상태 확인
3. Processing 완료 후 내부 테스터(Internal Testing) 배포

참고: Processing은 수 분에서 수십 분 걸릴 수 있습니다.

## 9. 자주 발생하는 이슈와 해결

### 9-1. VS Code 터미널에서 open 명령이 실패하는 경우

- 증상: kLSUnknownErr, procNotFound 등
- 원인: 터미널/샌드박스 실행 환경 제약
- 해결: Finder에서 직접 열거나 Xcode를 먼저 띄운 뒤 File > Open으로 Runner.xcworkspace 열기

### 9-2. iOS 배포 타깃 경고

- Pods에서 낮은 deployment target 경고가 나올 수 있음
- 경고만 있고 archive/upload가 성공하면 일단 진행 가능

### 9-3. 같은 빌드 번호 업로드 오류

- 해결: pubspec.yaml의 +빌드 번호를 증가시키고 다시 flutter build ipa --release

## 10. Firebase/알림 관련 참고

- Firebase 프로젝트: apaind
- Android 설정 파일: apt_community_app/android/app/google-services.json
- iOS 설정 파일: apt_community_app/ios/Runner/GoogleService-Info.plist

서버가 이벤트 발생 시 FCM을 보내야 앱 푸시가 도착합니다.
