# Step 3: auto-loop

## 읽어야 할 파일

먼저 아래 파일들을 읽고 프로젝트의 아키텍처와 설계 의도를 파악하라:

- `/CLAUDE.md`
- `/docs/ARCHITECTURE.md` (데이터 흐름, 상태 관리, Dual-Loop 패턴)
- `/docs/ADR.md` (전체 — 특히 ADR-002, 003, 005, 007, 008, 011)
- `/docs/PRD.md` (상수 & 기본값 표, 에러 케이스 표, 감마 전환 애니메이션, 밝기 슬라이더 범위 매핑)
- `/docs/DO_NOT_IMPLEMENT.md`

이전 step에서 생성/수정된 파일 (반드시 읽을 것):
- `/Gnomon/Services/LuxReader.swift` (Step 1에서 IORegistry로 교체됨)
- `/Gnomon/Services/GammaController.swift` (Step 2에서 생성됨)
- `/Gnomon/Services/ColorTemperature.swift` (Step 2에서 생성됨)
- `/Gnomon/Model/DisplayID.swift` (Step 2에서 생성됨)
- `/Gnomon/Model/BrightnessCurve.swift` (기존 — 출력 범위 변경 대상)
- `/Gnomon/ViewModels/AutoLoopController.swift` (기존 — 대규모 수정 대상)
- `/Gnomon/Services/CSVLogger.swift` (기존 — 스키마 변경 대상)

## 작업

AutoLoopController를 DDC에서 GammaController로 전환한다. 이 step이 핵심 연결 작업이다.

### 1. BrightnessCurve 출력 범위 변경

`BrightnessCurve.swift` 수정:
- `Parameters.minBrightness` / `maxBrightness`: Int → Float
- 기본값: `minBrightness: 0.08`, `maxBrightness: 1.0`
- `target()` 반환형: Int → Float
- 내부 로직은 동일 (로그 곡선), 출력 범위만 변경
- darkFloorLux 로직 유지 (lux ≤ darkFloorLux → minBrightness 반환)

**또는** BrightnessCurve는 기존대로 0~100 Int를 반환하고, AutoLoopController에서 매핑하는 방법도 가능. 기존 테스트와의 호환성을 고려하여 선택할 것. 어떤 방식이든 최종적으로 감마 0.08~1.0 범위가 GammaController에 전달되어야 한다.

### 2. AutoLoopController 전환

**의존성 교체:**
- `ddcClient: M1DDCClient` → `gammaController: GammaController`
- `activeMonitor: MonitorID?` → `activeDisplay: DisplayID?`

**제거할 것:**
- `contrast` 프로퍼티
- `userSetContrast()` 메서드
- `contrastWriteDebouncer`
- Step 0에서 남긴 모든 DDC stub

**추가할 것:**
- `targetCCT: Int = 6500` — 현재 색온도 (Kruithof 결과)
- 색온도 계산: `sampleOnce()` 안에서 `ColorTemperature.cctForLux(emaLux)` → `targetCCT`
- 색온도 RGB: `ColorTemperature.kelvinToRGB(targetCCT)` → `(rMul, gMul, bMul)`

**메서드 변경:**

`start()`:
- `ddcClient.listDisplays()` → `gammaController.listDisplays()`
- `pickMonitor()` → `pickDisplay()` (외장 디스플레이 선택, 내장 제외는 DisplayID에서 처리됨)
- `getBrightness()` / `getContrast()` 제거 → 감마는 초기 읽기 없음 (1.0에서 시작)
- `gammaController.captureOriginal(displayID:)` 호출 (원본 감마 캐시)

`sampleOnce()`:
- 기존: lux 읽기 → EMA → targetBrightness 계산
- 추가: targetCCT 계산 → kelvinToRGB

`syncIfNeeded()` / `snapSyncImmediately()`:
- `writeBrightnessWithRetry()` → `gammaController.apply(brightness:, rMul:, gMul:, bMul:, displayID:)`
- deadband 비교: 기존 Int 비교에서 Float 비교로 변경 (abs(target - last) >= 0.02 등)
- fade 사용: 일반 sync에서는 `gammaController.fade()` 사용, snap에서는 `apply()` 직접 (즉시 반응)

`userSetBrightness()`:
- 입력: 0~100 Int (UI 슬라이더 값)
- 변환: `gamma = 0.08 + (Float(value) / 100.0) * 0.92`
- `gammaController.apply()` 호출 (debounce 유지)
- CCT도 현재 targetCCT 값으로 함께 적용

`rediscoverMonitor()` → `rediscoverDisplay()`:
- `gammaController.listDisplays()` → 외장 선택
- 새 디스플레이 발견 시 `captureOriginal()` 호출

**앱 종료 시 복원:**
- `applicationWillTerminate` 알림 구독 추가 (AutoLoopController 또는 GnomonApp에서)
- `gammaController.restore()` 호출

### 3. CSVLogger 스키마 변경 (ADR-011)

**CSVLogEntry 변경:**
- `sentBrightness: Int` → `gammaBrightness: Float`
- `contrast: Int` → `cct: Int`
- `csvLine()` 포맷 업데이트

**CSV 헤더 변경:**
```
timestamp,raw_lux,ema_lux,target_brightness,gamma_brightness,cct,auto_on,manual_override,b_min,b_max
```

CSVLogger.ensureFile()가 헤더 불일치 시 기존 파일을 `log.csv.v1`로 리네임 → 새 헤더로 생성 (기존 코드에 이 로직이 이미 있음).

### 4. Notification 이름 갱신

Step 0에서 이미 변경했을 수 있으나, AutoLoopController의 `autoEnabled` didSet에서 발행하는 notification 이름이 `centuryiris`로 되어있는지 확인.

## Acceptance Criteria

```bash
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build 2>&1 | tail -5
```

빌드 성공. DDC 참조 완전 제거.

```bash
grep -rn "M1DDC\|NativeDDC\|MonitorID\|ddcClient\|setContrast\|getContrast\|contrastWrite" Gnomon/ViewModels/ Gnomon/Services/ Gnomon/Model/
```

출력 없음 (DDC 흔적 완전 제거 확인).

## 검증 절차

1. 위 AC 커맨드를 실행한다.
2. `AutoLoopController.swift`에서 `gammaController` 프로퍼티가 존재하고, `ddcClient`가 없는지 확인.
3. `targetCCT` 프로퍼티가 존재하는지 확인.
4. `CSVLogEntry`에 `gammaBrightness: Float`와 `cct: Int`가 있는지 확인.
5. 결과에 따라 `phases/0-iris-mvp/index.json`의 step 3을 업데이트한다.

## 금지사항

- DDC 관련 코드를 새로 작성하지 마라.
- contrast 조절 기능을 남기지 마라. 완전 제거.
- 채도 조절을 추가하지 마라 (DO_NOT_IMPLEMENT #3).
- 색온도 수동 조절을 추가하지 마라 (DO_NOT_IMPLEMENT #8). CCT는 항상 자동.
- 내장 디스플레이에 감마를 적용하지 마라 (DO_NOT_IMPLEMENT #11).
- f.lux 충돌 감지를 구현하지 마라 (DO_NOT_IMPLEMENT #10).
- 오버레이 fallback을 구현하지 마라 (DO_NOT_IMPLEMENT #9).
- 기존 EMAFilter, Debouncer, LuxCategory를 수정하지 마라. 그대로 재사용.
- DO_NOT_IMPLEMENT.md의 항목을 구현하지 마라.
