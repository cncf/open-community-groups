use std::collections::BTreeSet;

use uuid::Uuid;

use super::{
    EVENT_FORM_TABS, EventFormMode, EventFormSection, EventFormTabFlags, EventFormTabGroup,
    EventFormTabGroupKind, EventFormTabLazyLoad, form_tab_groups,
};

#[test]
fn test_event_form_section_renders_content_identifiers() {
    assert_eq!(EventFormSection::Contributors.to_string(), "contributors");
    assert_eq!(EventFormSection::DateVenue.to_string(), "date-venue");
    assert_eq!(
        EventFormSection::InvitationRequests.to_string(),
        "invitation-requests"
    );
    assert_eq!(EventFormSection::Payments.to_string(), "payments");
}

#[test]
fn test_event_form_tab_group_kind_labels() {
    assert_eq!(EventFormTabGroupKind::Event.label(), "Event");
    assert_eq!(EventFormTabGroupKind::FollowUp.label(), "Follow-up");
    assert_eq!(EventFormTabGroupKind::People.label(), "People");
    assert_eq!(EventFormTabGroupKind::Program.label(), "Program");
    assert_eq!(EventFormTabGroupKind::Registration.label(), "Registration");
}

#[test]
fn test_event_form_tabs_keep_groups_contiguous() {
    // Collect the group order from the catalog
    let mut seen_groups = Vec::new();
    for tab in EVENT_FORM_TABS {
        if seen_groups.last() != Some(&tab.group) {
            seen_groups.push(tab.group);
        }
    }

    // Check every group appears once, in lifecycle order
    assert_eq!(
        seen_groups,
        vec![
            EventFormTabGroupKind::Event,
            EventFormTabGroupKind::Registration,
            EventFormTabGroupKind::Program,
            EventFormTabGroupKind::People,
            EventFormTabGroupKind::FollowUp,
        ]
    );
}

#[test]
fn test_event_form_tabs_use_unique_sections() {
    let sections: BTreeSet<String> =
        EVENT_FORM_TABS.iter().map(|tab| tab.section.to_string()).collect();

    assert_eq!(sections.len(), EVENT_FORM_TABS.len());
}

#[test]
fn test_form_tab_groups_add_page_shows_authoring_subset() {
    // Build the add page groups
    let groups = form_tab_groups(&EventFormMode::Add, all_flags());

    // Check the authoring tabs keep the catalog order and empty groups are dropped
    assert_eq!(
        group_summaries(&groups),
        vec![
            "Event: details, date-venue, cohosts, contributors",
            "Registration: payments, questions",
            "Program: labels, cfs, sessions",
        ]
    );

    // Check add page tabs never lazy-load content
    assert!(
        groups
            .iter()
            .flat_map(|group| &group.tabs)
            .all(|tab| tab.lazy_load.is_none())
    );
}

#[test]
fn test_form_tab_groups_hides_flagged_update_tabs() {
    // Build the update page groups with every flag disabled
    let groups = form_tab_groups(
        &update_mode(Uuid::nil(), true),
        EventFormTabFlags::default(),
    );

    // Check flagged tabs are hidden and their groups keep the remaining tabs
    assert_eq!(
        group_summaries(&groups),
        vec![
            "Event: details, date-venue, cohosts, contributors",
            "Registration: payments, questions",
            "Program: labels, cfs, submissions, sessions",
            "People: attendees",
            "Follow-up: analytics",
        ]
    );
}

#[test]
fn test_form_tab_groups_lazy_loads_pending_invitation_requests_when_approval_required() {
    // Build the update page groups for an event requiring approval
    let event_id = Uuid::parse_str("00000000-0000-0000-0000-000000000002").unwrap();
    let groups = form_tab_groups(&update_mode(event_id, true), all_flags());

    // Check the requests tab opens with the default status filter
    assert_eq!(
        lazy_load(&groups, "invitation-requests"),
        Some(EventFormTabLazyLoad {
            indicator: "#invitation-requests-loading".to_string(),
            target: "#invitation-requests-content".to_string(),
            url: "/dashboard/group/events/00000000-0000-0000-0000-000000000002/invitation-requests"
                .to_string(),
        })
    );
}

