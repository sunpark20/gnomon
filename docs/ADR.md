# Architecture Decision Records

## 철학
"설치하면 바로 동작하는, 눈에 편한 자동 밝기 앱." 캘리브레이션 없이, 설정 없이, 켜면 바로. Lunar의 5%만 쓰는 사람을 위한 앱.

---

### ADR-001: 조도센서 — IORegistry AmbientBrightness
**결정**: `IORegistryEntryCreateCFProperty`로 `IOMobileFramebufferShim`의 `AmbientBrightness` 읽기
**이유**: App Sandbox에서 동작 확인됨 (PoC 4040/4040 성공). public IOKit 함수만 사용. 엔타이틀먼트/권한 불필요.
**변환**: `lux = Double(raw) / 65536.0`. raw ≤ 65536은 외장 디스플레이(고정값)이므로 스킵.
**에러 처리**:
- `IOServiceGetMatchingServices` 실패: 서비스 없음 에러 반환
- `IORegistryEntryCreateCFProperty` 실패: 프로퍼티 없음 에러 반환
- raw ≤ 65536: 해당 서비스 스킵, 다음 시도
- 모든 서비스 실패: 마지막 lux 값 유지
**트레이드오프**: 서비스명/프로퍼티명이 undocumented. App Review 거절 가능성 있으나, IOKit 레지스트리 읽기(read-only)는 다른 App Store 앱들도 사용하는 패턴.

### ADR-002: 밝기 제어 — CGSetDisplayTransferByTable (감마 테이블)
**결정**: 감마 테이블 조작으로 소프트웨어 디밍
**이유**: App Sandbox에서 동작. MonitorControlLite, BrightIntosh, GammaDimmer 등 App Store 앱이 이미 사용 중.
**구현 세부**:
- 앱 시작 시 `CGGetDisplayTransferByTable`로 원본 테이블 캐시 (256 엔트리 × RGB 3채널)
- 적용: `table[ch][i] = original[ch][i] × brightness × colorMul[ch]`
- 복원: `CGDisplayRestoreColorSyncSettings()` + 원본 테이블 직접 재적용 (belt-and-suspenders)
- 최소값 0.08 — 완전 블랙 방지 (사용자가 화면 못 찾는 상황 방지)
**에러 처리**:
- `CGSetDisplayTransferByTable` 반환값 체크 (CGError)
- 실패 시 로그 + 다음 주기에 재시도 (별도 fallback 없음)
- 원본 테이블 sum=0 감지 시 (크래시 복구): identity table(i/255)로 대체
**트레이드오프**: 백라이트 제어가 아닌 소프트웨어 필터. 어두운 환경에서 DDC 대비 명암비 저하. 사용자가 모니터 OSD에서 보상 가능.

### ADR-003: 색온도 — Tanner Helland + Kruithof 테이블
**결정**: Kelvin→RGB 변환은 Tanner Helland 공식 (public domain), lux→CCT 매핑은 Kruithof curve 기반 테이블
**공식 (Tanner Helland, T = kelvin / 100)**:
```
R: T ≤ 66 → 255, T > 66 → 329.698727446 × (T-60)^(-0.1332047592)
G: T ≤ 66 → 99.4708025861 × ln(T) - 161.1195681661, T > 66 → 288.1221695283 × (T-60)^(-0.0755148492)
B: T ≥ 66 → 255, T ≤ 19 → 0, else → 138.5177312231 × ln(T-10) - 305.0447927307
모든 값 [0,255] 클램프 후 /255 → [0.0, 1.0]
```
**Kruithof 매핑**:
| lux | CCT |
|---|---|
| < 50 | 2700K |
| 50~200 | 2700K → 3400K (선형 보간) |
| 200~500 | 3400K → 5000K (선형 보간) |
| ≥ 500 | 5000K → 6500K (선형 보간, 6500K에서 포화) |
**에러 처리**: 공식 자체에 에러 없음 (순수 수학). 입력 클램프만: kelvin ∈ [1000, 10000].
**트레이드오프**: CCT 센서 없이 lux만으로 색온도를 추정하므로 정밀도 한계. 그러나 사용자 체감상 충분.

### ADR-004: 캘리브레이션 없음
**결정**: A4 용지 캘리브레이션 제거
**이유**: 감마는 비율(0.08~1.0)이라 모니터에 무관하게 일정. DDC는 모니터마다 0~100의 실제 nits가 달라서 필요했지만 감마에서는 불필요.
**트레이드오프**: 개인화 수준이 약간 떨어지지만, "설치하면 바로 동작"이라는 가치가 더 큼. 설정에서 min/max/darkFloor 조절 가능.

