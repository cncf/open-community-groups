//! Contract tests for the `DBCommon` and cross-cutting error functions.

use anyhow::Result;
use chrono::{DateTime, NaiveDate};
use tokio_postgres::error::{DbError, SqlState};

use crate::{
    db::{PgExecutor, common::DBCommon, user_facing_message},
    types::{
        event::EventKind,
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

use super::helpers::*;

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
    assert!(
        event.cohosts.is_empty(),
        "event should have no cohosts, got {:?}",
        event.cohosts
    );
    assert!(event.has_registration_questions);
    assert_eq!(
        event.luma_url.as_deref(),
        Some("https://luma.com/contract-event")
    );
    assert_eq!(event.registration_questions.len(), 1);
    assert_eq!(event.registration_questions[0].prompt, "Meal preference");
    assert!(event.registration_questions_locked);
    assert_eq!(
        event.seller_display_name.as_deref(),
        Some("Contract Fiscal Sponsor")
    );
    assert_eq!(event.sessions.len(), 1);
    assert_eq!(event.sponsors.len(), 1);
    assert_contract_ticket_type(
        &event.ticket_types.as_ref().expect("event should have tickets")[0],
    );

    // Check event labels and session labels
    assert_eq!(event.labels, vec![contract_event_label()]);
    let sessions = event.sessions.values().flatten().collect::<Vec<_>>();
    let labeled_session = sessions
        .iter()
        .find(|session| session.session_id == session_id())
        .expect("labeled session should be listed");
    let unlabeled_session = sessions
        .iter()
        .find(|session| session.session_id == unlabeled_session_id())
        .expect("unlabeled session should be listed");
    assert_eq!(labeled_session.labels, vec![contract_event_label()]);
    assert!(
        unlabeled_session.labels.is_empty(),
        "unlabeled session should have no labels, got {:?}",
        unlabeled_session.labels
    );
    assert!(
        external_event.labels.is_empty(),
        "external event should have no labels, got {:?}",
        external_event.labels
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
    assert_eq!(
        external_event.seller_display_name.as_deref(),
        Some("Contract External Payee")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_event_summary_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load the event summaries through the Rust contract
    let event = db.get_event_summary(community_id(), group_id(), event_id()).await?;
    let external_event = db
        .get_event_summary(community_id(), group_id(), external_event_id())
        .await?;

    // Check required and computed event fields
    assert_eq!(event.event_id, event_id());
    assert!(
        event.cohosts.is_empty(),
        "event should have no cohosts, got {:?}",
        event.cohosts
    );
    assert!(!event.has_external_payment);
    assert!(event.has_registration_questions);
    assert_contract_ticket_type(
        &event.ticket_types.as_ref().expect("event should have tickets")[0],
    );
    assert_eq!(event.kind, EventKind::Hybrid);
    assert_eq!(event.waitlist_count, 1);

    // Check the venue zip code key
    assert_eq!(event.venue_zip_code.as_deref(), Some("94105"));

    // Check the external-payments summary marks off-platform payment collection
    assert_eq!(external_event.event_id, external_event_id());
    assert!(external_event.has_external_payment);

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
    assert_eq!(
        group.external_payments_seller_display_name.as_deref(),
        Some("Contract External Payee")
    );
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
    assert_eq!(
        group.region.as_ref().map(|region| region.name.as_str()),
        Some("North America")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_worker_queue_health_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work and the queue health before any change
    let uow = contract_unit_of_work().await?;
    let before = uow.get_worker_queue_health().await?;

    // Queue one old pending and one processing notification
    uow.execute(
        "
        insert into notification (created_at, delivery_status, kind, user_id)
        values
            (current_timestamp - interval '100 years', 'pending', 'event-welcome', $1::uuid),
            (current_timestamp, 'processing', 'event-welcome', $1::uuid)
        ",
        &[&organizer_id()],
    )
    .await?;

    // Load the queue health through the Rust contract
    let after = uow.get_worker_queue_health().await?;

    // Check only the notification queue counts the new jobs and reports the
    // oldest pending age in seconds
    assert_eq!(
        after.notifications.pending,
        before.notifications.pending + 1
    );
    assert_eq!(
        after.notifications.processing,
        before.notifications.processing + 1
    );
    assert!(
        after
            .notifications
            .oldest_pending_age_secs
            .is_some_and(|age| age >= 100 * 365 * 24 * 60 * 60),
        "unexpected oldest pending age: {:?}",
        after.notifications.oldest_pending_age_secs
    );
    assert_eq!(after.badge_award_jobs, before.badge_award_jobs);
    assert_eq!(after.payment_jobs, before.payment_jobs);

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
    assert_eq!(
        user_facing_message(&anyhow::Error::from(internal_err)),
        None
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_event_labels_deserializes() -> Result<()> {
    // Setup the contract database and event fixture
    let db = contract_tests_db()?;

    // Load event labels through the Rust contract
    let labels = db.list_event_labels(event_id()).await?;
    let unlabeled_event_labels = db.list_event_labels(external_event_id()).await?;

    // Check label identifier, color and name fields
    assert_eq!(labels, vec![contract_event_label()]);
    assert!(
        unlabeled_event_labels.is_empty(),
        "external event should have no labels, got {unlabeled_event_labels:?}"
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_group_organizers_deserializes() -> Result<()> {
    // Setup the contract database and group fixture
    let db = contract_tests_db()?;

    // Load the accepted group team through the Rust contract
    let organizers = db.list_group_organizers(group_id()).await?;

    // Check required and optional user fields of the only team member
    assert_eq!(organizers.len(), 1);
    assert_eq!(organizers[0].user_id, organizer_id());
    assert_eq!(organizers[0].username, "contract-organizer");
    assert_eq!(
        organizers[0].bio.as_deref(),
        Some("Builds reliable community platforms")
    );
    assert_eq!(
        organizers[0].github_url.as_deref(),
        Some("https://github.com/contract-organizer")
    );
    assert_eq!(organizers[0].name.as_deref(), Some("Contract Organizer"));
    assert_eq!(
        organizers[0].photo_url.as_deref(),
        Some("https://example.com/organizer.png")
    );
    assert_eq!(organizers[0].title.as_deref(), Some("Organizer"));
    assert!(organizers[0].bluesky_url.is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_events_deserializes() -> Result<()> {
    // Setup the contract database and event search filters
    let db = contract_tests_db()?;
    let filters = SearchEventsFilters {
        community: vec!["contract-community".to_string()],

        date_from: NaiveDate::from_ymd_opt(2099, 1, 1),
        date_to: NaiveDate::from_ymd_opt(2099, 12, 31),
        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Search events through the Rust contract
    let output = db.search_events(&filters).await?;

    // Check result totals and the returned event
    assert_eq!(output.total, 1);
    assert_eq!(output.events.len(), 1);
    assert_eq!(output.events[0].event_id, event_id());
    assert_eq!(output.events[0].name, "Future Contract Event");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_search_groups_deserializes() -> Result<()> {
    // Setup the contract database and group search filters
    let db = contract_tests_db()?;
    let filters = SearchGroupsFilters {
        community: vec!["contract-community".to_string()],

        limit: Some(10),
        offset: Some(0),

        ..Default::default()
    };

    // Search groups through the Rust contract
    let output = db.search_groups(&filters).await?;

    // Check result totals and the returned groups in name order
    assert_eq!(output.total, 2);
    assert_eq!(
        output
            .groups
            .iter()
            .map(|group| (group.group_id, group.name.as_str()))
            .collect::<Vec<_>>(),
        vec![
            (group_id(), "Contract Group"),
            (subgroup_id(), "Contract Subgroup")
        ]
    );

    Ok(())
}
