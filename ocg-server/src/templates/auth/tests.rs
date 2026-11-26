use crate::{
    config::LoginOptions,
    test_util::{element_html_with, element_text_with, opening_tag_with},
    types::tests::sample_site_settings,
};

use super::*;

#[test]
fn test_forgot_password_page_renders_form_and_sign_in_link() {
    // Render the forgot password page
    let body = ForgotPasswordPage {
        messages: vec![],
        page_id: PageId::ForgotPassword,
        path: "/forgot-password".to_string(),
        site_settings: sample_site_settings(),
        user: UserMenuState::default(),
    }
    .render()
    .unwrap();

    // Check heading, form contract, email input, and sign-in link
    assert!(body.contains("Forgot Password"));
    let form = opening_tag_with(&body, r#"action="/forgot-password""#);
    assert!(form.contains(r#"method="post""#));
    let email = opening_tag_with(&body, r#"id="email""#);
    assert!(email.contains(r#"type="email""#));
    assert!(email.contains(r#"name="email""#));
    assert!(email.contains(r#"autocomplete="email""#));
    assert!(body.contains("Send Reset Link"));
    assert!(body.contains(r#"href="/log-in""#));
}

#[test]
fn test_log_in_page_gates_recovery_controls_on_email_login() {
    let cases = [
        ("email login enabled", true, true),
        ("email login disabled", false, false),
    ];

    for (label, email, expected) in cases {
        // Render the log-in page for the case login option
        let body = LogInPage {
            login: LoginOptions {
                email,
                github: true,
                linuxfoundation: false,
            },
            messages: vec![],
            page_id: PageId::LogIn,
            path: "/log-in".to_string(),
            site_settings: sample_site_settings(),
            user: UserMenuState::default(),

            next_url: Some("%2Fdashboard".to_string()),
        }
        .render()
        .unwrap();

        // Check forgot-password and resend-verification controls follow email login
        assert_eq!(
            body.contains(r#"href="/forgot-password""#),
            expected,
            "forgot password link, {label}"
        );
        assert_eq!(
            body.contains(r#"action="/resend-verification?next_url=%2Fdashboard""#),
            expected,
            "resend verification form, {label}"
        );
        assert_eq!(
            body.contains("Didn't receive your verification email?"),
            expected,
            "resend verification trigger, {label}"
        );
    }
}

#[test]
fn test_reset_password_page_renders_token_action_and_password_confirmation_hooks() {
    // Check Debug formatting redacts the reset token
    let page = ResetPasswordPage {
        messages: vec![],
        page_id: PageId::ResetPassword,
        path: "/reset-password".to_string(),
        site_settings: sample_site_settings(),
        token: "sample-reset-token".to_string(),
        user: UserMenuState::default(),
    };
    let debug = format!("{page:?}");
    assert!(!debug.contains("sample-reset-token"));
    assert!(debug.contains("[redacted]"));

    // Render the reset password page without placing the token in `path`
    let body = page.render().unwrap();

    // Check form action, HTMX history suppression, and client-side password validation hooks
    assert!(body.contains(r#"hx-history="false""#));
    let form = opening_tag_with(&body, r#"id="reset-password-form""#);
    assert!(form.contains(r#"action="/reset-password/sample-reset-token""#));
    assert!(form.contains(r#"method="post""#));
    let password = opening_tag_with(&body, r#"id="password""#);
    assert!(password.contains("data-password"));
    assert!(password.contains(r#"autocomplete="new-password""#));
    let confirmation = opening_tag_with(&body, r#"id="password_confirmation""#);
    assert!(confirmation.contains("data-password-confirmation"));
    assert!(confirmation.contains(r#"autocomplete="new-password""#));
    assert!(body.contains(r#"href="/log-in""#));
}

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

#[test]
fn test_user_menu_section_renders_theme_choice_group() {
    let cases = [
        ("guest", UserMenuState::default()),
        ("member", sample_member()),
    ];

    for (label, user) in cases {
        // Render the menu for the case user
        let body = render_user_menu(user);

        // Check the group is labelled by the visible Theme label
        let group_needle = r#"aria-labelledby="user-menu-theme-label""#;
        let group_tag = opening_tag_with(&body, group_needle);
        assert!(group_tag.contains(r#"role="group""#), "{label}");
        assert_eq!(
            element_text_with(&body, r#"id="user-menu-theme-label""#),
            "Theme",
            "{label}"
        );

        // Check the group holds the light, dark and system choices in order
        let group = element_html_with(&body, group_needle);
        assert_eq!(
            group.matches(r#"role="menuitemradio""#).count(),
            3,
            "{label}"
        );
        let choices = ["light", "dark", "system"].map(|value| {
            let choice_needle = format!(r#"data-ocg-theme-choice="{value}""#);
            let choice_tag = opening_tag_with(group, &choice_needle);
            assert!(choice_tag.starts_with("<button"), "{label}, {value}");
            assert!(choice_tag.contains(r#"type="button""#), "{label}, {value}");
            assert!(
                choice_tag.contains(r#"role="menuitemradio""#),
                "{label}, {value}"
            );
            (group.find(&choice_needle).unwrap(), choice_tag)
        });
        assert!(
            choices[0].0 < choices[1].0 && choices[1].0 < choices[2].0,
            "{label}"
        );

        // Check only System is checked
        assert_eq!(
            group.matches(r#"aria-checked="true""#).count(),
            1,
            "{label}"
        );
        assert!(choices[0].1.contains(r#"aria-checked="false""#), "{label}");
        assert!(choices[1].1.contains(r#"aria-checked="false""#), "{label}");
        assert!(choices[2].1.contains(r#"aria-checked="true""#), "{label}");

        // Check the group precedes the desktop version row
        let group_position = body.find(group_needle).unwrap();
        let desktop_position = body.find(r#"data-viewport-mode="desktop""#).unwrap();
        assert!(group_position < desktop_position, "{label}");
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
