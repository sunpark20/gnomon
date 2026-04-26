# 아키텍처

## 디렉토리 구조 (Century Iris 전환 후)
```
Gnomon/
├── App/
│   ├── GnomonApp.swift            # @main, WindowGroup (이름은 파일명만 — 내부 Century Iris)
│   ├── AppDelegate.swift          # 중복 실행 방지, StatusBar 셋업
│   ├── StatusBarController.swift  # 메뉴바 아이콘 + 컨텍스트 메뉴
│   └── WindowManager.swift        # 창 토글, Cmd+W 가로채기
├── Services/
│   ├── LuxReader.swift            # 조도센서 (IORegistry) ← subprocess에서 교체
│   ├── GammaController.swift      # 감마 테이블 read/write/restore ← 신규 (NativeDDC+M1DDCClient 대체)
│   ├── ColorTemperature.swift     # Kelvin→RGB + Kruithof lux→CCT ← 신규
│   ├── CSVLogger.swift            # CSV 로깅 (actor, 30일 로테이션)
│   ├── HotkeyManager.swift        # Carbon 글로벌 단축키
│   ├── SystemInfo.swift           # 시스템 진단 정보
│   └── IconUpdater.swift          # 메뉴바 sundial 아이콘
├── ViewModels/
│   ├── AutoLoopController.swift   # 중앙 제어 허브 ← DDC→감마 전환
│   └── OnboardingViewModel.swift  # 온보딩 체크 ← DDC→감마 전환
├── Model/
│   ├── BrightnessCurve.swift      # lux→밝기 매핑 (재사용, 출력 범위만 변경)
│   ├── DisplayID.swift            # CGDirectDisplayID 래퍼 ← MonitorID 대체
│   ├── EMAFilter.swift            # 지수이동평균 + snap detection (재사용)
│   ├── LuxCategory.swift          # lux 카테고리 분류 (재사용)
│   └── Debouncer.swift            # 디바운스 유틸 (재사용)
├── Views/
│   ├── MainWindow.swift           # 메인 UI ← ContrastCard 제거
│   ├── BrightnessCard.swift       # 밝기 카드 (재사용, 미세 조정)
│   ├── AmbientSensorCard.swift    # 조도 카드 (재사용)
│   ├── Settings/
│   │   └── SettingsWindow.swift   # 설정 ← contrast hotkey 제거, 텍스트 변경
│   ├── Onboarding/
│   │   └── OnboardingWindow.swift # 온보딩 ← DDC→감마 체크 변경
│   └── Theme.swift                # GoldToggleStyle, GoldSlider (재사용)
└── Resources/
    └── Assets.xcassets            # AppIcon (Century Iris로 변경)
```

## 제거 대상
```
├── Services/
│   ├── NativeDDC.swift            # ✗ 삭제 (IOAVService Private API)
│   └── M1DDCClient.swift          # ✗ 삭제 (DDC 래퍼)
├── Model/
│   └── MonitorID.swift            # ✗ 삭제 (DDC entryID 기반 → DisplayID로 대체)
├── Views/
│   └── ContrastCard.swift         # ✗ 삭제 (DDC 대비 제어)
```

## 데이터 흐름

### 센서 → 제어 파이프라인
```
IORegistry (IOMobileFramebufferShim)
    │
    ▼
LuxReader.currentLux()            ←── 1초 주기 폴링
    │                                  raw / 65536.0 = lux
    ▼
EMAFilter.update(raw)             ←── α=0.2, snap: threshold=50, duration=3
    │
    ├── emaLux (smoothed)
    │       │
    │       ├── BrightnessCurve.target(lux:)
    │       │       │
    │       │       └── gammaBrightness: Float (0.08 ~ 1.0)
    │       │
    │       └── ColorTemperature.cctForLux(lux:)
    │               │
    │               ├── cct: Int (2700 ~ 6500 K)
    │               │
    │               └── kelvinToRGB(cct) → (rMul, gMul, bMul)
    │
    └── didSnapOnLastUpdate?
            │
            └── true → snapSyncImmediately()
```

