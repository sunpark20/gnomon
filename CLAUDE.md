# 프로젝트: Century Iris

Gnomon(DDC 기반 외장 모니터 자동 밝기 조절 앱)을 Century Iris(감마 테이블 기반, App Store 배포)로 전환 중.

## 기술 스택
- SwiftUI + AppKit (macOS 15.0+, Apple Silicon only)
- Swift 6.0 (strict concurrency: complete, warnings-as-errors)
- XcodeGen (project.yml → .xcodeproj 생성)
- IOKit (조도센서: IORegistryEntryCreateCFProperty, IOMobileFramebufferShim)
- CoreGraphics (감마 테이블: CGSetDisplayTransferByTable, CGGetDisplayTransferByTable)
- App Sandbox (com.apple.security.app-sandbox)
- Carbon Events (글로벌 단축키, Accessibility 권한 불필요)

## 아키텍처 규칙
- CRITICAL: Private API 사용 금지. IOAVService, BezelServices, CoreBrightness private framework, DisplayServices 등 절대 사용하지 말 것. App Store 심사 통과가 목표.
- CRITICAL: subprocess 실행 금지. Process/NSTask로 외부 바이너리 호출하면 sandbox에서 차단됨. corebrightnessdiag, m1ddc 등 CLI 도구 사용 불가.
- CRITICAL: 감마 테이블 복원 보장. applicationWillTerminate + signal handler에서 CGDisplayRestoreColorSyncSettings() 호출. 원본 테이블 캐시 → 직접 복원(belt-and-suspenders). 화면이 어둡게 멈추는 것 방지.
- CRITICAL: 감마 최소값 0.08. 완전 블랙(0.0) 방지. 사용자가 화면을 못 찾는 상황 방지.
- Gnomon 기존 패턴(EMA, Debouncer, BrightnessCurve, dual-loop) 최대한 재사용.
- @MainActor로 상태 관리 통일. CSVLogger만 actor 격리.

## 개발 프로세스
- 커밋 메시지: conventional commits (feat:, fix:, docs:, refactor:)
- 변경 후 빌드 통과 확인 필수
- 기존 테스트를 깨뜨리지 말 것

## 명령어
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build   # 빌드
xcodebuild -scheme CenturyIris -configuration Debug test                         # 테스트
./Scripts/gate.sh --skip-tests                                                   # 게이트 (lint + format + build)

## 참조 문서
- [docs/PRD.md](docs/PRD.md) — 제품 요구사항 (상수, 에러 케이스, 에지 케이스 전부 포함)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 아키텍처 (데이터 흐름, 상태 관리, 패턴)
- [docs/ADR.md](docs/ADR.md) — 기술 결정 기록 (11개 ADR, 각 에러 처리 포함)
- [research/software-dimming-algorithms.md](research/software-dimming-algorithms.md) — 감마/CCT 공식 + 학술 출처
- [research/adaptive-curves.md](research/adaptive-curves.md) — 밝기 곡선 학술 근거
- [appstore/metadata.md](appstore/metadata.md) — App Store 메타데이터

## 세션 핸드오프
- **[NEXT_SESSION.md](NEXT_SESSION.md)** — 이전 세션 미완료 TODO와 컨텍스트. 새 세션 시작 시 반드시 확인할 것.
