use serde::{Deserialize, Serialize};
use super::board::Position;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PieceStatus {
    Home,
    OnBoard,
    Finished,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Piece {
    pub id: usize,
    pub owner: usize,
    pub status: PieceStatus,
    pub position: Option<Position>,
    pub stacked_with: Vec<usize>,
    /// True when the piece has completed the full circuit and is waiting
    /// at node 0 to be scored.  Any throw result will finish this piece.
    pub completed_circuit: bool,
}

impl Piece {
    pub fn new(id: usize, owner: usize) -> Self {
        Self {
            id,
            owner,
            status: PieceStatus::Home,
            position: None,
            stacked_with: Vec::new(),
            completed_circuit: false,
        }
    }

    pub fn place_on_board(&mut self, pos: Position) {
        self.status = PieceStatus::OnBoard;
        self.position = Some(pos);
    }

    pub fn move_to(&mut self, pos: Position) {
        self.position = Some(pos);
    }

    pub fn send_home(&mut self) {
        self.status = PieceStatus::Home;
        self.position = None;
        self.stacked_with.clear();
        self.completed_circuit = false;
    }

    pub fn finish(&mut self) {
        self.status = PieceStatus::Finished;
        self.position = None;
        self.stacked_with.clear();
        self.completed_circuit = false;
    }

    pub fn is_home(&self) -> bool {
        self.status == PieceStatus::Home
    }

    pub fn is_on_board(&self) -> bool {
        self.status == PieceStatus::OnBoard
    }

    pub fn is_finished(&self) -> bool {
        self.status == PieceStatus::Finished
    }

    /// Add `other_id` to this piece's stacked_with list (one-directional).
    ///
    /// NOTE: This method only updates *this* piece.  Full bidirectional
    /// synchronisation (all group members reference each other) is the
    /// responsibility of the caller — see `GameState::apply_move_at` which
    /// builds the complete `full_group` and writes every member's
    /// `stacked_with` in one pass.  Do NOT call this method directly for
    /// in-game stacking; use `apply_move_at` instead.
    pub fn stack_with(&mut self, other_id: usize) {
        if !self.stacked_with.contains(&other_id) {
            self.stacked_with.push(other_id);
        }
    }

    /// Total pieces at this position (self + stacked)
    pub fn stack_count(&self) -> usize {
        1 + self.stacked_with.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::board::{Path, Position};

    fn make_piece(id: usize, owner: usize) -> Piece {
        Piece::new(id, owner)
    }

    // ── 기본 상태 ──

    /// 새로운 말은 Home 상태이고 position이 None 이어야 한다.
    #[test]
    fn test_new_piece_is_home() {
        let p = make_piece(0, 0);
        assert!(p.is_home());
        assert!(!p.is_on_board());
        assert!(!p.is_finished());
        assert!(p.position.is_none());
        assert!(p.stacked_with.is_empty());
        assert!(!p.completed_circuit);
    }

    /// place_on_board() 이후 상태가 OnBoard가 되고 위치가 설정돼야 한다.
    #[test]
    fn test_place_on_board() {
        let mut p = make_piece(0, 0);
        let pos = Position::new(3, Path::Outer);
        p.place_on_board(pos);
        assert!(p.is_on_board());
        assert_eq!(p.position, Some(pos));
    }

    // ── 이동 ──

    /// move_to() 호출 후 position이 새 위치로 업데이트 된다.
    #[test]
    fn test_move_to_updates_position() {
        let mut p = make_piece(0, 0);
        p.place_on_board(Position::new(1, Path::Outer));
        let new_pos = Position::new(5, Path::Outer);
        p.move_to(new_pos);
        assert_eq!(p.position, Some(new_pos));
    }

    /// 지름길(ShortcutA) 위치로 이동할 수 있어야 한다.
    #[test]
    fn test_move_to_shortcut_position() {
        let mut p = make_piece(0, 0);
        p.place_on_board(Position::new(5, Path::Outer));
        let shortcut_pos = Position::new(20, Path::ShortcutA);
        p.move_to(shortcut_pos);
        assert_eq!(p.position, Some(shortcut_pos));
    }

    // ── 귀가 ──

    /// send_home() 이후 Home 상태, position None, stacked_with 비어 있어야 한다.
    #[test]
    fn test_send_home_resets_all_state() {
        let mut p = make_piece(0, 0);
        p.place_on_board(Position::new(3, Path::Outer));
        p.stacked_with.push(1);
        p.completed_circuit = true;
        p.send_home();
        assert!(p.is_home());
        assert!(p.position.is_none());
        assert!(p.stacked_with.is_empty());
        assert!(!p.completed_circuit);
    }

    // ── 완주 ──

    /// finish() 이후 Finished 상태, position None, stacked_with 비어 있어야 한다.
    #[test]
    fn test_finish_resets_all_state() {
        let mut p = make_piece(0, 0);
        p.place_on_board(Position::new(18, Path::Outer));
        p.stacked_with.push(2);
        p.completed_circuit = true;
        p.finish();
        assert!(p.is_finished());
        assert!(p.position.is_none());
        assert!(p.stacked_with.is_empty());
        assert!(!p.completed_circuit);
    }

    // ── 스태킹 (업기) ──

    /// stack_with()를 호출하면 stacked_with에 상대 ID가 추가된다.
    #[test]
    fn test_stack_with_adds_id() {
        let mut p = make_piece(0, 0);
        p.stack_with(1);
        assert!(p.stacked_with.contains(&1));
        assert_eq!(p.stack_count(), 2);
    }

    /// 같은 ID를 중복 추가해도 한 번만 들어가야 한다.
    #[test]
    fn test_stack_with_no_duplicates() {
        let mut p = make_piece(0, 0);
        p.stack_with(1);
        p.stack_with(1);
        assert_eq!(p.stacked_with.len(), 1);
    }

    /// stack_with()는 단방향 갱신이므로, 양방향 스태킹이 필요하면 양쪽 모두 호출해야 한다.
    /// GameState::apply_move_at 가 full_group 전체를 갱신하는 방식 검증.
    #[test]
    fn test_stacking_bidirectional_via_explicit_calls() {
        let mut p0 = make_piece(0, 0);
        let mut p1 = make_piece(1, 0);

        // apply_move_at에서 수행하는 양방향 갱신을 수동으로 재현
        p0.stack_with(p1.id);
        p1.stack_with(p0.id);

        assert!(p0.stacked_with.contains(&p1.id), "p0 should reference p1");
        assert!(p1.stacked_with.contains(&p0.id), "p1 should reference p0");
        assert_eq!(p0.stack_count(), 2);
        assert_eq!(p1.stack_count(), 2);
    }

    /// stack_count()는 자신 포함 스택 전체 크기를 반환한다.
    #[test]
    fn test_stack_count_includes_self() {
        let mut p = make_piece(0, 0);
        assert_eq!(p.stack_count(), 1);
        p.stack_with(1);
        assert_eq!(p.stack_count(), 2);
        p.stack_with(2);
        assert_eq!(p.stack_count(), 3);
    }

    // ── 잡기 ──

    /// 잡힌 말은 send_home() 호출 후 Home 상태로 돌아가야 한다.
    #[test]
    fn test_captured_piece_sent_home() {
        let mut enemy = make_piece(4, 1);
        enemy.place_on_board(Position::new(3, Path::Outer));
        enemy.stack_with(5);

        // 잡기 처리: send_home()
        enemy.send_home();

        assert!(enemy.is_home(), "Captured piece should be sent home");
        assert!(enemy.position.is_none());
        assert!(enemy.stacked_with.is_empty(), "Stack cleared on capture");
    }

    /// 스택(업힌) 말 포함 리드 말을 잡으면 모두 귀가해야 한다.
    #[test]
    fn test_all_stacked_pieces_cleared_on_capture() {
        let mut lead = make_piece(4, 1);
        let mut follower = make_piece(5, 1);
        lead.place_on_board(Position::new(7, Path::Outer));
        follower.place_on_board(Position::new(7, Path::Outer));
        lead.stack_with(follower.id);
        follower.stack_with(lead.id);

        // 잡기: 리드 + 스택 멤버 모두 귀가
        lead.send_home();
        follower.send_home();

        assert!(lead.is_home());
        assert!(follower.is_home());
    }
}
