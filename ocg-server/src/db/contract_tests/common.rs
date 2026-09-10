//! Contract tests for the `DBCommon` and cross-cutting error functions.

use anyhow::Result;
use chrono::DateTime;
use tokio_postgres::error::{DbError, SqlState};

use crate::{
    db::common::DBCommon,
    types::{
        event::EventKind,
        payments::EventTicketType,
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

use super::helpers::{
    assert_contract_paid_ticket_type, assert_contract_ticket_type, community_id, contract_tests_db,
    contract_tests_pool, event_id, external_event_id, group_id, paid_event_id, paid_ticket_type_id,
    subgroup_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_full_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load the full community through the Rust contract
    let community = db.get_community_full(community_id()).await?;

    // Check required and optional community fields
    assert!(community.active);
    assert_eq!(community.community_id, community_id());
    assert_eq!(
        community.created_at,
        DateTime::from_timestamp(1_704_067_200, 0).unwrap()
    );
    assert_eq!(community.display_name, "Contract Community");
    assert_eq!(community.name, "contract-community");
    assert_eq!(
        community.ad_banner_link_url.as_deref(),
        Some("https://example.com/community-ad")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_community_summary_deserializes() -> Result<()> {
    // Setup the contract database and community fixture
    let db = contract_tests_db()?;

    // Load the community summary through the Rust contract
    let community = db.get_community_summary(community_id()).await?;

    // Check identity and advertising fields
    assert_eq!(
        community.ad_banner_url.as_deref(),
        Some("https://example.com/community-ad-banner.png")
    );
    assert_eq!(community.community_id, community_id());
    assert_eq!(community.name, "contract-community");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_full_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load the full event through the Rust contract
    let event = db.get_event_full(community_id(), group_id(), event_id()).await?;
    let external_event = db
        .get_event_full(community_id(), group_id(), external_event_id())
        .await?;

    // Check community and event details
    assert_eq!(event.attendee_count, 2);
    assert_eq!(
        event.community.ad_banner_link_url.as_deref(),
        Some("https://example.com/community-ad")
    );
    assert_eq!(
        event.community.ad_banner_url.as_deref(),
        Some("https://example.com/community-ad-banner.png")
    );
    assert_eq!(event.event_id, event_id());
    assert!(event.has_registration_questions);
    assert_eq!(
        event.luma_url.as_deref(),
        Some("https://luma.com/contract-event")
    );
    assert_eq!(event.registration_questions.len(), 1);
    assert_eq!(event.registration_questions[0].prompt, "Meal preference");
    assert!(event.registration_questions_locked);
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);
    assert_contract_ticket_type(
        &event.ticket_types.as_ref().expect("event should have tickets")[0],
    );

    // Check host and organizer provider profiles
    assert_eq!(
        event.hosts[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );
    assert_eq!(event.organizers.len(), 1);
    assert_eq!(
        event.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    // Check external-payment event fields deserialize completely
    assert_eq!(external_event.event_id, external_event_id());
    assert_eq!(
        external_event.external_payment_instructions.as_deref(),
        Some("Wire transfer using the purchase reference.")
    );
    assert_eq!(
        external_event.external_payment_url.as_deref(),
        Some("https://pay.example.test/contract-external")
    );
    assert_eq!(external_event.external_payment_window_hours, Some(72));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load the event summary through the Rust contract
    let event = db.get_event_summary(community_id(), group_id(), event_id()).await?;

    // Check required and computed event fields
    assert_eq!(event.event_id, event_id());
    assert!(!event.has_external_payment);
    assert!(event.has_registration_questions);
    assert!(
        event
            .ticket_types
            .as_ref()
            .is_some_and(|ticket_types| !ticket_types.is_empty())
    );
    assert_contract_ticket_type(
        &event.ticket_types.as_ref().expect("event should have tickets")[0],
    );
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.waitlist_count, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_external_payment_deserializes() -> Result<()> {
    // Setup the contract database and external-payments event
    let db = contract_tests_db()?;

    // Load the external-payments event summary through the Rust contract
    let event = db
        .get_event_summary(community_id(), group_id(), external_event_id())
        .await?;

    // Check the summary marks off-platform payment collection
    assert_eq!(event.event_id, external_event_id());
    assert!(event.has_external_payment);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_full_deserializes() -> Result<()> {
    // Setup the contract database and group fixtures
    let db = contract_tests_db()?;

    // Load the parent group through the Rust contract
    let group = db.get_group_full(community_id(), group_id()).await?;

    // Check the parent group and nested collections
    assert_eq!(
        group.community.ad_banner_link_url.as_deref(),
        Some("https://example.com/community-ad")
    );
    assert_eq!(
        group.community.ad_banner_url.as_deref(),
        Some("https://example.com/community-ad-banner.png")
    );
    assert_eq!(group.group_id, group_id());
    assert!(group.external_payments_enabled);
    assert_eq!(group.organizers.len(), 1);
    assert_eq!(group.sponsors.len(), 1);
    assert_eq!(group.subgroups.len(), 1);
    assert_eq!(group.subgroups[0].group_id, subgroup_id());
    assert!(group.parent.is_none());
    assert_eq!(
        group.organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );

    // Load the subgroup through the same contract
    let subgroup = db.get_group_full(community_id(), subgroup_id()).await?;

    // Check the subgroup parent relationship
    assert_eq!(
        subgroup
            .parent
            .as_ref()
            .expect("subgroup should have a parent")
            .group_id,
        group_id()
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_group_summary_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load the group summary through the Rust contract
    let group = db.get_group_summary(community_id(), group_id()).await?;

    // Check group identity and community fields
    assert_eq!(group.group_id, group_id());
    assert_eq!(group.community_name, "contract-community");
    assert!(group.region.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_internal_raise_keeps_default_sqlstate() -> Result<()> {
    // Setup a direct connection to call a worker-only function with invalid configuration
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;

    // Check internal invariant failures keep P0001 and never carry the user-facing code
    let internal_err = client
        .query_one("select cleanup_badge_award_jobs($1::bigint)", &[&0_i64])
        .await
        .expect_err("non-positive retention should be rejected");
    assert_eq!(internal_err.code(), Some(&SqlState::RAISE_EXCEPTION));
    assert_eq!(
        internal_err.as_db_error().map(DbError::message),
        Some("badge award job retention must be positive")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_cfs_labels_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load event submission labels through the Rust contract
    let labels = db.list_event_cfs_labels(event_id()).await?;

    // Check label color and name fields
    assert_eq!(labels.len(), 1);
    assert_eq!(labels[0].color, "#DBEAFE");
    assert_eq!(labels[0].name, "track / backend");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_ticket_types_deserializes() -> Result<()> {
    // Query the normalized ticket inventory through its SQL boundary
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    let row = client
        .query_one("select list_event_ticket_types($1)", &[&paid_event_id()])
        .await?;

    // Deserialize the exact JSON result into the production DTO
    let payload: serde_json::Value = row.try_get(0)?;
    let ticket_types: Vec<EventTicketType> = serde_json::from_value(payload)?;
    assert_eq!(ticket_types.len(), 2);
    let paid_ticket_type = ticket_types
        .iter()
        .find(|ticket_type| ticket_type.event_ticket_type_id == paid_ticket_type_id())
        .expect("paid ticket type to be returned");
    assert_contract_paid_ticket_type(paid_ticket_type);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_public_event_ticket_types_deserializes() -> Result<()> {
    // Query the attendee-facing ticket inventory through its SQL boundary
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    let row = client
        .query_one(
            "select list_public_event_ticket_types($1)",
            &[&paid_event_id()],
        )
        .await?;

    // Deserialize the exact JSON result into the production DTO
    let payload: serde_json::Value = row.try_get(0)?;
    let ticket_types: Vec<EventTicketType> = serde_json::from_value(payload)?;
    assert_eq!(ticket_types.len(), 2);
    let paid_ticket_type = ticket_types
        .iter()
        .find(|ticket_type| ticket_type.event_ticket_type_id == paid_ticket_type_id())
        .expect("public paid ticket type to be returned");
    assert_contract_paid_ticket_type(paid_ticket_type);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_events_deserializes() -> Result<()> {
    // Setup the contract database and event search filters
    let db = contract_tests_db()?;
    let filters = SearchEventsFilters {
        community: vec!["contract-community".to_string()],

        date_from: Some("2099-01-01".to_string()),
        date_to: Some("2099-12-31".to_string()),
        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Search events through the Rust contract
    let output = db.search_events(&filters).await?;

    // Check result totals and map bounds
    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert!(output.bbox.is_some());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_groups_deserializes() -> Result<()> {
    // Setup the contract database and group search filters
    let db = contract_tests_db()?;
    let filters = SearchGroupsFilters {
        community: vec!["contract-community".to_string()],

        include_bbox: Some(true),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Search groups through the Rust contract
    let output = db.search_groups(&filters).await?;

    // Check result totals and map bounds
    assert_eq!(output.total, 2);
    assert_eq!(output.groups.len(), 2);
    assert!(output.bbox.is_some());

    Ok(())
}
