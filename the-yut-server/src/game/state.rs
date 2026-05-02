use serde::{Deserialize, Serialize};
use serde_json::json;
use super::board::{Board, Path, Position};
use super::piece::{Piece, PieceStatus};
use super::turn::TurnManager;
use super::yut::{YutResult, YutThrower};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum GamePhase {
    WaitingForPlayers,
    Throwing,
    SelectingPiece,
    SelectingPath,
    GameOver,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerInfo {
    pub id: usize,
    pub name: String,
    pub session_token: String,
    pub is_host: bool,
    pub is_bot: bool,
}

#[derive(Debug)]
pub struct GameState {
    pub phase: GamePhase,
    pub players: Vec<PlayerInfo>,
    pub pieces: Vec<Piece>,
    pub board: Board,
    pub turn: TurnManager,
    pub pending_piece_id: Option<usize>,
    pub pending_distance: Option<u32>,  // remaining steps after junction
    pub winner: Option<usize>,
    next_player_id: usize,              // monotonically increasing ID counter
    /// Team assignments for 4-player mode: [[team0_id_a, team0_id_b], [team1_id_a, team1_id_b]]
    /// None for ≤3 players (free-for-all).
    pub teams: Option<Vec<Vec<usize>>>,
}

impl GameState {
    pub fn new() -> Self {
        Self {
            phase: GamePhase::WaitingForPlayers,
            players: Vec::new(),
            pieces: Vec::new(),
            board: Board::new(),
            turn: TurnManager::new(Vec::new()),
            pending_piece_id: None,
            pending_distance: None,
            winner: None,
            next_player_id: 0,
            teams: None,
        }
    }

    pub fn add_player(&mut self, name: String, session_token: String) -> usize {
        let id = self.next_player_id;
        self.next_player_id += 1;
        let is_host = self.players.is_empty();
        self.players.push(PlayerInfo {
            id,
            name,
            session_token,
            is_host,
            is_bot: false,
        });
        id
    }

    pub fn add_bot(&mut self, name: String) -> usize {
        let id = self.next_player_id;
        self.next_player_id += 1;
        self.players.push(PlayerInfo {
            id,
            name,
            session_token: String::new(),
            is_host: false,
            is_bot: true,
        });
        id
    }

    pub fn remove_player(&mut self, player_id: usize) {
        self.players.retain(|p| p.id != player_id);
    }

    pub fn start_game(&mut self) -> Result<(), String> {
        if self.players.len() < 2 {
            return Err("Need at least 2 players".to_string());
        }
        if self.players.len() > 4 {
            return Err("Maximum 4 players".to_string());
        }

        self.pieces.clear();
        for (player_index, player) in self.players.iter().enumerate() {
            for piece_idx in 0..4 {
                let global_id = player_index * 4 + piece_idx;
                self.pieces.push(Piece::new(global_id, player.id));
            }
        }

        let player_ids: Vec<usize> = self.players.iter().map(|p| p.id).collect();

        // 4 players = 2v2 team mode: players[0]+players[2] vs players[1]+players[3]
        if self.players.len() == 4 {
            self.teams = Some(vec![
                vec![player_ids[0], player_ids[2]],
                vec![player_ids[1], player_ids[3]],
            ]);
        } else {
            self.teams = None;
        }

        self.turn = TurnManager::new(player_ids);
        self.phase = GamePhase::Throwing;
        self.winner = None;
        self.pending_piece_id = None;
        self.pending_distance = None;
        Ok(())
    }

    pub fn throw_yut(&mut self, player_id: usize) -> Result<YutResult, String> {
        if self.phase != GamePhase::Throwing {
            return Err("Not in throwing phase".to_string());
        }
        if self.turn.current_player != player_id {
            return Err("Not your turn".to_string());
        }
        if !self.turn.should_throw() {
            return Err("You don't need to throw".to_string());
        }

        let result = YutThrower::throw();
        self.turn.record_throw(result);

        if !self.turn.should_throw() {
            self.phase = GamePhase::SelectingPiece;
            // Auto-skip BackDo if player has no pieces on the board
            self.auto_skip_unusable_backdo();
            // Auto-finish completed_circuit pieces if they're the only option
            self.auto_finish_completed_circuit();
        }

        Ok(result)
    }

    pub fn get_movable_pieces(&self, player_id: usize) -> Vec<usize> {
        self.pieces.iter()
            .filter(|p| p.owner == player_id && p.status != PieceStatus::Finished)
            .map(|p| p.id)
            .collect()
    }

    // ══════════════════════════════════════════════════════
    // PIECE SELECTION — entry point for a turn's move
    // ══════════════════════════════════════════════════════

    pub fn select_piece(&mut self, player_id: usize, piece_id: usize, result_index: usize) -> Result<MoveResult, String> {
        if self.phase != GamePhase::SelectingPiece {
            return Err("Not in piece selection phase".to_string());
        }
        if self.turn.current_player != player_id {
            return Err("Not your turn".to_string());
        }

        let piece = self.pieces.get(piece_id).ok_or("Invalid piece ID")?;
        if piece.owner != player_id {
            return Err("Not your piece".to_string());
        }
        if piece.is_finished() {
            return Err("Piece already finished".to_string());
        }

        if self.turn.pending_results.is_empty() {
            return Err("No pending yut results".to_string());
        }
        if result_index >= self.turn.pending_results.len() {
            return Err("Invalid result index".to_string());
        }

        // ── Special case: piece waiting at finish (completed_circuit) ──
        // Any throw result instantly finishes this piece.
        if self.pieces[piece_id].completed_circuit
            && self.pieces[piece_id].is_on_board()
        {
            let _result = self.turn.use_result(result_index).unwrap();
            let move_result = self.finish_piece(piece_id)?;
            self.advance_phase(player_id);
            return Ok(move_result);
        }

        let result = self.turn.use_result(result_index).unwrap();
        let distance = result.distance();

        // BackDo: move backward 1 step
        let move_result = if result.is_backward() {
            self.execute_backward_move(piece_id)?
        } else {
            self.execute_move(piece_id, distance)?
        };

        // Phase transition only if move completed (not waiting for path choice)
        if let MoveResult::Moved { .. } = &move_result {
            self.advance_phase(player_id);
        }

        Ok(move_result)
    }

    // ══════════════════════════════════════════════════════
    // PATH SELECTION — called when player chooses at a junction
    // ══════════════════════════════════════════════════════

    pub fn select_path(&mut self, player_id: usize, path_choice: &str) -> Result<MoveResult, String> {
        if self.phase != GamePhase::SelectingPath {
            return Err("Not in path selection phase".to_string());
        }
        if self.turn.current_player != player_id {
            return Err("Not your turn".to_string());
        }

        let piece_id = self.pending_piece_id.take().ok_or("No pending piece")?;
        let remaining = self.pending_distance.take().unwrap_or(1);

        let current_pos = self.pieces[piece_id].position.ok_or("Piece has no position")?;
        let next_pos = self.board.apply_path_choice(current_pos, path_choice);

        // Move piece to the chosen direction (1 step consumed)
        self.pieces[piece_id].move_to(next_pos);
        let steps_left = remaining.saturating_sub(1);

        // Continue movement with remaining steps
        let move_result = if steps_left == 0 {
            // No more steps — apply final move at current position
            self.apply_move_at(piece_id, next_pos)?
        } else {
            // Continue walking from new position
            self.execute_steps(piece_id, next_pos, steps_left)?
        };

        // Phase transition only if move completed
        if let MoveResult::Moved { .. } = &move_result {
            self.advance_phase(player_id);
        }

        Ok(move_result)
    }

    // ══════════════════════════════════════════════════════
    // CORE MOVEMENT ENGINE
    // ══════════════════════════════════════════════════════

    /// BackDo (백도): move a piece 1 step backward.
    /// If piece is at Home, it cannot be deployed (stays home, move is wasted).
    /// If piece is at start (node 0), it cannot go further back.
    fn execute_backward_move(&mut self, piece_id: usize) -> Result<MoveResult, String> {
        let piece = &self.pieces[piece_id];

        if piece.is_home() {
            // Can't deploy with BackDo — piece stays home, move is consumed
            return Ok(MoveResult::Moved {
                piece_id,
                new_node: 0,
                captured: Vec::new(),
                finished: false,
            });
        }

        let current_pos = piece.position.ok_or("Piece has no position")?;

        if let Some(prev_pos) = self.board.get_prev_position(current_pos) {
            // Move backward and apply captures/stacking at new position
            self.apply_move_at(piece_id, prev_pos)
        } else {
            // At start or can't go back — piece stays, move is consumed
            Ok(MoveResult::Moved {
                piece_id,
                new_node: current_pos.node,
                captured: Vec::new(),
                finished: false,
            })
        }
    }

    fn execute_move(&mut self, piece_id: usize, distance: u32) -> Result<MoveResult, String> {
        let piece = &self.pieces[piece_id];
        let is_deploying = piece.is_home();

        let start_pos = if is_deploying {
            let start = Position::new(0, Path::Outer);
            self.pieces[piece_id].place_on_board(start);
            start
        } else {
            piece.position.ok_or("Piece has no position")?
        };

        self.execute_steps(piece_id, start_pos, distance)
    }

    /// Walk step-by-step from `from` for `distance` steps.
    /// Junctions only trigger path choice when the piece STARTS at the junction
    /// (step 0). Pieces passing through a junction mid-movement continue on
    /// their current path — this matches real Yutnori rules.
    ///
    /// Finish rule: a piece must PASS THROUGH node 0 (not just land on it)
    /// to finish.  Landing exactly on node 0 places the piece there with
    /// `completed_circuit = true`; it can be captured and any subsequent
    /// throw will score it.
    fn execute_steps(&mut self, piece_id: usize, from: Position, distance: u32) -> Result<MoveResult, String> {
        if distance == 0 {
            return self.apply_move_at(piece_id, from);
        }

        let mut current = from;

        for step in 0..distance {
            let is_last_step = step == distance - 1;
            let next = self.board.get_next_positions(current, 1);

            if next.is_empty() {
                // Dead end — treat as finish
                return self.finish_piece(piece_id);
            }

            if next.len() > 1 && self.board.has_junction_at(current) {
                if step == 0 {
                    // Junction at starting position — ask player for path choice.
                    let remaining = distance; // all steps remain
                    self.pending_piece_id = Some(piece_id);
                    self.pending_distance = Some(remaining);
                    self.phase = GamePhase::SelectingPath;

                    return Ok(MoveResult::NeedsPathChoice(
                        self.board.get_junction_options(current),
                    ));
                } else {
                    // Mid-movement through junction — continue on same path.
                    let same_path: Vec<Position> = next.iter()
                        .filter(|p| p.path == current.path)
                        .copied()
                        .collect();
                    current = if same_path.is_empty() { next[0] } else { same_path[0] };

                    // Pass-through finish: piece goes PAST node 0 → finish
                    if current != from && self.board.is_finish(current)
                        && self.pieces[piece_id].is_on_board()
                        && !is_last_step
                    {
                        return self.finish_piece(piece_id);
                    }
                    continue;
                }
            }

            // Take the single available step
            current = next[0];

            // Pass-through finish: only finish if piece goes PAST node 0
            // (not on the last step — landing exactly means waiting)
            if current != from && self.board.is_finish(current)
                && self.pieces[piece_id].is_on_board()
                && !is_last_step
            {
                return self.finish_piece(piece_id);
            }
        }

        // Reached final destination — apply captures, stacking, etc.
        self.apply_move_at(piece_id, current)
    }

    /// Apply the move to a final resting position: captures, stacking, finish check.
    ///
    /// New finish rule: landing exactly on node 0 does NOT finish the piece.
    /// Instead the piece waits there with `completed_circuit = true`.
    /// It can be captured by opponents.  Any subsequent throw finishes it.
    fn apply_move_at(&mut self, piece_id: usize, pos: Position) -> Result<MoveResult, String> {
        // If piece lands exactly on node 0 after traversing the board,
        // mark it as waiting-to-score (completed_circuit) instead of finishing.
        if self.board.is_finish(pos) && self.pieces[piece_id].is_on_board() {
            let current_pos = self.pieces[piece_id].position;
            // Determine if the piece FORWARD-arrived at node 0 (completed circuit).
            // BackDo from node 1 → 0 should NOT set completed_circuit.
            // Forward arrival: piece was at node 15+ (outer), or node 24+ (shortcutA),
            // or node 28 (shortcutB), i.e. the last segment approaching finish.
            let is_forward_arrival = match current_pos {
                Some(p) => match p.path {
                    Path::Outer => p.node >= 15,    // nodes 15-19 → 0
                    Path::ShortcutB => p.node >= 27, // nodes 27-28 → 0
                    _ => false,
                },
                None => false,
            };
            if is_forward_arrival && !self.pieces[piece_id].completed_circuit {
                self.pieces[piece_id].completed_circuit = true;
            }
        }

        // Check for captures and stacking at the destination
        let owner = self.pieces[piece_id].owner;
        let mut to_capture = Vec::new();
        let mut to_stack = Vec::new();

        for other in &self.pieces {
            if other.id == piece_id || !other.is_on_board() {
                continue;
            }
            if let Some(other_pos) = other.position {
                if other_pos == pos {
                    // Teammates stack (friendly), opponents get captured
                    if self.are_teammates(other.owner, owner) {
                        to_stack.push(other.id);
                    } else {
                        to_capture.push(other.id);
                        for sid in &other.stacked_with {
                            to_capture.push(*sid);
                        }
                    }
                }
            }
        }

        // Apply captures (including stacked pieces on captured targets).
        // All pieces in to_capture are sent home together, then we scrub their
        // IDs from every remaining piece's stacked_with so no stale references
        // linger on the board (mirrors the clean-up done in finish_piece).
        let mut captured = Vec::new();
        for cid in &to_capture {
            self.pieces[*cid].send_home();
            captured.push(*cid);
        }
        // Remove captured IDs from every remaining piece's stacked_with.
        for piece in &mut self.pieces {
            piece.stacked_with.retain(|id| !captured.contains(id));
        }
        // Capture bonus: grant an extra throw when capturing with Do/Gae/Geol.
        // Yut/Mo already grant extra throws from the result itself.
        if !captured.is_empty() {
            self.turn.grant_capture_extra_turn();
        }

        // Apply move
        self.pieces[piece_id].move_to(pos);

        // Apply stacking — merge all stacked groups into one
        // Collect all piece IDs that should be in the new combined stack
        let mut all_stack_members: Vec<usize> = Vec::new();
        // Include the moving piece's existing stack
        all_stack_members.extend(self.pieces[piece_id].stacked_with.clone());
        // Include each friendly piece at destination and their stacks
        for sid in &to_stack {
            all_stack_members.push(*sid);
            all_stack_members.extend(self.pieces[*sid].stacked_with.clone());
        }
        // Deduplicate
        all_stack_members.sort();
        all_stack_members.dedup();
        // Remove self from list
        all_stack_members.retain(|&id| id != piece_id);

        // Set all members to have the same combined stack (excluding themselves)
        let full_group: Vec<usize> = {
            let mut g = all_stack_members.clone();
            g.push(piece_id);
            g.sort();
            g.dedup();
            g
        };

        // Propagate completed_circuit: if ANY piece in the group has it, all get it
        let any_completed = full_group.iter().any(|&id| self.pieces[id].completed_circuit);

        for &member_id in &full_group {
            let others: Vec<usize> = full_group.iter().copied().filter(|&id| id != member_id).collect();
            self.pieces[member_id].stacked_with = others;
            self.pieces[member_id].move_to(pos);
            if any_completed {
                self.pieces[member_id].completed_circuit = true;
            }
        }

        Ok(MoveResult::Moved {
            piece_id,
            new_node: pos.node,
            captured,
            finished: false,
        })
    }

    /// Mark piece (and stacked pieces) as finished.
    fn finish_piece(&mut self, piece_id: usize) -> Result<MoveResult, String> {
        let stacked = self.pieces[piece_id].stacked_with.clone();
        self.pieces[piece_id].finish(); // finish() clears stacked_with

        for sid in &stacked {
            self.pieces[*sid].finish();
        }

        // Clean up: remove finished pieces from any remaining stack references
        let all_finished: Vec<usize> = {
            let mut v = stacked.clone();
            v.push(piece_id);
            v
        };
        for piece in &mut self.pieces {
            piece.stacked_with.retain(|id| !all_finished.contains(id));
        }

        Ok(MoveResult::Moved {
            piece_id,
            new_node: 0,
            captured: Vec::new(),
            finished: true,
        })
    }

    /// Advance game phase after a completed move.
    ///
    /// Priority order (intentional):
    ///   1. Win check — game ends immediately regardless of remaining throws.
    ///   2. pending_results — consume all accumulated Yut/Mo bonus throws
    ///      (and any other queued results) before granting the capture bonus.
    ///      This matches real Yutnori rules: you use every result from the
    ///      current throw sequence before you get the capture re-throw.
    ///   3. extra_turn_from_capture — after all pending results are spent,
    ///      if a capture occurred the player gets one additional throw.
    ///   4. Advance to the next player's turn.
    fn advance_phase(&mut self, player_id: usize) {
        // Check win first
        if self.check_win(player_id) {
            self.winner = Some(player_id);
            self.phase = GamePhase::GameOver;
            return;
        }

        if self.turn.has_pending_results() {
            // More yut results to use — keep the same player's turn.
            self.phase = GamePhase::SelectingPiece;
            // Auto-skip BackDo if player has no pieces on the board
            self.auto_skip_unusable_backdo();
        } else if self.turn.extra_turn_from_capture {
            // All pending results consumed; capture bonus grants one more throw.
            self.turn.extra_turn_from_capture = false;
            self.turn.must_throw = true;
            self.phase = GamePhase::Throwing;
        } else {
            // Turn is fully over — advance to the next player.
            self.turn.advance_turn();
            self.phase = GamePhase::Throwing;
        }
    }

    /// Auto-consume BackDo results when the current player has no movable
    /// pieces for BackDo (all Home, Finished, or completed_circuit at node 0).
    /// BackDo can't deploy from Home and can't move backward from node 0,
    /// so it's unusable — skip it and advance the turn if nothing remains.
    /// Returns true if any BackDo results were consumed.
    pub fn auto_skip_unusable_backdo(&mut self) -> bool {
        if self.phase != GamePhase::SelectingPiece {
            return false;
        }

        let player_id = self.turn.current_player;
        // Check if player has any piece that can actually move backward
        let has_backdo_movable = self.pieces.iter()
            .any(|p| p.owner == player_id && p.is_on_board() && !p.completed_circuit);
        let has_onboard = has_backdo_movable;

        if has_onboard {
            return false;
        }

        // Remove all BackDo results from pending (they can't be used)
        let before = self.turn.pending_results.len();
        self.turn.pending_results.retain(|r| !r.is_backward());
        let removed = before - self.turn.pending_results.len();

        if removed == 0 {
            return false;
        }

        // If no more results remain, advance to next turn
        if self.turn.pending_results.is_empty() {
            if self.turn.extra_turn_from_capture {
                self.turn.extra_turn_from_capture = false;
                self.turn.must_throw = true;
                self.phase = GamePhase::Throwing;
            } else {
                self.turn.advance_turn();
                self.phase = GamePhase::Throwing;
            }
        }
        // Otherwise, remaining non-BackDo results can still be used

        true
    }

    /// Auto-finish pieces that have completed_circuit when ALL of the player's
    /// remaining (non-Finished) pieces are completed_circuit on the board.
    /// This handles the case where the last piece(s) are waiting at node 0
    /// and any throw should finish them without requiring user interaction.
    /// Returns the list of auto-finished piece IDs.
    pub fn auto_finish_completed_circuit(&mut self) -> Vec<usize> {
        if self.phase != GamePhase::SelectingPiece {
            return vec![];
        }

        let player_id = self.turn.current_player;

        // Get all non-finished piece IDs for this player
        let non_finished: Vec<usize> = self.pieces.iter()
            .filter(|p| p.owner == player_id && !p.is_finished())
            .map(|p| p.id)
            .collect();

        if non_finished.is_empty() {
            return vec![];
        }

        // ALL non-finished pieces must be completed_circuit and on board
        let all_completed = non_finished.iter().all(|&pid| {
            self.pieces[pid].completed_circuit && self.pieces[pid].is_on_board()
        });

        if !all_completed {
            return vec![];
        }

        // Need at least one non-BackDo result to finish a piece
        let non_backdo_count = self.turn.pending_results.iter()
            .filter(|r| !r.is_backward())
            .count();

        if non_backdo_count == 0 {
            return vec![];
        }

        // Auto-finish each completed_circuit piece (one result per piece)
        let mut finished_pieces = vec![];
        for &pid in &non_finished {
            if let Some(idx) = self.turn.pending_results.iter().position(|r| !r.is_backward()) {
                self.turn.pending_results.remove(idx);
                let _ = self.finish_piece(pid);
                finished_pieces.push(pid);
            }
        }

        // Check win
        if self.check_win(player_id) {
            self.winner = Some(player_id);
            self.phase = GamePhase::GameOver;
        } else {
            // Still have results or need to advance
            self.advance_phase(player_id);
        }

        finished_pieces
    }

    /// Check if two players are on the same team (always true for same player).
    pub fn are_teammates(&self, a: usize, b: usize) -> bool {
        if a == b {
            return true;
        }
        if let Some(ref teams) = self.teams {
            for team in teams {
                if team.contains(&a) && team.contains(&b) {
                    return true;
                }
            }
        }
        false
    }

    pub fn check_win(&self, player_id: usize) -> bool {
        if let Some(ref teams) = self.teams {
            // Team mode: all pieces of both teammates must be finished
            for team in teams {
                if team.contains(&player_id) {
                    return self.pieces.iter()
                        .filter(|p| team.contains(&p.owner))
                        .all(|p| p.is_finished());
                }
            }
            false
        } else {
            // Free-for-all: just this player's pieces
            self.pieces.iter()
                .filter(|p| p.owner == player_id)
                .all(|p| p.is_finished())
        }
    }

    /// Get display name for the winner. In team mode, returns "PlayerA & PlayerB".
    pub fn get_winner_display_name(&self, winner_id: usize) -> String {
        if let Some(ref teams) = self.teams {
            for team in teams {
                if team.contains(&winner_id) {
                    let names: Vec<String> = team.iter().filter_map(|&tid| {
                        self.players.iter().find(|p| p.id == tid).map(|p| p.name.clone())
                    }).collect();
                    return names.join(" & ");
                }
            }
        }
        // Free-for-all: single player name
        self.players.iter()
            .find(|p| p.id == winner_id)
            .map(|p| p.name.clone())
            .unwrap_or_default()
    }

    pub fn change_player_name(&mut self, player_id: usize, name: String) -> Result<(), String> {
        if let Some(player) = self.players.iter_mut().find(|p| p.id == player_id) {
            player.name = name;
            Ok(())
        } else {
            Err("Player not found".to_string())
        }
    }

    pub fn to_sync_json(&self) -> serde_json::Value {
        let players: Vec<serde_json::Value> = self.players.iter().map(|p| {
            json!({
                "id": p.id,
                "name": &p.name,
                "is_host": p.is_host,
                "is_bot": p.is_bot,
            })
        }).collect();

        let pieces: Vec<serde_json::Value> = self.pieces.iter().map(|p| {
            json!({
                "id": p.id,
                "owner": p.owner,
                "status": format!("{:?}", p.status),
                "node": p.position.map(|pos| pos.node),
                "path": p.position.map(|pos| format!("{:?}", pos.path)),
                "stacked_with": p.stacked_with,
                "completed_circuit": p.completed_circuit,
            })
        }).collect();

        let pending: Vec<String> = self.turn.pending_results.iter().map(|r| r.as_string()).collect();

        json!({
            "phase": format!("{:?}", self.phase),
            "players": players,
            "pieces": pieces,
            "current_turn": self.turn.current_player,
            "pending_results": pending,
            "must_throw": self.turn.should_throw(),
            "winner": self.winner,
            "teams": self.teams,
        })
    }
}

#[derive(Debug)]
pub enum MoveResult {
    Moved {
        piece_id: usize,
        new_node: u32,
        captured: Vec<usize>,
        finished: bool,
    },
    NeedsPathChoice(Vec<String>),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_players() {
        let mut state = GameState::new();
        let id0 = state.add_player("Alice".into(), "tok0".into());
        let id1 = state.add_player("Bob".into(), "tok1".into());
        assert_eq!(id0, 0);
        assert_eq!(id1, 1);
        assert!(state.players[0].is_host);
        assert!(!state.players[1].is_host);
    }

    #[test]
    fn test_add_bot() {
        let mut state = GameState::new();
        state.add_player("Alice".into(), "tok0".into());
        let bot_id = state.add_bot("Bot_Easy".into());
        assert_eq!(bot_id, 1);
        assert!(state.players[1].is_bot);
    }

    #[test]
    fn test_start_game() {
        let mut state = GameState::new();
        state.add_player("Alice".into(), "tok0".into());
        state.add_player("Bob".into(), "tok1".into());
        assert!(state.start_game().is_ok());
        assert_eq!(state.phase, GamePhase::Throwing);
        assert_eq!(state.pieces.len(), 8);
    }

    #[test]
    fn test_start_game_needs_2_players() {
        let mut state = GameState::new();
        state.add_player("Alice".into(), "tok0".into());
        assert!(state.start_game().is_err());
    }

    #[test]
    fn test_get_movable_pieces() {
        let mut state = GameState::new();
        state.add_player("Alice".into(), "tok0".into());
        state.add_player("Bob".into(), "tok1".into());
        state.start_game().unwrap();
        let movable = state.get_movable_pieces(0);
        assert_eq!(movable.len(), 4);
    }

    #[test]
    fn test_check_win_not_yet() {
        let mut state = GameState::new();
        state.add_player("Alice".into(), "tok0".into());
        state.add_player("Bob".into(), "tok1".into());
        state.start_game().unwrap();
        assert!(!state.check_win(0));
    }

    // ── 헬퍼: 2인 게임 셋업 ──
    fn setup_two_player_game() -> GameState {
        let mut state = GameState::new();
        state.add_player("Alice".into(), "tok0".into()); // player_id = 0
        state.add_player("Bob".into(), "tok1".into());   // player_id = 1
        state.start_game().unwrap();
        state
    }

    // ─────────────────────────────────────────────
    // 말 이동 (execute_move / execute_steps)
    // ─────────────────────────────────────────────

    /// 홈에서 도(1칸) 이동 시 말이 node 1에 놓인다.
    #[test]
    fn test_deploy_piece_with_do() {
        let mut state = setup_two_player_game();
        // Alice(0) 턴 — pending_results에 Do를 직접 주입한다.
        state.turn.pending_results.push(YutResult::Do);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        // piece 0은 Alice의 첫 번째 말
        let res = state.select_piece(0, 0, 0).unwrap();
        match res {
            MoveResult::Moved { piece_id, new_node, finished, .. } => {
                assert_eq!(piece_id, 0);
                assert_eq!(new_node, 1, "Do should move to node 1");
                assert!(!finished);
            }
            other => panic!("Expected Moved, got {:?}", other),
        }
        assert_eq!(state.pieces[0].position, Some(Position::new(1, Path::Outer)));
    }

    /// 홈에서 모(5칸) 이동 시 말이 node 5(TR 코너)에 놓인다.
    #[test]
    fn test_deploy_piece_with_mo_to_tr_corner() {
        let mut state = setup_two_player_game();
        state.turn.pending_results.push(YutResult::Mo);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        // node 5(TR)는 지름길 분기점이므로 NeedsPathChoice가 반환될 수 있다.
        let res = state.select_piece(0, 0, 0).unwrap();
        // 5칸 이동: Home(0) → 1→2→3→4→5. 마지막 스텝이 node5이므로 junction 트리거됨.
        match res {
            MoveResult::NeedsPathChoice(opts) => {
                assert!(opts.contains(&"outer".to_string()));
                assert!(opts.contains(&"shortcut".to_string()));
            }
            MoveResult::Moved { new_node, .. } => {
                assert_eq!(new_node, 5);
            }
        }
    }

    // ─────────────────────────────────────────────
    // 스태킹 (업기) — GameState 레벨 통합 검증
    // ─────────────────────────────────────────────

    /// 같은 플레이어의 두 말이 같은 노드에 착지하면 양방향으로 stacked_with가 설정된다.
    #[test]
    fn test_stacking_is_bidirectional_in_game_state() {
        let mut state = setup_two_player_game();

        // piece 0을 먼저 node 2로 이동 (Gae = 2칸)
        state.turn.pending_results.push(YutResult::Gae);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;
        state.select_piece(0, 0, 0).unwrap();

        // piece 1도 Gae로 node 2로 이동 (같은 플레이어이므로 스태킹)
        // 현재 턴이 Bob으로 넘어갔을 수 있으므로 TurnManager를 강제로 세팅한다.
        state.turn.current_player = 0;
        state.turn.pending_results.push(YutResult::Gae);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;
        state.select_piece(0, 1, 0).unwrap();

        // 양방향 검증
        let p0 = &state.pieces[0];
        let p1 = &state.pieces[1];
        assert_eq!(p0.position, Some(Position::new(2, Path::Outer)));
        assert_eq!(p1.position, Some(Position::new(2, Path::Outer)));
        assert!(p0.stacked_with.contains(&1), "piece 0 should reference piece 1");
        assert!(p1.stacked_with.contains(&0), "piece 1 should reference piece 0");
    }

    // ─────────────────────────────────────────────
    // 잡기 (캡처)
    // ─────────────────────────────────────────────

    /// Alice의 말이 Bob의 말이 있는 노드로 이동하면 Bob의 말이 귀가한다.
    #[test]
    fn test_capture_opponent_piece() {
        let mut state = setup_two_player_game();

        // Bob의 말(piece 4)을 node 3에 직접 배치한다.
        state.pieces[4].place_on_board(Position::new(3, Path::Outer));

        // Alice(0) 차례 — 걸(3칸): node 0 → 3
        state.turn.current_player = 0;
        state.turn.pending_results.push(YutResult::Geol);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let res = state.select_piece(0, 0, 0).unwrap();
        match res {
            MoveResult::Moved { captured, new_node, .. } => {
                assert_eq!(new_node, 3);
                assert!(captured.contains(&4), "Bob's piece 4 should be captured");
            }
            other => panic!("Expected Moved, got {:?}", other),
        }

        // Bob의 말은 귀가해야 한다.
        assert!(state.pieces[4].is_home(), "Captured piece should be Home");
        // 잡기 보너스: extra_turn_from_capture가 활성화돼야 한다.
        // (단, advance_phase에서 이미 소비됐을 수 있으므로 다음 phase 확인)
        // Alice는 다시 던지기 상태여야 한다.
        assert_eq!(state.phase, GamePhase::Throwing,
            "After capture with no extra results, phase should be Throwing for capture bonus");
    }

    /// 잡기 시 스택(업힌)된 말까지 모두 귀가해야 한다.
    #[test]
    fn test_capture_stacked_pieces_all_go_home() {
        let mut state = setup_two_player_game();

        // Bob의 두 말(piece 4, 5)을 node 2에 업혀서 배치한다.
        state.pieces[4].place_on_board(Position::new(2, Path::Outer));
        state.pieces[5].place_on_board(Position::new(2, Path::Outer));
        state.pieces[4].stack_with(5);
        state.pieces[5].stack_with(4);

        // Alice(0) — 개(2칸): 0 → 2
        state.turn.current_player = 0;
        state.turn.pending_results.push(YutResult::Gae);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let res = state.select_piece(0, 0, 0).unwrap();
        match res {
            MoveResult::Moved { captured, .. } => {
                assert!(captured.contains(&4), "piece 4 should be captured");
                assert!(captured.contains(&5), "piece 5 (stacked) should be captured");
            }
            other => panic!("Expected Moved, got {:?}", other),
        }

        assert!(state.pieces[4].is_home());
        assert!(state.pieces[5].is_home());
    }

    // ─────────────────────────────────────────────
    // 턴 관리 (TurnManager 통합)
    // ─────────────────────────────────────────────

    /// 윷 결과 후 같은 플레이어가 계속 던질 수 있어야 한다.
    #[test]
    fn test_yut_result_keeps_same_player_throwing() {
        let mut state = setup_two_player_game();
        state.turn.record_throw(YutResult::Yut);
        assert_eq!(state.turn.current_player, 0);
        assert!(state.turn.should_throw(), "Yut should require another throw");
    }

    /// 도 결과 후 말 이동, 그다음 턴이 Bob으로 넘어가야 한다.
    #[test]
    fn test_turn_advances_after_do_move() {
        let mut state = setup_two_player_game();
        state.turn.pending_results.push(YutResult::Do);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        state.select_piece(0, 0, 0).unwrap();
        // 이동 완료 후 Bob(1) 차례여야 한다.
        assert_eq!(state.turn.current_player, 1);
        assert!(state.turn.should_throw());
    }

    // ─────────────────────────────────────────────
    // 팀 모드 (4인)
    // ─────────────────────────────────────────────

    /// 4인 게임 시작 시 팀이 [0,2] vs [1,3]으로 나뉘어야 한다.
    #[test]
    fn test_four_player_team_assignment() {
        let mut state = GameState::new();
        for i in 0..4 {
            state.add_player(format!("P{}", i), format!("tok{}", i));
        }
        state.start_game().unwrap();

        let teams = state.teams.as_ref().expect("Teams should be set");
        assert_eq!(teams.len(), 2);
        // teams[0] = [player_id_0, player_id_2], teams[1] = [player_id_1, player_id_3]
        assert!(teams[0].contains(&0) && teams[0].contains(&2));
        assert!(teams[1].contains(&1) && teams[1].contains(&3));
    }

    /// 팀원끼리는 are_teammates가 true를 반환한다.
    #[test]
    fn test_are_teammates_same_team() {
        let mut state = GameState::new();
        for i in 0..4 {
            state.add_player(format!("P{}", i), format!("tok{}", i));
        }
        state.start_game().unwrap();

        assert!(state.are_teammates(0, 2), "P0 and P2 should be teammates");
        assert!(state.are_teammates(1, 3), "P1 and P3 should be teammates");
        assert!(!state.are_teammates(0, 1), "P0 and P1 should not be teammates");
        assert!(!state.are_teammates(0, 3), "P0 and P3 should not be teammates");
    }

    /// 같은 플레이어 자신과는 언제나 teammate여야 한다.
    #[test]
    fn test_are_teammates_self_is_always_true() {
        let state = setup_two_player_game();
        assert!(state.are_teammates(0, 0));
        assert!(state.are_teammates(1, 1));
    }

    // ─────────────────────────────────────────────
    // 승리 조건
    // ─────────────────────────────────────────────

    /// 플레이어의 모든 말이 Finished 상태가 되면 check_win이 true를 반환한다.
    #[test]
    fn test_check_win_when_all_pieces_finished() {
        let mut state = setup_two_player_game();
        // Alice(0)의 말(piece 0~3)을 모두 완주 처리한다.
        for i in 0..4 {
            state.pieces[i].finish();
        }
        assert!(state.check_win(0), "Alice should win when all her pieces finish");
        assert!(!state.check_win(1), "Bob should not win yet");
    }

    /// 일부 말만 Finished이면 check_win이 false를 반환한다.
    #[test]
    fn test_check_win_partial_finish_is_false() {
        let mut state = setup_two_player_game();
        state.pieces[0].finish();
        state.pieces[1].finish();
        // 나머지 2개(piece 2, 3)는 아직 Home
        assert!(!state.check_win(0));
    }

    // ─────────────────────────────────────────────
    // BackDo (백도)
    // ─────────────────────────────────────────────

    /// BackDo 시 말이 없으면 자동으로 턴이 넘어가야 한다.
    #[test]
    fn test_backdo_auto_skip_when_no_pieces_on_board() {
        let mut state = setup_two_player_game();
        // Alice(0) 모든 말은 Home (초기 상태)
        state.turn.pending_results.push(YutResult::BackDo);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let skipped = state.auto_skip_unusable_backdo();
        assert!(skipped, "BackDo should be auto-skipped when no pieces on board");
        assert_eq!(state.turn.current_player, 1, "Turn should advance to Bob");
    }

    // ─────────────────────────────────────────────
    // 자동 골인 (auto-finish completed_circuit)
    // ─────────────────────────────────────────────

    /// 마지막 말이 completed_circuit 상태일 때 non-BackDo 결과로 자동 골인
    #[test]
    fn test_auto_finish_last_completed_circuit_piece() {
        let mut state = setup_two_player_game();
        // Alice의 말 3개를 완주 처리
        for i in 0..3 {
            state.pieces[i].finish();
        }
        // 마지막 말(piece 3)을 node 0에 completed_circuit 상태로 배치
        state.pieces[3].place_on_board(Position::new(0, Path::Outer));
        state.pieces[3].completed_circuit = true;

        // Alice 턴에 Do 결과 부여
        state.turn.current_player = 0;
        state.turn.pending_results.push(YutResult::Do);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let finished = state.auto_finish_completed_circuit();
        assert!(finished.contains(&3), "Piece 3 should be auto-finished");
        assert!(state.pieces[3].is_finished(), "Piece 3 should be Finished");
        assert_eq!(state.phase, GamePhase::GameOver, "Game should be over");
        assert_eq!(state.winner, Some(0), "Alice should be the winner");
    }

    /// BackDo만 남아 있으면 auto-finish가 동작하지 않는다.
    #[test]
    fn test_auto_finish_skips_with_only_backdo() {
        let mut state = setup_two_player_game();
        for i in 0..3 {
            state.pieces[i].finish();
        }
        state.pieces[3].place_on_board(Position::new(0, Path::Outer));
        state.pieces[3].completed_circuit = true;

        state.turn.current_player = 0;
        state.turn.pending_results.push(YutResult::BackDo);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let finished = state.auto_finish_completed_circuit();
        assert!(finished.is_empty(), "No pieces should be auto-finished with only BackDo");
        assert!(!state.pieces[3].is_finished());
    }

    /// completed_circuit가 아닌 말이 있으면 auto-finish가 동작하지 않는다.
    #[test]
    fn test_auto_finish_skips_when_non_completed_piece_exists() {
        let mut state = setup_two_player_game();
        state.pieces[0].finish();
        state.pieces[1].finish();
        // piece 2는 보드 위에 있지만 completed_circuit 아님
        state.pieces[2].place_on_board(Position::new(5, Path::Outer));
        // piece 3는 completed_circuit
        state.pieces[3].place_on_board(Position::new(0, Path::Outer));
        state.pieces[3].completed_circuit = true;

        state.turn.current_player = 0;
        state.turn.pending_results.push(YutResult::Do);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let finished = state.auto_finish_completed_circuit();
        assert!(finished.is_empty(), "Should not auto-finish when non-completed pieces exist");
    }

    /// 말이 보드 위에 있을 때는 BackDo가 auto-skip되지 않는다.
    #[test]
    fn test_backdo_not_skipped_when_piece_on_board() {
        let mut state = setup_two_player_game();
        // Alice의 말 하나를 보드 위에 올린다.
        state.pieces[0].place_on_board(Position::new(3, Path::Outer));

        state.turn.pending_results.push(YutResult::BackDo);
        state.turn.must_throw = false;
        state.phase = GamePhase::SelectingPiece;

        let skipped = state.auto_skip_unusable_backdo();
        assert!(!skipped, "BackDo should not be auto-skipped when piece is on board");
        assert_eq!(state.turn.current_player, 0, "Turn should stay on Alice");
    }
}
