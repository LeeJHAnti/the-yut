# The Yut — 에이전트 워크플로우 설계서

**Version:** 1.1  
**Date:** 2026-04-10  
**Status:** Review — Implementation Aligned

---

## 1. 에이전트 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────┐
│                    🎯 ORCHESTRATOR                           │
│              (총괄 에이전트 — 프로젝트 관리)                  │
│                                                             │
│  역할: 작업 분배, 진행 추적, 에이전트 간 의존성 조율          │
│  산출물: 스프린트 계획, 진행 보고, 최종 통합 승인             │
└──────┬──────────┬──────────────┬──────────────┬─────────────┘
       │          │              │              │
       ▼          ▼              ▼              ▼
┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────────┐
│ 📋 DESIGN│ │ 🎨 ART   │ │ ⚙️  CORE DEV │ │ 🔧 INTEGRA- │
│  AGENT   │ │  AGENT   │ │    AGENT     │ │ TION AGENT   │
└──────────┘ └──────────┘ └──────────────┘ └──────────────┘
```

---

## 2. 에이전트별 상세 역할

### 2.1 🎯 Orchestrator (총괄 에이전트)

**핵심 역할:** 프로젝트 전체 생명주기 관리

**입력:** 요구사항(GDD), 에이전트 보고  
**출력:** 작업 지시, 스프린트 계획, 릴리즈 판단

**책임:**
- 스프린트 단위 작업 분배 및 우선순위 설정
- 에이전트 간 의존성 파악 및 병렬/순차 작업 결정
- 블로커 해결 및 의사결정 에스컬레이션
- 통합 빌드 트리거 및 품질 게이트 관리
- 마일스톤 진행률 추적

**의사결정 권한:**
- 기능 범위 조정 (scope cut/add)
- 에이전트 간 인터페이스 사양 확정
- 릴리즈 go/no-go 판단

---

### 2.2 📋 Design Agent (게임 기획 + 시스템 설계)

**핵심 역할:** 게임 규칙, UX 흐름, 시스템 사양을 확정하여 다른 에이전트에게 명확한 스펙을 제공

**입력:** GDD 초안, 유저 피드백  
**출력:** 상세 스펙 문서

**담당 산출물:**

| 산출물 | 설명 | 소비자 |
|--------|------|--------|
| 게임 규칙 상세 스펙 | 모든 엣지케이스 포함 (업힌 말 잡기, 연속 윷 등) | Core Dev |
| 말판 노드 그래프 JSON | 27개 노드의 좌표, 연결, 분기 정보 | Core Dev, Art |
| UI/UX 와이어프레임 | 각 화면의 요소 배치, 전환 흐름 | Art, Core Dev |
| 메시지 프로토콜 스펙 | 클라이언트↔서버 메시지 포맷 확정 | Core Dev |
| 밸런스 시뮬레이션 | 확률 분석, 평균 게임 시간 추정 | Orchestrator |

**작업 흐름:**
```
1. GDD 기반 규칙 상세화
   → 엣지케이스 정의 (30+ 시나리오)
   → 예: "업힌 말 3개가 지름길에서 잡히면?"
   → 예: "연속 윷 5회 후 이동 순서는?"

2. 말판 노드 데이터 확정
   → JSON 형태로 노드 좌표 + 연결 정보
   → Core Dev와 Art 에이전트 동시 소비

3. UI/UX 와이어프레임
   → 160×144 해상도 기준 레이아웃
   → 터치/마우스 인터랙션 영역 정의

4. 프로토콜 스펙 확정
   → 메시지 타입별 필드, 에러 코드
   → Core Dev의 서버/클라이언트 양쪽에서 참조
