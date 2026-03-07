/// TODO: Validate these bounds in-game by checking coordinates at zone edges.
const DEFAULT_BOUNDS: (f64, f64, f64, f64) = (-2048.0, -2048.0, 2048.0, 2048.0);

/// Zone bounding boxes as (name, (min_x, min_y, max_x, max_y)) in game world units.
pub const ZONES: &[(&str, (f64, f64, f64, f64))] = &[
    ("Serbule",         DEFAULT_BOUNDS),
    ("Eltibule",        DEFAULT_BOUNDS),
    ("Kur Mountains",   DEFAULT_BOUNDS),
    ("Povus",           DEFAULT_BOUNDS),
    ("Ilmari",          DEFAULT_BOUNDS),
    ("Gazluk",          DEFAULT_BOUNDS),
];

pub fn bounds_for(zone: &str) -> (f64, f64, f64, f64) {
    ZONES.iter()
        .find(|(name, _)| *name == zone)
        .map(|(_, b)| *b)
        .unwrap_or(DEFAULT_BOUNDS)
}
