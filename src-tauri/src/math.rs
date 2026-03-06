pub fn distance_squared(a: (f64, f64), b: (f64, f64)) -> f64 {
    let dx = a.0 - b.0;
    let dy = a.1 - b.1;
    dx * dx + dy * dy
}

pub fn distance(a: (f64, f64), b: (f64, f64)) -> f64 {
    distance_squared(a, b).sqrt()
}
