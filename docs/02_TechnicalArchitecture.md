# The Yut — 기술 아키텍처 설계서

**Version:** 1.1  
**Date:** 2026-04-10  
**Status:** Final — Implementation Complete

---

## 1. 시스템 아키텍처 전체도

```
┌─────────────────────────────────────────────────────┐
│                    CLIENT (Browser)                  │
│  ┌───────────────────────────────────────────────┐  │
│  │           Godot 4 (WASM / HTML5)              │  │
│  │  ┌─────────┐ ┌──────────┐ ┌───────────────┐  │  │
│  │  │ UI Layer│ │ Game View│ │ Animation Sys │  │  │
│  │  │ (Scenes)│ │ (Board)  │ │ (Tween+Sprite)│  │  │
│  │  └────┬────┘ └────┬─────┘ └───────┬───────┘  │  │
│  │       └───────┬───┘               │           │  │
│  │         ┌─────▼─────┐    ┌────────▼────────┐  │  │
│  │         │ Game       │    │ Input Handler   │  │  │
│  │         │ Controller │    │ (Flick Gesture) │  │  │
│  │         └─────┬──────┘    └────────┬────────┘  │  │
│  │               └──────┬─────────────┘           │  │
│  │               ┌──────▼──────┐                  │  │
│  │               │ Network     │                  │  │
│  │               │ Manager     │                  │  │
│  │               │ (WebSocket) │                  │  │
│  │               └──────┬──────┘                  │  │
│  └──────────────────────┼────────────────────────┘  │
└─────────────────────────┼───────────────────────────┘
                          │ WebSocket (JSON)
                          │
┌─────────────────────────┼───────────────────────────┐
│                    SERVER (Rust)                      │
│  ┌──────────────────────▼────────────────────────┐  │
│  │            Actix-Web (WebSocket Handler)       │  │
│  └──────────────────────┬────────────────────────┘  │
│                         │                            │
│  ┌──────────────────────▼────────────────────────┐  │
│  │              Connection Manager                │  │
│  │  - 세션 관리, 재접속 핸들링, 하트비트          │  │
│  └──────────────────────┬────────────────────────┘  │
│                         │                            │
│  ┌──────────┐  ┌────────▼────────┐  ┌────────────┐ │
│  │ Room     │  │ Game Engine     │  │ Matchmaker │ │
│  │ Manager  │←→│ (Rules + State) │  │ (Quick     │ │
│  │          │  │                 │  │  Start)    │ │
│  └──────────┘  └─────────────────┘  └────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## 2. 서버 아키텍처 (Rust + Actix-Web)

### 2.1 프로젝트 구조

```
the-yut-server/
├── Cargo.toml
├── check.sh / check.bat         # 빌드 검증 스크립트
├── src/
│   ├── main.rs                  # 서버 시작점, Actix-Web 설정
│   ├── bot.rs                   # 봇 AI (4난이도 레벨)
│   ├── messages.rs              # 클라이언트/서버 메시지 타입
│   ├── room.rs                  # 방 관리 + RoomManager
│   ├── ws_handler.rs            # WebSocket 연결 핸들러
│   └── game/
│       ├── mod.rs
│       ├── board.rs             # 말판 그래프 (27노드), 경로 탐색
│       ├── yut.rs               # 윷 던지기 RNG
│       ├── piece.rs             # 말 상태, 업기, 잡기
│       ├── state.rs             # GameState, 게임 단계, 이동 실행
│       └── turn.rs              # 턴 관리, 추가 턴
├── static/
│   └── index.html               # 테스트 클라이언트
└── Dockerfile
```

**주요 변경:**
- 단일 모듈 구조 (중첩 디렉토리 없음)
- `bot.rs` 추가: 4난이도 AI (Easy, Medium, Hard, Expert)
- `room.rs`에 통합: RoomManager, Room, BotInfo
- `messages.rs`: 통합된 메시지 정의
- `ws_handler.rs`: WebSocket 직접 처리

### 2.2 핵심 데이터 구조 (Rust)

```rust
// === 게임 상태 ===
#[derive(Debug, Clone)]
pub struct GameState {
    pub phase: GamePhase,
    pub players: Vec<PlayerInfo>,
    pub pieces: Vec<Piece>,
    pub board: Board,
    pub turn: TurnManager,
    pub pending_piece_id: Option<usize>,
    pub winner: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum GamePhase {
    WaitingForPlayers,              // 플레이어 대기 중
    Throwing,                       // 윷 던지기 단계
    SelectingPiece,                 // 말 선택 단계
    SelectingPath,                  // 지름길 선택 단계
    GameOver,                       // 게임 종료
}

// === 플레이어 정보 ===
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerInfo {
    pub id: usize,
    pub name: String,
    pub session_token: String,
    pub is_host: bool,
    pub is_bot: bool,
}

// === 말 ===
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Piece {
    pub id: usize,
    pub owner: usize,
    pub status: PieceStatus,
    pub position: Option<Position>,
    pub stacked_with: Vec<usize>,   // 업은 말 ID들
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PieceStatus {
    Home,                           // 출발 대기
    OnBoard,                        // 말판 위
    Finished,                       // 완주
}

// === 윷 결과 ===
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum YutResult {
    Do,     // 1칸 이동
    Gae,    // 2칸 이동
    Geol,   // 3칸 이동
    Yut,    // 4칸 이동 + 추가 턴
    Mo,     // 5칸 이동 + 추가 턴
}

impl YutResult {
    pub fn distance(&self) -> u32 {
        match self {
            Self::Do => 1,
            Self::Gae => 2,
            Self::Geol => 3,
            Self::Yut => 4,
            Self::Mo => 5,
        }
    }
    pub fn has_extra_turn(&self) -> bool {
        matches!(self, Self::Yut | Self::Mo)
    }
}

// === 봇 정보 ===
#[derive(Debug, Clone)]
pub struct BotInfo {
    pub player_id: usize,
    pub difficulty: BotDifficulty,  // Easy, Medium, Hard, Expert
}
```

### 2.3 말판 노드 그래프 구현

말판은 **위치 기반 그래프** (`Position = {node, path}`)로 구현:
- **27개 노드:** 외곽 19개(0~18) + 지름길 중간점 8개(20~26)
- **4가지 경로 타입:**
  - `Outer`: 바깥쪽 한 바퀴 (0→1→...→19→0, 완주)
  - `ShortcutA`: 지름길 A (5진입 → 20→22→23→15 → 다시 Outer로)
  - `ShortcutB`: 지름길 B (10/15진입 → 21→22→24→0, 완주)
  - `CenterExit`: 중앙 지름길 (22→25→26→0, 완주)

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Position {
    pub node: u32,
    pub path: Path,     // Outer, ShortcutA, ShortcutB, CenterExit
}

pub struct Board {
    graph: HashMap<Position, Vec<(Position, u32)>>,
}

impl Board {
    pub fn get_next_positions(&self, pos: Position, distance: u32) -> Vec<Position> {
        // BFS로 distance칸 이동 가능한 모든 위치 반환
    }

    pub fn has_junction_at(&self, pos: Position) -> bool {
        // 분기점(지름길 진입 가능)인지 확인
    }

    pub fn apply_path_choice(&self, pos: Position, choice: &str) -> Position {
        // 분기점에서 경로 선택 적용
    }
}
```

### 2.4 Room 관리 (parking_lot::Mutex 기반)

Room은 Actix Actor가 **아니라** `parking_lot::Mutex`로 보호되며, 클라이언트에게 `mpsc` 채널로 메시지를 전달합니다.

```rust
pub type ClientSender = mpsc::UnboundedSender<String>;

#[derive(Debug)]
pub struct Room {
    pub state: GameState,                           // 게임 상태
    pub clients: HashMap<usize, ClientSender>,      // 플레이어 ID → 채널
    pub bots: Vec<BotInfo>,                         // 봇 플레이어 목록
}

impl Room {
    pub fn add_player(&mut self, name: String, session_token: String, sender: ClientSender) -> usize {
        // 플레이어 추가, ID 반환
    }

    pub fn add_bot(&mut self, name: String, difficulty: BotDifficulty) -> usize {
        // 봇 추가 (플레이어로 등록됨)
    }

    pub fn send_to(&self, player_id: usize, msg: &ServerMessage) {
        // 특정 플레이어에게 메시지 전송
    }

    pub fn broadcast(&self, msg: &ServerMessage) {
        // 모든 클라이언트에게 브로드캐스트
    }
}

pub struct RoomManager;

impl RoomManager {
    pub fn create_room(rooms: &RoomMap) -> String {
        // 새 방 생성, 코드 반환
    }

    pub fn find_waiting_room(rooms: &RoomMap) -> Option<String> {
        // 빠른 매칭: 대기 중인 방 찾기
    }

    pub fn get_room(rooms: &RoomMap, code: &str) -> Option<Arc<Mutex<Room>>> {
        // 방 코드로 조회
    }
}
```

---

## 3. 클라이언트 아키텍처 (Godot 4)

### 3.1 프로젝트 구조

```
the-yut-client/
├── project.godot
├── export_presets.cfg          # HTML5 export 설정
├── scenes/
│   ├── main.tscn               # 루트 씬 (씬 전환 관리)
│   ├── title/
│   │   └── title_screen.tscn   # 타이틀 + 로비
│   ├── lobby/
│   │   └── waiting_room.tscn   # 대기실
│   ├── game/
│   │   ├── game_screen.tscn    # 게임 플레이 메인
│   │   ├── board.tscn          # 말판 씬
│   │   ├── piece.tscn          # 말 씬 (인스턴스화)
│   │   ├── yut_throw.tscn      # 윷 던지기 UI + 제스처
│   │   └── result_popup.tscn   # 결과 표시 팝업
│   └── result/
│       └── game_over.tscn      # 게임 종료 화면
├── scripts/
│   ├── autoload/
│   │   ├── network_manager.gd  # WebSocket 싱글톤
│   │   ├── game_state.gd       # 클라이언트 게임 상태
│   │   └── audio_manager.gd    # 사운드 관리
│   ├── game/
│   │   ├── board_controller.gd # 말판 렌더링 + 인터랙션
│   │   ├── piece_controller.gd # 말 애니메이션
│   │   ├── yut_input.gd        # 플릭 제스처 인식
│   │   ├── yut_animation.gd    # 윷 던지기 연출
│   │   └── turn_ui.gd          # 턴 표시 UI
│   └── ui/
│       ├── title_ui.gd
│       ├── lobby_ui.gd
│       └── name_input.gd
├── assets/
│   ├── sprites/
│   │   ├── board/              # 말판 타일셋
│   │   ├── pieces/             # 말 스프라이트 (4종)
│   │   ├── yut_sticks/         # 윷가락 스프라이트시트
│   │   ├── effects/            # 이펙트 스프라이트시트
│   │   └── ui/                 # UI 요소
│   ├── fonts/
│   │   └── gameboy_font.tres   # 픽셀 폰트
│   └── audio/
│       ├── sfx/                # 효과음 (.wav)
│       └── bgm/                # 배경음악 (.ogg)
└── shaders/
    └── crt_effect.gdshader     # 선택적: CRT 스캔라인 효과
```

### 3.2 핵심 씬 트리

```
Main (Node)
├── ScreenManager (Node)         # 화면 전환 관리
├── NetworkManager (Autoload)    # WebSocket 싱글톤
├── GameState (Autoload)         # 상태 관리
├── AudioManager (Autoload)      # 사운드
│
├── TitleScreen (Control)
│   ├── Logo (Sprite2D)          # "The Yut" 애니메이션 로고
│   ├── NameInput (LineEdit)     # 이름 입력
│   ├── QuickStartBtn (Button)
│   ├── CreateRoomBtn (Button)
│   └── JoinRoomBtn (Button)
│
├── WaitingRoom (Control)
│   ├── RoomCode (Label)
│   ├── PlayerList (VBoxContainer)
│   ├── ChangeNameBtn (Button)
│   └── StartGameBtn (Button)    # 방장만 visible
│
└── GameScreen (Node2D)
    ├── Camera2D                  # 픽셀 퍼펙트 카메라
    ├── Board (Node2D)
    │   ├── BoardSprite (Sprite2D)
    │   ├── NodeMarkers (Node2D)  # 각 노드 위치 마커
    │   └── Pieces (Node2D)       # 말 인스턴스 컨테이너
    ├── YutThrowArea (Control)
    │   ├── FlickDetector (Area2D)
    │   └── YutSticks (Node2D)    # 윷가락 애니메이션
    ├── TurnIndicator (Control)
    ├── PlayerInfoBar (HBoxContainer)
    └── EffectsLayer (CanvasLayer) # 화면 흔들림, 플래시 등
```

### 3.3 네트워크 매니저 (GDScript)

```gdscript
# network_manager.gd (Autoload)
extends Node

signal connected
signal disconnected
signal message_received(data: Dictionary)

var _ws := WebSocketPeer.new()
var _server_url: String

func connect_to_server(url: String) -> void:
    _server_url = url
    _ws.connect_to_url(url)

func send_message(data: Dictionary) -> void:
    _ws.send_text(JSON.stringify(data))

func _process(_delta: float) -> void:
    _ws.poll()
    var state = _ws.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        while _ws.get_available_packet_count() > 0:
            var packet = _ws.get_packet()
            var text = packet.get_string_from_utf8()
            var parsed = JSON.parse_string(text)
            if parsed:
                message_received.emit(parsed)
    elif state == WebSocketPeer.STATE_CLOSED:
        disconnected.emit()
```

### 3.4 플릭 제스처 인식

```gdscript
# yut_input.gd
extends Control

signal yut_flicked(power: float, direction: Vector2)

var _touch_start: Vector2
var _touch_start_time: float
var _is_touching := false

const MIN_FLICK_DISTANCE := 50.0
const MAX_FLICK_TIME := 0.5  # 500ms 이내에 플릭 완료

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        if event.pressed:
            _touch_start = event.position
            _touch_start_time = Time.get_ticks_msec() / 1000.0
            _is_touching = true
        elif _is_touching:
            _is_touching = false
            var end_pos = event.position
            var delta = end_pos - _touch_start
            var distance = delta.length()
            var elapsed = (Time.get_ticks_msec() / 1000.0) - _touch_start_time

            if distance >= MIN_FLICK_DISTANCE and elapsed <= MAX_FLICK_TIME:
                var power = clamp(distance / 300.0, 0.0, 1.0)
                yut_flicked.emit(power, delta.normalized())
```

### 3.5 말 이동 애니메이션 시스템

```gdscript
# piece_controller.gd
extends Node2D

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

func animate_move(path: Array[Vector2], on_complete: Callable) -> void:
    # 칸 단위 홉 애니메이션
    var tween = create_tween()
    for i in range(path.size()):
        var target = path[i]
        # 점프 곡선: 위로 올라갔다 내려오기
        tween.tween_property(self, "position", target, 0.15) \
            .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        # 스쿼시 & 스트레치
        tween.parallel().tween_property(sprite, "scale",
            Vector2(0.8, 1.3), 0.07).set_trans(Tween.TRANS_QUAD)
        tween.tween_property(sprite, "scale",
            Vector2(1.2, 0.8), 0.05)  # 착지 눌림
        tween.tween_property(sprite, "scale",
            Vector2(1.0, 1.0), 0.03)  # 복원
    tween.tween_callback(on_complete)

func animate_capture(target_pos: Vector2) -> void:
    # 잡힌 말: 튕겨나가며 사라짐
    var tween = create_tween()
    tween.tween_property(self, "position",
        position + Vector2(randf_range(-30, 30), -50), 0.3) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
    tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3)

func animate_stack() -> void:
    # 업기: 위로 살짝 떠서 합체
    var tween = create_tween()
    tween.tween_property(self, "position:y", position.y - 4, 0.1)
    tween.tween_property(self, "position:y", position.y - 2, 0.05)
```

---

## 4. 화면 흔들림 및 이펙트 시스템

```gdscript
# screen_effects.gd (Camera2D에 부착)
extends Camera2D

func shake(intensity: float = 4.0, duration: float = 0.2) -> void:
    var tween = create_tween()
    var original = offset
    for i in range(int(duration / 0.02)):
        var random_offset = Vector2(
            randf_range(-intensity, intensity),
            randf_range(-intensity, intensity)
        )
        tween.tween_property(self, "offset", random_offset, 0.02)
    tween.tween_property(self, "offset", original, 0.02)

func flash(color: Color = Color.WHITE, duration: float = 0.1) -> void:
    # 화면 플래시 (윷/모 시)
    var flash_rect = $FlashRect  # ColorRect, 전체 화면 덮음
    flash_rect.color = color
    flash_rect.visible = true
    var tween = create_tween()
    tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
    tween.tween_callback(func(): flash_rect.visible = false)
```

---

## 5. 로컬 개발 환경 설정

### 5.1 필요 도구

```bash
# Rust 서버
rustup (stable channel)
cargo

# Godot 클라이언트
Godot 4.3+ (standard build — .NET 불필요)

# 로컬 웹 서빙 (개발용)
# 옵션 A: Rust 서버에서 직접 정적 파일도 서빙
# 옵션 B: Python 간이 서버
python -m http.server 8080

# 브라우저: Chrome/Firefox (WebGL 2.0 지원)
```

### 5.2 로컬 실행 흐름

```bash
# 1. Rust 서버 빌드 및 실행
cd the-yut-server
cargo run --release
# → ws://localhost:9001 에서 WebSocket 리스닝
# → http://localhost:9001 에서 정적 파일도 서빙 (Godot export)

# 2. Godot HTML5 export
# Godot Editor → Export → HTML5 → Export Project
# 출력: the-yut-server/static/index.html + .wasm + .pck

# 3. 브라우저에서 접속
# http://localhost:9001
```

### 5.3 Rust 서버의 정적 파일 서빙

```rust
// main.rs — Actix-Web 설정
use actix_files as fs;
use actix_web::{web, App, HttpServer};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/ws", web::get().to(ws_handler))
            .service(fs::Files::new("/", "./static").index_file("index.html"))
    })
    .bind("0.0.0.0:9001")?
    .run()
    .await
}
```

### 5.4 Docker 배포 준비 (릴리즈용)

```dockerfile
# Dockerfile
FROM rust:1.77-slim AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/the-yut-server /usr/local/bin/
COPY --from=builder /app/static /opt/static
ENV STATIC_DIR=/opt/static
EXPOSE 9001
CMD ["the-yut-server"]
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  the-yut:
    build: .
    ports:
      - "9001:9001"
    environment:
      - RUST_LOG=info
      - STATIC_DIR=/opt/static
    restart: unless-stopped
```

---

## 6. 메시지 프로토콜 상세

모든 메시지는 `{type, payload}` JSON 형식:

### 6.1 클라이언트 → 서버

```json
// 방 생성
{ "type": "create_room", "payload": {} }

// 방 입장
{ "type": "join_room", "payload": { "code": "ABCD" } }

// 빠른 매칭
{ "type": "quick_match", "payload": {} }

// 봇 추가 (방장만)
{ "type": "add_bot", "payload": { "difficulty": "medium", "name": "Bot1" } }

// 이름 변경
{ "type": "change_name", "payload": { "name": "PlayerName" } }

// 게임 시작 (방장만)
{ "type": "start_game", "payload": {} }

// 윷 던지기
{ "type": "throw_yut", "payload": {} }

// 말 선택
{ "type": "select_piece", "payload": { "piece_id": 0 } }

// 경로 선택
{ "type": "select_path", "payload": { "choice": "shortcut" } }
```

### 6.2 서버 → 클라이언트

```json
// 방 생성 완료
{ "type": "room_created", "payload": { "code": "ABCD", "player_id": 0, "session_token": "..." } }

// 방 입장 완료
{ "type": "room_joined", "payload": { "room_code": "ABCD", "player_id": 0, "session_token": "...", "players": [...] } }

// 플레이어 입장
{ "type": "player_joined", "payload": { "player_id": 1, "player_name": "Bob" } }

// 플레이어 퇴장
{ "type": "player_left", "payload": { "player_id": 1 } }

// 게임 시작
{ "type": "game_started", "payload": { "players": [...] } }

// 당신의 차례
{ "type": "your_turn", "payload": { "player_id": 0, "can_throw": true } }

// 윷 결과
{ "type": "yut_result", "payload": { "result": "Do", "distance": 1, "extra_turn": false } }

// 말 이동 결과
{ "type": "piece_moved", "payload": { "piece_id": 0, "new_position": 5, "captured": ["player_1_piece_3"], "finished": false } }

// 경로 선택 필요
{ "type": "path_choice_required", "payload": { "piece_id": 2, "available_paths": ["outer", "shortcut"] } }

// 전체 상태 동기화
{ "type": "game_state_sync", "payload": { ...full GameState JSON... } }

// 게임 종료
{ "type": "game_over", "payload": { "winner_id": 0, "winner_name": "Alice" } }

// 에러
{ "type": "error", "payload": { "message": "Invalid move" } }
```

---

## 7. 봇 AI 시스템

서버에 통합된 봇 AI는 4가지 난이도 레벨을 지원합니다:

### 7.1 난이도 레벨

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BotDifficulty {
    Easy,       // 랜덤 선택
    Medium,     // 캡처 선호, 새 말 배치
    Hard,       // 위치 평가, 지름길 활용
    Expert,     // 완전 전략 평가, 스택 고려, 선읽기
}

pub struct BotAI;

impl BotAI {
    /// 주어진 난이도에서 이동할 말 선택
    pub fn choose_piece(
        state: &GameState,
        player_id: usize,
        difficulty: BotDifficulty,
    ) -> Option<usize>

    /// 분기점에서 경로 선택
    pub fn choose_path(
        state: &GameState,
        player_id: usize,
        options: &[String],
        difficulty: BotDifficulty,
    ) -> String
}
```

### 7.2 각 난이도의 전략

| 난이도 | 말 선택 전략 | 경로 선택 |
|--------|-----------|---------|
| **Easy** | 완주 가능한 말 → 기존 말 → 새 말 (랜덤) | 완전 랜덤 |
| **Medium** | 캡처 기회 우선(+50점) → 새 말 배치(+10점) → 기타 | 지름길 선호 |
| **Hard** | 완주 근처(+100점) → 캡처 → 지름길 위치(+20점) | 지름길 선호 |
| **Expert** | 재귀적 미니맥스 평가 (2턴 선읽기, 상대 위협 평가) | 지름길 선호 + 센터 탈출 고려 |

### 7.3 봇 추가 및 관리

```rust
// 방에 봇 추가
pub fn add_bot(&mut self, name: String, difficulty: BotDifficulty) -> usize {
    let player_id = self.state.add_bot(name);
    self.bots.push(BotInfo { player_id, difficulty });
    player_id
}

// 봇 정보 조회
pub fn get_bot_info(&self, player_id: usize) -> Option<&BotInfo>
```

### 7.4 봇의 자동 턴 처리

봇이 현재 플레이어일 때, 서버는 자동으로:
1. 윷 던지기 (난이도별 확률 없음 - 같은 RNG 사용)
2. 이동할 말 선택 (`choose_piece`)
3. 경로 선택 (`choose_path`)
4. 게임 상태 업데이트 및 브로드캐스트

---

## 8. 보안 및 치트 방지

1. **서버 권위 모델:** 모든 윷 결과와 이동 유효성은 서버에서만 계산
2. **세션 토큰:** 방 참가 시 UUID로 발급, 재접속 시 검증
3. **입력 검증:** 클라이언트에서 보내는 모든 메시지를 서버에서 검증
   - 현재 턴 플레이어 확인
   - 소유한 말인지 확인
   - 게임 단계 검증
4. **상태 동기화:** 행동 후 전체 상태를 브로드캐스트하여 desync 방지

---

## 9. 성능 고려사항

- **WebSocket 메시지 크기:** 턴제 게임이므로 메시지 빈도 낮음 (초당 1-2회 미만)
- **Godot WASM 크기:** 스프라이트 최적화로 3MB 이하 목표
- **동시 방 수:** `parking_lot::Mutex` 기반 경량 구조, 수천 개 동시 가능
- **메모리:** 방당 ~50KB (게임 상태 + 메시지 큐), 서버 1GB RAM으로 만 단위 방 가능
- **봇 AI:** 각 봇 턴마다 O(n²) 평가 (n=말의 수, 최대 16), 밀리초 단위 실행