```

---

### 2.3 🎨 Art Agent (UI + 이미지 + 테마 리소스 통합)

**핵심 역할:** Game Boy 흑백 도트 아트 에셋 제작 및 애니메이션 시퀀스 설계

**입력:** 아트 디렉션 (GDD 섹션 5), 와이어프레임 (Design Agent)  
**출력:** 게임 에셋, 스프라이트시트

**담당 산출물:**

| 산출물 | 형식 | 사양 |
|--------|------|------|
| 말판 스프라이트 | PNG | 128×128, 4색 팔레트 |
| 말 스프라이트 (4종) | PNG 스프라이트시트 | 8×8 각 프레임, idle/move/stack |
| 윷가락 스프라이트 | PNG 스프라이트시트 | 8×16, 던지기 12프레임 |
| 결과 텍스트 스프라이트 | PNG | 도/개/걸/윷/모 각각 |
| UI 프레임 / 버튼 | PNG 9-slice | Game Boy 윈도우 스타일 |
| 이펙트 (먼지, 별, 충격파) | PNG 스프라이트시트 | 16×16, 8~12프레임 |
| 타이틀 로고 | PNG | "The Yut" 80×32 |
| 픽셀 폰트 | .tres (Godot) | 영문 + 한글 기본 |
| 사운드 이펙트 | .wav / .ogg | 8bit 칩튠 스타일 |

**작업 흐름:**
```
1. 스타일 가이드 확정
   → 4색 팔레트 적용 샘플
   → 스프라이트 크기 규격

2. 핵심 에셋 제작 (Phase 1 필수)
   → 말판, 말, 윷가락 (게임 플레이에 필수)

3. 애니메이션 프레임 제작 (Phase 2~3)
   → 윷 던지기 시퀀스
   → 말 이동 홉 시퀀스
   → 잡기/업기 이펙트

4. UI 에셋 제작
   → 타이틀 화면, 로비, 결과 화면
   → 버튼, 입력 필드, 프레임

5. 사운드 제작 (Phase 3)
   → 효과음 + BGM
```

**핵심 제약:**
- 모든 에셋은 4색 팔레트 엄수
- 스프라이트는 정수 배율에서 깨짐 없어야 함
- Godot에서 임포트 가능한 형식 (.png, .tres, .wav, .ogg)

---

### 2.4 ⚙️ Core Dev Agent (게임 로직 + 엔진 코드)

**핵심 역할:** Rust 서버와 Godot 클라이언트의 핵심 로직 구현

**입력:** 기술 아키텍처 문서, Design Agent 스펙  
**출력:** 실행 가능한 서버 + 클라이언트 코드

**담당 영역:**

#### 서버 (Rust)
| 모듈 | 파일 | 핵심 기능 |
|------|------|-----------|
| WebSocket | `ws_handler.rs` | 연결 관리, 메시지 라우팅 |
| 방 관리 | `room.rs` | 생성, 참가, 매칭, 봇 관리 |
| 메시지 | `messages.rs` | 클라이언트/서버 메시지 타입 |
| 봇 AI | `bot.rs` | 4단계 난이도 AI (Easy~Expert) |
| 게임 엔진 | `game/state.rs` | 상태 머신, 턴 관리, 이동 실행 |
| 말판 | `game/board.rs` | 27노드 그래프, 경로 탐색 |
| 윷 로직 | `game/yut.rs` | RNG, 결과 생성, 확률 검증 |
| 말 로직 | `game/piece.rs` | 이동, 잡기, 업기, 완주 |
| 턴 관리 | `game/turn.rs` | 추가 턴, 턴 진행 |

#### 클라이언트 (Godot/GDScript)
| 모듈 | 파일 | 핵심 기능 |
|------|------|-----------|
| 네트워크 | `network_manager.gd` | WebSocket 통신 |
| 상태 관리 | `game_state.gd` | 서버 상태 반영 |
| 보드 렌더 | `board_controller.gd` | 말판 + 말 렌더링 |
| 입력 처리 | `yut_input.gd` | 플릭 제스처 인식 |
| 말 제어 | `piece_controller.gd` | 말 이동/잡기/업기 애니 |
| 윷 연출 | `yut_animation.gd` | 윷 던지기 풀 애니메이션 |

**작업 흐름:**
```
Phase 1: Foundation
  1. Rust 서버 스캐폴딩 (Actix-Web + WebSocket)
  2. 방 시스템 (생성/참가/매칭)
  3. Godot 프로젝트 설정 (해상도, 팔레트)
  4. 타이틀 → 로비 → 게임 화면 전환
  5. WebSocket 연결 확립

Phase 2: Core Gameplay
  6. 말판 노드 그래프 (서버)
  7. 윷 던지기 로직 (서버 RNG)
  8. 말 이동 로직 (경로 탐색 + 유효성)
  9. 잡기/업기/완주 로직
  10. 턴 시스템 (추가 턴 포함)
  11. 클라이언트 상태 동기화

Phase 3: Polish
  12. 애니메이션 시스템 연결 (Art 에셋)
  13. 재접속 처리
  14. 에러 핸들링
