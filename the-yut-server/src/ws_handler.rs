use actix_web::{web, HttpRequest, HttpResponse};
use actix_ws::Message;
use futures_util::StreamExt;
use tokio::sync::mpsc;
use uuid::Uuid;
use std::time::Duration;

use crate::bot::{BotAI, BotDifficulty};
use crate::messages::{ClientMessage, ServerMessage};
use crate::room::{RoomMap, RoomManager};
use crate::game::state::{GamePhase, MoveResult};

/// Delay (ms) after a yut throw — must be longer than the client animation.
/// Client yut animation takes ~1.7s (normal) / ~2.4s (extra turn).
const BOT_THROW_DELAY_MS: u64 = 2000;
const BOT_EXTRA_THROW_DELAY_MS: u64 = 2800;
/// Delay (ms) after piece selection / path selection (no yut animation playing).
const BOT_ACTION_DELAY_MS: u64 = 1200;

struct WsClient {
    player_id: Option<usize>,
    room_code: Option<String>,
    name: String,
    session_token: String,
    sender: mpsc::UnboundedSender<String>,
}

pub async fn ws_handler(
    req: HttpRequest,
    stream: web::Payload,
    rooms: web::Data<RoomMap>,
) -> Result<HttpResponse, actix_web::Error> {
    log::info!("WebSocket connection request from {:?}", req.peer_addr());
    let (response, session, msg_stream) = actix_ws::handle(&req, stream)?;
    log::info!("WebSocket handshake successful");

    let rooms_clone = rooms.get_ref().clone();

    // Spawn the entire WebSocket session handling as a background task.
    // This allows Ok(response) to be returned immediately, completing
    // the HTTP 101 upgrade so the client's ws.onopen fires.
    actix_rt::spawn(ws_session(session, msg_stream, rooms_clone));

    Ok(response)
}

async fn ws_session(
    mut session: actix_ws::Session,
    mut msg_stream: actix_ws::MessageStream,
    rooms: RoomMap,
) {
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();

    let mut client = WsClient {
        player_id: None,
        room_code: None,
        name: format!("Player_{}", &Uuid::new_v4().to_string()[..4]),
        session_token: Uuid::new_v4().to_string(),
        sender: tx,
    };

    let mut session_clone = session.clone();

    // Task: forward messages from channel to WebSocket
    actix_rt::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if session_clone.text(msg).await.is_err() {
                break;
            }
        }
    });

    // Main message loop
    while let Some(Ok(msg)) = msg_stream.next().await {
        match msg {
            Message::Text(text) => {
                let text_str = text.to_string();
                if let Ok(client_msg) = serde_json::from_str::<ClientMessage>(&text_str) {
                    handle_message(&mut client, &client_msg, &rooms, &mut session).await;
                } else {
                    let err = ServerMessage::error("Invalid message format".to_string());
                    let _ = session.text(err.as_json()).await;
                }
            }
            Message::Ping(bytes) => {
                let _ = session.pong(&bytes).await;
            }
            Message::Close(_) => {
                log::info!("WebSocket close frame received");
                handle_disconnect(&client, &rooms).await;
                break;
            }
            _ => {}
        }
    }

    log::info!("WebSocket session ended for {:?}", client.player_id);
    handle_disconnect(&client, &rooms).await;
}

async fn handle_disconnect(client: &WsClient, rooms: &RoomMap) {
    if let (Some(room_code), Some(player_id)) = (&client.room_code, client.player_id) {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();
            let player_name = room.state.players.iter()
                .find(|p| p.id == player_id)
                .map(|p| p.name.clone())
                .unwrap_or_else(|| "Unknown".to_string());

            log::info!("Player '{}' (ID: {}) left room {}", player_name, player_id, room_code);

            let msg = ServerMessage::player_left(player_id.to_string());
            room.broadcast_except(player_id, &msg);
            room.remove_player(player_id);
            if room.is_empty() {
                drop(room);
                RoomManager::remove_room(rooms, room_code);
                log::info!("Room {} deleted (all players left)", room_code);
            }
        }
    }
}

