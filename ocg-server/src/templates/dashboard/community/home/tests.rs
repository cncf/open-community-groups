use askama::Template;
use axum_messages::{Level, Message};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::UserMenuState,
        dashboard::community::{group_categories, regions},
    },
    test_util::opening_tag_with,
    types::tests::{sample_community_summary, sample_site_settings},
};

use super::{Content, Page};

#[test]
fn test_page_listens_for_dashboard_table_refresh() {
    // Setup the page with the group categories tab selected
    let community_id = Uuid::from_u128(1);
    let page = Page {
        communities: vec![sample_community_summary(community_id)],
        community_active: true,
        content: Content::GroupCategories(group_categories::ListPage {
            can_manage_taxonomy: false,
            categories: vec![],
        }),
        messages: vec![],
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".into(),
        selected_community_id: community_id,
        site_settings: sample_site_settings(),
        user: UserMenuState::default(),
    };

    // Render the page
    let html = page.render().unwrap();

    // Check the content region reloads the selected tab on the refresh event
    let content = opening_tag_with(&html, r#"id="dashboard-content""#);
    assert!(content.contains(r#"hx-trigger="refresh-community-dashboard-table"#));
    assert!(content.contains(r#"hx-get="/dashboard/community/group-categories""#));
}

#[test]
fn test_page_renders_shared_dashboard_shell_and_messages() {
    // Setup the page with a flash message
    let community_id = Uuid::from_u128(2);
    let page = Page {
        communities: vec![sample_community_summary(community_id)],
        community_active: true,
        content: Content::Regions(regions::ListPage {
            can_manage_taxonomy: false,
            regions: vec![],
        }),
        messages: vec![Message {
            level: Level::Success,
            message: "Region updated.".to_string(),
            metadata: None,
        }],
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".into(),
        selected_community_id: community_id,
        site_settings: sample_site_settings(),
        user: UserMenuState::default(),
    };

    // Render the page
    let html = page.render().unwrap();

    // Check the base shell renders the title, shared scripts, menu wrapper, and flash message
    assert!(html.contains("Community Dashboard"));
    assert!(opening_tag_with(&html, r#"id="dashboard-menu""#).contains(r#"hx-target="body""#));
    assert!(html.contains("/static/js/common/tooltip-panel"));
    assert!(html.contains("/static/js/dashboard/confirm-actions"));
    assert!(html.contains("/static/js/dashboard/menu-drawer"));
    assert!(html.contains("Region updated."));
}
