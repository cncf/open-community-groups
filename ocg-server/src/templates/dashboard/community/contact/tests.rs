use askama::Template;
use uuid::Uuid;

use crate::types::{
    dashboard::community::contact::{
        CommunityContactFilterOptions, CommunityContactGroupCategoryOption,
        CommunityContactRecipientsSummary, CommunityContactRegionOption,
    },
    group::GroupRoleSummary,
};

use super::{MultiSelectOption, Page};

#[test]
fn test_page_category_options_include_group_counts() {
    // Setup page with one category
    let group_category_id = Uuid::new_v4();
    let mut page = sample_page();
    page.filter_options.group_categories = vec![CommunityContactGroupCategoryOption {
        group_category_id,
        groups_count: 4,
        name: "Platform".to_string(),
    }];

    // Check the option label carries the group count
    assert_eq!(
        page.category_options(),
        vec![MultiSelectOption {
            name: "Platform (4)".to_string(),
            value: group_category_id.to_string(),
        }]
    );
}

#[test]
fn test_page_has_regions_is_false_without_regions() {
    assert!(!sample_page().has_regions());
}

#[test]
fn test_page_recipients_summary_uses_own_request_indicator() {
    // Render the page and isolate the recipients summary container tag
    let body = sample_page().render().unwrap();
    let start = body.find("id=\"community-contact-recipients\"").unwrap();
    let end = start + body[start..].find('>').unwrap();

    // Check preview requests do not inherit the send button spinner
    assert!(body[start..end].contains("hx-indicator=\"this\""));
}

#[test]
fn test_page_region_options_append_no_region() {
    // Setup page with one region
    let region_id = Uuid::new_v4();
    let mut page = sample_page();
    page.filter_options.no_region_groups_count = 2;
    page.filter_options.regions = vec![CommunityContactRegionOption {
        groups_count: 3,
        name: "Europe".to_string(),
        region_id,
    }];

    // Check regions are followed by the no region option
    assert!(page.has_regions());
    assert_eq!(
        page.region_options(),
        vec![
            MultiSelectOption {
                name: "Europe (3)".to_string(),
                value: region_id.to_string(),
            },
            MultiSelectOption {
                name: "No region (2)".to_string(),
                value: "none".to_string(),
            },
        ]
    );
}

#[test]
fn test_page_role_options_use_fixed_order_without_counts() {
    // Setup page with roles in alphabetical order
    let mut page = sample_page();
    page.roles = ["admin", "check-in-manager", "events-manager", "viewer"]
        .into_iter()
        .map(|id| GroupRoleSummary {
            display_name: format!("Role {id}"),
            group_role_id: id.to_string(),
        })
        .collect();

    // Check roles follow the display order and show names only
    let values: Vec<String> = page.role_options().into_iter().map(|option| option.value).collect();
    assert_eq!(
        values,
        vec!["admin", "events-manager", "check-in-manager", "viewer"]
    );
    assert_eq!(page.role_options()[0].name, "Role admin");
}

// Helpers.

/// Returns a contact page without filter options.
fn sample_page() -> Page {
    Page {
        can_send: true,
        default_notification_subject: "Community".to_string(),
        filter_options: CommunityContactFilterOptions::default(),
        filters_key: String::new(),
        roles: vec![],
        summary: CommunityContactRecipientsSummary::default(),
    }
}