async fn handle_message(
    client: &mut WsClient,
    msg: &ClientMessage,
    rooms: &RoomMap,
    session: &mut actix_ws::Session,
) {
    match msg.msg_type.as_str() {
        "create_room" => handle_create_room(client, rooms).await,
        "join_room" => {
            let code = msg.payload.get("code")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            handle_join_room(client, rooms, session, &code).await;
        }
        "quick_match" => handle_quick_match(client, rooms, session).await,
        "change_name" => {
            let name = msg.payload.get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            handle_change_name(client, rooms, session, &name).await;
        }
        "start_game" => handle_start_game(client, rooms, session).await,
        "throw_yut" => handle_throw_yut(client, rooms).await,
        "order_throw" => handle_order_throw(client, rooms).await,
        "select_piece" => {
            let piece_id = msg.payload.get("piece_id")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as usize;
            let result_index = msg.payload.get("result_index")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as usize;
            handle_select_piece(client, rooms, piece_id, result_index).await;
        }
        "select_path" => {
            let choice = msg.payload.get("path_choice")
                .and_then(|v| v.as_str())
                .unwrap_or("outer")
                .to_string();
            handle_select_path(client, rooms, &choice).await;
        }
        "add_bot" => {
            let difficulty = msg.payload.get("difficulty")
                .and_then(|v| v.as_str())
                .unwrap_or("easy")
                .to_string();
            handle_add_bot(client, rooms, session, &difficulty).await;
        }
        "heartbeat" => {
            // Acknowledged silently
        }
        _ => {
            let err = ServerMessage::error(format!("Unknown message type: {}", msg.msg_type));
            let _ = session.text(err.as_json()).await;
        }
    }
}

/// Leave the current room (if any). Cleans up the player from the room,
/// notifies other players, and deletes the room if empty.
async fn leave_current_room(client: &mut WsClient, rooms: &RoomMap) {
    if let (Some(room_code), Some(player_id)) = (&client.room_code, client.player_id) {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();
            let player_name = room.state.players.iter()
                .find(|p| p.id == player_id)
                .map(|p| p.name.clone())
                .unwrap_or_else(|| "Unknown".to_string());

            log::info!("Player '{}' (ID: {}) leaving room {} (auto-leave)", player_name, player_id, room_code);

            let msg = ServerMessage::player_left(player_id.to_string());
            room.broadcast_except(player_id, &msg);
            room.remove_player(player_id);
            if room.is_empty() {
                let code = room_code.clone();
                drop(room);
                RoomManager::remove_room(rooms, &code);
                log::info!("Room {} deleted (all players left after auto-leave)", code);
            }
        }
        client.room_code = None;
        client.player_id = None;
    }
}

async fn handle_create_room(client: &mut WsClient, rooms: &RoomMap) {
    // Auto-leave current room if already in one (prevents ghost players)
    leave_current_room(client, rooms).await;

    let code = RoomManager::create_room(rooms);
    if let Some(room_arc) = RoomManager::get_room(rooms, &code) {
        let mut room = room_arc.lock();
        let player_id = room.add_player(
            client.name.clone(),
            client.session_token.clone(),
            client.sender.clone(),
        );
        client.player_id = Some(player_id);
        client.room_code = Some(code.clone());

        log::info!("Room created: code={}, player_id={}, player_name='{}' (host)", code, player_id, client.name);

        let msg = ServerMessage::room_created(
            code,
            player_id.to_string(),
            client.session_token.clone(),
        );
        room.send_to(player_id, &msg);
    }
}

