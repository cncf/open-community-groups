use super::{Context, ContextCommunity, ContextGroup, ContextPerson, Event, Input};

#[test]
fn test_context_defaults_missing_lists() {
    let input = input_with_context(r#"{"kind_label":"Virtual"}"#);

    // Check the context parsed, so the empty lists come from the serde defaults
    let context = input.context();
    assert_eq!(context.kind_label.as_deref(), Some("Virtual"));
    assert!(context.cohosts.is_empty());
    assert!(context.organizers.is_empty());
    let event = Event::from(input);
    assert!(event.cohosts.is_empty());
    assert!(event.organizers.is_empty());
}

#[test]
fn test_context_keeps_empty_cohosts_list() {
    let input = input_with_context(r#"{"cohosts":[],"kind_label":"Virtual"}"#);

    assert_eq!(input.context().kind_label.as_deref(), Some("Virtual"));
    assert!(Event::from(input).cohosts.is_empty());
}

#[test]
fn test_event_drops_people_without_name() {
    // Setup one named and two unnamed people for every role
    let input = input_with_context(
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
            }"#,
    );

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
fn test_event_has_no_people_or_sponsors_when_people_lack_names() {
    let input = input_with_context(
        r#"{
                "hosts":[{"username":"host"}],
                "organizers":[{"name":" ","username":"organizer"}],
                "speakers":[{"username":"speaker"}]
            }"#,
    );

    assert!(!Event::from(input).has_people_or_sponsors());
}

#[test]
fn test_event_has_people_or_sponsors_with_named_organizer_only() {
    let input =
        input_with_context(r#"{"organizers":[{"name":"Organizer Name","username":"organizer"}]}"#);

    assert!(Event::from(input).has_people_or_sponsors());
}

#[test]
fn test_event_has_people_or_sponsors_with_sponsors_when_people_lack_names() {
    let input = input_with_context(
        r#"{
                "organizers":[{"username":"organizer"}],
                "sponsors":[{"level":"Gold","name":"Sponsor"}]
            }"#,
    );

    assert!(Event::from(input).has_people_or_sponsors());
}

#[test]
fn test_event_keeps_named_session_labels_with_palette_colors() {
    let input = input_with_context(
        r##"{"sessions":[{"name":"Keynote","labels":[
                {"color":"#FFD866","name":" Cloud "},
                {"color":"#000000","name":"Unknown color"},
                {"color":"#FC9867","name":"  "},
                {"name":"Missing color"}
            ]}]}"##,
    );

    let sessions = Event::from(input).sessions;

    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].labels.len(), 1);
    assert_eq!(sessions[0].labels[0].color, "#FFD866");
    assert_eq!(sessions[0].labels[0].name, "Cloud");
}

#[test]
fn test_event_keeps_organizers_in_submitted_order() {
    // Setup organizers in a non-alphabetical order
    let input = input_with_context(
        r#"{"organizers":[
                {"company":"Example","name":"Zoe Organizer","title":"Lead","username":"zoe"},
                {"name":"Ada Organizer","username":"ada"}
            ]}"#,
    );

    // Build the preview
    let organizers = Event::from(input).organizers;

    // Check the order and display data
    assert_eq!(usernames(&organizers), ["zoe", "ada"]);
    assert_eq!(organizers[0].display_name(), "Zoe Organizer");
    assert_eq!(organizers[0].subtitle().as_deref(), Some("Lead, Example"));
}

#[test]
fn test_event_normalizes_cohost_entries() {
    let input = input_with_context(
        r#"{"cohosts":[
                {"name":" Alpha ","status":"Approved","logo_url":"https://example.test/a.png",
                    "logo_dark_url":" https://example.test/a-dark.png "},
                {"name":"Beta","status":"pending","logo_url":" ",
                    "logo_dark_url":"https://example.test/b-dark.png"},
                {"name":"Gamma","status":"rejected"},
                {"name":"  ","status":"pending"}
            ]}"#,
    );

    let cohosts = Event::from(input).cohosts;

    assert_eq!(cohosts.len(), 2);
    assert_eq!(cohosts[0].name_label(), "Alpha");
    assert!(cohosts[0].is_approved());
    assert_eq!(
        cohosts[0].logo_url.as_deref(),
        Some("https://example.test/a.png")
    );
    assert_eq!(
        cohosts[0].logo_dark_url.as_deref(),
        Some("https://example.test/a-dark.png")
    );
    assert_eq!(cohosts[1].name_label(), "Beta");
    assert!(!cohosts[1].is_approved());
    assert!(cohosts[1].logo_url.is_none());
    assert!(cohosts[1].logo_dark_url.is_none());
}

