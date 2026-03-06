use crate::path_optimizer::optimize_path;
use crate::triangulator::triangulate;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU32, Ordering};

static NEXT_ID: AtomicU32 = AtomicU32::new(1);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Survey {
    pub id: u32,
    pub zone: String,
    pub x: f64,
    pub y: f64,
    pub collected: bool,
    pub route_order: Option<usize>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct AppState {
    pub surveys: Vec<Survey>,
    pub motherlode_readings: Vec<((f64, f64), f64)>,
    pub motherlode_location: Option<(f64, f64)>,
    pub player_position: Option<(f64, f64)>,
}

impl AppState {
    pub fn add_survey(&mut self, zone: String, x: f64, y: f64) {
        self.surveys.push(Survey {
            id: NEXT_ID.fetch_add(1, Ordering::SeqCst),
            zone,
            x,
            y,
            collected: false,
            route_order: None,
        });
        self.recalculate_route();
    }

    pub fn mark_collected(&mut self, id: u32) {
        if let Some(s) = self.surveys.iter_mut().find(|s| s.id == id) {
            s.collected = true;
        }
        self.recalculate_route();
    }

    pub fn add_motherlode_reading(&mut self, pos: (f64, f64), distance: f64) {
        self.motherlode_readings.push((pos, distance));
        if self.motherlode_readings.len() >= 3 {
            self.motherlode_location = triangulate(&self.motherlode_readings);
        }
    }

    /// Set motherlode location directly from a directional offset reading.
    pub fn set_motherlode_location(&mut self, x: f64, y: f64) {
        self.motherlode_location = Some((x, y));
    }

    pub fn clear_surveys(&mut self) {
        self.surveys.clear();
    }

    pub fn clear_motherlode(&mut self) {
        self.motherlode_readings.clear();
        self.motherlode_location = None;
    }

    fn recalculate_route(&mut self) {
        // Collect indices and coordinates without holding references into self.surveys
        let active: Vec<(usize, f64, f64)> = self.surveys
            .iter()
            .enumerate()
            .filter(|(_, s)| !s.collected)
            .map(|(i, s)| (i, s.x, s.y))
            .collect();

        let points: Vec<(f64, f64)> = active.iter().map(|(_, x, y)| (*x, *y)).collect();
        let start = self.player_position.unwrap_or((0.0, 0.0));
        let order = optimize_path(start, &points);

        for s in self.surveys.iter_mut() {
            s.route_order = None;
        }
        for (route_pos, &point_idx) in order.iter().enumerate() {
            let survey_idx = active[point_idx].0;
            self.surveys[survey_idx].route_order = Some(route_pos + 1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_survey_appends() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 100.0, 200.0);
        assert_eq!(s.surveys.len(), 1);
        assert_eq!(s.surveys[0].x, 100.0);
        assert!(!s.surveys[0].collected);
    }

    #[test]
    fn test_mark_collected() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 100.0, 200.0);
        let id = s.surveys[0].id;
        s.mark_collected(id);
        assert!(s.surveys[0].collected);
    }

    #[test]
    fn test_route_order_assigned_after_add() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 10.0, 0.0);
        s.add_survey("Serbule".into(), 5.0, 0.0);
        assert_eq!(s.surveys[1].route_order, Some(1));
        assert_eq!(s.surveys[0].route_order, Some(2));
    }

    #[test]
    fn test_add_motherlode_reading() {
        let mut s = AppState::default();
        s.add_motherlode_reading((0.0, 0.0), 100.0);
        assert_eq!(s.motherlode_readings.len(), 1);
        assert!(s.motherlode_location.is_none());
    }

    #[test]
    fn test_clear_surveys() {
        let mut s = AppState::default();
        s.add_survey("Serbule".into(), 1.0, 2.0);
        s.clear_surveys();
        assert!(s.surveys.is_empty());
    }
}
