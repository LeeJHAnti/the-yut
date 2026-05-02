use std::collections::HashMap;
use std::sync::Arc;
use parking_lot::Mutex;
use rand::Rng;
use serde_json::json;
use tokio::sync::mpsc;

use crate::bot::BotDifficulty;
use crate::game::state::GameState;
use crate::messages::ServerMessage;

pub type RoomMap = Arc<parking_lot::Mutex<HashMap<String, Arc<Mutex<Room>>>>>;
pub type ClientSender = mpsc::UnboundedSender<String>;

/// Info about a bot player in the room
#[derive(Debug, Clone)]
pub struct BotInfo {
    pub player_id: usize,
    pub difficulty: BotDifficulty,
}

#[derive(Debug)]
pub struct Room {
    pub state: GameState,
    pub clients: HashMap<usize, ClientSender>,
    pub bots: Vec<BotInfo>,
}

impl Room {
    pub fn new() -> Self {
        Self {
            state: GameState::new(),
            clients: HashMap::new(),
            bots: Vec::new(),
        }
    }

    pub fn add_player(&mut self, name: String, session_token: String, sender: ClientSender) -> usize {
        let player_id = self.state.add_player(name, session_token);
        self.clients.insert(player_id, sender);
        player_id
    }

    pub fn add_bot(&mut self, name: String, difficulty: BotDifficulty) -> usize {
        let player_id = self.state.add_bot(name);
        self.bots.push(BotInfo {
            player_id,
            difficulty,
        });
        player_id
    }

    pub fn remove_player(&mut self, player_id: usize) {
        self.state.remove_player(player_id);
        self.clients.remove(&player_id);
        self.bots.retain(|b| b.player_id != player_id);
    }

    pub fn player_count(&self) -> usize {
        self.state.players.len()
    }

    pub fn is_full(&self) -> bool {
        self.state.players.len() >= 4
    }

    pub fn is_empty(&self) -> bool {
        // Only consider human players when checking if room is empty
        self.clients.is_empty()
    }

    pub fn is_waiting(&self) -> bool {
        self.state.phase == crate::game::state::GamePhase::WaitingForPlayers
    }

    /// Get bot info for a given player ID, if they are a bot
    pub fn get_bot_info(&self, player_id: usize) -> Option<&BotInfo> {
        self.bots.iter().find(|b| b.player_id == player_id)
    }

    pub fn send_to(&self, player_id: usize, msg: &ServerMessage) {
        if let Some(sender) = self.clients.get(&player_id) {
            let _ = sender.send(msg.as_json());
        }
    }

    pub fn broadcast(&self, msg: &ServerMessage) {
        let json = msg.as_json();
        for sender in self.clients.values() {
            let _ = sender.send(json.clone());
        }
    }

    pub fn broadcast_except(&self, exclude_id: usize, msg: &ServerMessage) {
        let json = msg.as_json();
        for (id, sender) in &self.clients {
            if *id != exclude_id {
                let _ = sender.send(json.clone());
            }
        }
    }

    pub fn get_players_json(&self) -> Vec<serde_json::Value> {
        self.state.players.iter().map(|p| {
            json!({
                "id": p.id,
                "name": &p.name,
                "is_host": p.is_host,
                "is_bot": p.is_bot,
            })
        }).collect()
    }
}

fn generate_room_code() -> String {
    let mut rng = rand::thread_rng();
    let chars: Vec<char> = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars().collect();
    (0..4).map(|_| chars[rng.gen_range(0..chars.len())]).collect()
}

pub struct RoomManager;

impl RoomManager {
    pub fn create_room(rooms: &RoomMap) -> String {
        let mut rooms_lock = rooms.lock();
        loop {
            let code = generate_room_code();
            if !rooms_lock.contains_key(&code) {
                rooms_lock.insert(code.clone(), Arc::new(Mutex::new(Room::new())));
                return code;
            }
        }
    }

    pub fn find_waiting_room(rooms: &RoomMap) -> Option<String> {
        let rooms_lock = rooms.lock();
        for (code, room) in rooms_lock.iter() {
            let room_lock = room.lock();
            if room_lock.is_waiting() && !room_lock.is_full() && room_lock.player_count() > 0 {
                return Some(code.clone());
            }
        }
        None
    }

    pub fn get_room(rooms: &RoomMap, code: &str) -> Option<Arc<Mutex<Room>>> {
        let rooms_lock = rooms.lock();
        rooms_lock.get(code).cloned()
    }

    pub fn remove_room(rooms: &RoomMap, code: &str) {
        let mut rooms_lock = rooms.lock();
        rooms_lock.remove(code);
    }
}
