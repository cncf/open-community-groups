use crate::{
    test_util::{element_html_with, element_text_with, opening_tag_with},
    types::tests::sample_site_settings,
};

use super::*;

#[test]
fn test_events_results_section_empty_states_are_not_alerts() {
    let cases = [
        ("list", ViewMode::List, None),
        ("map", ViewMode::Map, Some(empty_events_widget_data())),
        (
            "calendar",
            ViewMode::Calendar,
            Some(empty_events_widget_data()),
        ),
    ];

    for (label, view_mode, widget_data) in cases {
        // Render the empty results section in the case view mode
        let body = EventsResultsSection {
            events: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
            view_mode: Some(view_mode),
            widget_data,
        }
        .render()
        .unwrap();

        // Check the empty state renders as static text, not an alert
        assert!(body.contains("No events found"), "{label}");
        assert!(!body.contains(r#"role="alert""#), "{label}");
    }
}

#[test]
fn test_events_section_date_inputs_have_labels() {
    let body = render_default_events_section();

    // Check each date input sits in a label that names it
    for (name, label) in [("date_from", "From"), ("date_to", "To")] {
        let input = body
            .find(&format!(r#"name="{name}""#))
            .unwrap_or_else(|| panic!("{name} input"));
        let label_start = body[..input]
            .rfind("<label")
            .unwrap_or_else(|| panic!("{name} label"));
        let label_html = element_html_with(&body[label_start..], "<label");
        assert!(label_html.contains(&format!(r#"name="{name}""#)), "{name}");
        assert_eq!(element_text_with(label_html, "<label"), label, "{name}");
    }
}

#[test]
fn test_events_section_groups_type_and_date_filters() {
    let body = render_default_events_section();

    // Read the legend of every fieldset, in the sheet form and then the sidebar form
    let legends: Vec<String> = body
        .match_indices("<fieldset")
        .map(|(start, _)| {
            let fieldset = element_html_with(&body[start..], "<fieldset");
            element_text_with(fieldset, "<legend")
        })
        .collect();

    // Check each form groups its Type and Date filters under a named fieldset
    assert_eq!(legends, ["Type", "Date", "Type", "Date"]);
}

#[test]
fn test_events_section_marks_community_dependent_filters() {
    // Render the events section with a viewer location so Distance renders
    let body = EventsSection {
        filters: SearchEventsFilters {
            latitude: Some(40.71),
            longitude: Some(-74.01),
            ..Default::default()
        },
        filters_options: community_scoped_filters_options(),
        results_section: EventsResultsSection {
            events: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
            view_mode: None,
            widget_data: None,
        },
    }
    .render()
    .unwrap();

    // Check only the community-scoped filters carry the marker
    let cases = [
        (r#"title="Community" name="community""#, false),
        (r#"title="Distance" name="distance""#, false),
        (r#"title="Event category" name="event_category""#, true),
        (r#"title="Group" name="group""#, true),
        (r#"title="Group category" name="group_category""#, true),
        (r#"title="Region" name="region""#, true),
    ];
    for (needle, dependent) in cases {
        let tag = opening_tag_with(&body, needle);
        assert_eq!(
            tag.contains("data-community-dependent"),
            dependent,
            "{needle}"
        );
    }
}

#[test]
fn test_events_section_search_tips_is_a_named_modal_dialog() {
    let body = render_default_events_section();

    // Check the search tips modal is a modal dialog named by its title
    let dialog = opening_tag_with(&body, r#"id="search-tips""#);
    assert!(dialog.contains(r#"role="dialog""#));
    assert!(dialog.contains(r#"aria-modal="true""#));
    assert!(dialog.contains(r#"aria-labelledby="search-tips-title""#));

    // Check the title names the dialog
    assert_eq!(
        element_text_with(&body, r#"id="search-tips-title""#),
        "Search tips"
    );
}

#[test]
fn test_events_section_view_mode_is_a_named_radiogroup() {
    let body = render_default_events_section();

    // Check the view switch is a radio group named View
    let group = opening_tag_with(&body, r#"role="radiogroup""#);
    assert!(group.contains(r#"aria-label="View""#));

    // Check its options are view mode radios
    for id in ["list", "calendar"] {
        let radio = opening_tag_with(&body, &format!(r#"id="{id}""#));
        assert!(radio.contains(r#"type="radio""#), "{id}");
        assert!(radio.contains(r#"name="view_mode""#), "{id}");
    }
}

#[test]
fn test_groups_results_section_empty_states_are_not_alerts() {
    let cases = [
        ("list", ViewMode::List, None),
        ("map", ViewMode::Map, Some(SearchGroupsOutput::default())),
    ];

    for (label, view_mode, widget_data) in cases {
        // Render the empty results section in the case view mode
        let body = GroupsResultsSection {
            groups: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
            view_mode: Some(view_mode),
            widget_data,
        }
        .render()
        .unwrap();

        // Check the empty state renders as static text, not an alert
        assert!(
            body.contains("We can&#39;t seem to find any groups"),
            "{label}"
        );
        assert!(!body.contains(r#"role="alert""#), "{label}");
    }
}

#[test]
fn test_groups_section_marks_community_dependent_filters() {
    // Render the groups section with a viewer location so Distance renders
    let body = GroupsSection {
        filters: SearchGroupsFilters {
            latitude: Some(40.71),
            longitude: Some(-74.01),
            ..Default::default()
        },
        filters_options: community_scoped_filters_options(),
        results_section: GroupsResultsSection {
            groups: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
            view_mode: None,
            widget_data: None,
        },
    }
    .render()
    .unwrap();

    // Check only the community-scoped filters carry the marker
    let cases = [
        (r#"title="Community" name="community""#, false),
        (r#"title="Distance" name="distance""#, false),
        (r#"title="Group category" name="group_category""#, true),
        (r#"title="Region" name="region""#, true),
    ];
    for (needle, dependent) in cases {
        let tag = opening_tag_with(&body, needle);
        assert_eq!(
            tag.contains("data-community-dependent"),
            dependent,
            "{needle}"
        );
    }
}

#[test]
fn test_page_title_names_explore() {
    // Render the explore page shell without sections
    let body = Page {
        entity: Entity::Events,
        events_section: None,
        groups_section: None,
        page_id: PageId::SiteExplore,
        path: "/explore".into(),
        site_settings: sample_site_settings(),
        user: UserMenuState::default(),
    }
    .render()
    .unwrap();

    // Check the page title names the page and the site
    assert!(body.contains("<title>Explore · Test Site</title>"));
}

// Helpers.

/// Returns filter options with one entry for every filter the explore page renders.
fn community_scoped_filters_options() -> FiltersOptions {
    let option = |name: &str, value: &str| {
        vec![FilterOption {
            name: name.to_string(),
            value: value.to_string(),
        }]
    };

    FiltersOptions {
        communities: option("Community", "community"),
        distance: option("50 km", "50000"),

        event_category: Some(option("Meetup", "meetup")),
        group_category: Some(option("Tech", "tech")),
        groups: Some(option("Group", "group")),
        region: Some(option("Europe", "europe")),
    }
}

/// Returns empty map and calendar widget data for events.
fn empty_events_widget_data() -> SearchEventsOutput<EventMinimal> {
    SearchEventsOutput {
        events: vec![],
        total: 0,

        bbox: None,
        truncated: false,
    }
}

/// Renders the events section with default filters and no results.
fn render_default_events_section() -> String {
    EventsSection {
        filters: SearchEventsFilters::default(),
        filters_options: FiltersOptions::default(),
        results_section: EventsResultsSection {
            events: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
            view_mode: None,
            widget_data: None,
        },
    }
    .render()
    .unwrap()
}
