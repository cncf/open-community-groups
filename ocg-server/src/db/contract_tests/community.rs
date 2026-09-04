//! Contract tests for the `DBCommunity` functions.

use anyhow::Result;

use crate::{db::community::DBCommunity, types::event::EventKind};

use super::helpers::{community_id, contract_tests_db, event_id, group_id, subgroup_id};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_recently_added_groups_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load recently added groups through the Rust contract
    let groups = db.get_community_recently_added_groups(community_id()).await?;

    // Check both seeded groups are returned
    assert_eq!(groups.len(), 2);
    assert!(groups.iter().any(|group| group.group_id == group_id()));
    assert!(groups.iter().any(|group| group.group_id == subgroup_id()));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_site_stats_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load public community statistics through the Rust contract
    let stats = db.get_community_site_stats(community_id()).await?;

    // Check event and group totals deserialize as expected
    assert_eq!(stats.events, 2);
    assert_eq!(stats.events_attendees, 1);
    assert_eq!(stats.groups, 2);
    assert_eq!(stats.groups_members, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_upcoming_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load upcoming community events through the Rust contract
    let events = db
        .get_community_upcoming_events(community_id(), vec![EventKind::Hybrid])
        .await?;

    // Check the matching event collection
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());

    Ok(())
}
