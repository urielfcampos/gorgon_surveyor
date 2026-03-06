/// Given 3+ (position, distance) readings, return the estimated target point.
/// Uses circle-circle intersection. Returns None if geometry fails or < 3 readings.
pub fn triangulate(readings: &[((f64, f64), f64)]) -> Option<(f64, f64)> {
    if readings.len() < 3 {
        return None;
    }
    let candidates = circle_intersections(readings[0], readings[1])?;
    let ((x3, y3), r3) = readings[2];
    candidates
        .into_iter()
        .min_by(|&(ax, ay), &(bx, by)| {
            let da = (euclidean((ax, ay), (x3, y3)) - r3).abs();
            let db = (euclidean((bx, by), (x3, y3)) - r3).abs();
            da.partial_cmp(&db).unwrap()
        })
}

fn circle_intersections(
    ((x1, y1), r1): ((f64, f64), f64),
    ((x2, y2), r2): ((f64, f64), f64),
) -> Option<Vec<(f64, f64)>> {
    let d = euclidean((x1, y1), (x2, y2));
    if d > r1 + r2 || d < (r1 - r2).abs() || d < 1e-9 {
        return None;
    }
    let a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d);
    let h_sq = r1 * r1 - a * a;
    if h_sq < 0.0 {
        return None;
    }
    let h = h_sq.sqrt();
    let mx = x1 + a * (x2 - x1) / d;
    let my = y1 + a * (y2 - y1) / d;

    if h < 1e-9 {
        return Some(vec![(mx, my)]);
    }

    Some(vec![
        (mx + h * (y2 - y1) / d, my - h * (x2 - x1) / d),
        (mx - h * (y2 - y1) / d, my + h * (x2 - x1) / d),
    ])
}

fn euclidean(a: (f64, f64), b: (f64, f64)) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dist(a: (f64, f64), b: (f64, f64)) -> f64 {
        ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
    }

    #[test]
    fn test_needs_three_readings() {
        assert!(triangulate(&[((0.0, 0.0), 100.0), ((50.0, 0.0), 60.0)]).is_none());
    }

    #[test]
    fn test_triangulates_known_point() {
        let target = (100.0f64, 100.0);
        let readings = vec![
            ((0.0, 0.0), dist(target, (0.0, 0.0))),
            ((200.0, 0.0), dist(target, (200.0, 0.0))),
            ((100.0, 200.0), dist(target, (100.0, 200.0))),
        ];
        let result = triangulate(&readings).unwrap();
        assert!((result.0 - target.0).abs() < 0.01, "x off: {}", result.0);
        assert!((result.1 - target.1).abs() < 0.01, "y off: {}", result.1);
    }

    #[test]
    fn test_triangulates_negative_coords() {
        let target = (-300.0f64, -150.0);
        let readings = vec![
            ((0.0, 0.0), dist(target, (0.0, 0.0))),
            ((-600.0, 0.0), dist(target, (-600.0, 0.0))),
            ((-300.0, -400.0), dist(target, (-300.0, -400.0))),
        ];
        let result = triangulate(&readings).unwrap();
        assert!((result.0 - target.0).abs() < 0.01);
        assert!((result.1 - target.1).abs() < 0.01);
    }
}