async fn handle_join_room(client: &mut WsClient, rooms: &RoomMap, session: &mut actix_ws::Session, code: &str) {
    let code_upper = code.to_uppercase();

    // Prevent joining the same room you're already in
    if let Some(ref current_code) = client.room_code {
        if current_code == &code_upper {
            let err = ServerMessage::error("Already in this room".to_string());
            let _ = session.text(err.as_json()).await;
            return;
        }
    }

    // Auto-leave current room if already in one
    leave_current_room(client, rooms).await;

    if let Some(room_arc) = RoomManager::get_room(rooms, &code_upper) {
        let mut room = room_arc.lock();
        if room.is_full() {
            let err = ServerMessage::error("Room is full".to_string());
            let _ = session.text(err.as_json()).await;
            return;
        }
        if !room.is_waiting() {
            let err = ServerMessage::error("Game already in progress".to_string());
            let _ = session.text(err.as_json()).await;
            return;
        }

        let player_id = room.add_player(
            client.name.clone(),
            client.session_token.clone(),
            client.sender.clone(),
        );
        client.player_id = Some(player_id);
        client.room_code = Some(code_upper.clone());

        log::info!("Player '{}' (ID: {}) joined room {}", client.name, player_id, code_upper);

        let players = room.get_players_json();
        let join_msg = ServerMessage::room_joined(
            code_upper,
            player_id.to_string(),
            client.session_token.clone(),
            players,
        );
        room.send_to(player_id, &join_msg);

        let notify = ServerMessage::player_joined(player_id.to_string(), client.name.clone());
        room.broadcast_except(player_id, &notify);
    } else {
        let err = ServerMessage::error("Room not found".to_string());
        let _ = session.text(err.as_json()).await;
    }
}

async fn handle_quick_match(client: &mut WsClient, rooms: &RoomMap, session: &mut actix_ws::Session) {
    if let Some(code) = RoomManager::find_waiting_room(rooms) {
        handle_join_room(client, rooms, session, &code).await;
    } else {
        handle_create_room(client, rooms).await;
    }
}

async fn handle_change_name(client: &mut WsClient, rooms: &RoomMap, session: &mut actix_ws::Session, name: &str) {
    if name.is_empty() || name.len() > 20 {
        let err = ServerMessage::error("Name must be 1-20 characters".to_string());
        let _ = session.text(err.as_json()).await;
        return;
    }
    client.name = name.to_string();

    if let (Some(room_code), Some(player_id)) = (&client.room_code, client.player_id) {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();
            let _ = room.state.change_player_name(player_id, name.to_string());
            let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
            room.broadcast(&sync);
        }
    }
}

async fn handle_add_bot(client: &mut WsClient, rooms: &RoomMap, session: &mut actix_ws::Session, difficulty: &str) {
    let player_id = match client.player_id {
        Some(id) => id,
        None => {
            let err = ServerMessage::error("Not in a room".to_string());
            let _ = session.text(err.as_json()).await;
            return;
        }
    };

    if let Some(room_code) = &client.room_code {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();

            // Only host can add bots
            if let Some(player) = room.state.players.iter().find(|p| p.id == player_id) {
                if !player.is_host {
                    let err = ServerMessage::error("Only host can add bots".to_string());
                    room.send_to(player_id, &err);
                    return;
                }
            }

            if room.is_full() {
                let err = ServerMessage::error("Room is full".to_string());
                room.send_to(player_id, &err);
                return;
            }

            let bot_difficulty = BotDifficulty::from_str(difficulty);
            let bot_name = format!("Bot_{}", bot_difficulty.name());
            let bot_id = room.add_bot(bot_name.clone(), bot_difficulty.clone());

            log::info!("Bot '{}' (difficulty: {:?}, ID: {}) added to room {} by player {}",
                      bot_name, bot_difficulty, bot_id, room_code, player_id);

            let notify = ServerMessage::player_joined(bot_id.to_string(), bot_name);
            room.broadcast(&notify);

            let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
            room.broadcast(&sync);
        }
    }
}

