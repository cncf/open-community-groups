use super::{ContextPerson, Event, Input};

#[test]
fn context_defaults_cohosts_when_key_is_missing() {
    let input = Input {
        preview_context: Some(r#"{"kind_label":"Virtual"}"#.to_string()),
        ..Input::default()
    };

    assert!(input.context().cohosts.is_empty());
    assert!(Event::from(input).cohosts.is_empty());
}

#[test]
fn context_defaults_organizers_when_key_is_missing() {
    let input = Input {
        preview_context: Some(r#"{"kind_label":"Virtual"}"#.to_string()),
        ..Input::default()
    };

    assert!(input.context().organizers.is_empty());
    assert!(Event::from(input).organizers.is_empty());
}

#[test]
fn context_keeps_empty_cohosts_list() {
    let input = Input {
        preview_context: Some(r#"{"cohosts":[]}"#.to_string()),
        ..Input::default()
    };

    assert!(Event::from(input).cohosts.is_empty());
}

#[test]
fn event_drops_people_without_name() {
    // Setup one named and two unnamed people for every role
    let input = Input {
        preview_context: Some(
            r#"{
                "hosts":[
                    {"name":"Host Name","username":"host"},
                    {"username":"host-no-name"},
                    {"name":"  ","username":"host-blank-name"}
                ],
                "organizers":[
                    {"name":"Organizer Name","username":"organizer"},
                    {"username":"organizer-no-name"},
                    {"name":"  ","username":"organizer-blank-name"}
                ],
                "sessions":[{"name":"Keynote","speakers":[
                    {"name":"Session Speaker Name","username":"session-speaker"},
                    {"username":"session-speaker-no-name"},
                    {"name":"  ","username":"session-speaker-blank-name"}
                ]}],
                "speakers":[
                    {"name":"Speaker Name","username":"speaker"},
                    {"username":"speaker-no-name"},
                    {"name":"  ","username":"speaker-blank-name"}
                ]
            }"#
            .to_string(),
        ),
        ..Input::default()
    };

    // Build the preview
    let event = Event::from(input);

    // Check only the named people remain
    assert_eq!(usernames(&event.hosts), ["host"]);
    assert_eq!(usernames(&event.organizers), ["organizer"]);
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(usernames(&event.sessions[0].speakers), ["session-speaker"]);
    assert_eq!(usernames(&event.speakers), ["speaker"]);
}

#[test]
fn event_has_no_people_or_sponsors_when_people_lack_names() {
    let input = Input {
        preview_context: Some(
            r#"{
                "hosts":[{"username":"host"}],
                "organizers":[{"name":" ","username":"organizer"}],
                "speakers":[{"username":"speaker"}]
            }"#
            .to_string(),
        ),
        ..Input::default()
    };

    assert!(!Event::from(input).has_people_or_sponsors());
}

#[test]
fn event_has_people_or_sponsors_with_named_organizer_only() {
    let input = Input {
        preview_context: Some(
            r#"{"organizers":[{"name":"Organizer Name","username":"organizer"}]}"#.to_string(),
        ),
        ..Input::default()
    };

    assert!(Event::from(input).has_people_or_sponsors());
}

#[test]
fn event_has_people_or_sponsors_with_sponsors_when_people_lack_names() {
    let input = Input {
        preview_context: Some(
            r#"{
                "organizers":[{"username":"organizer"}],
                "sponsors":[{"level":"Gold","name":"Sponsor"}]
            }"#
            .to_string(),
        ),
        ..Input::default()
    };

    assert!(Event::from(input).has_people_or_sponsors());
}

#[test]
fn event_keeps_named_session_labels_with_palette_colors() {
    let input = Input {
        preview_context: Some(
            r##"{"sessions":[{"name":"Keynote","labels":[
                {"color":"#FFD866","name":" Cloud "},
                {"color":"#000000","name":"Unknown color"},
                {"color":"#FC9867","name":"  "},
                {"name":"Missing color"}
            ]}]}"##
                .to_string(),
        ),
        ..Input::default()
    };

    let sessions = Event::from(input).sessions;

    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].labels.len(), 1);
    assert_eq!(sessions[0].labels[0].color, "#FFD866");
    assert_eq!(sessions[0].labels[0].name, "Cloud");
}

#[test]
fn event_keeps_organizers_in_submitted_order() {
    // Setup organizers in a non-alphabetical order
    let input = Input {
        preview_context: Some(
            r#"{"organizers":[
                {"company":"Example","name":"Zoe Organizer","title":"Lead","username":"zoe"},
                {"name":"Ada Organizer","username":"ada"}
            ]}"#
            .to_string(),
        ),
        ..Input::default()
    };

    // Build the preview
    let organizers = Event::from(input).organizers;

    // Check the order and display data
    assert_eq!(usernames(&organizers), ["zoe", "ada"]);
    assert_eq!(organizers[0].display_name(), "Zoe Organizer");
    assert_eq!(organizers[0].subtitle().as_deref(), Some("Lead, Example"));
}

#[test]
fn event_normalizes_cohost_entries() {
    let input = Input {
        preview_context: Some(
            r#"{"cohosts":[
                {"name":" Alpha ","status":"Approved","logo_url":"https://example.test/a.png"},
                {"name":"Beta","status":"pending","logo_url":" "},
                {"name":"Gamma","status":"rejected"},
                {"name":"  ","status":"pending"}
            ]}"#
            .to_string(),
        ),
        ..Input::default()
    };

    let cohosts = Event::from(input).cohosts;

    assert_eq!(cohosts.len(), 2);
    assert_eq!(cohosts[0].name_label(), "Alpha");
    assert!(cohosts[0].is_approved());
    assert_eq!(
        cohosts[0].logo_url.as_deref(),
        Some("https://example.test/a.png")
    );
    assert_eq!(cohosts[1].name_label(), "Beta");
    assert!(!cohosts[1].is_approved());
    assert!(cohosts[1].logo_url.is_none());
}

// Helpers.

/// Returns the usernames of the provided preview people.
fn usernames(people: &[ContextPerson]) -> Vec<&str> {
    people
        .iter()
        .filter_map(|person| person.username.as_deref())
        .collect()
}
