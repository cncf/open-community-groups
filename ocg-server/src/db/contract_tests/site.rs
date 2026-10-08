//! Contract tests for the `DBSite` functions.

use anyhow::Result;
use chrono::{NaiveDate, TimeZone, Utc};

use crate::{
    db::site::DBSite,
    types::{
        event::EventKind,
        search::{SearchEventsFilters, SearchGroupsFilters, ViewMode},
        site::explore::Entity,
    },
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_filters_options_deserializes() -> Result<()> {
    // Setup the contract database and exploration scope
    let db = contract_tests_db()?;

    // Load event filter options through the Rust contract
    let options = db
        .get_filters_options(Some("contract-community".to_string()), Some(Entity::Events))
        .await?;

    // Check community and distance options
    assert_eq!(options.communities.len(), 1);
    assert_eq!(options.communities[0].value, "contract-community");
    assert!(!options.distance.is_empty());

    // Check event category options
    let event_category = options.event_category.expect("event categories should be present");
    assert_eq!(event_category.len(), 1);
    assert_eq!(event_category[0].name, "Conference");

    // Check group options
    let groups = options.groups.expect("groups should be present");
    assert_eq!(groups.len(), 2);
    assert!(groups.iter().any(|group| group.name == "Contract Group"));
    assert!(groups.iter().any(|group| group.name == "Contract Subgroup"));

    // Check region options
    let region = options.region.expect("regions should be present");
    assert_eq!(region.len(), 1);
    assert_eq!(region[0].name, "North America");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_public_event_summary_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load a published and an unpublished event through the Rust contract
    let public_event = db.get_public_event_summary(event_id()).await?;
    let unpublished_event = db.get_public_event_summary(cohost_matrix_event_id()).await?;

    // Check only the published event has a public summary
    let public_event = public_event.expect("published event should have a public summary");
    assert_eq!(public_event.event_id, event_id());
    assert_eq!(public_event.name, "Future Contract Event");
    assert!(unpublished_event.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_public_group_summary_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load an active and an inactive group through the Rust contract
    let public_group = db.get_public_group_summary(group_id()).await?;
    let inactive_group = db.get_public_group_summary(claim_group_id()).await?;

    // Check only the active group has a public summary
    let public_group = public_group.expect("active group should have a public summary");
    assert_eq!(public_group.group_id, group_id());
    assert_eq!(public_group.name, "Contract Group");
    assert!(inactive_group.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_home_stats_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load homepage statistics through the Rust contract
    let stats = db.get_site_home_stats().await?;

    // Check site event and group totals
    assert_eq!(stats.events, 2);
    assert_eq!(stats.events_attendees, 1);
    assert_eq!(stats.groups, 2);
    assert_eq!(stats.groups_members, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_recently_added_groups_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load recently added site groups through the Rust contract
    let groups = db.get_site_recently_added_groups().await?;

    // Check both seeded groups are returned
    assert_eq!(groups.len(), 2);
    assert!(groups.iter().any(|group| group.group_id == group_id()));
    assert!(groups.iter().any(|group| group.group_id == subgroup_id()));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_settings_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load site settings through the Rust contract
    let settings = db.get_site_settings().await?;

    // Check branding, theme, and identity fields
    assert_eq!(
        settings.copyright_notice.as_deref(),
        Some("Copyright Contract Site")
    );
    assert_eq!(settings.site_id, site_id());
    assert_eq!(
        settings.theme.palette.get(&50).map(String::as_str),
        Some("#eff6ff")
    );
    assert_eq!(settings.theme.primary_color, "#0066cc");
    assert_eq!(settings.title, "Contract Site");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_stats_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load site statistics through the Rust contract
    let stats = db.get_site_stats().await?;

    // Check site entity totals
    assert_eq!(stats.attendees.total, 1);
    assert_eq!(stats.events.total, 2);
    assert_eq!(stats.groups.total, 2);
    assert_eq!(stats.members.total, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_site_upcoming_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load upcoming site events through the Rust contract
    let events = db.get_site_upcoming_events(vec![EventKind::Hybrid]).await?;

    // Check the matching event collection
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_communities_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Load communities through the Rust contract
    let communities = db.list_communities().await?;

    // Check the seeded community summary
    assert_eq!(communities.len(), 1);
    assert_eq!(communities[0].community_id, community_id());
    assert_eq!(communities[0].name, "contract-community");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_events_minimal_deserializes() -> Result<()> {
    // Setup the contract database and the map and calendar filters
    let db = contract_tests_db()?;
    let map_filters = SearchEventsFilters {
        community: vec!["contract-community".to_string()],

        date_from: NaiveDate::from_ymd_opt(2000, 1, 1),
        date_to: NaiveDate::from_ymd_opt(2099, 12, 31),
        view_mode: Some(ViewMode::Map),
        ..Default::default()
    };
    let calendar_filters = SearchEventsFilters {
        community: vec!["contract-community".to_string()],

        date_from: NaiveDate::from_ymd_opt(2099, 5, 1),
        date_to: NaiveDate::from_ymd_opt(2099, 5, 31),
        view_mode: Some(ViewMode::Calendar),
        ..Default::default()
    };

    // Search minimal events through the Rust contract, capping the map at one item
    let map_output = db.search_events_minimal(&map_filters, 1).await?;
    let calendar_output = db.search_events_minimal(&calendar_filters, 1000).await?;

    // Check the capped map payload
    assert_eq!(map_output.events.len(), 1);
    let event = &map_output.events[0];
    assert_eq!(event.community_name, "contract-community");
    assert_eq!(event.event_id, past_event_id());
    assert_eq!(event.group_slug, "contract-group");
    assert_eq!(event.name, "Past Contract Event");
    assert_eq!(event.slug, "past-contract-event");
    assert_eq!(
        event.ends_at,
        Some(Utc.with_ymd_and_hms(2000, 5, 20, 19, 0, 0).unwrap())
    );
    assert_eq!(event.group_slug_pretty, None);
    assert_eq!(event.latitude, Some(37.7749));
    assert_eq!(event.longitude, Some(-122.4194));
    assert_eq!(
        event.starts_at,
        Some(Utc.with_ymd_and_hms(2000, 5, 20, 17, 0, 0).unwrap())
    );
    assert_eq!(map_output.total, 2);
    assert!(map_output.bbox.is_some());
    assert!(map_output.truncated);

    // Check the calendar payload
    assert_eq!(calendar_output.events.len(), 1);
    assert_eq!(calendar_output.events[0].event_id, event_id());
    assert_eq!(calendar_output.total, 1);
    assert!(calendar_output.bbox.is_none());
    assert!(!calendar_output.truncated);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_groups_minimal_deserializes() -> Result<()> {
    // Setup the contract database and group filters
    let db = contract_tests_db()?;
    let filters = SearchGroupsFilters {
        community: vec!["contract-community".to_string()],

        view_mode: Some(ViewMode::Map),
        ..Default::default()
    };

    // Search minimal groups through the Rust contract
    let output = db.search_groups_minimal(&filters, 1000).await?;

    // Check the located group payload
    assert_eq!(output.groups.len(), 1);
    let group = &output.groups[0];
    assert!(group.active);
    assert_eq!(group.community_name, "contract-community");
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.name, "Contract Group");
    assert_eq!(group.slug, "contract-group");
    assert_eq!(group.latitude, Some(37.7749));
    assert_eq!(group.longitude, Some(-122.4194));
    assert_eq!(group.slug_pretty, None);
    assert_eq!(output.total, 1);
    assert!(output.bbox.is_some());
    assert!(!output.truncated);

    Ok(())
}
