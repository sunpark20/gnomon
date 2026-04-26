# Step 5: test-verify

## 읽어야 할 파일

먼저 아래 파일들을 읽고 프로젝트의 아키텍처와 설계 의도를 파악하라:

- `/CLAUDE.md`
- `/docs/PRD.md` (상수 & 기본값, 에러 케이스)
- `/docs/ADR.md` (전체)
- `/docs/DO_NOT_IMPLEMENT.md`

이전 step에서 생성/수정된 파일 (반드시 읽을 것):
- `/Gnomon/Services/LuxReader.swift` (Step 1)
- `/Gnomon/Services/GammaController.swift` (Step 2)
- `/Gnomon/Services/ColorTemperature.swift` (Step 2)
- `/Gnomon/Model/DisplayID.swift` (Step 2)
- `/Gnomon/Model/BrightnessCurve.swift` (Step 3에서 수정됨)
- `/Gnomon/ViewModels/AutoLoopController.swift` (Step 3에서 수정됨)
- `/Gnomon/Services/CSVLogger.swift` (Step 3에서 수정됨)

기존 테스트 파일:
- `/GnomonTests/LuxReaderTests.swift` (Step 1에서 수정됨)
- `/GnomonTests/AutoLoopControllerTests.swift`
- `/GnomonTests/BrightnessCurveTests.swift` (있다면)
- `/GnomonTests/EMAFilterTests.swift` (있다면)
- `/GnomonTests/M1DDCClientTests.swift` (삭제 대상)

## 작업

### 1. M1DDCClientTests.swift 삭제

DDC 전용 테스트 파일 삭제. 더 이상 M1DDCClient가 없으므로.

### 2. ColorTemperatureTests.swift 생성

`/GnomonTests/ColorTemperatureTests.swift` 생성.

**테스트 케이스:**
- `kelvinToRGB(6500)` → r, g, b 모두 1.0에 근사 (D65 백색점)
- `kelvinToRGB(2700)` → r > g > b (웜톤, 블루가 가장 낮음)
- `kelvinToRGB(10000)` → r < g < b (쿨톤, 레드가 가장 낮음)
- `kelvinToRGB(1000)` → 모든 값 [0, 1] 범위 내
- 경계값: `kelvinToRGB(1000)`, `kelvinToRGB(10000)`
- `cctForLux(0)` → 2700
- `cctForLux(25)` → 2700 (50 미만)
- `cctForLux(50)` → 2700 (경계)
- `cctForLux(125)` → 2700~3400 사이 (선형 보간)
- `cctForLux(200)` → 3400 (경계)
- `cctForLux(350)` → 3400~5000 사이
- `cctForLux(500)` → 5000 (경계)
- `cctForLux(1000)` → 5000~6500 사이
- `cctForLux(10000)` → 6500 (포화)

### 3. GammaControllerTests.swift 생성

`/GnomonTests/GammaControllerTests.swift` 생성.

**테스트 케이스:**
- `listDisplays()` → 빈 배열 아님 (외장 모니터 연결 시)
- `listDisplays()` → 내장 디스플레이가 결과에 포함되지 않음
- `captureOriginal()` → 크래시 없음
- `apply(brightness: 1.0, rMul: 1.0, gMul: 1.0, bMul: 1.0, ...)` → CGError.success (원본 유지)
- `apply(brightness: 0.08, ...)` → CGError.success (최소값)
- `restore()` → 크래시 없음

주의: 감마 테이블 변경은 실제 화면에 영향을 주므로 테스트 후 반드시 `restore()` 호출. `addTeardownBlock`에서 복원.

### 4. BrightnessCurveTests.swift 업데이트

Step 3에서 BrightnessCurve의 출력 범위가 변경되었을 수 있음. 기존 테스트의 assertion 값을 새 범위에 맞게 수정.

- `target(lux: 0)` → minBrightness (0.08 또는 0)
- `target(lux: 15)` → minBrightness (darkFloorLux)
- `target(lux: 2000)` → maxBrightness (1.0 또는 100)
- `target(lux: 500)` → 중간값

### 5. AutoLoopControllerTests.swift 업데이트

- DDC 관련 assertion 제거 (contrast 등)
- `userSetBrightness` 테스트: 0~100 입력이 autoEnabled를 false로 바꾸는지 확인
- `toggleAuto` 테스트: 기존 유지
- 새 프로퍼티 확인: `targetCCT`가 존재하는지

### 6. 전체 빌드 + Gate 통과

```bash
xcodegen generate
xcodebuild -scheme CenturyIris -configuration Debug build
./Scripts/gate.sh --skip-tests
```

모든 명령이 성공해야 한다.

### 7. DDC 흔적 최종 검증

```bash
grep -rn "DDC\|NativeDDC\|M1DDC\|IOAVService\|corebrightnessdiag\|MonitorID\|ContrastCard\|setContrast\|getContrast" Gnomon/ GnomonTests/
```

출력이 없어야 한다 (주석, 문서 참조 제외).

### 8. Private API 최종 검증

```bash
grep -rn "@_silgen_name\|IOServiceOpen\|IOConnectCallMethod\|BezelServices\|CoreBrightness" Gnomon/
```

출력이 없어야 한다.

## Acceptance Criteria

```bash
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build 2>&1 | tail -5 && echo "BUILD OK"
```

```bash
./Scripts/gate.sh --skip-tests 2>&1 | tail -3
```

두 명령 모두 성공.

```bash
grep -rn "DDC\|NativeDDC\|M1DDC\|IOAVService\|corebrightnessdiag\|@_silgen_name" Gnomon/ GnomonTests/ | grep -v "//.*DDC" | wc -l
```

출력: 0

## 검증 절차

1. 위 AC 커맨드 3개를 모두 실행한다.
2. 테스트 실행 시도:
   ```bash
   xcodebuild -scheme CenturyIris -configuration Debug test 2>&1 | tail -10
   ```
   LSUIElement 이슈로 실패할 수 있음 — 실패해도 빌드 자체가 성공이면 OK.
3. 결과에 따라 `phases/0-iris-mvp/index.json`의 step 5를 업데이트한다.

## 금지사항

- 테스트를 통과시키기 위해 프로덕션 코드의 로직을 변경하지 마라. 테스트 assertion을 수정할 것.
- DDC 관련 테스트를 새로 작성하지 마라.
- 테스트에서 Private API를 사용하지 마라.
- DO_NOT_IMPLEMENT.md의 항목에 대한 테스트를 작성하지 마라.
