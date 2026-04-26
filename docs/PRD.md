# PRD: Century Iris

## 목표
MacBook 조도센서를 이용해 외장 모니터의 밝기와 색온도를 자동 조절하는 App Store 배포용 macOS 앱.

## 사용자
- MacBook + 외장 모니터 사용하는 Apple Silicon Mac 유저
- 모니터 밝기를 매번 수동으로 바꾸는 게 귀찮은 사람
- 가볍고 단순한 자동 밝기 앱을 원하는 사람

## 핵심 기능

### 1. 조도 기반 자동 밝기
- MacBook 조도센서(IORegistry `IOMobileFramebufferShim` → `AmbientBrightness`)로 주변 밝기 감지
- 1초 주기 폴링, EMA 필터(α=0.2) 적용
- 로그 곡선으로 lux → 감마 밝기(0.08~1.0) 매핑: `b_min + (b_max - b_min) × clamp(log10(lux+1) / log10(ceiling+1), 0, 1)`
- 기본값: minBrightness=0.08, maxBrightness=1.0, luxCeiling=2000, darkFloorLux=15
- darkFloorLux(15) 이하: minBrightness 고정 반환 (덮인 센서/암흑 노이즈 필터)
- CGSetDisplayTransferByTable로 감마 테이블 적용 (30초 주기 또는 snap 시 즉시)

### 2. 조도 기반 자동 색온도
- Kruithof 테이블로 lux → CCT(2700K~6500K) 매핑
- Tanner Helland 공식으로 CCT → RGB 비율 변환 (public domain)
- 감마 테이블에 밝기 × RGB 비율을 곱해서 한 번에 적용
- 6500K(D65 백색점)이 기본 — 밝은 환경에서 색 변환 없음

### 3. 메뉴바 상주
- LSUIElement: YES (독에 안 뜸)
- 좌클릭: 메인 창 토글
- 우클릭: 컨텍스트 메뉴 (Show Window, Quit)
- 아이콘: sundial 스타일 (IconUpdater, lux 기반 동적 렌더)

### 4. 수동 오버라이드
- 슬라이더로 밝기 수동 조절 → 자동 모드 OFF
- 200ms 디바운스로 감마 쓰기 빈도 제한
- "Auto" 토글로 자동 모드 복귀

### 5. 글로벌 단축키
- Carbon API 기반 (Accessibility 권한 불필요)
- 기본 바인딩: ⌃⌥⌘ +/-/B/G
- DDC contrast 단축키(⌃⌥⌘ [/]) 제거
- 설정에서 재바인딩 가능 (더블클릭 → 키 입력 → 저장)

## Snap Detection (급변 감지)
- |raw - ema| ≥ 50 lux가 3회 연속(3초) → EMA 우회, 즉시 감마 적용
- 사용 사례: 조명 켜기/끄기, 센서 가림/해제, 커튼 개폐
- snap 후 sync loop 리스케줄 (타이머 리셋)

## MVP 제외 사항
- 채도 조절 (학술적 기준 없음)
- 명암/대비 조절 (모니터 OSD에서 사용자 직접, 온보딩 안내)
- 멀티 모니터 (v2 예정)
- Intel Mac 지원
- DDC/CI 하드웨어 밝기 (Private API, sandbox 불가)
- 캘리브레이션 (감마는 비율이므로 모니터 무관)

## App Store 정보
- **이름**: Century Iris
- **부제(한국어)**: 외장 모니터 자동 밝기 조절
- **부제(영어)**: Auto Monitor Brightness
- **번들 ID**: com.sunguk.centuryiris
- **가격**: 무료
- **카테고리**: Utilities

## 상수 & 기본값