async fn handle_start_game(client: &mut WsClient, rooms: &RoomMap, session: &mut actix_ws::Session) {
    let player_id = match client.player_id {
        Some(id) => id,
        None => {
            let err = ServerMessage::error("Not in a room".to_string());
            let _ = session.text(err.as_json()).await;
            return;
        }
    };

    if let Some(room_code) = &client.room_code {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();

            if let Some(player) = room.state.players.iter().find(|p| p.id == player_id) {
                if !player.is_host {
                    let err = ServerMessage::error("Only host can start the game".to_string());
                    room.send_to(player_id, &err);
                    return;
                }
            }

            match room.state.start_game() {
                Ok(()) => {
                    let player_names: Vec<String> = room.state.players.iter().map(|p| p.name.clone()).collect();
                    log::info!("Game started in room {}: {} players: {:?}",
                              room_code, room.state.players.len(), player_names);

                    let players = room.get_players_json();
                    let msg = ServerMessage::game_started(players);
                    room.broadcast(&msg);

                    // Send full state sync so clients have pieces data immediately
                    let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                    room.broadcast(&sync);

                    // Game starts in DecidingOrder phase — notify who throws first
                    if room.state.phase == GamePhase::DecidingOrder {
                        if let Some(first_thrower) = room.state.order_current_thrower() {
                            let turn_msg = ServerMessage::order_your_turn(first_thrower.to_string());
                            room.broadcast(&turn_msg);

                            // If first thrower is a bot, schedule order throw
                            if room.state.players.iter().any(|p| p.id == first_thrower && p.is_bot) {
                                let rooms_clone = rooms.clone();
                                let code_clone = room_code.clone();
                                drop(room);
                                schedule_bot_turn(rooms_clone, code_clone, BOT_ACTION_DELAY_MS);
                                return;
                            }
                        }
                    } else {
                        // Fallback: if somehow already past DecidingOrder
                        let current = room.state.turn.current_player;
                        let turn_msg = ServerMessage::your_turn(current.to_string(), true);
                        room.broadcast(&turn_msg);

                        if check_needs_bot_turn(&room) {
                            let rooms_clone = rooms.clone();
                            let code_clone = room_code.clone();
                            drop(room);
                            schedule_bot_turn(rooms_clone, code_clone, BOT_ACTION_DELAY_MS);
                            return;
                        }
                    }
                }
                Err(e) => {
                    let err = ServerMessage::error(e);
                    room.send_to(player_id, &err);
                }
            }
        }
    }
}

async fn handle_throw_yut(client: &mut WsClient, rooms: &RoomMap) {
    let player_id = match client.player_id {
        Some(id) => id,
        None => return,
    };

    if let Some(room_code) = &client.room_code {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();

            match room.state.throw_yut(player_id) {
                Ok(result) => {
                    // Use the result's own extra-turn flag (not should_throw())
                    // because auto_skip_unusable_backdo() inside throw_yut may
                    // have advanced the turn, flipping should_throw() to true
                    // for the NEXT player — which would skip the sync/turn messages.
                    let grants_extra = result.has_extra_turn();
                    let msg = ServerMessage::yut_result(
                        result.as_string(),
                        result.distance(),
                        grants_extra,
                    );
                    room.broadcast(&msg);

                    if !grants_extra {
                        // Check if completed_circuit pieces were auto-finished
                        // (auto_finish_completed_circuit runs inside throw_yut)
                        if room.state.phase == GamePhase::GameOver {
                            // Auto-finish triggered game over
                            let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                            room.broadcast(&sync);

                            if let Some(winner_id) = room.state.winner {
                                let winner_name = room.state.get_winner_display_name(winner_id);
                                log::info!("Game ended (auto-finish): winner='{}' (ID: {})", winner_name, winner_id);
                                let go_msg = ServerMessage::game_over(
                                    winner_id.to_string(),
                                    winner_name,
                                );
                                room.broadcast(&go_msg);
                            }
                            return;
                        }

                        // This throw didn't grant an extra turn, so the throwing
                        // sub-phase for this result is done.  Send state sync.
                        let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                        room.broadcast(&sync);

                        // Check if BackDo was auto-skipped or auto-finish
                        // advanced the turn
                        let current_turn = room.state.turn.current_player;
                        if current_turn != player_id {
                            let turn_msg = ServerMessage::your_turn(
                                current_turn.to_string(),
                                room.state.turn.should_throw(),
                            );
                            room.broadcast(&turn_msg);

                            // If next player is a bot, schedule its turn
                            if check_needs_bot_turn(&room) {
                                let rooms_clone = rooms.clone();
                                let code_clone = room_code.clone();
                                drop(room);
                                schedule_bot_turn(rooms_clone, code_clone, BOT_ACTION_DELAY_MS);
                                return;
                            }
                        }
                    }
                }
                Err(e) => {
                    let err = ServerMessage::error(e);
                    room.send_to(player_id, &err);
                }
            }
        }
    }
}