### ADR-005: 밝기+색온도만, 채도/명암 제외
**결정**: v1에서 감마 테이블로 밝기+색온도 2개만 제어
**이유**: 밝기 80% + 색온도 15% = 95% 눈 피로 감소 효과. 채도/명암은 학술적 캘리브레이션 기준 없음. 명암은 모니터 OSD로 사용자 직접 조절.
**트레이드오프**: 파워유저에겐 기능이 부족할 수 있으나, 그들은 Lunar/BetterDisplay를 쓰면 됨.

### ADR-006: App Sandbox
**결정**: `com.apple.security.app-sandbox` 적용
**이유**: App Store 필수 요건. PoC에서 센서+감마 모두 sandbox 내 동작 확인됨.
**영향**:
- CSV 로그 경로: `~/Library/Containers/com.sunguk.centuryiris/Data/Library/Application Support/` 하위
- `CSVLogger.defaultLogDirectory()` 경로 자동 변경 (sandbox container)
- corebrightnessdiag 실행 불가 → IORegistry로 대체 (ADR-001)
- IOAVService 사용 불가 → 감마 테이블로 대체 (ADR-002)

### ADR-007: 밝기 곡선 — 로그 함수 (Gnomon 재사용)
**결정**: `b_min + (b_max - b_min) × clamp(log10(lux+1) / log10(ceiling+1), 0, 1)`
**이유**: 베버-페히너 법칙 기반. Gnomon에서 검증됨.
**변경점**: 출력 범위 DDC 0~100 → 감마 0.08~1.0. `BrightnessCurve.Parameters.default`의 min/max를 Int에서 Float로 변경하거나, 매핑 레이어 추가.
**에지 케이스**:
- lux=0: log10(1)=0 → minBrightness
- lux=darkFloorLux(15): 커브 평가 없이 minBrightness 직접 반환
- lux=ceiling(2000): normalized=1.0 → maxBrightness
- lux>ceiling: normalized>1.0 → clamp(1.0) → maxBrightness

### ADR-008: 감마 crash recovery
**결정**: 다중 레이어 복원
**구현**:
1. `applicationWillTerminate`: `CGDisplayRestoreColorSyncSettings()` 호출
2. `signal(SIGTERM, handler)` + `signal(SIGABRT, handler)`: 같은 복원 호출
3. 앱 시작 시 원본 감마 테이블 캐시 → 종료 시 원본으로 직접 복원 (CGDisplayRestore 버그 대비)
4. SIGKILL은 잡을 수 없음 → macOS 로그아웃 시 감마 자동 리셋
**참고**: Lunar, MonitorControl 모두 같은 패턴 사용. CGDisplayRestoreColorSyncSettings()가 간혹 테이블을 0으로 설정하는 macOS 버그 있음 (GammaDimmer 문서화) → 원본 캐시 직접 복원이 belt-and-suspenders.

### ADR-009: DisplayID — CGDirectDisplayID 기반
**결정**: MonitorID(DDC entryID) → DisplayID(CGDirectDisplayID) 전환
**이유**: 감마 API는 CGDirectDisplayID를 요구. DDC의 IOKit entryID는 더 이상 필요 없음.
**구현**: `CGGetActiveDisplayList` → `[DisplayID]`, `CGDisplayIsBuiltin`으로 내장/외장 구분.
**에지 케이스**: 모니터 재연결 시 CGDirectDisplayID가 변경될 수 있음 → didChangeScreenParametersNotification에서 재탐색.

### ADR-010: HotkeyManager — Contrast 단축키 제거
**결정**: `.contrastUp`/`.contrastDown` 액션 제거
**이유**: 감마 모델에서 contrast 제어 없음 (모니터 OSD로 직접).
**영향**: HotkeyAction enum에서 2개 case 제거. 기존 사용자의 UserDefaults `hotkeyBindings.v1` 키에 이전 바인딩이 남아있을 수 있으나, enum 디코딩 시 unknown case는 무시되므로 문제 없음.
**Carbon signature**: `0x474E_4F4D ("GNOM")` → `0x4952_4953 ("IRIS")`로 변경 (선택사항, 기능에 영향 없음).

### ADR-011: CSV 로그 스키마 변경
**결정**: contrast 필드 → cct 필드, sent_brightness 범위 변경
**기존**: `timestamp,raw_lux,ema_lux,target_brightness,sent_brightness,contrast,auto_on,manual_override,b_min,b_max`
**신규**: `timestamp,raw_lux,ema_lux,target_brightness,gamma_brightness,cct,auto_on,manual_override,b_min,b_max`
**마이그레이션**: CSVLogger.ensureFile()에서 헤더 불일치 감지 → 기존 파일을 `log.csv.v1`로 리네임, 새 헤더로 생성. 기존 데이터 보존.
