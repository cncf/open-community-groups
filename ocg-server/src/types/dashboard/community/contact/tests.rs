use garde::Validate;
use uuid::Uuid;

use crate::{types::group::GroupRole, validation::MAX_CONTACT_FILTER_VALUES};

use super::{CommunityContactFilters, RegionFilterValue};

#[test]
fn test_community_contact_filters_canonical_query_is_empty_without_filters() {
    assert_eq!(CommunityContactFilters::default().to_canonical_query(), "");
}

#[test]
fn test_community_contact_filters_canonical_query_keeps_order_and_encoding() {
    // Setup filters with values in a non-sorted order
    let category_b = Uuid::parse_str("00000000-0000-0000-0000-00000000000b").unwrap();
    let category_a = Uuid::parse_str("00000000-0000-0000-0000-00000000000a").unwrap();
    let region = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
    let filters = CommunityContactFilters {
        group_category_ids: vec![category_b, category_a],
        regions: vec![
            RegionFilterValue::NoRegion,
            RegionFilterValue::Region(region),
        ],
        roles: vec![GroupRole::EventsManager, GroupRole::Admin],
    };

    // Check the query matches the URLSearchParams serialization
    assert_eq!(
        filters.to_canonical_query(),
        format!(
            "filters%5Bgroup_category_ids%5D%5B%5D={category_b}\
             &filters%5Bgroup_category_ids%5D%5B%5D={category_a}\
             &filters%5Bregions%5D%5B%5D=none\
             &filters%5Bregions%5D%5B%5D={region}\
             &filters%5Broles%5D%5B%5D=events-manager\
             &filters%5Broles%5D%5B%5D=admin"
        )
    );
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