| 상수 | 값 | 용도 |
|---|---|---|
| 샘플 주기 | 1.0초 | 조도센서 폴링 |
| 싱크 주기 | 30초 | 감마 테이블 적용 (설정 가능) |
| EMA α | 0.2 | 스무딩 (1초 샘플 → ~5초 반응) |
| Snap threshold | 50 lux | 급변 감지 |
| Snap duration | 3 samples | 급변 확인 (3초) |
| Deadband | 2% | 최소 밝기 변화량 (쓸데없는 쓰기 방지) |
| 감마 최소값 | 0.08 | 완전 블랙 방지 |
| 감마 최대값 | 1.0 | 모니터 원래 밝기 |
| Dark floor lux | 15 | 이하면 최소 밝기 고정 |
| Lux ceiling | 2000 | 로그 곡선 상한 |
| CCT 범위 | 2700K ~ 6500K | 색온도 매핑 범위 |
| 수동 디바운스 | 200ms | 슬라이더 드래그 디바운스 |
| 재탐색 디바운스 | 2초 | 모니터 재발견 디바운스 |
| 초기 싱크 딜레이 | 2초 | 앱 시작 후 첫 싱크 |
| CSV 보존 | 30일 | 로그 로테이션 |

## 에러 케이스 & 에지 케이스

| 상황 | 처리 | 비고 |
|---|---|---|
| IORegistry 서비스 없음 | `activeMonitor = nil`, UI에 "센서 연결 해제" 표시 | IOMobileFramebufferShim 없는 환경 |
| AmbientBrightness 프로퍼티 없음 | 마지막 lux 값 유지, 에러 로그 | 외장 모니터만 있는 경우 |
| raw ≤ 65536 (외장 디스플레이) | 해당 서비스 스킵, 다음 서비스 시도 | 외장 모니터는 고정값 반환 |
| lux < 0 (이론상 불가) | max(0, lux)로 클램프 | BrightnessCurve에서 처리 |
| lux = 0 (센서 덮임) | darkFloorLux 로직으로 minBrightness 반환 | 화면 최소 밝기 유지 |
| CGSetDisplayTransferByTable 실패 | 에러 로그, 다음 주기에 재시도 | CGError 반환값 체크 |
| 감마 테이블 sum = 0 (전부 검정) | 0.08 최소값으로 방지 | Lunar crash recovery 패턴 참고 |
| Night Shift 감마 충돌 | 저장된 감마 vs 현재 감마 비교, 불일치 시 로그 | v1에서는 알림만, 자동 전환 안 함 |
| 앱 정상 종료 | applicationWillTerminate에서 CGDisplayRestoreColorSyncSettings() | 감마 복원 보장 |
| 앱 크래시 (SIGTERM/SIGABRT) | signal handler에서 CGDisplayRestoreColorSyncSettings() | 최선 노력 (SIGKILL은 잡을 수 없음) |
| 앱 크래시 (SIGKILL) | macOS 로그아웃 시 감마 자동 리셋 | 최악의 경우 재부팅으로 복구 |
| 모니터 핫플러그 (연결/분리) | NSApplication.didChangeScreenParametersNotification → 2초 디바운스 후 디스플레이 재탐색 | |
| 맥 슬립/웨이크 | NSWorkspace.didWakeNotification → 2초 디바운스 후 감마 재적용 | 웨이크 후 감마가 리셋됨 |
| UserDefaults 값 없음/손상 | 기본값 사용 (BrightnessCurve.Parameters.default) | loadPersistedPreferences에서 guard |
| 중복 앱 실행 | 기존 인스턴스 활성화, 새 인스턴스 종료 | AppDelegate.applicationDidFinishLaunching |
| CGDirectDisplayID 변경 | 모니터 재연결 시 ID 변경 가능 → 재탐색 로직으로 대응 | |
| 설정 입력 유효성 | minBrightness < maxBrightness 검증, 무효 시 이전 값 유지 | SettingsWindow |
| 싱크 간격 < 1초 | 경고 표시 "Too fast" | SettingsWindow UI |
| 싱크 간격 > 3600초 | 경고 표시 "Very slow" | SettingsWindow UI |

## 사용자 여정 (User Journey)

### 1. 첫 실행 (온보딩)
1. App Store에서 다운로드 → 앱 실행
2. 메뉴바에 아이콘 등장 + 온보딩 창 자동 표시
3. 체크 2개 자동 실행:
   - "Checking ambient light sensor…" → IORegistry 읽기 테스트
   - "Checking display…" → CGGetDisplayTransferByTable 테스트
