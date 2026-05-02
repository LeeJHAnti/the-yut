use rand::Rng;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum YutResult {
    Do,      // 도: 1 step forward
    BackDo,  // 백도: 1 step backward (special Do with baekdo stick)
    Gae,     // 개: 2 steps forward
    Geol,    // 걸: 3 steps forward
    Yut,     // 윷: 4 steps forward + extra turn
    Mo,      // 모: 5 steps forward + extra turn
}

impl YutResult {
    /// Movement distance. BackDo returns 1 but moves backward (handled in state.rs).
    pub fn distance(&self) -> u32 {
        match self {
            YutResult::Do | YutResult::BackDo => 1,
            YutResult::Gae => 2,
            YutResult::Geol => 3,
            YutResult::Yut => 4,
            YutResult::Mo => 5,
        }
    }

    /// Whether this result moves backward instead of forward.
    pub fn is_backward(&self) -> bool {
        matches!(self, YutResult::BackDo)
    }

    pub fn has_extra_turn(&self) -> bool {
        matches!(self, YutResult::Yut | YutResult::Mo)
    }

    pub fn as_string(&self) -> String {
        match self {
            YutResult::Do => "Do".to_string(),
            YutResult::BackDo => "BackDo".to_string(),
            YutResult::Gae => "Gae".to_string(),
            YutResult::Geol => "Geol".to_string(),
            YutResult::Yut => "Yut".to_string(),
            YutResult::Mo => "Mo".to_string(),
        }
    }
}

pub struct YutThrower;

impl YutThrower {
    pub fn throw() -> YutResult {
        let mut rng = rand::thread_rng();
        let roll = rng.gen_range(0..16);

        if roll < 4 {
            // Do result — 25% chance the baekdo-marked stick is the flat one
            let baekdo_roll = rng.gen_range(0..4);
            if baekdo_roll == 0 {
                YutResult::BackDo
            } else {
                YutResult::Do
            }
        }
        else if roll < 10 { YutResult::Gae }
        else if roll < 14 { YutResult::Geol }
        else if roll == 14 { YutResult::Yut }
        else { YutResult::Mo }
    }

