//! Contract tests for the `DBGroup` functions.

use anyhow::Result;

use crate::{db::group::DBGroup, types::event::EventKind};

use super::helpers::{community_id, contract_tests_db, event_id, group_id, past_event_id};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_by_slug_deserializes() -> Result<()> {
    // Setup the contract database and group slug
    let db = contract_tests_db()?;

    // Load the full group by slug through the Rust contract
    let group = db
        .get_group_full_by_slug(community_id(), "contract-group")
        .await?
        .expect("contract group should exist");

    // Check the group and nested collection fields
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.name, "Contract Group");
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);
    assert_eq!(group.subgroups.len(), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_past_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load past group events through the Rust contract
    let events = db
        .get_group_past_events(
            community_id(),
            "contract-group",
            vec![EventKind::Virtual],
            10,
        )
        .await?;

    // Check the matching past event
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, past_event_id());
    assert_eq!(events[0].kind, EventKind::Virtual);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_upcoming_events_deserializes() -> Result<()> {
    // Setup the contract database and event kind filter
    let db = contract_tests_db()?;

    // Load upcoming group events through the Rust contract
    let events = db
        .get_group_upcoming_events(
            community_id(),
            "contract-group",
            vec![EventKind::Hybrid],
            10,
        )
        .await?;

    // Check the matching upcoming event
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_id, event_id());
    assert_eq!(events[0].kind, EventKind::Hybrid);

    Ok(())
}