4. 모두 통과 시 **모니터 설정 안내 카드** 표시:
   - "모니터 밝기를 밝은 환경에서 편한 수준으로 설정하세요."
   - "화면이 탁하게 느껴지면 모니터 Contrast를 70~80으로 올려보세요."
   - (이유: 감마 디밍은 모니터 하드웨어 밝기에서 '내리기만' 하므로, 모니터가 너무 어두우면 앱이 더 어둡게 만들 수밖에 없음)
5. "Start" 버튼 → 자동 모드 즉시 시작, 메인 창 표시

### 2. 일상 사용 (자동 모드)
- 메뉴바 아이콘만 보이고 독에 안 뜸
- 1초마다 조도 읽기 → EMA 스무딩 → 30초마다 감마 적용
- 밝은 환경: 감마 1.0(원래 밝기) + 6500K(쿨톤)
- 어두운 환경: 감마 ↓ + 웜톤(2700K) → 눈 편안함
- 급변(조명 켜기/끄기): 3초 내 즉시 반응 (snap detection)
- 사용자는 아무것도 안 해도 됨

### 3. 수동 오버라이드
- 메뉴바 좌클릭 → 메인 창 토글
- 밝기 슬라이더 드래그 → **자동 모드 자동 OFF**, 수동 값 적용
- "Auto" 토글 다시 ON → 자동 모드 복귀
- 색온도는 v1에서 **항상 자동** (수동 CCT 조절 없음)

### 4. 웨이크 (잠자기 → 깨기)
- macOS가 잠자기 해제 시 감마 테이블을 리셋함
- 앱이 2초 후 감마를 재적용
- **사용자 체감**: 깨어난 후 ~2초간 모니터가 원래 밝기로 번쩍 → 다시 어두워짐
- (이건 모든 감마 앱의 공통 한계, 피할 수 없음)

### 5. 모니터 연결/분리
- 외장 모니터 연결: 2초 후 자동 탐색 → 감마 적용 시작
- 외장 모니터 분리: activeDisplay = nil, 내장 디스플레이로 전환 가능
- **내장 디스플레이**: 지원하지 않음. macOS Auto-Brightness + True Tone이 처리. 외장 모니터 전용 앱.
- 외장 모니터 없으면 앱이 대기 상태 (감마 적용 안 함, 센서만 계속 읽음)

### 6. 앱 종료
- "Quit Century Iris" (메뉴바 우클릭)
- 감마 즉시 복원 → 모니터가 원래 밝기/색온도로 돌아감
- fade-out으로 부드럽게 복원 (~500ms, 30단계)

### 7. Night Shift 동시 사용
- Night Shift는 낮은 레벨의 API를 사용 (감마 테이블과 충돌하지 않음 — Lunar FAQ 확인)
- f.lux 같은 감마 기반 앱과는 충돌 가능 → 사용자에게 맡김 (감지/알림 구현하지 않음)

### 8. 스크린샷 / 화면 녹화
- 감마 테이블 변경은 스크린샷에 반영되지 않음 (GPU 출력단 이후에 적용)
- 사용자가 보는 화면과 캡처 결과가 다를 수 있음
- (이건 감마 디밍의 특성이며, 장점으로 볼 수도 있음 — 녹화물이 원래 색으로 보존)

## UI 결정 사항

### 밝기 슬라이더 범위
- 사용자에게 **0~100%** 로 표시 (기존 Gnomon과 동일한 UX)
- 내부적으로 0% → 감마 0.08, 100% → 감마 1.0으로 매핑
- 매핑: `gamma = 0.08 + (value / 100) × 0.92`
- 사용자는 DDC→감마 전환을 인식할 필요 없음

### 우측 카드 레이아웃 (밝기 + 색온도 합침)
- ContrastCard 삭제 → 밝기와 색온도를 하나의 카드로 합침
- 카드가 우측 전체 차지
- 구조 (위→아래):
  ```
  ☀ Brightness              [Auto] 토글
                      Sync Now  11s
            75 %
  Min                            Max
  ■■■■■■■■■■■■■■■■●──────  (수동 조절)
  ────────────── 중앙 경계 ──────────────
  3400K                        6500K
  ■■■■■■■■■●─────────────  (조절 불가)
  🌡 Color Temperature          Auto
   (주황 → 노랑 → 흰 → 파랑 그라데이션)
  ```
