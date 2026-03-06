use regex::Regex;
use std::sync::OnceLock;

#[derive(Debug, PartialEq, Clone)]
pub enum LogEvent {
    /// "The Good Metal Slab is 815m west and 1441m north."
    /// Directional offset from player position to the survey resource.
    /// dx > 0 = east, dx < 0 = west. dy > 0 = north, dy < 0 = south.
    SurveyOffset { dx: f64, dy: f64 },
    /// "The treasure is 1000 meters away"
    /// Raw distance to a motherlode — requires triangulation from 3 positions.
    MotherlodeDistance { meters: f64 },
    SurveyCollected,
}

fn survey_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        // Format: "The <item name> is <N>m <west|east> and <N>m <north|south>."
        Regex::new(r"The .+? is (\d+)m (west|east) and (\d+)m (north|south)\.").unwrap()
    })
}

fn motherlode_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        // Format: "The treasure is 1000 meters away"
        Regex::new(r"The treasure is (\d+(?:\.\d+)?) meters away").unwrap()
    })
}

fn collected_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"You collected the survey reward").unwrap()
    })
}

pub fn parse_line(line: &str) -> Option<LogEvent> {
    // Motherlode must be checked first — its pattern is a subset of the survey pattern
    if let Some(caps) = motherlode_re().captures(line) {
        return Some(LogEvent::MotherlodeDistance {
            meters: caps[1].parse().ok()?,
        });
    }
    if let Some(caps) = survey_re().captures(line) {
        let ew_dist: f64 = caps[1].parse().ok()?;
        let ns_dist: f64 = caps[3].parse().ok()?;
        let dx = if &caps[2] == "east" { ew_dist } else { -ew_dist };
        let dy = if &caps[4] == "north" { ns_dist } else { -ns_dist };
        return Some(LogEvent::SurveyOffset { dx, dy });
    }
    if collected_re().is_match(line) {
        return Some(LogEvent::SurveyCollected);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_survey_west_north() {
        let line = "The Good Metal Slab is 815m west and 1441m north.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::SurveyOffset { dx: -815.0, dy: 1441.0 }));
    }

    #[test]
    fn test_parse_survey_east_south() {
        let line = "The Iron Ore is 200m east and 50m south.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::SurveyOffset { dx: 200.0, dy: -50.0 }));
    }

    #[test]
    fn test_parse_motherlode_distance() {
        let line = "The treasure is 1000 meters away";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::MotherlodeDistance { meters: 1000.0 }));
    }

    #[test]
    fn test_motherlode_not_matched_as_survey() {
        // Motherlode message must not be parsed as a SurveyOffset
        let line = "The treasure is 1000 meters away";
        assert!(!matches!(parse_line(line), Some(LogEvent::SurveyOffset { .. })));
    }

    #[test]
    fn test_parse_survey_collected() {
        let line = "You collected the survey reward.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::SurveyCollected));
    }

    #[test]
    fn test_unrelated_line_returns_none() {
        assert_eq!(parse_line("You say: Hello world!"), None);
        assert_eq!(parse_line(""), None);
    }
}