### 감마 테이블 적용
```
GammaController.apply(brightness:, rMul:, gMul:, bMul:, displayID:)
    │
    ├── 1. 원본 감마 테이블 캐시 (captureOriginal, 앱 시작 시 1회)
    │
    ├── 2. 통합 테이블 생성:
    │      for i in 0..<256:
    │          r[i] = origR[i] × brightness × rMul
    │          g[i] = origG[i] × brightness × gMul
    │          b[i] = origB[i] × brightness × bMul
    │
    └── 3. CGSetDisplayTransferByTable(displayID, 256, r, g, b)
```

### 복원 흐름
```
앱 종료/크래시
    │
    ├── applicationWillTerminate → CGDisplayRestoreColorSyncSettings()
    ├── SIGTERM/SIGABRT handler → CGDisplayRestoreColorSyncSettings()
    └── SIGKILL → macOS 로그아웃 시 자동 리셋
```

## 상태 관리

### AutoLoopController (@Observable, @MainActor)

**센서 상태:**
- `currentLux: Double` — 최신 raw lux
- `emaLux: Double` — EMA 필터된 lux

**밝기 상태:**
- `targetBrightness: Float` — 곡선 계산 결과 (0.08~1.0)
- `lastSentBrightness: Float?` — 마지막 감마 적용 값
- `lastSyncAt: Date?` — 마지막 감마 적용 시각
- `nextSyncAt: Date?` — 다음 예정 시각

**색온도 상태:**
- `targetCCT: Int` — Kruithof 테이블 결과 (2700~6500)

**제어 상태:**
- `autoEnabled: Bool` — 자동 모드 on/off (didSet에서 notification 발행)
- `isPaused: Bool` — 일시정지
- `manualOverrideAt: Date?` — 수동 조작 시각

**디스플레이 상태:**
- `activeDisplay: DisplayID?` — 현재 선택된 디스플레이 (CGDirectDisplayID 래퍼)

**파라미터:**
- `parameters: BrightnessCurve.Parameters` — 곡선 설정 (UserDefaults 연동)
- `syncInterval: TimeInterval` — 싱크 주기 (UserDefaults 연동)

### 디스플레이 식별 (DDC → 감마 전환)

**기존 (MonitorID):**
- `slot: Int` — 탐색 순서
- `displayName: String` — IORegistry DisplayProductName
- `uuid: String` — IOKit entryID (UInt64 문자열화)
- 비교: uuid 기반 Hashable

**신규 (DisplayID):**
- `id: CGDirectDisplayID` — CoreGraphics 디스플레이 ID
- `name: String` — 디스플레이 이름
- `isBuiltIn: Bool` — CGDisplayIsBuiltin 결과
- 비교: CGDirectDisplayID 기반 Hashable
- 탐색: CGGetActiveDisplayList → DisplayID 배열

## 패턴

### Dual-Loop
- **Sampling Loop** (1Hz): 센서 읽기 + EMA + 타겟 계산 + snap 감지 → UI 반영
- **Sync Loop** (30s default): 실제 감마 테이블 적용 → 빈번한 GPU LUT 쓰기 방지
- Snap 발생 시 sync loop 즉시 트리거 + 타이머 리셋

### Debouncer
- 수동 슬라이더: 200ms (감마 쓰기 빈도 제한)
- 모니터 재탐색: 2s (웨이크/핫플러그 이벤트 묶음)

### Crash Recovery
- 앱 시작 시 원본 감마 캐시
- 정상/비정상 종료 시 CGDisplayRestoreColorSyncSettings()
- 원본 테이블 캐시 → 직접 복원 (CGDisplayRestoreColorSyncSettings 버그 대비)

### Thread Safety
- AutoLoopController: @MainActor (모든 상태 변경 메인 스레드)
- CSVLogger: actor (파일 I/O 격리)
- LuxReader: Sendable struct (상태 없음)
- GammaController: @MainActor (CGSetDisplayTransferByTable은 메인 스레드 권장)
- EMAFilter: Sendable struct (값 타입)

### Persistence (UserDefaults)
| 키 | 타입 | 기본값 | 용도 |
|---|---|---|---|
| syncIntervalSeconds | Double | 30 | 싱크 주기 |
| brightnessMin | Int→Float | 0→0.08 | 곡선 최소 밝기 |
| brightnessMax | Int→Float | 100→1.0 | 곡선 최대 밝기 |
| darkFloorLux | Double | 15 | 암흑 임계값 |
| onboardingCompletedAt | Double | 0 | 온보딩 완료 시각 (Unix) |
| hotkeyBindings.v1 | JSON | defaults | 단축키 바인딩 |
