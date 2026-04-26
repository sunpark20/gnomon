# Step 0: project-setup

## 읽어야 할 파일

먼저 아래 파일들을 읽고 프로젝트의 아키텍처와 설계 의도를 파악하라:

- `/CLAUDE.md`
- `/docs/PRD.md`
- `/docs/ARCHITECTURE.md`
- `/docs/ADR.md`
- `/docs/DO_NOT_IMPLEMENT.md`
- `/project.yml`
- `/Gnomon/App/GnomonApp.swift`
- `/Gnomon/App/AppDelegate.swift`
- `/Gnomon/App/StatusBarController.swift`
- `/Gnomon/App/WindowManager.swift`
- `/Gnomon/Views/Settings/SettingsWindow.swift`
- `/Gnomon/Services/HotkeyManager.swift`
- `/Scripts/release.sh`
- `/Scripts/gate.sh`

## 작업

이 step은 Century Iris로의 인프라 전환을 수행한다. 코드 로직은 변경하지 않고, 이름/ID/설정만 바꾸고, DDC 전용 파일을 삭제한다.

### 1. 번들 ID/이름 변경

**project.yml:**
- `name: Gnomon` → `name: CenturyIris`
- `bundleIdPrefix: com.sunguk.gnomon` → `bundleIdPrefix: com.sunguk.centuryiris`
- target "Gnomon" → "CenturyIris":
  - `PRODUCT_BUNDLE_IDENTIFIER: com.sunguk.centuryiris`
  - `PRODUCT_NAME: Century Iris`
  - `MARKETING_VERSION: "2.0.0"` (새 앱이므로)
- target "GnomonTests" → "CenturyIrisTests":
  - `PRODUCT_BUNDLE_IDENTIFIER: com.sunguk.centuryiris.tests`
  - TEST_HOST 경로도 CenturyIris.app으로 변경
- scheme "Gnomon" → "CenturyIris"
- `ENABLE_APP_SANDBOX: YES` 추가 (또는 별도 entitlements 파일 참조)

**Entitlements 파일 생성:**
- `Gnomon/CenturyIris.entitlements` 파일 생성:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.app-sandbox</key>
      <true/>
  </dict>
  </plist>
  ```
- project.yml에서 target 설정에 `CODE_SIGN_ENTITLEMENTS: Gnomon/CenturyIris.entitlements` 추가

### 2. 하드코딩 문자열 변경

| 파일 | 변경 |
|---|---|
| GnomonApp.swift | 윈도우 타이틀 "Gnomon" → "Century Iris", "Gnomon Settings" → "Century Iris Settings" |
| GnomonApp.swift | Notification.Name 3개: `com.sunguk.gnomon.*` → `com.sunguk.centuryiris.*` |
| StatusBarController.swift | "Quit Gnomon" → "Quit Century Iris" |
| WindowManager.swift | "Gnomon" 메뉴 검색 문자열 → "Century Iris" |
| SettingsWindow.swift | 헤더 "Gnomon" → "Century Iris", 버전 텍스트 "Gnomon · v..." → "Century Iris · v..." |
| HotkeyManager.swift | Carbon signature `0x474E_4F4D` ("GNOM") → `0x4952_4953` ("IRIS") |

### 3. DDC 전용 파일 삭제

아래 4개 파일을 삭제한다:
- `Gnomon/Services/NativeDDC.swift`
- `Gnomon/Services/M1DDCClient.swift`
- `Gnomon/Model/MonitorID.swift`
- `Gnomon/Views/ContrastCard.swift`

삭제 후 빌드가 깨지는 것은 **예상대로**다. 이 step에서는 삭제된 파일을 참조하는 코드를 **최소한의 stub으로 대체**하여 빌드만 통과시킨다:
- `AutoLoopController.swift`에서 M1DDCClient/MonitorID 참조: 해당 프로퍼티/메서드를 임시 주석 또는 stub으로 대체 (빌드 통과 목적)
- `MainWindow.swift`에서 ContrastCard 참조 (1줄): 해당 줄 삭제
- `OnboardingViewModel.swift`에서 M1DDCClient 참조: stub으로 대체
- `GnomonApp.swift`에서 contrastUp/contrastDown hotkey 액션: 해당 case 제거

stub은 다음 step들(1, 2, 3)에서 실제 구현으로 교체된다.

### 4. Scripts 업데이트

- `release.sh`: "Gnomon" → "CenturyIris" (scheme, archive path, DMG name 등)
- `gate.sh`: `-project Gnomon.xcodeproj -scheme Gnomon` → `-project CenturyIris.xcodeproj -scheme CenturyIris`

## Acceptance Criteria

```bash
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build 2>&1 | tail -5
```

빌드가 **성공**해야 한다 (warning은 허용, error는 불가).

## 검증 절차

1. 위 AC 커맨드를 실행한다.
2. 아키텍처 체크리스트를 확인한다:
   - NativeDDC.swift, M1DDCClient.swift, MonitorID.swift, ContrastCard.swift가 삭제되었는가?
   - Entitlements 파일이 생성되고 sandbox가 활성화되었는가?
   - "Gnomon" 문자열이 UI에 남아있지 않은가? (grep으로 확인)
3. 결과에 따라 `phases/0-iris-mvp/index.json`의 step 0을 업데이트한다.

## 금지사항

- DDC 관련 코드를 새로 작성하지 마라. 삭제만 한다.
- AutoLoopController의 로직을 변경하지 마라. stub으로 빌드만 통과시킨다. 실제 로직 변경은 Step 3에서 한다.
- 기존 테스트를 수정하지 마라. 빌드 에러가 나는 테스트 파일은 stub으로 최소 대체만 한다.
- DO_NOT_IMPLEMENT.md의 항목을 구현하지 마라.
