use askama::Template;
use percent_encoding::percent_decode_str;
use uuid::Uuid;

use crate::{
    test_util::normalize_whitespace,
    types::{
        dashboard::community::contact::{
            CommunityContactFilterOptions, CommunityContactFilters,
            CommunityContactGroupCategoryOption, CommunityContactGroupLabel,
            CommunityContactRecipientGroup, CommunityContactRecipientsSummary,
            CommunityContactRegionOption, RegionFilterValue,
        },
        group::{GroupRole, GroupRoleSummary},
    },
    validation::MAX_CONTACT_FILTER_VALUES,
};

use super::{MultiSelectOption, Page, RecipientsSummary};

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
fn test_page_group_options_keep_database_order() {
    // Setup page with groups in the order the database returned them
    let rust_group_id = Uuid::new_v4();
    let go_group_id = Uuid::new_v4();
    let mut page = sample_page();
    page.filter_options.groups = vec![
        CommunityContactGroupLabel {
            group_id: rust_group_id,
            label: "Rust · Platform".to_string(),
        },
        CommunityContactGroupLabel {
            group_id: go_group_id,
            label: "Go · Platform · Europe".to_string(),
        },
    ];

    // Check options keep the order and use the labels as names
    assert_eq!(
        page.group_options(),
        vec![
            MultiSelectOption {
                name: "Rust · Platform".to_string(),
                value: rust_group_id.to_string(),
            },
            MultiSelectOption {
                name: "Go · Platform · Europe".to_string(),
                value: go_group_id.to_string(),
            },
        ]
    );
}

#[test]
fn test_page_groups_filter_adds_subgroups_hint_to_legend() {
    // Setup page of a community with subgroups
    let mut page = sample_page_with_group();
    page.filter_options.has_subgroups = true;

    // Render the page and isolate the groups filter tag
    let body = page.render().unwrap();
    let tag = start_tag(&body, "community-contact-groups");

    // Check the legend explains that selected groups don't bring their subgroups
    assert!(tag.contains(&format!(
        r#"legend="Select up to {MAX_CONTACT_FILTER_VALUES} groups. Selecting a group doesn't include its subgroups; select them too.""#
    )));
}

