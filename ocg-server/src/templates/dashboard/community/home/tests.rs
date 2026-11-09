use askama::Template;
use uuid::Uuid;

use crate::{
    templates::{PageId, auth::UserMenuState, dashboard::community::group_categories},
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