#[test]
fn test_form_tab_groups_lazy_loads_review_sections() {
    // Build the update page groups for an event without approval
    let event_id = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
    let groups = form_tab_groups(&update_mode(event_id, false), all_flags());

    // Check each review section loads its content once from the event routes
    assert_eq!(
        lazy_load(&groups, "submissions"),
        Some(EventFormTabLazyLoad {
            indicator: "#submissions-loading".to_string(),
            target: "#submissions-content".to_string(),
            url: "/dashboard/group/events/00000000-0000-0000-0000-000000000001/submissions"
                .to_string(),
        })
    );
    assert_eq!(
        lazy_load(&groups, "attendees"),
        Some(EventFormTabLazyLoad {
            indicator: "#attendees-loading".to_string(),
            target: "#attendees-content".to_string(),
            url: "/dashboard/group/events/00000000-0000-0000-0000-000000000001/attendees"
                .to_string(),
        })
    );
    assert_eq!(
        lazy_load(&groups, "invitation-requests"),
        Some(EventFormTabLazyLoad {
            indicator: "#invitation-requests-loading".to_string(),
            target: "#invitation-requests-content".to_string(),
            url: "/dashboard/group/events/00000000-0000-0000-0000-000000000001/invitation-requests?status=all".to_string(),
        })
    );
    assert_eq!(
        lazy_load(&groups, "surveys"),
        Some(EventFormTabLazyLoad {
            indicator: "#surveys-loading".to_string(),
            target: "#surveys-content".to_string(),
            url: "/dashboard/group/events/00000000-0000-0000-0000-000000000001/surveys".to_string(),
        })
    );
    assert_eq!(
        lazy_load(&groups, "waitlist"),
        Some(EventFormTabLazyLoad {
            indicator: "#waitlist-loading".to_string(),
            target: "#waitlist-content".to_string(),
            url: "/dashboard/group/events/00000000-0000-0000-0000-000000000001/waitlist"
                .to_string(),
        })
    );

    // Check sections rendered with the page or by page scripts have no attributes
    for section in ["analytics", "details", "payments"] {
        assert_eq!(lazy_load(&groups, section), None, "section {section}");
    }
}

#[test]
fn test_form_tab_groups_marks_only_first_tab_active() {
    // Build the update page groups
    let groups = form_tab_groups(&update_mode(Uuid::nil(), true), all_flags());

    // Check only the details tab starts active
    let active_sections: Vec<String> = groups
        .iter()
        .flat_map(|group| &group.tabs)
        .filter(|tab| tab.active)
        .map(|tab| tab.section.to_string())
        .collect();
    assert_eq!(active_sections, vec!["details"]);
}

#[test]
fn test_form_tab_groups_update_page_shows_every_visible_tab() {
    // Build the update page groups with every flag enabled
    let groups = form_tab_groups(&update_mode(Uuid::nil(), true), all_flags());

    // Check every tab is grouped by lifecycle in catalog order
    assert_eq!(
        group_summaries(&groups),
        vec![
            "Event: details, date-venue, cohosts, contributors",
            "Registration: payments, questions",
            "Program: labels, cfs, submissions, sessions",
            "People: attendees, invitation-requests, waitlist",
            "Follow-up: surveys, analytics",
        ]
    );

    // Check the tab labels and icons shown to organizers
    let tabs: Vec<(&str, &str)> = groups
        .iter()
        .flat_map(|group| &group.tabs)
        .map(|tab| (tab.label, tab.icon))
        .collect();
    assert_eq!(
        tabs,
        vec![
            ("Details", "event"),
            ("Date & Venue", "calendar"),
            ("Co-hosts", "cohosts"),
            ("Contributors", "user-plus"),
            ("Tickets", "ticket"),
            ("Questions", "list-check"),
            ("Labels", "tag"),
            ("CFS", "megaphone"),
            ("Submissions", "submission"),
            ("Sessions", "presentation"),
            ("Attendees", "attendees"),
            ("Requests", "request-invitation"),
            ("Waitlist", "waitlist"),
            ("Surveys", "survey"),
            ("Analytics", "charts"),
        ]
    );
}

// Helpers.

/// Returns flags that show every conditionally visible tab.
fn all_flags() -> EventFormTabFlags {
    EventFormTabFlags {
        invitation_requests: true,
        surveys: true,
        waitlist: true,
    }
}

/// Returns each group as its heading followed by its tab sections.
fn group_summaries(groups: &[EventFormTabGroup]) -> Vec<String> {
    groups
        .iter()
        .map(|group| {
            let sections: Vec<String> =
                group.tabs.iter().map(|tab| tab.section.to_string()).collect();
            format!("{}: {}", group.label, sections.join(", "))
        })
        .collect()
}

/// Returns the lazy-load request of the tab for the given section.
fn lazy_load(groups: &[EventFormTabGroup], section: &str) -> Option<EventFormTabLazyLoad> {
    groups
        .iter()
        .flat_map(|group| &group.tabs)
        .find(|tab| tab.section.to_string() == section)
        .and_then(|tab| tab.lazy_load.clone())
}

/// Returns the update page mode for the given event.
fn update_mode(event_id: Uuid, attendee_approval_required: bool) -> EventFormMode {
    EventFormMode::Update {
        attendee_approval_required,
        event_id,
    }
}
