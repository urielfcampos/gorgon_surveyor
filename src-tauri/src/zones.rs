/// Zone bounding boxes as (name, (min_x, min_y, max_x, max_y)) in game world units.
/// TODO: Validate these bounds in-game by checking coordinates at zone edges.
pub const ZONES: &[(&str, (f64, f64, f64, f64))] = &[
    ("Serbule",         (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Eltibule",        (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Kur Mountains",   (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Povus",           (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Ilmari",          (-2048.0, -2048.0, 2048.0, 2048.0)),
    ("Gazluk",          (-2048.0, -2048.0, 2048.0, 2048.0)),
];

pub fn bounds_for(zone: &str) -> (f64, f64, f64, f64) {
    ZONES.iter()
        .find(|(name, _)| *name == zone)
        .map(|(_, b)| *b)
        .unwrap_or((-2048.0, -2048.0, 2048.0, 2048.0))
}
