use std::collections::{HashMap, HashSet};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Path {
    Outer,
    ShortcutA,
    ShortcutB,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Position {
    pub node: u32,
    pub path: Path,
}

impl Position {
    pub fn new(node: u32, path: Path) -> Self {
        Self { node, path }
    }

    #[cfg(test)]
    pub fn start() -> Self {
        Self { node: 0, path: Path::Outer }
    }
}

// ══════════════════════════════════════════════════════════════════
// Traditional Yut Board (윷판)
// ══════════════════════════════════════════════════════════════════
//
// Movement: COUNTER-CLOCKWISE
//
//   TL(10)---9----8----7----6---TR(5)
//     | ╲                     ╱ |
//    11   25               20   4
//     |     26           21     |
//    12       ╲   22   ╱        3
//     |        (center)         |
//    13       ╱   22   ╲        2
//     |     27           23     |
//    14   28               24   1
//     | ╱                     ╲ |
//   BL(15)--16---17---18---19--START(0)
//
// Outer ring (20 nodes, counter-clockwise):
//   0(BR) → 1→2→3→4 → 5(TR) → 6→7→8→9 → 10(TL)
//         → 11→12→13→14 → 15(BL) → 16→17→18→19 → 0(finish)
//
// Diagonal A — TR(5) → center → BL(15):
//   5 → 20 → 21 → 22(center) → 23 → 24 → 15
//   * 5에서 3칸 = center,  5에서 6칸 = BL(15)
//
// Diagonal B — TL(10) → center → BR(0=finish):
//   10 → 25 → 26 → 22(center) → 27 → 28 → 0
//   * 10에서 3칸 = center,  10에서 6칸 = finish
//
// Center junction (22, ShortcutA only):
//   "continue"    → 23 (toward BL via ShortcutA)
//   "center_exit" → 27 (switch to ShortcutB toward finish)
// ══════════════════════════════════════════════════════════════════

#[derive(Debug)]
pub struct Board {
    graph: HashMap<Position, Vec<(Position, u32)>>,
}

impl Board {
    pub fn new() -> Self {
        let mut graph = HashMap::new();

        // ── Outer ring: 0 → 1 → 2 → ... → 19 → 0(finish) ──
        for node in 0..19 {
            let pos = Position::new(node, Path::Outer);
            let next_pos = Position::new(node + 1, Path::Outer);
            graph.entry(pos).or_insert_with(Vec::new).push((next_pos, 1));
        }
        graph.entry(Position::new(19, Path::Outer))
            .or_insert_with(Vec::new)
            .push((Position::new(0, Path::Outer), 1));

        // ── Junction at node 5 (TR): enter Diagonal A ──
        graph.entry(Position::new(5, Path::Outer))
            .or_insert_with(Vec::new)
            .push((Position::new(20, Path::ShortcutA), 1));

        // ── Junction at node 10 (TL): enter Diagonal B ──
        graph.entry(Position::new(10, Path::Outer))
            .or_insert_with(Vec::new)
            .push((Position::new(25, Path::ShortcutB), 1));

        // ── Diagonal A: TR(5) → 20 → 21 → 22 → 23 → 24 → BL(15) ──
        for (from, to) in [
            (Position::new(20, Path::ShortcutA), Position::new(21, Path::ShortcutA)),
            (Position::new(21, Path::ShortcutA), Position::new(22, Path::ShortcutA)),
            (Position::new(22, Path::ShortcutA), Position::new(23, Path::ShortcutA)),
            (Position::new(23, Path::ShortcutA), Position::new(24, Path::ShortcutA)),
            (Position::new(24, Path::ShortcutA), Position::new(15, Path::Outer)),
        ] {
            graph.entry(from).or_insert_with(Vec::new).push((to, 1));
        }

        // ── Diagonal B: TL(10) → 25 → 26 → 22 → 27 → 28 → BR(0=finish) ──
        for (from, to) in [
            (Position::new(25, Path::ShortcutB), Position::new(26, Path::ShortcutB)),
            (Position::new(26, Path::ShortcutB), Position::new(22, Path::ShortcutB)),
            (Position::new(22, Path::ShortcutB), Position::new(27, Path::ShortcutB)),
            (Position::new(27, Path::ShortcutB), Position::new(28, Path::ShortcutB)),
            (Position::new(28, Path::ShortcutB), Position::new(0, Path::Outer)),
        ] {
            graph.entry(from).or_insert_with(Vec::new).push((to, 1));
        }

        // ── Center diagonal switch (ShortcutA → ShortcutB) ──
        // At center on Diagonal A, allow switching to Diagonal B toward finish.
        graph.entry(Position::new(22, Path::ShortcutA))
            .or_insert_with(Vec::new)
            .push((Position::new(27, Path::ShortcutB), 1));

        Self { graph }
    }

    /// Get all possible final positions after moving `distance` steps from `pos`.
    pub fn get_next_positions(&self, pos: Position, distance: u32) -> Vec<Position> {
        let mut current = vec![pos];
        let mut remaining = distance;

        while remaining > 0 {
            let mut next_set = HashSet::new();
            let mut next = Vec::new();
            for curr_pos in &current {
                if let Some(neighbors) = self.graph.get(curr_pos) {
                    for (neighbor, _cost) in neighbors {
                        if next_set.insert(*neighbor) {
                            next.push(*neighbor);
                        }
                    }
                }
            }
            current = next;
            remaining -= 1;
        }

        current
    }

    /// Check if the finish node is reached at ANY intermediate step (not just final).
    /// This implements the traditional yut rule: passing through finish = finishing.
    pub fn passes_through_finish(&self, pos: Position, distance: u32) -> bool {
        let mut current = vec![pos];

        for _step in 0..distance {
            let mut next_set = HashSet::new();
            let mut next = Vec::new();
            for curr_pos in &current {
                if let Some(neighbors) = self.graph.get(curr_pos) {
                    for (neighbor, _cost) in neighbors {
                        if self.is_finish(*neighbor) {
                            return true;
                        }
                        if next_set.insert(*neighbor) {
                            next.push(*neighbor);
                        }
                    }
                }
            }
            current = next;
        }

        false
    }

    pub fn has_junction_at(&self, pos: Position) -> bool {
        matches!(pos,
            Position { node: 5, path: Path::Outer }
            | Position { node: 10, path: Path::Outer }
            | Position { node: 22, path: Path::ShortcutA }
        )
    }

    pub fn get_junction_options(&self, pos: Position) -> Vec<String> {
        match pos {
            Position { node: 5, path: Path::Outer }
            | Position { node: 10, path: Path::Outer } => {
                vec!["outer".to_string(), "shortcut".to_string()]
            }
            Position { node: 22, path: Path::ShortcutA } => {
                // At center on diagonal A: continue to BL(15) or switch toward finish(0)
                vec!["continue".to_string(), "center_exit".to_string()]
            }
            _ => Vec::new(),
        }
    }

    /// Apply path choice at a junction. ALWAYS returns the next position
    /// (one step forward on the chosen path), consuming 1 step of movement.
    pub fn apply_path_choice(&self, pos: Position, choice: &str) -> Position {
        match (pos, choice) {
            // TR corner (node 5)
            (Position { node: 5, path: Path::Outer }, "shortcut") =>
                Position::new(20, Path::ShortcutA),
            (Position { node: 5, path: Path::Outer }, "outer") =>
                Position::new(6, Path::Outer),
            // TL corner (node 10)
            (Position { node: 10, path: Path::Outer }, "shortcut") =>
                Position::new(25, Path::ShortcutB),
            (Position { node: 10, path: Path::Outer }, "outer") =>
                Position::new(11, Path::Outer),
            // Center on diagonal A (node 22)
            (Position { node: 22, path: Path::ShortcutA }, "center_exit") =>
                Position::new(27, Path::ShortcutB),
            (Position { node: 22, path: Path::ShortcutA }, "continue") =>
                Position::new(23, Path::ShortcutA),
            _ => pos,
        }
    }

    pub fn is_finish(&self, pos: Position) -> bool {
        pos.node == 0 && pos.path == Path::Outer
    }

    /// Get the previous position (1 step backward) on the outer ring.
    /// Used for BackDo (백도) rule. Returns None if can't go backward.
    /// BackDo only applies on the outer ring and follows clockwise (reverse) direction.
    pub fn get_prev_position(&self, pos: Position) -> Option<Position> {
        match pos.path {
            Path::Outer => {
                if pos.node == 0 {
                    // At start/finish — can't go backward further
                    None
                } else if pos.node == 1 {
                    // BackDo from node 1 → node 0 (piece waits at start/finish)
                    Some(Position::new(0, Path::Outer))
                } else {
                    Some(Position::new(pos.node - 1, Path::Outer))
                }
            }
            // BackDo on shortcuts: go back one node on the shortcut path
            Path::ShortcutA => {
                match pos.node {
                    20 => Some(Position::new(5, Path::Outer)),   // back to junction
                    21 => Some(Position::new(20, Path::ShortcutA)),
                    22 => Some(Position::new(21, Path::ShortcutA)),
                    23 => Some(Position::new(22, Path::ShortcutA)),
                    24 => Some(Position::new(23, Path::ShortcutA)),
                    _ => None,
                }
            }
            Path::ShortcutB => {
                match pos.node {
                    25 => Some(Position::new(10, Path::Outer)),  // back to junction
                    26 => Some(Position::new(25, Path::ShortcutB)),
                    22 => Some(Position::new(26, Path::ShortcutB)),
                    27 => Some(Position::new(22, Path::ShortcutB)),
                    28 => Some(Position::new(27, Path::ShortcutB)),
                    _ => None,
                }
            }
        }
    }

    #[allow(dead_code)]
    pub fn get_neighbors(&self, pos: Position) -> Option<&Vec<(Position, u32)>> {
        self.graph.get(&pos)
    }
}

impl Default for Board {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_board_creation() {
        let board = Board::new();
        let start = Position::start();
        let next = board.get_next_positions(start, 1);
        assert!(!next.is_empty());
    }

    #[test]
    fn test_outer_path_progression() {
        let board = Board::new();
        // From start (0), 1 step → node 1
        let next = board.get_next_positions(Position::new(0, Path::Outer), 1);
        assert!(next.contains(&Position::new(1, Path::Outer)));
    }

    #[test]
    fn test_movement_direction() {
        // Movement goes: 0(BR) → UP right side → 5(TR)
        let board = Board::new();
        let pos = board.get_next_positions(Position::new(0, Path::Outer), 5);
        assert!(pos.contains(&Position::new(5, Path::Outer)),
            "5 steps from start should reach TR corner (node 5)");
    }

    #[test]
    fn test_junction_at_node_5() {
        let board = Board::new();
        let pos_5 = Position::new(5, Path::Outer);
        assert!(board.has_junction_at(pos_5));
        let options = board.get_junction_options(pos_5);
        assert!(options.contains(&"outer".to_string()));
        assert!(options.contains(&"shortcut".to_string()));
    }

    #[test]
    fn test_junction_at_node_10() {
        let board = Board::new();
        let pos_10 = Position::new(10, Path::Outer);
        assert!(board.has_junction_at(pos_10));
    }

    #[test]
    fn test_shortcut_a_full_path() {
        // Diagonal A: 5 → 20 → 21 → 22 → 23 → 24 → 15 (6 steps from junction)
        let board = Board::new();
        let entry = board.apply_path_choice(Position::new(5, Path::Outer), "shortcut");
        assert_eq!(entry, Position::new(20, Path::ShortcutA));

        // 20 → 21 → 22 → 23 → 24 → 15 (5 steps)
        let result = board.get_next_positions(entry, 5);
        assert!(result.iter().any(|p| p.node == 15 && p.path == Path::Outer),
            "5 steps from node 20 on ShortcutA should reach BL (node 15), got {:?}", result);
    }

    #[test]
    fn test_shortcut_a_3_steps_to_center() {
        // 5에서 3칸 = 중앙(22)
        let board = Board::new();
        let entry = board.apply_path_choice(Position::new(5, Path::Outer), "shortcut");
        // entry = node 20. From 20: 20→21(1) →22(2). That's 2 steps.
        // But from 5, taking shortcut = entering node 20 (1 step), then 20→21(2), 21→22(3)
        // So from the junction choice, we need to count: 5→20 is the "shortcut" entry,
        // then 20→21→22 is 2 more steps. Total from 5 = 3 steps to center.
        let result = board.get_next_positions(entry, 2);
        assert!(result.iter().any(|p| p.node == 22),
            "2 steps from node 20 should reach center (22), got {:?}", result);
    }

    #[test]
    fn test_shortcut_a_6_steps_to_bl() {
        // 5에서 6칸 = 좌하단(15)
        let board = Board::new();
        let entry = board.apply_path_choice(Position::new(5, Path::Outer), "shortcut");
        // entry = 20. 20→21→22→23→24→15 = 5 steps from 20
        let result = board.get_next_positions(entry, 5);
        assert!(result.iter().any(|p| p.node == 15 && p.path == Path::Outer),
            "5 steps from node 20 should reach BL (15), got {:?}", result);
    }

    #[test]
    fn test_shortcut_b_full_path() {
        // Diagonal B: 10 → 25 → 26 → 22 → 27 → 28 → 0(finish)
        let board = Board::new();
        let entry = board.apply_path_choice(Position::new(10, Path::Outer), "shortcut");
        assert_eq!(entry, Position::new(25, Path::ShortcutB));

        // 25 → 26 → 22 → 27 → 28 → 0 (5 steps)
        let result = board.get_next_positions(entry, 5);
        assert!(result.iter().any(|p| p.node == 0),
            "5 steps from node 25 on ShortcutB should reach finish (0), got {:?}", result);
    }

    #[test]
    fn test_shortcut_b_3_steps_to_center() {
        // 10에서 3칸 = 중앙(22)
        let board = Board::new();
        let entry = board.apply_path_choice(Position::new(10, Path::Outer), "shortcut");
        let result = board.get_next_positions(entry, 2);
        assert!(result.iter().any(|p| p.node == 22),
            "2 steps from node 25 should reach center (22), got {:?}", result);
    }

    #[test]
    fn test_center_switch_diagonal() {
        // At center on ShortcutA, choose "center_exit" → switches to ShortcutB toward finish
        let board = Board::new();
        let pos = Position::new(22, Path::ShortcutA);
        let switched = board.apply_path_choice(pos, "center_exit");
        assert_eq!(switched, Position::new(27, Path::ShortcutB));

        // From 27: 27 → 28 → 0 (2 steps to finish)
        let result = board.get_next_positions(switched, 2);
        assert!(result.iter().any(|p| p.node == 0));
    }

    #[test]
    fn test_center_junction_on_shortcut_a() {
        let board = Board::new();
        let pos = Position::new(22, Path::ShortcutA);
        assert!(board.has_junction_at(pos));

        // From center on ShortcutA, 1 step gives TWO options:
        // - 23 (continue A toward BL)
        // - 27 (switch to B toward finish)
        let next = board.get_next_positions(pos, 1);
        assert!(next.iter().any(|p| p.node == 23), "Should have path to 23 (continue A)");
        assert!(next.iter().any(|p| p.node == 27), "Should have path to 27 (switch to B)");
    }

    #[test]
    fn test_no_junction_on_shortcut_b_center() {
        let board = Board::new();
        let pos = Position::new(22, Path::ShortcutB);
        // ShortcutB at center has only one direction: toward finish
        assert!(!board.has_junction_at(pos));
        let next = board.get_next_positions(pos, 1);
        assert_eq!(next.len(), 1);
        assert_eq!(next[0].node, 27);
    }

    #[test]
    fn test_full_outer_loop() {
        let board = Board::new();
        let result = board.get_next_positions(Position::new(0, Path::Outer), 20);
        assert!(result.iter().any(|p| p.node == 0));
    }

    #[test]
    fn test_passes_through_finish() {
        let board = Board::new();
        // Piece at node 18, rolling 3: 18→19→0(finish!) → should detect pass-through
        assert!(board.passes_through_finish(Position::new(18, Path::Outer), 3));

        // Piece at node 18, rolling 1: 18→19, no finish
        assert!(!board.passes_through_finish(Position::new(18, Path::Outer), 1));

        // Piece at node 19, rolling 1: 19→0(finish!)
        assert!(board.passes_through_finish(Position::new(19, Path::Outer), 1));

        // Piece on ShortcutB node 27, rolling 3: 27→28→0(finish!)
        assert!(board.passes_through_finish(Position::new(27, Path::ShortcutB), 3));
    }
}
