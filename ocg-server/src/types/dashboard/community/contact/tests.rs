use garde::Validate;
use uuid::Uuid;

use crate::{types::group::GroupRole, validation::MAX_CONTACT_FILTER_VALUES};

use super::{CommunityContactFilters, RegionFilterValue};

#[test]
fn test_community_contact_filters_accepts_group_ids_up_to_the_limit() {
    let filters = CommunityContactFilters {
        group_ids: vec![Uuid::nil(); MAX_CONTACT_FILTER_VALUES],
        ..Default::default()
    };

    assert!(filters.validate().is_ok());
}

#[test]
fn test_community_contact_filters_canonical_query_is_empty_without_filters() {
    assert_eq!(CommunityContactFilters::default().to_canonical_query(), "");
}

#[test]
fn test_community_contact_filters_canonical_query_sorts_names_and_keeps_value_order() {
    // Setup filters with values in a non-sorted order
    let category_b = Uuid::parse_str("00000000-0000-0000-0000-00000000000b").unwrap();
    let category_a = Uuid::parse_str("00000000-0000-0000-0000-00000000000a").unwrap();
    let group_b = Uuid::parse_str("00000000-0000-0000-0000-000000000022").unwrap();
    let group_a = Uuid::parse_str("00000000-0000-0000-0000-000000000021").unwrap();
    let region = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
    let filters = CommunityContactFilters {
        group_category_ids: vec![category_b, category_a],
        group_ids: vec![group_b, group_a],
        regions: vec![
            RegionFilterValue::NoRegion,
            RegionFilterValue::Region(region),
        ],
        roles: vec![GroupRole::EventsManager, GroupRole::Admin],
    };

    // Check the query matches the sorted URLSearchParams serialization, with
    // filters ordered by name and values in their submitted order
    assert_eq!(
        filters.to_canonical_query(),
        format!(
            "filters%5Bgroup_category_ids%5D%5B%5D={category_b}\
             &filters%5Bgroup_category_ids%5D%5B%5D={category_a}\
             &filters%5Bgroup_ids%5D%5B%5D={group_b}\
             &filters%5Bgroup_ids%5D%5B%5D={group_a}\
             &filters%5Bregions%5D%5B%5D=none\
             &filters%5Bregions%5D%5B%5D={region}\
             &filters%5Broles%5D%5B%5D=events-manager\
             &filters%5Broles%5D%5B%5D=admin"
        )
    );
}

#[test]
fn test_community_contact_filters_default_missing_lists_to_all() {
    // Deserialize filters that only select a role
    let filters: CommunityContactFilters = serde_json::from_str(r#"{"roles": ["admin"]}"#).unwrap();

    // Check every omitted filter means All
    assert_eq!(filters.group_category_ids, Vec::<Uuid>::new());
    assert_eq!(filters.group_ids, Vec::<Uuid>::new());
    assert_eq!(filters.regions, Vec::<RegionFilterValue>::new());
    assert_eq!(filters.roles, vec![GroupRole::Admin]);
}

#[test]
fn test_community_contact_filters_rejects_oversized_group_ids() {
    // Setup filters selecting one group more than allowed
    let filters = CommunityContactFilters {
        group_ids: vec![Uuid::nil(); MAX_CONTACT_FILTER_VALUES + 1],
        ..Default::default()
    };

    // Check the report names the oversized group filter
    let report = filters.validate().unwrap_err();
    assert!(report.to_string().contains("group_ids"));
}

#[test]
fn test_community_contact_filters_rejects_oversized_lists() {
    let filters = CommunityContactFilters {
        roles: vec![GroupRole::Admin; MAX_CONTACT_FILTER_VALUES + 1],
        ..Default::default()
    };

    assert!(filters.validate().is_err());
}

#[test]
fn test_community_contact_filters_serializes_group_ids_for_the_database() {
    // Setup filters selecting two groups
    let group_a = Uuid::parse_str("00000000-0000-0000-0000-000000000021").unwrap();
    let group_b = Uuid::parse_str("00000000-0000-0000-0000-000000000022").unwrap();
    let filters = CommunityContactFilters {
        group_ids: vec![group_b, group_a],
        ..Default::default()
    };

    // Check the database filters carry the groups in their submitted order
    assert_eq!(
        serde_json::to_value(&filters).unwrap()["group_ids"],
        serde_json::json!([group_b, group_a])
    );
}

#[test]
fn test_region_filter_value_parses_none_and_uuid() {
    // Setup encoded region values
    let region = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();

    // Check both variants round-trip through their string encoding
    let values: Vec<RegionFilterValue> =
        serde_json::from_str(&format!(r#"["none", "{region}"]"#)).unwrap();
    assert_eq!(
        values,
        vec![
            RegionFilterValue::NoRegion,
            RegionFilterValue::Region(region)
        ]
    );
    assert_eq!(
        serde_json::to_string(&values).unwrap(),
        format!(r#"["none","{region}"]"#)
    );
}

#[test]
fn test_region_filter_value_rejects_invalid_values() {
    let result = serde_json::from_str::<RegionFilterValue>(r#""somewhere""#);

    assert!(result.is_err());
}
