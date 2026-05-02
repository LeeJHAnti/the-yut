//! Bot AI module for single-player mode.
//!
//! Four difficulty levels:
//! - Easy: Random moves
//! - Medium: Prefers captures, avoids danger
//! - Hard: Position evaluation with shortcut awareness
//! - Expert: Full strategic evaluation with stacking and look-ahead

use rand::Rng;
use serde::{Deserialize, Serialize};

use crate::game::board::{Path, Position};
use crate::game::piece::Piece;
use crate::game::state::GameState;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BotDifficulty {
    Easy,
    Medium,
    Hard,
    Expert,
}

impl BotDifficulty {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "easy" => BotDifficulty::Easy,
            "medium" => BotDifficulty::Medium,
            "hard" => BotDifficulty::Hard,
            "expert" => BotDifficulty::Expert,
            _ => BotDifficulty::Easy,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            BotDifficulty::Easy => "Easy",
            BotDifficulty::Medium => "Medium",
            BotDifficulty::Hard => "Hard",
            BotDifficulty::Expert => "Expert",
        }
    }
}

pub struct BotAI;

impl BotAI {
    /// Choose which piece to move for the given bot player.
    /// Returns the piece_id to select.
    pub fn choose_piece(
        state: &GameState,
        player_id: usize,
        difficulty: BotDifficulty,
    ) -> Option<usize> {
        let movable = state.get_movable_pieces(player_id);
        if movable.is_empty() {
            return None;
        }

        match difficulty {
            BotDifficulty::Easy => Self::choose_random(&movable),
            BotDifficulty::Medium => Self::choose_medium(state, player_id, &movable),
            BotDifficulty::Hard => Self::choose_hard(state, player_id, &movable),
            BotDifficulty::Expert => Self::choose_expert(state, player_id, &movable),
        }
    }

    /// Choose a path when at a junction.
    pub fn choose_path(
        _state: &GameState,
        _player_id: usize,
        options: &[String],
        difficulty: BotDifficulty,
    ) -> String {
        if options.is_empty() {
            return "outer".to_string();
        }

        match difficulty {
            BotDifficulty::Easy => {
                let mut rng = rand::thread_rng();
                options[rng.gen_range(0..options.len())].clone()
            }
            BotDifficulty::Medium | BotDifficulty::Hard | BotDifficulty::Expert => {
                // Prefer shortcuts — they're shorter paths to finish
                if options.contains(&"shortcut".to_string()) {
                    "shortcut".to_string()
                } else if options.contains(&"center_exit".to_string()) {
                    "center_exit".to_string()
                } else {
                    options[0].clone()
                }
            }
        }
    }

    // ---- Easy: Random ----
    fn choose_random(movable: &[usize]) -> Option<usize> {
        let mut rng = rand::thread_rng();
        Some(movable[rng.gen_range(0..movable.len())])
    }

    // ---- Medium: Prefer captures, enter new pieces ----
    fn choose_medium(state: &GameState, player_id: usize, movable: &[usize]) -> Option<usize> {
        let distance = state.turn.pending_results.first()?.distance();

        // Score each piece
        let mut best_id = movable[0];
        let mut best_score = -100i32;

        for &pid in movable {
            let piece = &state.pieces[pid];
            let score = Self::score_medium(state, piece, player_id, distance);
            if score > best_score {
                best_score = score;
                best_id = pid;
            }
        }

        Some(best_id)
    }

    fn score_medium(state: &GameState, piece: &Piece, player_id: usize, distance: u32) -> i32 {
        let mut score = 0i32;

        // Completed-circuit piece at finish — high priority but not absolute.
        // Bot considers other moves too (e.g., capturing, advancing other pieces).
        if piece.completed_circuit && piece.is_on_board() {
            score += 120;
            return score;
        }

        if piece.is_home() {
            // Deploying a new piece is moderately good
            score += 10;
            return score;
        }

        let pos = match piece.position {
            Some(p) => p,
            None => return -50,
        };

        let destinations = state.board.get_next_positions(pos, distance);
        if destinations.is_empty() {
            // Would finish — great!
            return 100;
        }

        for dest in &destinations {
            // Check if we can capture an opponent
            for other in &state.pieces {
                if other.owner != player_id && other.is_on_board() {
                    if let Some(other_pos) = other.position {
                        if other_pos == *dest {
                            score += 50 + (other.stack_count() as i32 * 10);
                        }
                    }
                }
            }
            // Check if we'd land on a friendly (stacking)
            for other in &state.pieces {
                if other.id != piece.id && other.owner == player_id && other.is_on_board() {
                    if let Some(other_pos) = other.position {
                        if other_pos == *dest {
                            score += 5;
                        }
                    }
                }
            }
        }

        score
    }

