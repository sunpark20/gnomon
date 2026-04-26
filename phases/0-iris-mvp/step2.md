# Step 2: gamma-service

## 읽어야 할 파일

먼저 아래 파일들을 읽고 프로젝트의 아키텍처와 설계 의도를 파악하라:

- `/CLAUDE.md`
- `/docs/ARCHITECTURE.md` (데이터 흐름, 감마 테이블 적용 다이어그램)
- `/docs/ADR.md` (ADR-002: 감마 테이블, ADR-003: 색온도, ADR-008: crash recovery, ADR-009: DisplayID)
- `/docs/PRD.md` (상수 & 기본값 표, 감마 전환 애니메이션)
- `/docs/DO_NOT_IMPLEMENT.md`
- `/research/software-dimming-algorithms.md` (Tanner Helland 공식, Kruithof 테이블)
- `/PoC/main.swift` (GammaController 참조 구현)

이전 step에서 생성/수정된 파일:
- Step 0에서 NativeDDC.swift, M1DDCClient.swift, MonitorID.swift가 삭제됨.

## 작업

DDC 제어를 대체하는 3개의 신규 파일을 생성한다.

### 1. DisplayID.swift (Model)

`/Gnomon/Model/DisplayID.swift` 생성. 삭제된 MonitorID를 대체.

```swift
struct DisplayID: Hashable, Sendable, Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
}
```

**디스플레이 탐색 static 메서드:**
```swift
static func activeDisplays() -> [DisplayID]
```
- `CGGetActiveDisplayList(16, &ids, &count)` 호출
- 각 ID에 대해 `CGDisplayIsBuiltin` 체크
- 디스플레이 이름: `CGDisplayBounds`로 해상도 기반 이름 또는 IORegistry에서 DisplayProductName 읽기
- 내장 디스플레이 제외하고 외장만 반환 (DO_NOT_IMPLEMENT #11: 내장 디스플레이 지원 안 함)

### 2. GammaController.swift (Service)

`/Gnomon/Services/GammaController.swift` 생성. 삭제된 NativeDDC+M1DDCClient를 대체.

**@MainActor 클래스** (CGSetDisplayTransferByTable은 메인 스레드 권장):

```swift
@MainActor
final class GammaController {
    func listDisplays() -> [DisplayID]
    func captureOriginal(displayID: CGDirectDisplayID)
    func apply(brightness: Float, rMul: Float, gMul: Float, bMul: Float, displayID: CGDirectDisplayID) -> CGError
    func fade(from: Float, to: Float, rMul: Float, gMul: Float, bMul: Float, displayID: CGDirectDisplayID, duration: TimeInterval = 0.5, steps: Int = 30) async
    func restore()
}
```

**핵심 규칙:**
- `captureOriginal`: 앱 시작 시 1회 호출. 256 엔트리 × RGB 3채널 원본 캐시. 원본 sum=0이면 identity table(i/255)로 대체 (crash recovery).
- `apply`: `table[ch][i] = original[ch][i] × brightness × colorMul[ch]`. brightness는 0.08~1.0 클램프. CGError 반환.
- `fade`: from→to로 steps 단계에 걸쳐 smooth 전환. 각 단계 `apply` 호출 + `Task.sleep(nanoseconds: duration/steps)`. Task 취소 시 즉시 중단.
- `restore`: `CGDisplayRestoreColorSyncSettings()` 호출 + 원본 테이블 직접 재적용 (belt-and-suspenders, ADR-008).

**signal handler 등록:**
- 앱 시작 시 `signal(SIGTERM, handler)`, `signal(SIGABRT, handler)` 등록
- handler에서 `CGDisplayRestoreColorSyncSettings()` 호출

### 3. ColorTemperature.swift (Service)

`/Gnomon/Services/ColorTemperature.swift` 생성.

**enum ColorTemperature (namespace):**

```swift
enum ColorTemperature {
    static func kelvinToRGB(_ kelvin: Int) -> (r: Float, g: Float, b: Float)
    static func cctForLux(_ lux: Double) -> Int
}
```

**kelvinToRGB — Tanner Helland 공식 (ADR-003):**
```
T = kelvin / 100
R: T ≤ 66 → 255, T > 66 → 329.698727446 × (T-60)^(-0.1332047592)
G: T ≤ 66 → 99.4708025861 × ln(T) - 161.1195681661, T > 66 → 288.1221695283 × (T-60)^(-0.0755148492)
B: T ≥ 66 → 255, T ≤ 19 → 0, else → 138.5177312231 × ln(T-10) - 305.0447927307
모든 값 [0,255] 클램프 후 /255 → [0.0, 1.0]
```

입력 클램프: kelvin ∈ [1000, 10000].

**cctForLux — Kruithof 테이블 (ADR-003):**
| lux | CCT |
|---|---|
| < 50 | 2700K |
| 50~200 | 2700K → 3400K (선형 보간) |
| 200~500 | 3400K → 5000K (선형 보간) |
| ≥ 500 | 5000K → 6500K (선형 보간, 6500K에서 포화) |

선형 보간 공식: `cct = low + (high - low) × (lux - luxLow) / (luxHigh - luxLow)`

## Acceptance Criteria

```bash
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build 2>&1 | tail -5
```

빌드 성공. 3개 파일 모두 컴파일 에러 없음.

```bash
ls Gnomon/Services/GammaController.swift Gnomon/Services/ColorTemperature.swift Gnomon/Model/DisplayID.swift
```

3개 파일 모두 존재.

## 검증 절차

1. 위 AC 커맨드를 실행한다.
2. `grep -r "IOAVService\|@_silgen_name" Gnomon/` → Private API 참조 없음 확인.
3. GammaController가 `import CoreGraphics`와 `import IOKit`만 사용하는지 확인.
4. ColorTemperature.kelvinToRGB(6500)이 (1.0, 1.0, 1.0)에 근사하는지 논리적으로 확인 (6500K = D65 백색점).
5. 결과에 따라 `phases/0-iris-mvp/index.json`의 step 2를 업데이트한다.

## 금지사항

- Private API를 사용하지 마라 (IOAVService, @_silgen_name 등).
- 오버레이 윈도우(NSWindow shade)를 구현하지 마라 (DO_NOT_IMPLEMENT #9).
- 내장 디스플레이를 반환하지 마라 (DO_NOT_IMPLEMENT #11). `DisplayID.activeDisplays()`는 외장만 반환.
- AutoLoopController를 수정하지 마라. 이 step은 서비스 생성만 한다.
- 채도/명암 조절을 구현하지 마라 (DO_NOT_IMPLEMENT #3, #4).
- DO_NOT_IMPLEMENT.md의 항목을 구현하지 마라.