async fn handle_order_throw(client: &mut WsClient, rooms: &RoomMap) {
    let player_id = match client.player_id {
        Some(id) => id,
        None => return,
    };

    if let Some(room_code) = &client.room_code {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let mut room = room_arc.lock();

            match room.state.order_throw(player_id) {
                Ok((result, all_done)) => {
                    // Broadcast the throw result
                    let msg = ServerMessage::order_throw_result(
                        player_id.to_string(),
                        result.as_string(),
                        result.distance(),
                    );
                    room.broadcast(&msg);

                    if all_done {
                        // Order decided — broadcast final order
                        let player_order: Vec<serde_json::Value> = room.state.players.iter()
                            .map(|p| serde_json::json!({
                                "id": p.id,
                                "name": &p.name,
                            }))
                            .collect();
                        let decided_msg = ServerMessage::order_decided(player_order);
                        room.broadcast(&decided_msg);

                        // Send sync with new phase (Throwing) and updated player order
                        let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                        room.broadcast(&sync);

                        // Notify first player it's their turn to throw
                        let current = room.state.turn.current_player;
                        let turn_msg = ServerMessage::your_turn(current.to_string(), true);
                        room.broadcast(&turn_msg);

                        // Bot scheduling for first actual turn
                        if check_needs_bot_turn(&room) {
                            let rooms_clone = rooms.clone();
                            let code_clone = room_code.clone();
                            drop(room);
                            schedule_bot_turn(rooms_clone, code_clone, BOT_ACTION_DELAY_MS);
                        }
                    } else {
                        // Check if there was a tie (throwers were reset)
                        let throwers_reset = room.state.order_current_idx == 0
                            && room.state.order_results.is_empty();
                        if throwers_reset {
                            let tied_ids: Vec<String> = room.state.order_throwers.iter()
                                .map(|id| id.to_string())
                                .collect();
                            let tie_msg = ServerMessage::order_tie(tied_ids);
                            room.broadcast(&tie_msg);
                        }

                        // Send sync
                        let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                        room.broadcast(&sync);

                        // Notify next thrower
                        if let Some(next_thrower) = room.state.order_current_thrower() {
                            let turn_msg = ServerMessage::order_your_turn(next_thrower.to_string());
                            room.broadcast(&turn_msg);

                            // If next thrower is a bot, schedule
                            if room.state.players.iter().any(|p| p.id == next_thrower && p.is_bot) {
                                let rooms_clone = rooms.clone();
                                let code_clone = room_code.clone();
                                drop(room);
                                schedule_bot_turn(rooms_clone, code_clone, BOT_THROW_DELAY_MS);
                            }
                        }
                    }
                }
                Err(e) => {
                    let err = ServerMessage::error(e);
                    room.send_to(player_id, &err);
                }
            }
        }
    }
}

async fn handle_select_piece(client: &mut WsClient, rooms: &RoomMap, piece_id: usize, result_index: usize) {
    let player_id = match client.player_id {
        Some(id) => id,
        None => return,
    };

    if let Some(room_code) = &client.room_code {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let needs_bot = {
                let mut room = room_arc.lock();
                process_piece_selection(&mut room, player_id, piece_id, result_index);
                check_needs_bot_turn(&room)
            };
            if needs_bot {
                schedule_bot_turn(rooms.clone(), room_code.clone(), BOT_ACTION_DELAY_MS);
            }
        }
    }
}

async fn handle_select_path(client: &mut WsClient, rooms: &RoomMap, choice: &str) {
    let player_id = match client.player_id {
        Some(id) => id,
        None => return,
    };

    if let Some(room_code) = &client.room_code {
        if let Some(room_arc) = RoomManager::get_room(rooms, room_code) {
            let needs_bot = {
                let mut room = room_arc.lock();
                process_path_selection(&mut room, player_id, choice);
                check_needs_bot_turn(&room)
            };
            if needs_bot {
                schedule_bot_turn(rooms.clone(), room_code.clone(), BOT_ACTION_DELAY_MS);
            }
        }
    }
}

