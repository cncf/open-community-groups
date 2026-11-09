use askama::Template;

use crate::{
    test_util::element_text_with,
    types::{
        community::{CommunityRole, CommunityRoleSummary},
        dashboard::community::team::CommunityTeamMember,
        pagination::NavigationLinks,
        tests::sample_community_team_member,
    },
};

use super::ListPage;

#[test]
fn test_list_page_escapes_member_identity() {
    // Setup a member whose name contains markup
    let member = CommunityTeamMember {
        name: Some("<b>Ada</b> & co".to_string()),
        ..sample_community_team_member(true)
    };

    // Render the list page with management controls
    let html = sample_page(vec![member], true).render().unwrap();

    // Check the name is escaped everywhere it renders
    assert!(html.contains("&#60;b&#62;Ada&#60;/b&#62; &#38; co"));
    assert!(!html.contains("<b>Ada</b>"));
}

#[test]
fn test_list_page_marks_only_pending_members() {
    // Render the list page with an accepted member only
    let accepted_html = sample_page(vec![sample_community_team_member(true)], true)
        .render()
        .unwrap();

    // Check accepted members have no invitation badge
    assert!(!accepted_html.contains("Invitation sent"));

    // Render the list page with a pending member only
    let pending_html = sample_page(vec![sample_community_team_member(false)], true)
        .render()
        .unwrap();

    // Check pending members have the invitation badge
    assert!(pending_html.contains("Invitation sent"));
}

#[test]
fn test_list_page_read_only_role_badge_shows_display_name() {
    // Setup a groups manager member
    let member = CommunityTeamMember {
        role: Some(CommunityRole::GroupsManager),
        ..sample_community_team_member(true)
    };

    // Render the list page without team management
    let html = sample_page(vec![member], false).render().unwrap();

    // Check the read-only badge shows the role display name
    assert!(!html.contains("data-team-role-select"));
    assert!(element_text_with(&html, r#"id="team-list""#).contains("Groups Manager"));
    assert!(!html.contains(">groups-manager<"));
}

#[test]
fn test_list_page_renders_member_photo_and_name_fallback() {
    // Setup a member with a photo and a name
    let named = CommunityTeamMember {
        name: Some("Ada Lovelace".to_string()),
        photo_url: Some("https://example.test/ada.png".to_string()),
        username: "ada-lovelace".to_string(),
        ..sample_community_team_member(true)
    };

    // Render the list page and check the photo and name render
    let named_html = sample_page(vec![named], false).render().unwrap();
    assert!(named_html.contains(r#"image-url="https://example.test/ada.png""#));
    assert!(element_text_with(&named_html, r#"id="team-list""#).contains("Ada Lovelace"));

    // Setup a member without a photo or a name
    let unnamed = CommunityTeamMember {
        name: None,
        photo_url: None,
        username: "ada-lovelace".to_string(),
        ..sample_community_team_member(true)
    };

    // Render the list page and check the username replaces the missing name
    let unnamed_html = sample_page(vec![unnamed], false).render().unwrap();
    assert!(!unnamed_html.contains("image-url="));
    assert!(element_text_with(&unnamed_html, r#"id="team-list""#).contains("ada-lovelace"));
}

#[test]
fn test_list_page_renders_role_select_only_when_manageable() {
    // Render the list page with and without team management
    let manageable_html = sample_page(vec![sample_community_team_member(true)], true)
        .render()
        .unwrap();
    let read_only_html = sample_page(vec![sample_community_team_member(true)], false)
        .render()
        .unwrap();

    // Check only managers get the role select
    assert!(manageable_html.contains("data-team-role-select"));
    assert!(!read_only_html.contains("data-team-role-select"));
}

#[test]
fn test_role_display_name_uses_role_summary() {
    // Setup a page with the role summaries
    let mut page = sample_page(vec![], false);

    // Check known roles use their display names
    assert_eq!(page.role_display_name(&CommunityRole::Admin), "Admin");
    assert_eq!(
        page.role_display_name(&CommunityRole::GroupsManager),
        "Groups Manager"
    );

    // Check roles missing from the summaries fall back to their identifiers
    page.roles.clear();
    assert_eq!(
        page.role_display_name(&CommunityRole::GroupsManager),
        "groups-manager"
    );
}

// Helpers.

/// Community team list page with the given members and management access.
fn sample_page(members: Vec<CommunityTeamMember>, can_manage_team: bool) -> ListPage {
    let total = members.len();

    ListPage {
        can_manage_team,
        members,
        navigation_links: NavigationLinks::default(),
        roles: vec![
            CommunityRoleSummary {
                community_role_id: "admin".to_string(),
                display_name: "Admin".to_string(),
            },
            CommunityRoleSummary {
                community_role_id: "groups-manager".to_string(),
                display_name: "Groups Manager".to_string(),
            },
            CommunityRoleSummary {
                community_role_id: "viewer".to_string(),
                display_name: "Viewer".to_string(),
            },
        ],
        total,
        total_admins_accepted: 2,

        offset: None,
    }
}