    // ---- Hard: Position evaluation + shortcut awareness ----
    fn choose_hard(state: &GameState, player_id: usize, movable: &[usize]) -> Option<usize> {
        let distance = state.turn.pending_results.first()?.distance();

        let mut best_id = movable[0];
        let mut best_score = i32::MIN;

        for &pid in movable {
            let piece = &state.pieces[pid];
            let score = Self::score_hard(state, piece, player_id, distance);
            if score > best_score {
                best_score = score;
                best_id = pid;
            }
        }

        Some(best_id)
    }

    fn score_hard(state: &GameState, piece: &Piece, player_id: usize, distance: u32) -> i32 {
        let mut score = Self::score_medium(state, piece, player_id, distance);

        if piece.is_home() {
            return score;
        }

        let pos = match piece.position {
            Some(p) => p,
            None => return score,
        };

        let destinations = state.board.get_next_positions(pos, distance);

        for dest in &destinations {
            // Bonus for reaching junction nodes (opportunity for shortcuts)
            if state.board.has_junction_at(*dest) {
                score += 15;
            }

            // Bonus for advancing closer to finish on shortcut paths
            match dest.path {
                Path::ShortcutA | Path::ShortcutB => {
                    score += 10; // Shortcuts are efficient
                }
                Path::Outer => {}
            }

            // Penalty for being near opponent pieces (danger)
            for other in &state.pieces {
                if other.owner != player_id && other.is_on_board() {
                    if let Some(other_pos) = other.position {
                        let danger = Self::distance_between_positions(other_pos, *dest);
                        if danger <= 5 && danger > 0 {
                            // Stacked pieces are more valuable, so penalize risk more
                            score -= (6 - danger as i32) * piece.stack_count() as i32;
                        }
                    }
                }
            }
        }

        // Advancing far pieces is generally better (closer to finish)
        if pos.path == Path::Outer {
            score += (pos.node as i32) / 2;
        }

        score
    }

    // ---- Expert: Advanced strategy with look-ahead ----
    fn choose_expert(state: &GameState, player_id: usize, movable: &[usize]) -> Option<usize> {
        let distance = state.turn.pending_results.first()?.distance();

        let mut best_id = movable[0];
        let mut best_score = i32::MIN;

        for &pid in movable {
            let piece = &state.pieces[pid];
            let score = Self::score_expert(state, piece, player_id, distance);
            if score > best_score {
                best_score = score;
                best_id = pid;
            }
        }

        Some(best_id)
    }

    fn score_expert(state: &GameState, piece: &Piece, player_id: usize, distance: u32) -> i32 {
        let mut score = Self::score_hard(state, piece, player_id, distance);

        // Expert considers stacking strategy: moving lone pieces is risky
        if piece.is_on_board() && piece.stacked_with.is_empty() {
            // Lone piece — slightly penalize unless capturing
            score -= 3;
        }

        // Expert prefers to keep pieces spread across the board
        if piece.is_home() {
            let on_board_count = state.pieces.iter()
                .filter(|p| p.owner == player_id && p.is_on_board())
                .count();
            if on_board_count < 2 {
                score += 20; // Encourage deploying at least 2 pieces
            }
        }

        // Expert evaluates "finish potential": how many steps to finish
        if let Some(pos) = piece.position {
            let steps_to_finish = Self::estimate_steps_to_finish(pos);
            // Closer to finish = higher priority
            score += (30 - steps_to_finish as i32).max(0);
        }

        // Expert considers opponent threats more carefully
        if piece.is_on_board() {
            if let Some(pos) = piece.position {
                let threat = Self::count_opponent_threats(state, player_id, pos);
                // Stacked pieces should flee from threats
                score -= threat * piece.stack_count() as i32 * 3;
            }
        }

        score
    }

    // ---- Utility functions ----

    /// Estimate the "threat distance" between two positions.
    /// Uses steps-to-finish as a proxy — pieces close to the same finish
    /// distance are more likely to interact.
    fn distance_between_positions(a: Position, b: Position) -> u32 {
        let steps_a = Self::estimate_steps_to_finish(a);
        let steps_b = Self::estimate_steps_to_finish(b);
        if steps_a > steps_b { steps_a - steps_b } else { steps_b - steps_a }
    }

