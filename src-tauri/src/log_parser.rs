use regex::Regex;
use std::sync::OnceLock;

#[derive(Debug, PartialEq, Clone)]
pub enum LogEvent {
    SurveyPlaced { zone: String, x: f64, y: f64 },
    MotherlodeDistance { meters: f64 },
    SurveyCollected,
}

fn survey_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        // Format: "Survey marked at <Zone> (<x>, <y>)"
        // TODO: Validate against real game logs and update if needed
        Regex::new(r"Survey marked at (.+?) \((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)").unwrap()
    })
}

fn motherlode_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"The motherlode is (\d+(?:\.\d+)?) meters away").unwrap()
    })
}

fn collected_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"You collected the survey reward").unwrap()
    })
}

pub fn parse_line(line: &str) -> Option<LogEvent> {
    if let Some(caps) = survey_re().captures(line) {
        return Some(LogEvent::SurveyPlaced {
            zone: caps[1].to_string(),
            x: caps[2].parse().ok()?,
            y: caps[3].parse().ok()?,
        });
    }
    if let Some(caps) = motherlode_re().captures(line) {
        return Some(LogEvent::MotherlodeDistance {
            meters: caps[1].parse().ok()?,
        });
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
    fn test_parse_survey_placement() {
        let line = "Survey marked at Serbule (123, 456)";
        let event = parse_line(line);
        assert_eq!(
            event,
            Some(LogEvent::SurveyPlaced { zone: "Serbule".into(), x: 123.0, y: 456.0 })
        );
    }

    #[test]
    fn test_parse_motherlode_distance() {
        let line = "The motherlode is 347 meters away.";
        let event = parse_line(line);
        assert_eq!(event, Some(LogEvent::MotherlodeDistance { meters: 347.0 }));
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

    #[test]
    fn test_negative_coordinates() {
        let line = "Survey marked at Eltibule (-500, -123)";
        let event = parse_line(line);
        assert_eq!(
            event,
            Some(LogEvent::SurveyPlaced { zone: "Eltibule".into(), x: -500.0, y: -123.0 })
        );
    }
}
