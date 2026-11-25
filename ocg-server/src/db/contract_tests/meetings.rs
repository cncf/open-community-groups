//! Contract tests for the `DBMeetings` functions.

use std::time::Duration;

use anyhow::Result;

use crate::{
    db::{PgExecutor, meetings::DBMeetings},
    types::meetings::MeetingProvider,
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_for_auto_end_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work
    let uow = contract_unit_of_work().await?;

    // Claim the meeting eligible for automatic ending
    let candidate = uow
        .claim_meeting_for_auto_end()
        .await?
        .expect("contract auto-end candidate should exist");

    // Check the provider meeting contract
    assert_eq!(candidate.meeting_id, auto_end_meeting_id());
    assert_eq!(candidate.provider, MeetingProvider::Zoom);
    assert_eq!(candidate.provider_meeting_id, "contract-auto-end");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_out_of_sync_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work
    let uow = contract_unit_of_work().await?;

    // Claim the meeting requiring provider synchronization
    let meeting = uow
        .claim_meeting_out_of_sync()
        .await?
        .expect("contract meeting sync candidate should exist");

    // Check synchronization inputs and first-attempt claim metadata
    assert_eq!(meeting.provider, MeetingProvider::Zoom);
    assert_eq!(meeting.sync_attempts, 1);
    assert!(meeting.create_attempted_at.is_none());
    assert_eq!(meeting.duration, Some(Duration::from_hours(1)));
    assert_eq!(meeting.event_id, Some(sync_event_id()));
    assert!(meeting.last_provider_host_user.is_none());
    assert!(meeting.sync_claimed_at.is_some());
    assert!(meeting.sync_state_hash.is_some());
    assert_eq!(
        meeting.topic.as_deref(),
        Some("Contract Meeting Sync Event")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_meeting_sync_retry_preserves_create_attempt_sticky_host_and_backoff()
-> Result<()> {
    // Setup a rolled-back unit of work and claim the sync event for its first create attempt
    let uow = contract_unit_of_work().await?;
    let first_claim = uow
        .claim_meeting_out_of_sync()
        .await?
        .expect("first sync claim should succeed");
    assert!(first_claim.create_attempted_at.is_none());
    assert_eq!(first_claim.sync_attempts, 1);

    // Reserve a Zoom host on the active claim
    let starts_at = first_claim.starts_at.expect("starts_at should exist");
    let ends_at = first_claim.ends_at().expect("ends_at should exist");
    let host = uow
        .assign_zoom_host_user(
            &first_claim,
            &["sticky-host@example.com".to_string()],
            1,
            starts_at,
            ends_at,
        )
        .await?;
    assert_eq!(host.as_deref(), Some("sticky-host@example.com"));

    // Release with backoff and confirm immediate re-claim is suppressed
    uow.release_meeting_sync_claim(&first_claim, Some(Duration::from_mins(5)))
        .await?;
    assert!(uow.claim_meeting_out_of_sync().await?.is_none());

    // Save an unrelated field (description only) and confirm backoff is preserved
    let unrelated_payload = serde_json::json!({
        "capacity": 100,
        "category_id": event_category_id(),
        "description": "Updated description only without changing meeting inputs",
        "ends_at": "2099-06-01T11:00:00",
        "kind_id": "virtual",
        "meeting_provider_id": "zoom",
        "meeting_requested": true,
        "name": "Contract Meeting Sync Event",
        "starts_at": "2099-06-01T10:00:00",
        "timezone": "UTC"
    });
    uow.execute(
        "select update_event($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
        &[
            &organizer_id(),
            &claim_group_id(),
            &sync_event_id(),
            &unrelated_payload,
        ],
    )
    .await?;
    assert!(uow.claim_meeting_out_of_sync().await?.is_none());

    // Materially edit the backed-off event through update_event and verify the
    // new state is immediately claimable with a fresh attempt count while
    // preserving create-attempt and sticky host tracking
    let event_payload = serde_json::json!({
        "capacity": 100,
        "category_id": event_category_id(),
        "description": "A meeting sync event edited during retry backoff",
        "ends_at": "2099-06-01T11:00:00",
        "kind_id": "virtual",
        "meeting_provider_id": "zoom",
        "meeting_requested": true,
        "name": "Contract Meeting Sync Event Edited",
        "starts_at": "2099-06-01T10:00:00",
        "timezone": "UTC"
    });
    uow.execute(
        "select update_event($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
        &[
            &organizer_id(),
            &claim_group_id(),
            &sync_event_id(),
            &event_payload,
        ],
    )
    .await?;

    // Re-claim after the edit and verify create-attempt tracking and sticky host survived
    let retry_claim = uow
        .claim_meeting_out_of_sync()
        .await?
        .expect("re-claim after material edit during backoff should succeed");
    assert!(retry_claim.create_attempted_at.is_some());
    assert_eq!(
        retry_claim.last_provider_host_user.as_deref(),
        Some("sticky-host@example.com")
    );
    assert_eq!(retry_claim.sync_attempts, 1);
    assert_eq!(
        retry_claim.topic.as_deref(),
        Some("Contract Meeting Sync Event Edited")
    );

    Ok(())
}