// ---- Shared game action processors (used by both human and bot) ----

fn process_piece_selection(room: &mut crate::room::Room, player_id: usize, piece_id: usize, result_index: usize) {
    match room.state.select_piece(player_id, piece_id, result_index) {
        Ok(move_result) => {
            match move_result {
                MoveResult::Moved { piece_id, new_node, captured, finished } => {
                    let captured_strs: Vec<String> = captured.iter().map(|c| c.to_string()).collect();
                    let msg = ServerMessage::piece_moved(
                        piece_id as u32,
                        new_node,
                        captured_strs,
                        finished,
                    );
                    room.broadcast(&msg);

                    if room.state.phase == GamePhase::GameOver {
                        if let Some(winner_id) = room.state.winner {
                            let winner_name = room.state.get_winner_display_name(winner_id);

                            let all_players: Vec<String> = room.state.players.iter().map(|p| p.name.clone()).collect();
                            log::info!("Game ended: winner='{}' (ID: {}), all_players: {:?}",
                                      winner_name, winner_id, all_players);

                            let go_msg = ServerMessage::game_over(
                                winner_id.to_string(),
                                winner_name,
                            );
                            room.broadcast(&go_msg);
                        }
                    } else {
                        let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                        room.broadcast(&sync);

                        let current = room.state.turn.current_player;
                        let can_throw = room.state.turn.should_throw();
                        let turn_msg = ServerMessage::your_turn(current.to_string(), can_throw);
                        room.broadcast(&turn_msg);

                        // Bot turn scheduling is handled by the caller
                    }
                }
                MoveResult::NeedsPathChoice(options) => {
                    // Bot path choices are handled immediately (no delay needed
                    // within a single move — delay is between turns)
                    let current = room.state.turn.current_player;
                    if let Some(bot_info) = room.get_bot_info(current) {
                        let choice = BotAI::choose_path(&room.state, current, &options, bot_info.difficulty);
                        process_path_selection(room, current, &choice);
                    } else {
                        let msg = ServerMessage::path_choice_required(piece_id as u32, options);
                        room.send_to(player_id, &msg);
                    }
                }
            }
        }
        Err(e) => {
            let err = ServerMessage::error(e);
            room.send_to(player_id, &err);
        }
    }
}

fn process_path_selection(room: &mut crate::room::Room, player_id: usize, choice: &str) {
    match room.state.select_path(player_id, choice) {
        Ok(move_result) => {
            match move_result {
                MoveResult::Moved { piece_id, new_node, captured, finished } => {
                    let captured_strs: Vec<String> = captured.iter().map(|c| c.to_string()).collect();
                    let msg = ServerMessage::piece_moved(
                        piece_id as u32,
                        new_node,
                        captured_strs,
                        finished,
                    );
                    room.broadcast(&msg);

                    if room.state.phase == GamePhase::GameOver {
                        if let Some(winner_id) = room.state.winner {
                            let winner_name = room.state.get_winner_display_name(winner_id);

                            let all_players: Vec<String> = room.state.players.iter().map(|p| p.name.clone()).collect();
                            log::info!("Game ended: winner='{}' (ID: {}), all_players: {:?}",
                                      winner_name, winner_id, all_players);

                            let go_msg = ServerMessage::game_over(
                                winner_id.to_string(),
                                winner_name,
                            );
                            room.broadcast(&go_msg);
                        }
                    } else {
                        let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                        room.broadcast(&sync);

                        let current = room.state.turn.current_player;
                        let can_throw = room.state.turn.should_throw();
                        let turn_msg = ServerMessage::your_turn(current.to_string(), can_throw);
                        room.broadcast(&turn_msg);

                        // Bot turn scheduling is handled by the caller
                    }
                }
                MoveResult::NeedsPathChoice(options) => {
                    // Movement after path choice hit another junction
                    let current = room.state.turn.current_player;
                    if let Some(bot_info) = room.get_bot_info(current) {
                        let choice = BotAI::choose_path(&room.state, current, &options, bot_info.difficulty);
                        process_path_selection(room, current, &choice);
                    } else {
                        let piece_id = room.state.pending_piece_id.unwrap_or(0);
                        let msg = ServerMessage::path_choice_required(piece_id as u32, options);
                        room.send_to(player_id, &msg);
                    }
                }
            }
        }
        Err(e) => {
            let err = ServerMessage::error(e);
            room.send_to(player_id, &err);
        }
    }
}

