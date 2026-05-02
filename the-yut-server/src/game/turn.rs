use super::yut::YutResult;

#[derive(Debug, Clone)]
pub struct TurnManager {
    pub current_player: usize,          // actual player ID
    pub player_ids: Vec<usize>,         // ordered list of player IDs
    current_index: usize,               // index into player_ids
    pub pending_results: Vec<YutResult>,
    pub must_throw: bool,
    pub extra_turn_from_capture: bool,  // capture bonus: grants one more throw
}

impl TurnManager {
    pub fn new(player_ids: Vec<usize>) -> Self {
        let first = player_ids.first().copied().unwrap_or(0);
        Self {
            current_player: first,
            player_ids,
            current_index: 0,
            pending_results: Vec::new(),
            must_throw: true,
            extra_turn_from_capture: false,
        }
    }

    /// Record a throw result.
    ///
    /// `must_throw` is set to `true` only when the result itself grants an
    /// extra throw (Yut / Mo).  For ordinary results (Do / Gae / Geol /
    /// BackDo) `must_throw` becomes `false`, meaning the player moves next.
    /// A capture bonus (`extra_turn_from_capture`) is handled separately
    /// after all pending_results are consumed — see `GameState::advance_phase`.
    pub fn record_throw(&mut self, result: YutResult) {
        let extra = result.has_extra_turn();
        self.pending_results.push(result);
        self.must_throw = extra; // true only for Yut/Mo
    }

    pub fn use_result(&mut self, index: usize) -> Option<YutResult> {
        if index < self.pending_results.len() {
            Some(self.pending_results.remove(index))
        } else {
            None
        }
    }

    pub fn has_pending_results(&self) -> bool {
        !self.pending_results.is_empty()
    }

    pub fn should_throw(&self) -> bool {
        self.must_throw
    }

    /// Grant an extra throw from capturing an opponent's piece.
    /// Only effective when the throw result was Do/Gae/Geol (non-extra).
    /// Yut/Mo already grant extra throws via must_throw, so capture
    /// bonus doesn't double-stack with those.
    pub fn grant_capture_extra_turn(&mut self) {
        self.extra_turn_from_capture = true;
    }

    /// Check if the current turn is fully complete (no throws, no moves, no extras)
    #[allow(dead_code)]
    pub fn is_turn_complete(&self) -> bool {
        !self.must_throw && !self.extra_turn_from_capture && self.pending_results.is_empty()
    }

