use crate::test_util::opening_tag_with;

use super::*;

#[test]
fn test_user_menu_section_gates_dashboard_rows_by_team() {
    let cases = [
        ("member of the team", Some(true), true),
        ("not a member of the team", Some(false), false),
        ("team membership unknown", None, false),
    ];

    for (label, belongs_to_team, shown) in cases {
        // Render the menu with the case community team membership
        let body = render_user_menu(UserMenuState {
            belongs_to_community_team: belongs_to_team,
            ..sample_member()
        });

        // Check the community dashboard row follows the membership
        assert_eq!(
            body.contains(r#"href="/dashboard/community""#),
            shown,
            "community dashboard row, {label}"
        );

        // Render the menu with the case group team membership
        let body = render_user_menu(UserMenuState {
            belongs_to_any_group_team: belongs_to_team,
            ..sample_member()
        });

        // Check the group dashboard row and its shortcut follow the membership
        assert_eq!(
            body.contains(r#"id="user-menu-group-dashboard-link""#),
            shown,
            "group dashboard link, {label}"
        );
        assert_eq!(
            body.contains(r#"href="/dashboard/group?tab=check-in""#),
            shown,
            "group check-in shortcut, {label}"
        );
    }
}

#[test]
fn test_user_menu_section_keeps_docs_row_unboosted() {
    let cases = [
        ("guest", UserMenuState::default()),
        ("member", sample_member()),
    ];

    for (label, user) in cases {
        // Render the menu for the case user
        let body = render_user_menu(user);

        // Check the Docs row opts out of HTMX boosting
        let docs_link = opening_tag_with(&body, r#"href="/docs""#);
        assert!(docs_link.contains(r#"hx-boost="false""#), "{label}");
    }
}

#[test]
fn test_user_menu_section_links_openprofile_only_for_linux_foundation() {
    let cases = [
        ("linuxfoundation", Some("linuxfoundation"), true),
        ("github", Some("github"), false),
        ("no provider", None, false),
    ];

    for (label, auth_provider, shown) in cases {
        // Render the menu with the case authentication provider
        let body = render_user_menu(UserMenuState {
            auth_provider: auth_provider.map(str::to_string),
            ..sample_member()
        });

        // Check the openprofile.dev link follows the provider
        assert_eq!(
            body.contains(r#"href="https://openprofile.dev""#),
            shown,
            "{label}"
        );
    }
}

#[test]
fn test_user_menu_section_marks_guest_trigger() {
    // Render the menu for a guest
    let body = render_user_menu(UserMenuState::default());

    // Check the trigger marks the guest state without profile completion
    let trigger = opening_tag_with(&body, r#"id="user-dropdown-button""#);
    assert!(trigger.contains(r#"data-logged-in="false""#));
    assert!(!trigger.contains("data-profile-complete"));
}

#[test]
fn test_user_menu_section_marks_member_profile_completion() {
    let cases = [
        ("complete profile", true, r#"data-profile-complete="true""#),
        (
            "incomplete profile",
            false,
            r#"data-profile-complete="false""#,
        ),
    ];

    for (label, profile_complete, expected_marker) in cases {
        // Render the menu with the case profile completion
        let body = render_user_menu(UserMenuState {
            profile_complete,
            ..sample_member()
        });

        // Check the trigger marks the member and their profile completion
        let trigger = opening_tag_with(&body, r#"id="user-dropdown-button""#);
        assert!(trigger.contains(r#"data-logged-in="true""#), "{label}");
        assert!(trigger.contains(expected_marker), "{label}");
    }
}

#[test]
fn test_user_menu_section_renders_named_menu_trigger() {
    let cases = [
        ("guest", UserMenuState::default()),
        ("member", sample_member()),
    ];

    for (label, user) in cases {
        // Render the menu for the case user
        let logged_in = user.logged_in;
        let body = render_user_menu(user);

        // Check the trigger is a collapsed menu button for the dropdown
        let trigger = opening_tag_with(&body, r#"id="user-dropdown-button""#);
        assert!(trigger.contains(r#"type="button""#), "{label}");
        assert!(trigger.contains(r#"aria-haspopup="menu""#), "{label}");
        assert!(
            trigger.contains(r#"aria-controls="user-dropdown""#),
            "{label}"
        );
        assert!(trigger.contains(r#"aria-expanded="false""#), "{label}");

        // Check the trigger is named User menu for the case user
        if logged_in {
            assert!(body.contains(r#"<span class="sr-only">User menu</span>"#));
            assert!(!trigger.contains("aria-label"));
        } else {
            assert!(trigger.contains(r#"aria-label="User menu""#));
        }
    }
}

// Helpers.

/// Renders the user menu section for the given user.
fn render_user_menu(user: UserMenuState) -> String {
    UserMenuSection { user }.render().unwrap()
}

/// Returns a logged-in member with a complete profile and no teams.
fn sample_member() -> UserMenuState {
    UserMenuState {
        logged_in: true,
        profile_complete: true,

        name: Some("Jane Doe".to_string()),
        username: Some("jane".to_string()),
        ..Default::default()
    }
}