#[test]
fn test_page_groups_filter_caps_selection_to_filter_limit() {
    // Render the page of a community without subgroups and isolate the groups filter tag
    let body = sample_page_with_group().render().unwrap();
    let tag = start_tag(&body, "community-contact-groups");

    // Check the picker caps the selection and its legend states the limit only
    assert!(tag.contains(&format!(r#"max-selected="{MAX_CONTACT_FILTER_VALUES}""#)));
    assert!(tag.contains(&format!(
        r#"legend="Select up to {MAX_CONTACT_FILTER_VALUES} groups.""#
    )));
    assert!(!tag.contains(" disabled"));
}

#[test]
fn test_page_groups_filter_closes_after_each_pick() {
    // Render the page of a community with one group and isolate the groups filter tag
    let body = sample_page_with_group().render().unwrap();
    let tag = start_tag(&body, "community-contact-groups");

    // Check the filter is labelled, keeps the label order and closes after a pick
    assert!(body.contains(
        r#"<label id="community-contact-groups-label" class="form-label">Groups</label>"#
    ));
    assert!(tag.contains(r#"labelledby="community-contact-groups-label""#));
    assert!(tag.contains(r#"name="filters[group_ids]""#));
    assert!(tag.contains("keep-order"));
    assert!(tag.contains("close-on-select"));
    assert!(tag.contains(r#"placeholder="All groups""#));
    assert!(tag.contains("Go · Platform · Europe"));
}

#[test]
fn test_page_groups_filter_is_disabled_without_groups() {
    // Render the page of a community without active groups and isolate the groups filter tag
    let body = sample_page().render().unwrap();
    let tag = start_tag(&body, "community-contact-groups");

    // Check the picker is disabled and explains why, without options or a cap
    assert!(tag.contains(r#"labelledby="community-contact-groups-label""#));
    assert!(tag.contains(r#"name="filters[group_ids]""#));
    assert!(tag.contains(" disabled "));
    assert!(tag.contains(r#"legend="This community has no active groups.""#));
    assert!(!tag.contains("max-selected="));
    assert!(!tag.contains("options="));
}

#[test]
fn test_page_recipients_summary_posts_filters_only() {
    // Collect the field names of every filter from the canonical query
    let filters = CommunityContactFilters {
        group_category_ids: vec![Uuid::new_v4()],
        group_ids: vec![Uuid::new_v4()],
        regions: vec![RegionFilterValue::NoRegion],
        roles: vec![GroupRole::Admin],
    };
    let mut filter_names: Vec<String> = filters
        .to_canonical_query()
        .split('&')
        .map(|pair| {
            let (name, _) = pair.split_once('=').unwrap();
            percent_decode_str(name).decode_utf8().unwrap().to_string()
        })
        .collect();
    filter_names.dedup();

    // Render the page and isolate the recipients summary container tag
    let body = sample_page().render().unwrap();
    let tag = start_tag(&body, "community-contact-recipients");

    // Check previews post every filter field only, leaving the message out
    assert!(tag.contains(r#"hx-post="/dashboard/community/contact/recipients""#));
    assert!(tag.contains(&format!(r#"hx-params="{}""#, filter_names.join(","))));
    assert!(tag.contains(
        r#"hx-params="filters[group_category_ids][],filters[group_ids][],filters[regions][],filters[roles][]""#
    ));
    assert!(tag.contains(r##"hx-include="#community-contact-filters""##));
    assert!(!tag.contains("hx-get"));
}

#[test]
fn test_page_recipients_summary_uses_own_request_indicator() {
    // Render the page and isolate the recipients summary container tag
    let body = sample_page().render().unwrap();
    let tag = start_tag(&body, "community-contact-recipients");

    // Check preview requests do not inherit the send button spinner
    assert!(tag.contains("hx-indicator=\"this\""));
}

#[test]
fn test_page_region_options_append_no_region() {
    // Setup page with one region
    let region_id = Uuid::new_v4();
    let mut page = sample_page();
    assert!(!page.has_regions());
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

#[test]
fn test_recipients_summary_lists_one_unmatched_group_without_people() {
    // Setup a summary without matching people and one unmatched group
    let summary = CommunityContactRecipientsSummary {
        unmatched_groups: vec![sample_group_label("Rust · Platform")],
        ..Default::default()
    };

    // Render the recipients summary
    let body = normalize_whitespace(&sample_recipients(summary).render().unwrap());

    // Check the empty summary is followed by the singular notice, which skips
    // the email clause as nobody receives it
    assert!(body.contains("No group team members match these filters."));
    assert!(body.contains(
        r#"<p id="community-contact-unmatched-groups-title"> 1 selected group has no matching team members: </p>"#
    ));
    assert!(!body.contains("won't receive the email"));
    assert!(body.contains(r#"<li class="break-words">Rust · Platform</li>"#));
}

#[test]
fn test_recipients_summary_lists_unmatched_groups_with_people() {
    // Setup a summary with matching people and two unmatched groups
    let mut summary = sample_summary_with_people();
    summary.unmatched_groups = vec![
        sample_group_label("Go · Platform · Europe"),
        sample_group_label("Rust · Platform"),
    ];

    // Render the recipients summary
    let body = normalize_whitespace(&sample_recipients(summary).render().unwrap());

    // Check the plural notice follows the collapsed matching groups list
    let notice = &body[body.find("</details>").unwrap()..];
    assert!(notice.contains(
        r#"<p id="community-contact-unmatched-groups-title"> 2 selected groups have no matching team members and won't receive the email: </p>"#
    ));
    assert!(notice.contains(r#"aria-labelledby="community-contact-unmatched-groups-title""#));
    assert!(notice.contains(
        r#"<li class="break-words">Go · Platform · Europe</li> <li class="break-words">Rust · Platform</li>"#
    ));
}

#[test]
fn test_recipients_summary_omits_unmatched_notice_when_every_group_matches() {
    // Render a summary whose selected groups all contribute seats
    let body = sample_recipients(sample_summary_with_people()).render().unwrap();

    // Check only the matching groups are rendered
    assert!(body.contains("Show groups"));
    assert!(!body.contains("community-contact-unmatched-groups-title"));
}

// Helpers.

/// Returns a group label for the unmatched groups notice.
fn sample_group_label(label: &str) -> CommunityContactGroupLabel {
    CommunityContactGroupLabel {
        group_id: Uuid::new_v4(),
        label: label.to_string(),
    }
}

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

/// Returns a contact page of a community with one active group.
fn sample_page_with_group() -> Page {
    let mut page = sample_page();
    page.filter_options.groups = vec![CommunityContactGroupLabel {
        group_id: Uuid::new_v4(),
        label: "Go · Platform · Europe".to_string(),
    }];
    page
}

/// Returns the recipients summary partial for the given summary.
fn sample_recipients(summary: CommunityContactRecipientsSummary) -> RecipientsSummary {
    RecipientsSummary {
        filters_key: String::new(),
        summary,
    }
}

/// Returns a summary with one matching group and no unmatched groups.
fn sample_summary_with_people() -> CommunityContactRecipientsSummary {
    CommunityContactRecipientsSummary {
        groups: vec![CommunityContactRecipientGroup {
            group_category_name: "Platform".to_string(),
            group_id: Uuid::new_v4(),
            name: "Kubernetes".to_string(),
            seats_count: 2,

            region_name: None,
        }],
        groups_count: 1,
        people_count: 2,
        seats_count: 2,
        unmatched_groups: vec![],
    }
}

/// Returns the start tag of the element with the given identifier.
fn start_tag<'a>(body: &'a str, id: &str) -> &'a str {
    let start = body.find(&format!(r#"id="{id}""#)).unwrap();
    let end = start + body[start..].find('>').unwrap();
    &body[start..end]
}
