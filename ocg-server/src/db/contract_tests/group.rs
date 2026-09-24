//! Contract tests for the `DBGroup` functions.

use anyhow::Result;

use crate::{
    db::{PgExecutor, group::DBGroup},
    types::event::EventKind,
};

use super::helpers::*;

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
async fn db_contracts_get_group_upcoming_events_includes_cross_community_cohosted_events()
-> Result<()> {
    // Setup a rolled-back unit of work with the co-hosted event public
    let uow = contract_unit_of_work().await?;
    uow.execute(
        "update community set active = true where community_id = $1::uuid",
        &[&cohost_community_id()],
    )
    .await?;
    uow.execute(
        "
        update event
        set
            published = true,
            published_at = current_timestamp,
            test_event = false
        where event_id = $1::uuid
        ",
        &[&cohost_matrix_event_id()],
    )
    .await?;

    // Load the co-host group's upcoming events through the Rust contract
    let events = uow
        .get_group_upcoming_events(
            cohost_community_id(),
            "contract-cross-community-cohost",
            vec![EventKind::Hybrid],
            10,
        )
        .await?;

    // Check the owner's event is listed under the owner's community with credit
    assert_eq!(events.len(), 1);
    let event = &events[0];
    assert_eq!(event.event_id, cohost_matrix_event_id());
    assert_eq!(event.community_name, "contract-community");
    assert!(event.is_cohosted_by(cohost_cross_community_group_id()));
    let cohost = event
        .cohosts
        .iter()
        .find(|cohost| cohost.group_id == cohost_cross_community_group_id())
        .expect("cross-community co-host to be credited");
    assert_eq!(cohost.community_name, "contract-cross-community");
    assert_eq!(cohost.public_slug(), "cross-community-cohost");
    assert!(
        event
            .cohosts
            .iter()
            .all(|cohost| cohost.group_id != cohost_pending_group_id())
    );

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
    assert!(events[0].cohosts.is_empty());

    Ok(())
}