    pub fn advance_turn(&mut self) {
        self.current_index = (self.current_index + 1) % self.player_ids.len();
        self.current_player = self.player_ids[self.current_index];
        self.must_throw = true;
        self.extra_turn_from_capture = false;
        self.pending_results.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_turn(ids: Vec<usize>) -> TurnManager {
        TurnManager::new(ids)
    }

    // ── 초기 상태 ──

    /// 새 TurnManager의 첫 번째 플레이어가 current_player가 되어야 한다.
    #[test]
    fn test_initial_current_player() {
        let tm = make_turn(vec![10, 20, 30]);
        assert_eq!(tm.current_player, 10);
    }

    /// 새 TurnManager는 처음에 던지기 상태(must_throw = true)여야 한다.
    #[test]
    fn test_initial_must_throw() {
        let tm = make_turn(vec![0, 1]);
        assert!(tm.should_throw());
    }

    // ── record_throw ──

    /// 도/개/걸 던지기 후 pending_results에 결과가 쌓이고 must_throw는 false여야 한다.
    #[test]
    fn test_record_throw_non_extra() {
        let mut tm = make_turn(vec![0, 1]);
        tm.record_throw(YutResult::Gae);
        assert_eq!(tm.pending_results.len(), 1);
        assert!(!tm.should_throw(), "Gae should not require another throw");
    }

    /// 윷 던지기 후 must_throw가 true여야 한다 (추가 던지기 의무).
    #[test]
    fn test_record_throw_yut_requires_extra_throw() {
        let mut tm = make_turn(vec![0, 1]);
        tm.record_throw(YutResult::Yut);
        assert!(tm.should_throw(), "Yut should require extra throw");
        assert_eq!(tm.pending_results.len(), 1);
    }

    /// 모 던지기 후 must_throw가 true여야 한다.
    #[test]
    fn test_record_throw_mo_requires_extra_throw() {
        let mut tm = make_turn(vec![0, 1]);
        tm.record_throw(YutResult::Mo);
        assert!(tm.should_throw(), "Mo should require extra throw");
    }

    /// 윷 + 개 순서로 던지면 pending_results에 2개가 쌓이고 더 이상 던지지 않아도 된다.
    #[test]
    fn test_record_throw_yut_then_gae_accumulates() {
        let mut tm = make_turn(vec![0, 1]);
        tm.record_throw(YutResult::Yut); // extra throw required
        assert!(tm.should_throw());
        tm.record_throw(YutResult::Gae); // no more extra
        assert!(!tm.should_throw());
        assert_eq!(tm.pending_results.len(), 2);
    }

    // ── use_result ──

    /// use_result(0)은 pending_results의 첫 번째 결과를 제거하고 반환한다.
    #[test]
    fn test_use_result_removes_entry() {
        let mut tm = make_turn(vec![0, 1]);
        tm.record_throw(YutResult::Geol);
        let r = tm.use_result(0);
        assert_eq!(r, Some(YutResult::Geol));
        assert!(tm.pending_results.is_empty());
    }

    /// 유효하지 않은 인덱스에 대해 None을 반환한다.
    #[test]
    fn test_use_result_out_of_bounds_returns_none() {
        let mut tm = make_turn(vec![0, 1]);
        assert!(tm.use_result(0).is_none());
    }

    // ── advance_turn ──

    /// advance_turn() 이후 다음 플레이어로 전환되고 must_throw가 true가 돼야 한다.
    #[test]
    fn test_advance_turn_cycles_players() {
        let mut tm = make_turn(vec![0, 1, 2]);
        assert_eq!(tm.current_player, 0);
        tm.advance_turn();
        assert_eq!(tm.current_player, 1);
        tm.advance_turn();
        assert_eq!(tm.current_player, 2);
        tm.advance_turn();
        assert_eq!(tm.current_player, 0, "Should wrap around to first player");
    }

    /// advance_turn() 후 pending_results가 비워진다.
    #[test]
    fn test_advance_turn_clears_pending() {
        let mut tm = make_turn(vec![0, 1]);
        tm.record_throw(YutResult::Do);
        tm.advance_turn();
        assert!(tm.pending_results.is_empty());
    }

    /// advance_turn() 후 extra_turn_from_capture가 초기화된다.
    #[test]
    fn test_advance_turn_resets_capture_extra() {
        let mut tm = make_turn(vec![0, 1]);
        tm.grant_capture_extra_turn();
        tm.advance_turn();
        assert!(!tm.extra_turn_from_capture);
    }

    // ── grant_capture_extra_turn ──

    /// grant_capture_extra_turn() 호출 후 extra_turn_from_capture가 true가 된다.
    #[test]
    fn test_grant_capture_extra_turn() {
        let mut tm = make_turn(vec![0, 1]);
        assert!(!tm.extra_turn_from_capture);
        tm.grant_capture_extra_turn();
        assert!(tm.extra_turn_from_capture);
    }

    // ── is_turn_complete ──

    /// 던지기도 없고 pending도 없고 capture 보너스도 없을 때 complete여야 한다.
    #[test]
    fn test_is_turn_complete_when_nothing_pending() {
        let mut tm = make_turn(vec![0, 1]);
        // 초기에는 must_throw = true이므로 아직 complete가 아니다
        assert!(!tm.is_turn_complete());

        // 도 던지고 결과를 소비한다
        tm.record_throw(YutResult::Do);
        tm.use_result(0);
        assert!(tm.is_turn_complete());
    }
}
