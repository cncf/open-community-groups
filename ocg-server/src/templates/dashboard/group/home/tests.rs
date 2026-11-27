use askama::Template;
use axum_messages::{Level, Message};
use uuid::Uuid;

use crate::{
    templates::{PageId, auth::UserMenuState, dashboard::group::sponsors},
    test_util::{element_html_with, opening_tag_with},
    types::{
        dashboard::group::home::UserGroupsByCommunity,
        pagination::NavigationLinks,
        tests::{sample_community_summary, sample_group_minimal, sample_site_settings},
    },
};

use super::{Content, Page};

#[test]
fn test_page_renders_group_shell_overrides_messages_and_modals() {
    // Setup the group dashboard page with a flash message
    let community_id = Uuid::from_u128(1);
    let group_id = Uuid::from_u128(2);
    let page = Page {
        can_manage_badges: false,
        can_manage_check_ins: false,
        can_manage_inbox: false,
        content: Content::Sponsors(sponsors::ListPage {
            can_manage_sponsors: false,
            navigation_links: NavigationLinks::default(),
            sponsors: vec![],
            total: 0,

            offset: None,
        }),
        groups_by_community: vec![UserGroupsByCommunity {
            community: sample_community_summary(community_id),
            groups: vec![sample_group_minimal(group_id)],
        }],
        inbox_open_count: 0,
        is_check_in_fallback: false,
        is_inbox_fallback: false,
        messages: vec![Message {
            level: Level::Success,
            message: "Sponsor saved.".to_string(),
            metadata: None,
        }],
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".into(),
        payments_ready: false,
        selected_community_id: community_id,
        selected_group_id: group_id,
        site_settings: sample_site_settings(),
        user: UserMenuState::default(),
    };

    // Render the page
    let html = page.render().unwrap();

    // Check the group shell overrides menu HTMX attributes and spinner classes
    let menu = opening_tag_with(&html, r#"id="dashboard-menu""#);
    assert!(menu.contains(r##"hx-target="#dashboard-layout""##));
    assert!(menu.contains(r##"hx-select="#dashboard-layout""##));
    assert!(menu.contains(r##"hx-select-oob="#mobile-dashboard-view:outerHTML""##));
    assert!(menu.contains(r#"hx-swap="outerHTML show:window:top""#));

    let spinner = opening_tag_with(&html, r#"id="dashboard-spinner""#);
    assert!(spinner.contains(r#"class="hx-spinner -mt-0.5 relative""#));

    // Check shared scripts, flash messages, and group modals render inside main
    assert!(html.contains("Group Dashboard"));
    assert!(html.contains("/static/js/common/tooltip-panel"));
    assert!(html.contains("/static/js/dashboard/confirm-actions"));
    assert!(html.contains("/static/js/dashboard/menu-drawer"));

    let main = element_html_with(&html, r#"id="dashboard-main-content""#);
    assert!(main.contains("Sponsor saved."));
    assert!(main.contains("<user-info-modal></user-info-modal>"));
    assert!(main.contains("<badge-award-modal></badge-award-modal>"));
}
