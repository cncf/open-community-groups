use askama::Template;
use uuid::Uuid;

use crate::{test_util::normalize_whitespace, types::tests::sample_group_full};

use super::UpdatePage;

#[test]
fn test_update_page_renders_group_id_in_details() {
    // Setup page for one group
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let page = UpdatePage {
        can_manage_groups: true,
        categories: vec![],
        group: sample_group_full(community_id, group_id),
        has_child_links: false,
        parent_options: vec![],
        regions: vec![],
    };

    // Render the page
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the details title shows the group id
    assert!(html.contains("(ID: "));
    assert!(html.contains(&format!(">{group_id}</span>)")));
}