#[test]
fn test_event_lists_missing_fields() {
    let complete = Input {
        category_id: Some("category".to_string()),
        description: Some("Description".to_string()),
        kind_id: Some("virtual".to_string()),
        meeting_join_url: Some("https://meet.example.test".to_string()),
        name: Some("Event".to_string()),
        starts_at: Some("2099-05-10T10:00".to_string()),
        timezone: Some("Europe/Madrid".to_string()),
        ..Input::default()
    };
    let in_person = Input {
        kind_id: Some("in-person".to_string()),
        meeting_join_url: None,
        ..complete.clone()
    };
    let cfs_enabled = Input {
        cfs_enabled: Some("true".to_string()),
        ..complete.clone()
    };
    let cases: [(&str, Input, &[&str]); 10] = [
        ("complete virtual event", complete.clone(), &[]),
        (
            "empty input",
            Input::default(),
            &[
                "Event name",
                "Event type",
                "Category",
                "Timezone",
                "Start date",
                "Description",
            ],
        ),
        (
            "virtual event without meeting",
            Input {
                meeting_join_url: None,
                ..complete.clone()
            },
            &["Online meeting details"],
        ),
        (
            "virtual event with requested meeting",
            Input {
                meeting_join_url: None,
                meeting_requested: Some("true".to_string()),
                ..complete.clone()
            },
            &[],
        ),
        (
            "in-person event without venue",
            in_person.clone(),
            &["Venue details"],
        ),
        (
            "in-person event with venue",
            Input {
                venue_city: Some("Madrid".to_string()),
                ..in_person.clone()
            },
            &[],
        ),
        (
            "hybrid event without venue or meeting",
            Input {
                kind_id: Some("hybrid".to_string()),
                ..in_person
            },
            &["Venue details", "Online meeting details"],
        ),
        (
            "type from the context label",
            Input {
                kind_id: None,
                preview_context: Some(r#"{"kind_label":"Virtual"}"#.to_string()),
                ..complete
            },
            &[],
        ),
        (
            "cfs enabled without its fields",
            cfs_enabled.clone(),
            &["CFS open date", "CFS close date", "CFS description"],
        ),
        (
            "cfs enabled with its fields",
            Input {
                cfs_description: Some("Send talks".to_string()),
                cfs_ends_at: Some("2099-05-01T10:00".to_string()),
                cfs_starts_at: Some("2099-04-01T10:00".to_string()),
                ..cfs_enabled
            },
            &[],
        ),
    ];

    for (case, input, expected) in cases {
        assert_eq!(Event::from(input).missing_fields, expected, "{case}");
    }
}

#[test]
fn test_event_pairs_dark_images_with_the_chosen_level() {
    // Setup cases: (label, event pair, group pair, expected pair), where the
    // community pair is always (c, c-dark)
    let cases = [
        (
            "event pair",
            (Some("e"), Some("e-dark")),
            (Some("g"), Some("g-dark")),
            (Some("e"), Some("e-dark")),
        ),
        (
            "event light without dark while the group has a dark",
            (Some("e"), None),
            (Some("g"), Some("g-dark")),
            (Some("e"), None),
        ),
        (
            "blank event dark is dropped",
            (Some("e"), Some(" ")),
            (Some("g"), Some("g-dark")),
            (Some("e"), None),
        ),
        (
            "event dark without event light falls through to the group pair",
            (None, Some("e-dark")),
            (Some("g"), Some("g-dark")),
            (Some("g"), Some("g-dark")),
        ),
        (
            "blank event light falls through to the group pair",
            (Some(" "), Some("e-dark")),
            (Some("g"), Some("g-dark")),
            (Some("g"), Some("g-dark")),
        ),
        (
            "group light without dark while the community has a dark",
            (None, None),
            (Some("g"), None),
            (Some("g"), None),
        ),
        (
            "orphan group dark falls through to the community pair",
            (None, None),
            (None, Some("g-dark")),
            (Some("c"), Some("c-dark")),
        ),
    ];

    for kind in ["banner", "logo"] {
        for (label, event_pair, group_pair, expected) in cases {
            // Build the preview with the case images for the image kind
            let event = Event::from(branded_input(kind, event_pair, group_pair));

            // Check the image keeps the dark variant of its own level
            let (light, dark) = if kind == "banner" {
                (event.banner_url, event.banner_dark_url)
            } else {
                (event.logo_url, event.logo_dark_url)
            };
            assert_eq!(light, image_url(kind, expected.0), "{kind}: {label}");
            assert_eq!(dark, image_url(kind, expected.1), "{kind}: {label}");
        }
    }
}

#[test]
fn test_event_pairs_no_dark_image_without_branding() {
    // Build the preview with dark images but no light image at any level
    let event = Event::from(Input {
        banner_dark_url: Some("https://example.test/banner-dark.png".to_string()),
        logo_dark_url: Some("https://example.test/logo-dark.png".to_string()),
        ..Input::default()
    });

    // Check the orphan dark images are ignored
    assert_eq!(event.banner_url, None);
    assert_eq!(event.banner_dark_url, None);
    assert_eq!(event.logo_url, None);
    assert_eq!(event.logo_dark_url, None);
}

// Helpers.

/// Returns an input with the given (light, dark) event and group pairs for one
/// image kind, over a community with the (c, c-dark) pair.
fn branded_input(
    kind: &str,
    event_pair: (Option<&str>, Option<&str>),
    group_pair: (Option<&str>, Option<&str>),
) -> Input {
    // Setup the community and group branding context for the image kind
    let url = |value: Option<&str>| image_url(kind, value);
    let (community, group) = if kind == "banner" {
        (
            ContextCommunity {
                banner_dark_url: url(Some("c-dark")),
                banner_url: url(Some("c")),
                ..ContextCommunity::default()
            },
            ContextGroup {
                banner_dark_url: url(group_pair.1),
                banner_url: url(group_pair.0),
                ..ContextGroup::default()
            },
        )
    } else {
        (
            ContextCommunity {
                logo_dark_url: url(Some("c-dark")),
                logo_url: url(Some("c")),
                ..ContextCommunity::default()
            },
            ContextGroup {
                logo_dark_url: url(group_pair.1),
                logo_url: url(group_pair.0),
                ..ContextGroup::default()
            },
        )
    };
    let context = Context {
        community: Some(community),
        group: Some(group),
        ..Context::default()
    };

    // Setup the event images for the image kind
    let mut input = Input {
        preview_context: Some(serde_json::to_string(&context).unwrap()),
        ..Input::default()
    };
    if kind == "banner" {
        input.banner_dark_url = url(event_pair.1);
        input.banner_url = url(event_pair.0);
    } else {
        input.logo_dark_url = url(event_pair.1);
        input.logo_url = url(event_pair.0);
    }
    input
}

/// Returns the image URL for a level token and image kind, keeping blank
/// tokens blank.
fn image_url(kind: &str, token: Option<&str>) -> Option<String> {
    token.map(|token| {
        if token.trim().is_empty() {
            token.to_string()
        } else {
            format!("{token}-{kind}")
        }
    })
}

/// Returns an input carrying only the given preview context JSON.
fn input_with_context(context: &str) -> Input {
    Input {
        preview_context: Some(context.to_string()),
        ..Input::default()
    }
}

/// Returns the usernames of the provided preview people.
fn usernames(people: &[ContextPerson]) -> Vec<&str> {
    people
        .iter()
        .filter_map(|person| person.username.as_deref())
        .collect()
}
