use askama::Template;

use crate::{
    templates::{PageId, auth::UserMenuState},
    test_util::{element_html_with, element_text_with},
    types::tests::{sample_site_settings, sample_site_stats},
};

use super::*;

/// Millisecond timestamp of January 1, 2024 at 00:00 UTC.
const JANUARY_2024_MS: i64 = 1_704_067_200_000;

/// Millisecond timestamp of February 1, 2024 at 00:00 UTC.
const FEBRUARY_2024_MS: i64 = 1_706_745_600_000;

#[test]
fn test_monthly_summary_describes_one_month() {
    let section = section_with(vec![("2024-03".to_string(), 1)], vec![]);
    let view = StatsSectionView {
        kind: StatsSectionKind::Members,
        section: &section,
    };

    assert_eq!(
        view.monthly_summary(),
        "New members per month: 1 new member in March 2024."
    );
}

#[test]
fn test_monthly_summary_describes_range_and_earliest_peak() {
    let section = section_with(
        vec![
            ("2024-01".to_string(), 2),
            ("2024-02".to_string(), 5),
            ("2024-03".to_string(), 5),
            ("2024-04".to_string(), 1),
        ],
        vec![],
    );
    let view = StatsSectionView {
        kind: StatsSectionKind::Events,
        section: &section,
    };

    assert_eq!(
        view.monthly_summary(),
        "New events per month: 13 new events from January 2024 to April 2024. \
         The busiest month was February 2024 with 5."
    );
}

#[test]
fn test_monthly_summary_is_empty_without_data() {
    let section = section_with(vec![], vec![]);
    let view = StatsSectionView {
        kind: StatsSectionKind::Groups,
        section: &section,
    };

    assert_eq!(view.monthly_summary(), "");
}

#[test]
fn test_monthly_summary_keeps_malformed_month_labels() {
    let section = section_with(
        vec![("2024-13".to_string(), 3), ("soon".to_string(), 1_500)],
        vec![],
    );
    let view = StatsSectionView {
        kind: StatsSectionKind::Attendees,
        section: &section,
    };

    assert_eq!(
        view.monthly_summary(),
        "New attendees per month: 1,503 new attendees from 2024-13 to soon. \
         The busiest month was soon with 1,500."
    );
}

