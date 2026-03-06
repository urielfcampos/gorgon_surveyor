/// Returns the indices of `points` in the order a nearest-neighbor TSP heuristic visits them,
/// starting from `start`.
pub fn optimize_path(start: (f64, f64), points: &[(f64, f64)]) -> Vec<usize> {
    if points.is_empty() {
        return vec![];
    }

    let mut unvisited: Vec<usize> = (0..points.len()).collect();
    let mut order = Vec::with_capacity(points.len());
    let mut current = start;

    while !unvisited.is_empty() {
        let nearest_pos = unvisited
            .iter()
            .enumerate()
            .min_by(|(_, &a), (_, &b)| {
                euclidean(current, points[a])
                    .partial_cmp(&euclidean(current, points[b]))
                    .unwrap()
            })
            .map(|(i, _)| i)
            .unwrap();

        let point_idx = unvisited.remove(nearest_pos);
        current = points[point_idx];
        order.push(point_idx);
    }

    order
}

fn euclidean(a: (f64, f64), b: (f64, f64)) -> f64 {
    let dx = a.0 - b.0;
    let dy = a.1 - b.1;
    (dx * dx + dy * dy).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_input() {
        assert_eq!(optimize_path((0.0, 0.0), &[]), Vec::<usize>::new());
    }

    #[test]
    fn test_single_point() {
        assert_eq!(optimize_path((0.0, 0.0), &[(5.0, 5.0)]), vec![0]);
    }

    #[test]
    fn test_nearest_neighbor_ordering() {
        // Start at origin.
        // Points: A(1,0), B(10,0), C(2,0)
        // nearest to origin → A(idx 0), nearest to A → C(idx 2), nearest to C → B(idx 1)
        let points = vec![(1.0f64, 0.0), (10.0, 0.0), (2.0, 0.0)];
        let result = optimize_path((0.0, 0.0), &points);
        assert_eq!(result, vec![0, 2, 1]);
    }

    #[test]
    fn test_start_position_affects_order() {
        // Start far right — B(10,0) should be first
        let points = vec![(1.0f64, 0.0), (10.0, 0.0), (2.0, 0.0)];
        let result = optimize_path((12.0, 0.0), &points);
        assert_eq!(result[0], 1); // B is closest to start (12,0)
    }
}
