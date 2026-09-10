//! Contract tests for the `DBMeetings` functions.

use std::time::Duration;

use anyhow::Result;

use crate::{db::meetings::DBMeetings, services::meetings::MeetingProvider};

use super::helpers::{auto_end_meeting_id, contract_tests_db, sync_event_id};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_meeting_for_auto_end_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the meeting eligible for automatic ending
    let candidate = db
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
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the meeting requiring provider synchronization
    let meeting = db
        .claim_meeting_out_of_sync()
        .await?
        .expect("contract meeting sync candidate should exist");

    // Check synchronization inputs and claim metadata
    assert_eq!(meeting.duration, Some(Duration::from_hours(1)));
    assert_eq!(meeting.event_id, Some(sync_event_id()));
    assert_eq!(meeting.provider, MeetingProvider::Zoom);
    assert!(meeting.sync_claimed_at.is_some());
    assert!(meeting.sync_state_hash.is_some());
    assert_eq!(
        meeting.topic.as_deref(),
        Some("Contract Meeting Sync Event")
    );

    Ok(())
}
