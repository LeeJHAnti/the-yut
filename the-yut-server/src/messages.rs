use serde::{Deserialize, Serialize};
use serde_json::json;

/// Client-to-server message format.
/// The client sends JSON with `{type, payload}` structure.
/// We only deserialize on the server side — no builder methods needed.
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ClientMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    #[serde(default)]
    pub payload: serde_json::Value,
}

/// Server-to-client message format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerMessage {
    #[serde(rename = "type")]
    pub msg_type: String,
    #[serde(default)]
    pub payload: serde_json::Value,
}

impl ServerMessage {
    pub fn room_created(code: String, player_id: String, session_token: String) -> Self {
        Self {
            msg_type: "room_created".to_string(),
            payload: json!({
                "code": code,
                "player_id": player_id,
                "session_token": session_token,
            }),
        }
    }

    pub fn room_joined(room_code: String, player_id: String, session_token: String, players: Vec<serde_json::Value>) -> Self {
        Self {
            msg_type: "room_joined".to_string(),
            payload: json!({
                "room_code": room_code,
                "player_id": player_id,
                "session_token": session_token,
                "players": players,
            }),
        }
    }

    pub fn player_joined(player_id: String, player_name: String) -> Self {
        Self {
            msg_type: "player_joined".to_string(),
            payload: json!({
                "player_id": player_id,
                "player_name": player_name,
            }),
        }
    }

    pub fn player_left(player_id: String) -> Self {
        Self {
            msg_type: "player_left".to_string(),
            payload: json!({
                "player_id": player_id,
            }),
        }
    }

    pub fn game_started(players: Vec<serde_json::Value>) -> Self {
        Self {
            msg_type: "game_started".to_string(),
            payload: json!({
                "players": players,
            }),
        }
    }

    pub fn your_turn(player_id: String, can_throw: bool) -> Self {
        Self {
            msg_type: "your_turn".to_string(),
            payload: json!({
                "player_id": player_id,
                "can_throw": can_throw,
            }),
        }
    }

    pub fn yut_result(result: String, distance: u32, extra_turn: bool) -> Self {
        Self {
            msg_type: "yut_result".to_string(),
            payload: json!({
                "result": result,
                "distance": distance,
                "extra_turn": extra_turn,
            }),
        }
    }

    pub fn piece_moved(piece_id: u32, new_position: u32, captured: Vec<String>, finished: bool) -> Self {
        Self {
            msg_type: "piece_moved".to_string(),
            payload: json!({
                "piece_id": piece_id,
                "new_position": new_position,
                "captured": captured,
                "finished": finished,
            }),
        }
    }

    pub fn path_choice_required(piece_id: u32, available_paths: Vec<String>) -> Self {
        Self {
            msg_type: "path_choice_required".to_string(),
            payload: json!({
                "piece_id": piece_id,
                "available_paths": available_paths,
            }),
        }
    }

    pub fn game_state_sync(state: serde_json::Value) -> Self {
        Self {
            msg_type: "game_state_sync".to_string(),
            payload: state,
        }
    }

    pub fn game_over(winner_id: String, winner_name: String) -> Self {
        Self {
            msg_type: "game_over".to_string(),
            payload: json!({
                "winner_id": winner_id,
                "winner_name": winner_name,
            }),
        }
    }

    pub fn error(message: String) -> Self {
        Self {
            msg_type: "error".to_string(),
            payload: json!({
                "message": message,
            }),
        }
    }

    pub fn as_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
}