    /// Deterministic throw for testing
    #[cfg(test)]
    pub fn throw_with_seed(seed: u64) -> YutResult {
        use rand::SeedableRng;
        let mut rng = rand::rngs::StdRng::seed_from_u64(seed);
        let roll = rng.gen_range(0..16);

        if roll < 4 { YutResult::Do }
        else if roll < 10 { YutResult::Gae }
        else if roll < 14 { YutResult::Geol }
        else if roll == 14 { YutResult::Yut }
        else { YutResult::Mo }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_yut_result_distances() {
        assert_eq!(YutResult::Do.distance(), 1);
        assert_eq!(YutResult::BackDo.distance(), 1);
        assert_eq!(YutResult::Gae.distance(), 2);
        assert_eq!(YutResult::Geol.distance(), 3);
        assert_eq!(YutResult::Yut.distance(), 4);
        assert_eq!(YutResult::Mo.distance(), 5);
    }

    #[test]
    fn test_backward() {
        assert!(!YutResult::Do.is_backward());
        assert!(YutResult::BackDo.is_backward());
        assert!(!YutResult::Gae.is_backward());
    }

    #[test]
    fn test_extra_turn() {
        assert!(!YutResult::Do.has_extra_turn());
        assert!(!YutResult::BackDo.has_extra_turn());
        assert!(!YutResult::Gae.has_extra_turn());
        assert!(!YutResult::Geol.has_extra_turn());
        assert!(YutResult::Yut.has_extra_turn());
        assert!(YutResult::Mo.has_extra_turn());
    }

    #[test]
    fn test_seeded_throw() {
        let r1 = YutThrower::throw_with_seed(42);
        let r2 = YutThrower::throw_with_seed(42);
        assert_eq!(r1, r2, "Same seed should give same result");
    }

    #[test]
    fn test_yut_probabilities() {
        let mut counts = [0u32; 5];
        let iterations = 160_000;

        for _ in 0..iterations {
            match YutThrower::throw() {
                YutResult::Do => counts[0] += 1,
                YutResult::BackDo => counts[0] += 1, // BackDo counts with Do for probability check
                YutResult::Gae => counts[1] += 1,
                YutResult::Geol => counts[2] += 1,
                YutResult::Yut => counts[3] += 1,
                YutResult::Mo => counts[4] += 1,
            }
        }

        let do_pct = (counts[0] as f64 / iterations as f64) * 100.0;
        let gae_pct = (counts[1] as f64 / iterations as f64) * 100.0;
        let geol_pct = (counts[2] as f64 / iterations as f64) * 100.0;
        let yut_pct = (counts[3] as f64 / iterations as f64) * 100.0;
        let mo_pct = (counts[4] as f64 / iterations as f64) * 100.0;

        assert!((do_pct - 25.0).abs() < 1.5, "Do: {}%", do_pct);
        assert!((gae_pct - 37.5).abs() < 1.5, "Gae: {}%", gae_pct);
        assert!((geol_pct - 25.0).abs() < 1.5, "Geol: {}%", geol_pct);
        assert!((yut_pct - 6.25).abs() < 1.5, "Yut: {}%", yut_pct);
        assert!((mo_pct - 6.25).abs() < 1.5, "Mo: {}%", mo_pct);
    }

    // ── 추가 테스트: 결과가 6가지 중 하나인지 검증 ──

    /// throw()의 결과가 반드시 도/백도/개/걸/윷/모 6가지 중 하나임을 확인한다.
    #[test]
    fn test_throw_result_is_valid_variant() {
        for _ in 0..1000 {
            let r = YutThrower::throw();
            let valid = matches!(
                r,
                YutResult::Do
                    | YutResult::BackDo
                    | YutResult::Gae
                    | YutResult::Geol
                    | YutResult::Yut
                    | YutResult::Mo
            );
            assert!(valid, "Unexpected result variant: {:?}", r);
        }
    }

    /// 윷 결과 시 추가 던지기 플래그가 true 인지 확인한다.
    #[test]
    fn test_yut_has_extra_turn() {
        assert!(YutResult::Yut.has_extra_turn(), "Yut should grant extra turn");
    }

    /// 모 결과 시 추가 던지기 플래그가 true 인지 확인한다.
    #[test]
    fn test_mo_has_extra_turn() {
        assert!(YutResult::Mo.has_extra_turn(), "Mo should grant extra turn");
    }

    /// 도/백도/개/걸은 추가 던지기 플래그가 false 임을 확인한다.
    #[test]
    fn test_non_yut_mo_no_extra_turn() {
        assert!(!YutResult::Do.has_extra_turn());
        assert!(!YutResult::BackDo.has_extra_turn());
        assert!(!YutResult::Gae.has_extra_turn());
        assert!(!YutResult::Geol.has_extra_turn());
    }

    /// BackDo는 is_backward()가 true 이고 나머지는 모두 false 여야 한다.
    #[test]
    fn test_only_backdo_is_backward() {
        for r in [
            YutResult::Do,
            YutResult::Gae,
            YutResult::Geol,
            YutResult::Yut,
            YutResult::Mo,
        ] {
            assert!(!r.is_backward(), "{:?} should not be backward", r);
        }
        assert!(YutResult::BackDo.is_backward());
    }

    /// as_string()이 빈 문자열을 반환하지 않음을 확인한다.
    #[test]
    fn test_as_string_non_empty() {
        for r in [
            YutResult::Do,
            YutResult::BackDo,
            YutResult::Gae,
            YutResult::Geol,
            YutResult::Yut,
            YutResult::Mo,
        ] {
            assert!(!r.as_string().is_empty(), "{:?}.as_string() should not be empty", r);
        }
    }
}