#[test]
fn test_page_renders_empty_sections_without_summaries() {
    // Render the page without statistics
    let html = sample_page().render().unwrap();

    // Check every chart shows the empty state without a summary
    let main = element_html_with(&html, r#"id="main-content""#);
    assert_eq!(main.matches("No data available yet").count(), 8);
    assert!(!main.contains("-running-chart"));
    assert!(!main.contains("-monthly-chart"));
    assert!(!main.contains("over time:"));
    assert!(!main.contains("per month:"));
}

#[test]
fn test_page_renders_headings_and_chart_summaries() {
    // Setup the page with statistics in every section but attendees
    let mut page = sample_page();
    for section in [
        &mut page.stats.events,
        &mut page.stats.groups,
        &mut page.stats.members,
    ] {
        *section = section_with(
            vec![("2024-01".to_string(), 1), ("2024-02".to_string(), 1)],
            vec![(JANUARY_2024_MS, 1), (FEBRUARY_2024_MS, 2)],
        );
    }

    // Render the page
    let html = page.render().unwrap();
    let main = element_html_with(&html, r#"id="main-content""#);

    // Check the page and section headings
    assert_eq!(main.matches("<h1").count(), 1);
    assert_eq!(element_text_with(main, "<h1"), "Stats");
    assert_eq!(main.matches("<h2").count(), 4);
    let heading_positions = ["Groups", "Members", "Events", "Attendees"]
        .map(|title| main.find(&format!(">{title}</h2>")).unwrap());
    assert!(heading_positions.is_sorted());

    // Check the charts with data and their text summaries
    for (key, title, singular, plural) in [
        ("groups", "Groups", "group", "groups"),
        ("members", "Members", "member", "members"),
        ("events", "Events", "event", "events"),
    ] {
        assert!(main.contains(&format!(r#"id="{key}-running-chart""#)));
        assert!(main.contains(&format!(r#"id="{key}-monthly-chart""#)));
        assert!(main.contains(&format!(
            "{title} over time: went from 1 {singular} in January 2024 to 2 {plural} in \
             February 2024."
        )));
        assert!(main.contains(&format!(
            "New {plural} per month: 2 new {plural} from January 2024 to February 2024. \
             The busiest month was January 2024 with 1."
        )));
    }

    // Check the empty attendees section shows the empty state without a summary
    assert!(!main.contains("attendees-running-chart"));
    assert!(!main.contains("attendees-monthly-chart"));
    assert_eq!(main.matches("No data available yet").count(), 2);
    assert!(!main.contains("Attendees over time:"));
    assert!(!main.contains("New attendees per month:"));
}

#[test]
fn test_page_title_names_stats() {
    // Render the stats page
    let html = sample_page().render().unwrap();

    // Check the page title names the page and the site
    assert!(html.contains("<title>Stats · Test Site</title>"));
}

#[test]
fn test_running_summary_formats_thousands() {
    let section = section_with(
        vec![],
        vec![(JANUARY_2024_MS, 1_200), (FEBRUARY_2024_MS, 1_234_567)],
    );
    let view = StatsSectionView {
        kind: StatsSectionKind::Attendees,
        section: &section,
    };

    assert_eq!(
        view.running_summary(),
        "Attendees over time: went from 1,200 attendees in January 2024 \
         to 1,234,567 attendees in February 2024."
    );
}

#[test]
fn test_running_summary_is_empty_without_a_chart() {
    for running_total in [vec![], vec![(JANUARY_2024_MS, 3)]] {
        let section = section_with(vec![], running_total);
        let view = StatsSectionView {
            kind: StatsSectionKind::Groups,
            section: &section,
        };

        assert_eq!(view.running_summary(), "");
    }
}

#[test]
fn test_running_summary_keeps_invalid_timestamps() {
    let section = section_with(vec![], vec![(JANUARY_2024_MS, 2), (i64::MAX, 3)]);
    let view = StatsSectionView {
        kind: StatsSectionKind::Events,
        section: &section,
    };

    assert_eq!(
        view.running_summary(),
        format!(
            "Events over time: went from 2 events in January 2024 to 3 events in {}.",
            i64::MAX
        )
    );
}

#[test]
fn test_running_summary_uses_singular_and_plural() {
    let section = section_with(vec![], vec![(JANUARY_2024_MS, 1), (FEBRUARY_2024_MS, 2)]);
    let view = StatsSectionView {
        kind: StatsSectionKind::Groups,
        section: &section,
    };

    assert_eq!(
        view.running_summary(),
        "Groups over time: went from 1 group in January 2024 to 2 groups in February 2024."
    );
}

#[test]
fn test_sections_follow_page_order() {
    // Setup the page with a distinct total per section
    let mut page = sample_page();
    page.stats.attendees.total = 4;
    page.stats.events.total = 3;
    page.stats.groups.total = 1;
    page.stats.members.total = 2;

    // Collect the sections in display order
    let sections = page.sections();

    // Check each section pairs its kind with the matching statistics
    let described = sections
        .iter()
        .map(|view| (view.kind.key(), view.kind.title(), view.section.total))
        .collect::<Vec<_>>();
    assert_eq!(
        described,
        [
            ("groups", "Groups", 1),
            ("members", "Members", 2),
            ("events", "Events", 3),
            ("attendees", "Attendees", 4),
        ]
    );
}

// Helpers.

/// Builds a stats page without statistics.
fn sample_page() -> Page {
    Page {
        page_id: PageId::SiteStats,
        path: "/stats".to_string(),
        site_settings: sample_site_settings(),
        stats: sample_site_stats(),
        user: UserMenuState::default(),
    }
}

/// Builds a stats section with the given chart series.
fn section_with(per_month: Vec<(String, i64)>, running_total: Vec<(i64, i64)>) -> SiteStatsSection {
    let total = per_month.iter().map(|(_, count)| count).sum();
    SiteStatsSection {
        per_month,
        running_total,
        total,
    }
}