/// Check if the current player is a bot that needs to act.
fn check_needs_bot_turn(room: &crate::room::Room) -> bool {
    if room.state.phase == GamePhase::GameOver {
        return false;
    }
    // During DecidingOrder, check the current order thrower instead
    if room.state.phase == GamePhase::DecidingOrder {
        if let Some(thrower) = room.state.order_current_thrower() {
            return room.state.players.iter().any(|p| p.id == thrower && p.is_bot);
        }
        return false;
    }
    let current = room.state.turn.current_player;
    room.get_bot_info(current).is_some()
}

/// Schedule a delayed bot action. Each call processes ONE step, then
/// re-schedules if more steps are needed. This creates visible delays
/// between bot actions (throw → piece select → move) so players can
/// follow what the bot is doing.
fn schedule_bot_turn(rooms: RoomMap, room_code: String, delay_ms: u64) {
    actix_rt::spawn(async move {
        tokio::time::sleep(Duration::from_millis(delay_ms)).await;

        let room_arc = match RoomManager::get_room(&rooms, &room_code) {
            Some(r) => r,
            None => return,
        };

        let (needs_more, next_delay) = {
            let mut room = room_arc.lock();
            process_single_bot_action(&mut room)
        };
        // Lock is dropped here

        if needs_more {
            schedule_bot_turn(rooms, room_code, next_delay);
        }
    });
}