- 밝기 슬라이더: 기존 GoldSlider (수동 조절 가능)
- 색온도 슬라이더: 읽기 전용, thumb이 자동으로 움직임
- 색온도 슬라이더 바: Razer Chroma 스타일 웜(주황/앰버)→쿨(청백) 그라데이션
- 색온도 숫자 "3400K" 실시간 갱신
- "Auto" 배지 (토글 아님, 항상 자동 표시)

### 감마 전환 애니메이션
- 밝기/색온도 변경 시 **smooth fade**: ~500ms, 30단계
- `CGSetDisplayTransferByTable`을 30번 호출 (16ms 간격)
- GPU LUT 쓰기는 < 1ms이므로 성능 영향 없음
- 앱 종료 시에도 fade-out으로 부드럽게 복원

### 메뉴바 컨텍스트 메뉴
- "Show Window" (기존 유지)
- "Quit Century Iris" ("Quit Gnomon"에서 변경)

### 설정 변경
- Contrast 관련 설정 제거
- Contrast 단축키 행 제거 (⌃⌥⌘ [/])
- CCT on/off 토글 추가 (새 섹션 또는 밝기 범위 섹션 하위)
- "Gnomon" 텍스트 → "Century Iris"
- 홈페이지 URL 변경
- 이메일 유지

## 디자인
- Gnomon 기존 디자인 유지 (GoldToggleStyle, GoldSlider, 웜톤 테마)
- 앱 이름/아이콘을 Century Iris로 변경
- 색상 팔레트 변경 없음 (beige background, gold accent, warm brown text)

## 온보딩 변경
- "Detecting external monitor…" → "Checking display…"
- DDC 체크 → CGGetDisplayTransferByTable로 감마 지원 확인
- Lunar 충돌 경고 제거
- "No DDC-addressable monitor" → "Display not supported" (거의 발생 안 함)
- **모니터 설정 안내 카드 추가** (하드웨어 밝기/명암 조절 안내)
- 온보딩 완료 후 바로 자동 모드 시작 (캘리브레이션 단계 없음)
- "Welcome to Gnomon" → "Welcome to Century Iris"

## Notification 이름 변경
| 기존 (Gnomon) | 변경 (Century Iris) |
|---|---|
| com.sunguk.gnomon.toggleWindow | com.sunguk.centuryiris.toggleWindow |
| com.sunguk.gnomon.autoStateChanged | com.sunguk.centuryiris.autoStateChanged |
| com.sunguk.gnomon.hotkeysChanged | com.sunguk.centuryiris.hotkeysChanged |

## 하드코딩 문자열 변경
| 위치 | 기존 | 변경 |
|---|---|---|
| GnomonApp.swift:19 | "Gnomon" (윈도우 타이틀) | "Century Iris" |
| GnomonApp.swift:46 | "Gnomon Settings" | "Century Iris Settings" |
| SettingsWindow.swift:127 | "Gnomon" (헤더) | "Century Iris" |
| SettingsWindow.swift:377 | "Gnomon · v..." | "Century Iris · v..." |
| OnboardingWindow.swift:66 | "Welcome to Gnomon" | "Welcome to Century Iris" |
| StatusBarController.swift | "Quit Gnomon" | "Quit Century Iris" |
| WindowManager.swift | "New Gnomon Window" 메뉴 검색 | "New Century Iris Window" |
| SettingsWindow.swift:360 | homeninja.vercel.app/#gnomon | 새 URL (TBD) |

## CSV 로그 필드 변경
| 기존 | 변경 |
|---|---|
| sent_brightness (0~100 DDC) | gamma_brightness (0.08~1.0) |
| contrast (0~100 DDC) | cct (2700~6500 Kelvin) |
| 나머지 필드 유지 | |
