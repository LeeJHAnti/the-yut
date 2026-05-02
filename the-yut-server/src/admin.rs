use actix_web::{web, HttpResponse};
use serde_json::{json, Value};

use crate::room::{RoomMap, RoomManager};
use crate::game::state::GamePhase;

/// GET /admin/rooms — List all rooms with their status, player count, phase, player names
pub async fn list_rooms(rooms: web::Data<RoomMap>) -> HttpResponse {
    let rooms_lock = rooms.lock();

    let mut room_list = Vec::new();
    for (code, room_arc) in rooms_lock.iter() {
        let room = room_arc.lock();
        let player_names: Vec<String> = room.state.players.iter().map(|p| p.name.clone()).collect();

        room_list.push(json!({
            "code": code,
            "player_count": room.state.players.len(),
            "player_names": player_names,
            "phase": format!("{:?}", room.state.phase),
            "has_winner": room.state.winner.is_some(),
            "bot_count": room.bots.len(),
            "human_count": room.clients.len(),
        }));
    }

    log::info!("Admin: Listed {} rooms", room_list.len());

    HttpResponse::Ok().json(json!({
        "success": true,
        "total_rooms": room_list.len(),
        "rooms": room_list,
    }))
}

/// GET /admin/rooms/{code} — Detailed room info including pieces, turn state
pub async fn get_room_detail(
    code: web::Path<String>,
    rooms: web::Data<RoomMap>,
) -> HttpResponse {
    let code = code.into_inner();
    let rooms_lock = rooms.lock();

    match rooms_lock.get(&code) {
        Some(room_arc) => {
            let room = room_arc.lock();

            let players: Vec<Value> = room.state.players.iter().map(|p| {
                json!({
                    "id": p.id,
                    "name": &p.name,
                    "is_host": p.is_host,
                    "is_bot": p.is_bot,
                })
            }).collect();

            let pieces: Vec<Value> = room.state.pieces.iter().map(|p| {
                json!({
                    "id": p.id,
                    "owner": p.owner,
                    "status": format!("{:?}", p.status),
                    "node": p.position.map(|pos| pos.node),
                    "path": p.position.map(|pos| format!("{:?}", pos.path)),
                    "stacked_with": p.stacked_with,
                })
            }).collect();

            let pending_results: Vec<String> = room.state.turn.pending_results.iter()
                .map(|r| r.as_string())
                .collect();

            log::info!("Admin: Retrieved details for room {}", code);

            HttpResponse::Ok().json(json!({
                "success": true,
                "code": &code,
                "phase": format!("{:?}", room.state.phase),
                "current_turn": room.state.turn.current_player,
                "must_throw": room.state.turn.should_throw(),
                "winner": room.state.winner,
                "pending_piece_id": room.state.pending_piece_id,
                "pending_distance": room.state.pending_distance,
                "players": players,
                "pieces": pieces,
                "pending_results": pending_results,
                "clients_connected": room.clients.len(),
                "bots_count": room.bots.len(),
            }))
        }
        None => {
            log::warn!("Admin: Room {} not found", code);
            HttpResponse::NotFound().json(json!({
                "success": false,
                "error": format!("Room {} not found", code),
            }))
        }
    }
}

/// DELETE /admin/rooms/{code} — Force delete a room (disconnect all players)
pub async fn delete_room(
    code: web::Path<String>,
    rooms: web::Data<RoomMap>,
) -> HttpResponse {
    let code = code.into_inner();
    let mut rooms_lock = rooms.lock();

    if rooms_lock.contains_key(&code) {
        let room_arc = rooms_lock.remove(&code).unwrap();
        let room = room_arc.lock();
        let player_count = room.state.players.len();

        log::warn!("Admin: Forced deletion of room {} with {} players", code, player_count);

        HttpResponse::Ok().json(json!({
            "success": true,
            "message": format!("Room {} deleted", code),
            "players_disconnected": player_count,
        }))
    } else {
        log::warn!("Admin: Attempted to delete non-existent room {}", code);
        HttpResponse::NotFound().json(json!({
            "success": false,
            "error": format!("Room {} not found", code),
        }))
    }
}

/// DELETE /admin/rooms/{code}/players/{player_id} — Kick a player from a room
pub async fn kick_player(
    path: web::Path<(String, usize)>,
    rooms: web::Data<RoomMap>,
) -> HttpResponse {
    let (code, player_id) = path.into_inner();
    let rooms_lock = rooms.lock();

    match rooms_lock.get(&code) {
        Some(room_arc) => {
            let mut room = room_arc.lock();

            // Find player name before removing
            let player_name = room.state.players.iter()
                .find(|p| p.id == player_id)
                .map(|p| p.name.clone());

            match player_name {
                Some(name) => {
                    room.remove_player(player_id);
                    log::warn!("Admin: Kicked player {} ({}) from room {}", player_id, name, code);

                    HttpResponse::Ok().json(json!({
                        "success": true,
                        "message": format!("Player {} kicked from room {}", player_id, code),
                        "player_name": name,
                        "remaining_players": room.state.players.len(),
                    }))
                }
                None => {
                    log::warn!("Admin: Attempted to kick non-existent player {} from room {}", player_id, code);
                    HttpResponse::NotFound().json(json!({
                        "success": false,
                        "error": format!("Player {} not found in room {}", player_id, code),
                    }))
                }
            }
        }
        None => {
            log::warn!("Admin: Attempted to access non-existent room {}", code);
            HttpResponse::NotFound().json(json!({
                "success": false,
                "error": format!("Room {} not found", code),
            }))
        }
    }
}

/// GET /admin/stats — Server stats (total rooms, total players, total active games)
pub async fn get_server_stats(rooms: web::Data<RoomMap>) -> HttpResponse {
    let rooms_lock = rooms.lock();

    let mut total_players = 0;
    let mut total_humans = 0;
    let mut total_bots = 0;
    let mut active_games = 0;
    let mut waiting_rooms = 0;
    let mut games_over = 0;

    for room_arc in rooms_lock.values() {
        let room = room_arc.lock();
        total_players += room.state.players.len();
        total_humans += room.clients.len();
        total_bots += room.bots.len();

        match room.state.phase {
            GamePhase::GameOver => games_over += 1,
            GamePhase::WaitingForPlayers => waiting_rooms += 1,
            _ => active_games += 1,
        }
    }

    log::info!(
        "Admin: Server stats — {} rooms, {} total players ({} humans, {} bots), {} active games",
        rooms_lock.len(),
        total_players,
        total_humans,
        total_bots,
        active_games,
    );

    HttpResponse::Ok().json(json!({
        "success": true,
        "total_rooms": rooms_lock.len(),
        "total_players": total_players,
        "total_human_players": total_humans,
        "total_bot_players": total_bots,
        "active_games": active_games,
        "waiting_for_players_rooms": waiting_rooms,
        "games_over": games_over,
    }))
}