```

---

### 2.5 🔧 Integration Agent (빌드 + 테스트 + 리소스 연결)

**핵심 역할:** 모든 에이전트의 산출물을 통합하고, 빌드/테스트/배포 파이프라인 관리

**입력:** 각 에이전트 산출물  
**출력:** 실행 가능한 통합 빌드

**담당 영역:**

| 영역 | 상세 |
|------|------|
| 빌드 시스템 | Rust cargo build + Godot HTML5 export 자동화 |
| 에셋 통합 | Art 에셋을 Godot 프로젝트에 임포트, import 설정 |
| 테스트 | 서버 단위테스트, 통합테스트, 수동 플레이테스트 |
| 로컬 환경 | 원클릭 로컬 서버 실행 스크립트 |
| Docker | 릴리즈용 컨테이너 빌드 |
| CI/CD | (선택) GitHub Actions 파이프라인 |

**작업 흐름:**
```
1. 빌드 스크립트 작성
   → build.sh: Rust 빌드 → Godot export → 정적 파일 복사
   → 로컬 실행: run_local.sh

2. 에셋 임포트 파이프라인
   → Art Agent가 /assets에 에셋 저장
   → Godot .import 파일 자동 생성 검증
   → 스프라이트시트 → AtlasTexture 변환

3. 테스트 실행
   → cargo test (서버 로직)
   → 수동 플레이테스트 체크리스트 실행
   → 멀티 브라우저 동시 접속 테스트

4. 배포 준비
   → Docker 이미지 빌드 + 테스트
   → 로컬 Docker 실행으로 최종 검증
```

---

## 3. 에이전트 간 의존성 맵

```
                        Phase 1        Phase 2        Phase 3
                        ─────────      ─────────      ─────────

Design Agent        ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
  (규칙/스펙 확정)   ↓ 규칙 스펙     ↓ 프로토콜
                     ↓               ↓
Art Agent           ░░░░███████████░░░░░████████████░░░░░░░░░
  (에셋 제작)          ↓ 기본 에셋         ↓ 애니메이션/사운드
                       ↓                   ↓
Core Dev Agent      ░░░░░░░████████████████████████░░░░░░░░░░
  (코드 구현)                              ↓ 코드 + 에셋
                                           ↓
Integration Agent   ░░░░░░░░░░░░░░░░░░░░░░░░████████████████
  (통합/테스트)                                빌드+테스트+배포
```

### 의존성 상세

```
Design Agent ──[규칙 스펙]──→ Core Dev Agent
Design Agent ──[와이어프레임]──→ Art Agent
Design Agent ──[노드 그래프]──→ Core Dev Agent + Art Agent
Design Agent ──[프로토콜 스펙]──→ Core Dev Agent

Art Agent ──[스프라이트/에셋]──→ Integration Agent
Core Dev Agent ──[서버+클라이언트 코드]──→ Integration Agent

Integration Agent ──[빌드 결과/버그 리포트]──→ Core Dev Agent / Art Agent
Integration Agent ──[테스트 결과]──→ Orchestrator

