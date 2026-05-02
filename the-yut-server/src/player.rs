use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerSession {
    pub player_id: usize,
    pub name: String,
    pub session_token: String,
    pub room_code: Option<String>,
    pub connected: bool,
}

impl PlayerSession {
    pub fn new(player_id: usize, name: String, session_token: String) -> Self {
        Self {
            player_id,
            name,
            session_token,
            room_code: None,
            connected: true,
        }
    }
}
