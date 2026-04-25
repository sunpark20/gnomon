# Gnomon — Background Wiki

> 마지막 갱신: 2026-04-21
> 이 문서는 bgraw.md에서 핵심을 추려 정리한 것입니다.

---

## 한 줄 요약

MacBook 조도센서를 빌려서 외장 모니터 밝기를 자동 조절하는 무료 macOS 앱.

## 왜 만들었나

MacBook 내장 화면은 주변 밝기에 따라 알아서 밝아지는데, 외장 모니터는 그대로. 해 뜨면 외장만 어둡게 보이고, 밤에는 외장만 눈부심. 기존 앱들(Lunar $23, BetterDisplay $22, Iris ~$15)은 다 유료에 기능이 너무 많음. Lunar 15일 평가판 써봤는데 쓰는 기능은 딱 하나 — "Sensor Mode (조도 자동 밝기)" 뿐이라 그 기능만 직접 만들기로 함.

## 무엇을 하는가

- MacBook 조도센서로 주변 밝기 실시간 감지
- DDC/CI 프로토콜로 외장 모니터 밝기 자동 조절 (30초 주기)
- 급격한 조도 변화는 즉시 반영
- 로그 곡선 기반 밝기 매핑 (베버-페히너 법칙)
- 단축키로 수동 밝기/대비 조절 (⌃⌥⌘+방향키)
- 메뉴바에만 상주 (독에 안 뜸)
- 한 화면에서 현재 lux, 타겟 밝기, 다음 동기화까지 남은 초 확인

## 무엇을 하지 않는가 (의도적)

| 제외 기능 | 이유 |
|---|---|
| 색온도 자동 조정 | macOS Night Shift가 이미 잘 함. 단일 lux 센서로 색온도 추정 불가 |
| MacBook 내장 디스플레이 | macOS Auto-Brightness + True Tone이 이미 처리 |
| Software Dim | DDC 최소 밝기로 충분. 소프트웨어 오버레이는 HDR/색 정확도 훼손 |
| 대비 자동 조정 | 효과 크기가 밝기의 5-10% 수준. 잘못 조정하면 부작용 큼 |
| AI Learning | 복잡도 대비 가치 작음. 로그만 기록 |
| Intel Mac | IOAVService는 Apple Silicon 전용 |
| 멀티 모니터 | v1은 단일 모니터. v2 예정 |

## 기술 결정

| 영역 | 선택 | 근거 |
|---|---|---|
| 밝기 곡선 | `log10(lux+1) / log10(2001)` | 베버-페히너 법칙. Lunar/Android/Windows 모두 로그 계열 |
| DDC 전송 | IOAVService 네이티브 | 외부 바이너리 의존 없음 |
| 스무딩 | EMA α=0.2 | ~5초 반응 지연. 순간 플리커 무시 |
| 데드밴드 | ±2 unit | DDC 마모 방지, 최소 체감 변화 |
| 대비 | 수동 고정 (기본 70) | EIZO 권고: "한 번 맞추고 그대로 둘 것" |
| A4 용지 테스트 | 밝기 곡선 설계 앵커 | 모니터가 종이보다 밝으면 눈 피로. ISO 120-150 cd/m²와 일치 |

## 경쟁 제품 비교

| 앱 | 가격 | 자동 밝기 | 대비 | 색온도 | 포지셔닝 |
|---|---|---|---|---|---|
| **Lunar** | $23 | 로그 곡선 + 학습 | 밝기 종속 | Pro만 | 전문, 만능 |
| **MonitorControl** | 무료 | 내장 디스플레이 mirror | mirror | X | 기본, 심플 |
| **BetterDisplay** | $22 | macOS 기본 의존 | X | X | 디스플레이 유틸 |
| **f.lux** | 무료 | X | X | 시간 기반 | 수면/서카디안 |
| **Gnomon** | **무료** | 로그 곡선 (lux 직접) | 수동 고정 | X | 단순, Lunar-lite |

## 알려진 한계

1. Apple Silicon Mac만 지원 (M1/M2/M3/M4/M5)
2. 단일 외장 모니터만 (v2에서 멀티 예정)
3. DDC 미지원 모니터는 동작 불가 (드묾)
4. HDMI 직결 시 DDC 안 통하는 경우 있음 (USB-C/Thunderbolt 권장)
5. macOS 15+ 만 지원
6. 곡선 파라미터가 개발자 환경(LG HDR 4K)에 맞춰져 있어 개인 튜닝 필요할 수 있음

## 대상 사용자

- MacBook + 외장 모니터 사용하는 Apple Silicon Mac 유저
- Lunar의 5%만 쓰는 사람 (조도 기반 자동 밝기만 필요)
- 무료 + 단순함을 원하는 사람

## 라이선스 / 가격

- 무료, 평생 무료
- MIT 라이선스
- GitHub 오픈소스: https://github.com/sunpark20/gnomon
- 가입/로그인 없음, 광고 없음, 구독 없음

## 추가 정보

- 다운로드: https://github.com/sunpark20/gnomon/releases
- 홈페이지: https://ninjaturtle.win/#gnomon
- 밝기 곡선 학술 근거: research/adaptive-curves.md (70+ 인용, ISO/학술 논문 기반)