Orchestrator ──[작업 지시]──→ 모든 에이전트
Orchestrator ──[의사결정]──→ Design Agent (스펙 변경 시)
```

---

## 4. 스프린트 계획

### Sprint 1 (Week 1~2): Foundation

| 에이전트 | 작업 | 산출물 |
|----------|------|--------|
| Design | 규칙 엣지케이스 30개+ 정의 | `rules_spec.json` |
| Design | 말판 노드 좌표/연결 JSON | `board_graph.json` |
| Design | 와이어프레임 4화면 | `wireframes.png` |
| Art | 스타일 가이드 + 팔레트 확정 | `style_guide.png` |
| Art | 말판 + 말 + 윷가락 기본 스프라이트 | `sprites/*.png` |
| Core Dev | Rust 서버 스캐폴딩 | `the-yut-server/` |
| Core Dev | Godot 프로젝트 초기 설정 | `the-yut-client/` |
| Core Dev | 방 시스템 (생성/참가) | WebSocket 통신 |
| Integration | 빌드 스크립트, 로컬 실행 환경 | `build.sh`, `run_local.sh` |

### Sprint 2 (Week 3~4): Core Gameplay

| 에이전트 | 작업 | 산출물 |
|----------|------|--------|
| Design | 프로토콜 스펙 최종 확정 | `protocol_spec.md` |
| Art | 윷 던지기 애니메이션 프레임 | `yut_throw_sheet.png` |
| Art | 말 이동 홉 애니메이션 | `piece_move_sheet.png` |
| Core Dev | 윷 던지기 + 말 이동 로직 (서버) | 게임 엔진 코드 |
| Core Dev | 플릭 제스처 + 보드 렌더링 (클라) | 클라이언트 코드 |
| Core Dev | 턴 시스템 + 상태 동기화 | 멀티플레이 동작 |
| Integration | 중간 빌드 + 2인 테스트 | 테스트 리포트 |

### Sprint 3 (Week 5~6): Polish

| 에이전트 | 작업 | 산출물 |
|----------|------|--------|
| Art | 이펙트 (먼지, 별, 충격파) | `effects_sheet.png` |
| Art | UI 에셋 (버튼, 프레임) | `ui_assets/*.png` |
| Art | 사운드 이펙트 + BGM | `audio/*.wav`, `*.ogg` |
| Core Dev | 애니메이션 연결 + 화면 흔들림 | 연출 완성 |
| Core Dev | 재접속 + 에러 핸들링 | 안정성 |
| Integration | 4인 동시 접속 테스트 | 테스트 리포트 |
| Integration | 브라우저 호환성 테스트 | 호환성 리포트 |

### Sprint 4 (Week 7): Release Prep

| 에이전트 | 작업 | 산출물 |
|----------|------|--------|
| Integration | Docker 빌드 + 외부 서버 배포 | 배포 완료 |
| Integration | 성능 최적화 | 최적화 리포트 |
| Orchestrator | 최종 QA + 릴리즈 판단 | go/no-go |

---

## 5. 커뮤니케이션 프로토콜

### 5.1 에이전트 간 산출물 전달 규칙

```
1. 모든 산출물은 /TheYut/ 프로젝트 폴더 내 지정 위치에 저장
2. 산출물 완료 시 Orchestrator에게 보고
3. Orchestrator가 다음 에이전트에게 작업 트리거
4. 의존성 있는 작업은 선행 산출물 검증 후 시작
```

### 5.2 폴더 구조 (전체 프로젝트)

```
TheYut/
├── docs/
│   ├── 01_GDD_GameDesignDocument.md
│   ├── 02_TechnicalArchitecture.md
│   ├── 03_AgentWorkflow.md
│   ├── rules_spec.json          ← Design Agent
│   ├── board_graph.json         ← Design Agent
│   ├── protocol_spec.md         ← Design Agent
│   └── wireframes/              ← Design Agent
├── the-yut-server/              ← Core Dev Agent
│   ├── Cargo.toml
│   ├── src/                     ← main, bot, messages, room, ws_handler, game/
│   ├── check.sh / check.bat    ← 빌드 검증 스크립트
│   ├── static/                  ← 테스트 클라이언트 + Godot HTML5 export 위치
│   └── Dockerfile
├── the-yut-client/              ← Core Dev Agent + Art Agent
│   ├── project.godot
│   ├── scenes/
│   ├── scripts/
│   ├── assets/                  ← Art Agent 에셋 저장
│   └── shaders/
├── build.sh                     ← Integration Agent
├── run_local.sh                 ← Integration Agent
└── docker-compose.yml           ← Integration Agent
```

---

## 6. 품질 게이트 (Quality Gates)

각 스프린트 종료 시 통과해야 하는 기준:

### Sprint 1 Gate
- [ ] WebSocket으로 2개 브라우저 연결 성공
- [ ] 방 생성 → 참가 → 대기실 표시 동작
- [ ] 말판이 화면에 올바르게 렌더링됨
- [ ] 4색 팔레트 엄수 확인

### Sprint 2 Gate
- [ ] 윷 던지기 → 결과 표시 → 말 이동 전체 흐름 동작
- [ ] 잡기/업기 로직 정상 동작
- [ ] 2인 동시 플레이 가능
- [ ] 서버 단위테스트 80%+ 커버리지

### Sprint 3 Gate
- [ ] 4인 동시 플레이 안정적
- [ ] 모든 애니메이션 + 이펙트 적용
- [ ] 사운드 적용
- [ ] 재접속 정상 동작
- [ ] Chrome + Firefox 호환

### Sprint 4 Gate (릴리즈)
- [ ] Docker 빌드 성공
- [ ] 외부 서버 배포 + 접속 가능
- [ ] 10게임 연속 크래시 없음
- [ ] 평균 로딩 3초 이내
