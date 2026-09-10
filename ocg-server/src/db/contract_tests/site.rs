//! Contract tests for the `DBSite` functions.

use anyhow::Result;

use crate::{
    db::site::DBSite,
    types::{event::EventKind, site::explore::Entity},
};

use super::helpers::{community_id, contract_tests_db, event_id, group_id, site_id, subgroup_id};

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