    /// Legacy distance for outer ring nodes only (used in tests).
    fn distance_between(a: u32, b: u32) -> u32 {
        // Simple ring distance on the outer path (20 nodes)
        if a >= 20 || b >= 20 {
            // Diagonal nodes — fall back to large distance (no simple ring calc)
            return 20;
        }
        let forward = if b >= a { b - a } else { 20 + b - a };
        let backward = if a >= b { a - b } else { 20 + a - b };
        forward.min(backward)
    }

    fn estimate_steps_to_finish(pos: Position) -> u32 {
        match pos.path {
            Path::Outer => {
                // Outer ring: node N needs (20 - N) steps to reach finish (node 0)
                // Node 0 with completed_circuit = 0 steps (any throw finishes)
                if pos.node == 0 { 0 } else { 20 - pos.node }
            }
            Path::ShortcutA => {
                // Diagonal A: TR(5) → 20→21→22→23→24 → BL(15), then 15→16→17→18→19→0
                // At center (22), can switch to ShortcutB: 22→27→28→0 = 3 steps (best)
                match pos.node {
                    20 => 7, // 20→21→22(switch)→27→28→0 = best via center switch
                    21 => 6,
                    22 => 3, // best: switch to diagonal B at center → 27→28→0
                    23 => 7, // 23→24→15, then 15→16→17→18→19→0 = 2+5 = 7
                    24 => 6, // 24→15, then 5 outer = 6
                    _ => 12,
                }
            }
            Path::ShortcutB => {
                // Diagonal B: TL(10) → 25→26→22→27→28 → BR(0=finish)
                match pos.node {
                    25 => 5,
                    26 => 4,
                    22 => 3,
                    27 => 2,
                    28 => 1,
                    _ => 8,
                }
            }
        }
    }

    fn count_opponent_threats(state: &GameState, player_id: usize, pos: Position) -> i32 {
        let mut threats = 0;
        for other in &state.pieces {
            if other.owner != player_id && other.is_on_board() {
                if let Some(other_pos) = other.position {
                    let dist = Self::distance_between_positions(other_pos, pos);
                    // Pieces within 5 steps are a threat
                    if dist <= 5 && dist > 0 {
                        threats += 1;
                    }
                }
            }
        }
        threats
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bot_difficulty_from_str() {
        assert_eq!(BotDifficulty::from_str("easy"), BotDifficulty::Easy);
        assert_eq!(BotDifficulty::from_str("HARD"), BotDifficulty::Hard);
        assert_eq!(BotDifficulty::from_str("expert"), BotDifficulty::Expert);
        assert_eq!(BotDifficulty::from_str("unknown"), BotDifficulty::Easy);
    }

    #[test]
    fn test_distance_between() {
        assert_eq!(BotAI::distance_between(0, 5), 5);
        assert_eq!(BotAI::distance_between(18, 2), 4);
        assert_eq!(BotAI::distance_between(5, 5), 0);
    }

    #[test]
    fn test_estimate_steps() {
        assert_eq!(BotAI::estimate_steps_to_finish(Position::new(15, Path::Outer)), 5);
        assert_eq!(BotAI::estimate_steps_to_finish(Position::new(28, Path::ShortcutB)), 1);
        assert_eq!(BotAI::estimate_steps_to_finish(Position::new(27, Path::ShortcutB)), 2);
        assert_eq!(BotAI::estimate_steps_to_finish(Position::new(20, Path::ShortcutA)), 7);
        assert_eq!(BotAI::estimate_steps_to_finish(Position::new(22, Path::ShortcutA)), 3);
    }

    #[test]
    fn test_choose_path_shortcuts() {
        let state = GameState::new();
        let options = vec!["outer".to_string(), "shortcut".to_string()];
        let choice = BotAI::choose_path(&state, 0, &options, BotDifficulty::Hard);
        assert_eq!(choice, "shortcut");
    }

    #[test]
    fn test_easy_bot_returns_valid_piece() {
        let mut state = GameState::new();
        state.add_player("Human".into(), "tok0".into());
        state.add_bot("Bot".into());
        state.start_game().unwrap();
        // Simulate a throw so there's a pending result
        state.turn.must_throw = false;
        state.turn.pending_results.push(crate::game::yut::YutResult::Gae);
        state.phase = crate::game::state::GamePhase::SelectingPiece;

        let choice = BotAI::choose_piece(&state, 1, BotDifficulty::Easy);
        assert!(choice.is_some());
        let pid = choice.unwrap();
        assert!(state.pieces[pid].owner == 1);
    }
}