/// Process exactly ONE bot action. Returns (needs_more, next_delay_ms).
fn process_single_bot_action(room: &mut crate::room::Room) -> (bool, u64) {
    if room.state.phase == GamePhase::GameOver {
        return (false, 0);
    }

    // DecidingOrder: the actor is the order thrower, not turn.current_player
    if room.state.phase == GamePhase::DecidingOrder {
        let current_thrower = match room.state.order_current_thrower() {
            Some(t) => t,
            None => return (false, 0),
        };
        let is_bot = room.state.players.iter().any(|p| p.id == current_thrower && p.is_bot);
        if !is_bot {
            return (false, 0);
        }
        return match room.state.order_throw(current_thrower) {
            Ok((result, all_done)) => {
                let msg = ServerMessage::order_throw_result(
                    current_thrower.to_string(),
                    result.as_string(),
                    result.distance(),
                );
                room.broadcast(&msg);

                if all_done {
                    let player_order: Vec<serde_json::Value> = room.state.players.iter()
                        .map(|p| serde_json::json!({
                            "id": p.id,
                            "name": &p.name,
                        }))
                        .collect();
                    let decided_msg = ServerMessage::order_decided(player_order);
                    room.broadcast(&decided_msg);

                    let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                    room.broadcast(&sync);

                    let current_player = room.state.turn.current_player;
                    let turn_msg = ServerMessage::your_turn(current_player.to_string(), true);
                    room.broadcast(&turn_msg);

                    (check_needs_bot_turn(room), BOT_ACTION_DELAY_MS)
                } else {
                    // Check for tie
                    let throwers_reset = room.state.order_current_idx == 0
                        && room.state.order_results.is_empty();
                    if throwers_reset {
                        let tied_ids: Vec<String> = room.state.order_throwers.iter()
                            .map(|id| id.to_string())
                            .collect();
                        let tie_msg = ServerMessage::order_tie(tied_ids);
                        room.broadcast(&tie_msg);
                    }

                    let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                    room.broadcast(&sync);

                    if let Some(next_thrower) = room.state.order_current_thrower() {
                        let turn_msg = ServerMessage::order_your_turn(next_thrower.to_string());
                        room.broadcast(&turn_msg);

                        let is_bot = room.state.players.iter()
                            .any(|p| p.id == next_thrower && p.is_bot);
                        (is_bot, BOT_THROW_DELAY_MS)
                    } else {
                        (false, 0)
                    }
                }
            }
            Err(_) => (false, 0),
        };
    }

    // Normal game phases: actor is turn.current_player
    let current = room.state.turn.current_player;
    let bot_info = match room.get_bot_info(current) {
        Some(info) => info.clone(),
        None => return (false, 0),
    };

    match room.state.phase {
        GamePhase::Throwing => {
            if !room.state.turn.should_throw() {
                return (false, 0);
            }
            match room.state.throw_yut(current) {
                Ok(result) => {
                    let grants_extra = result.has_extra_turn();
                    let msg = ServerMessage::yut_result(
                        result.as_string(),
                        result.distance(),
                        grants_extra,
                    );
                    room.broadcast(&msg);

                    if grants_extra {
                        // Extra turn — throw again after longer delay (extra animation ~2.4s)
                        (true, BOT_EXTRA_THROW_DELAY_MS)
                    } else {
                        // Check if auto-finish triggered game over
                        if room.state.phase == GamePhase::GameOver {
                            let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                            room.broadcast(&sync);
                            if let Some(winner_id) = room.state.winner {
                                let winner_name = room.state.get_winner_display_name(winner_id);
                                log::info!("Game ended (bot auto-finish): winner='{}' (ID: {})", winner_name, winner_id);
                                let go_msg = ServerMessage::game_over(winner_id.to_string(), winner_name);
                                room.broadcast(&go_msg);
                            }
                            return (false, 0);
                        }

                        // Done throwing — send sync.  auto_skip_unusable_backdo()
                        // may have advanced the turn inside throw_yut(), so
                        // should_throw() could be true for the NEXT player.
                        let sync = ServerMessage::game_state_sync(room.state.to_sync_json());
                        room.broadcast(&sync);

                        // If turn changed (BackDo auto-skipped), notify clients
                        let new_current = room.state.turn.current_player;
                        if new_current != current {
                            let turn_msg = ServerMessage::your_turn(
                                new_current.to_string(),
                                room.state.turn.should_throw(),
                            );
                            room.broadcast(&turn_msg);
                        }

                        // Continue if current (possibly new) player is still a bot
                        // Wait for yut animation to finish (~1.7s) before next action
                        (check_needs_bot_turn(room), BOT_THROW_DELAY_MS)
                    }
                }
                Err(_) => (false, 0),
            }
        }
        GamePhase::SelectingPiece => {
            if let Some(piece_id) = BotAI::choose_piece(&room.state, current, bot_info.difficulty) {
                process_piece_selection(room, current, piece_id, 0);
                // Check if bot still needs to act (more results, or next player is bot)
                (check_needs_bot_turn(room), BOT_ACTION_DELAY_MS)
            } else {
                // No movable pieces, advance turn
                room.state.turn.advance_turn();
                room.state.phase = GamePhase::Throwing;
                let next = room.state.turn.current_player;
                let turn_msg = ServerMessage::your_turn(next.to_string(), true);
                room.broadcast(&turn_msg);
                (check_needs_bot_turn(room), BOT_ACTION_DELAY_MS)
            }
        }
        GamePhase::SelectingPath => {
            // Shouldn't normally reach here (bot path choices are handled inline
            // in process_piece_selection), but handle gracefully
            let options = if let Some(pid) = room.state.pending_piece_id {
                if let Some(pos) = room.state.pieces[pid].position {
                    room.state.board.get_junction_options(pos)
                } else {
                    vec!["outer".to_string()]
                }
            } else {
                vec!["outer".to_string()]
            };

            let choice = BotAI::choose_path(&room.state, current, &options, bot_info.difficulty);
            process_path_selection(room, current, &choice);
            (check_needs_bot_turn(room), BOT_ACTION_DELAY_MS)
        }
        _ => (false, 0),
    }
}
