# Step 1: lux-reader

## 읽어야 할 파일

먼저 아래 파일들을 읽고 프로젝트의 아키텍처와 설계 의도를 파악하라:

- `/CLAUDE.md`
- `/docs/ADR.md` (ADR-001: 조도센서)
- `/docs/DO_NOT_IMPLEMENT.md`
- `/Gnomon/Services/LuxReader.swift` (현재 subprocess 구현)
- `/GnomonTests/LuxReaderTests.swift`
- `/PoC/main.swift` (IORegistry 구현 참조 — `readAmbientLux()` 함수)

이전 step에서 생성/수정된 파일:
- Step 0에서 project.yml, entitlements가 변경됨. 빌드 구조 파악 목적으로 읽을 것.

## 작업

LuxReader를 subprocess(`/usr/libexec/corebrightnessdiag`) 방식에서 IORegistry(`IOMobileFramebufferShim` → `AmbientBrightness`) 방식으로 교체한다.

### LuxReader.swift 교체

**현재 구현 (제거할 것):**
- `ProcessRunner.run(executablePath, args: ["status-info"])` 호출
- stdout에서 `AggregatedLux` 키 파싱 (ObjC style + XML plist fallback)

**새 구현:**
- `IOServiceMatching("IOMobileFramebufferShim")` → `IOServiceGetMatchingServices` → iterator
- 각 서비스에서 `IORegistryEntryCreateCFProperty(service, "AmbientBrightness")` 읽기
- `NSNumber`로 캐스팅 → `uint64Value` 추출
- raw > 65536이면 유효 (외장 디스플레이는 고정 65536 반환 → 스킵)
- `lux = Double(raw) / 65536.0`
- iterator와 service 해제: `IOObjectRelease`

**시그니처 (변경 없음):**
```swift
public struct LuxReader: Sendable {
    public func currentLux() async throws -> Double
}
```

**에러 enum 변경:**
```swift
enum ReadError: Error, LocalizedError {
    case serviceNotFound      // IOMobileFramebufferShim 없음
    case propertyNotFound     // AmbientBrightness 프로퍼티 없음
    case noValidReading       // 모든 서비스가 raw ≤ 65536
}
```

**제거할 것:**
- `executablePath` 프로퍼티와 `defaultPath` 상수
- `extractAggregatedLux`, `extractObjCStyle`, `extractXMLPlistStyle` 정적 메서드
- `ProcessRunner` 의존성 (LuxReader에서만 사용한다면 ProcessRunner도 삭제 가능, 다른 곳에서 사용하는지 확인할 것)

**참조 구현:** `/PoC/main.swift`의 `readAmbientLux()` 함수. 이 코드가 sandbox에서 4040/4040 성공 확인됨.

### LuxReaderTests.swift 업데이트

- 기존 파싱 테스트(ObjC style, XML plist) 제거
- IORegistry 통합 테스트 추가: `currentLux()` 호출 → 값이 0 이상인지 확인
- 에러 케이스 테스트는 IORegistry를 직접 mocking하기 어려우므로 생략 가능

## Acceptance Criteria

```bash
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build 2>&1 | tail -5
```

빌드 성공. LuxReader가 IOKit import를 사용하고 ProcessRunner/corebrightnessdiag 참조가 없어야 한다.

```bash
grep -r "corebrightnessdiag\|ProcessRunner" Gnomon/Services/LuxReader.swift
```

출력 없음 (참조 제거 확인).

## 검증 절차

1. 위 AC 커맨드를 실행한다.
2. `grep -r "corebrightnessdiag" Gnomon/` → 참조가 LuxReader 외에 남아있지 않은지 확인.
3. 결과에 따라 `phases/0-iris-mvp/index.json`의 step 1을 업데이트한다.

## 금지사항

- subprocess/Process/NSTask를 사용하지 마라. sandbox에서 차단됨.
- Private framework (CoreBrightness, BezelServices)를 import하지 마라.
- `IOServiceOpen`/`IOConnectCallMethod`를 사용하지 마라. sandbox에서 차단됨. `IORegistryEntryCreateCFProperty`만 사용.
- AutoLoopController를 수정하지 마라. 이 step은 LuxReader만 교체한다.
- DO_NOT_IMPLEMENT.md의 항목을 구현하지 마라.
