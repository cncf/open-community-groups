//! Contract tests for the `DBNotifications` functions.

use anyhow::{Context, Result};
use chrono::Utc;

use crate::db::notifications::DBNotifications;

use super::helpers::{contract_tests_db, notification_id};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_pending_notification_deserializes() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Claim the seeded notification through the production wrapper
    let claim_started_at = Utc::now();
    let notification = db
        .claim_pending_notification()
        .await?
        .context("pending contract notification should be claimable")?;
    let claim_finished_at = Utc::now();

    // Check the complete delivery contract and claim identity were decoded
    assert!(notification.attachments.is_empty());
    let clock_tolerance = chrono::Duration::seconds(1);
    assert!(notification.delivery_claimed_at >= claim_started_at - clock_tolerance);
    assert!(notification.delivery_claimed_at <= claim_finished_at + clock_tolerance);
    assert_eq!(notification.email, "organizer.contract@example.com");
    assert_eq!(notification.kind.to_string(), "event-welcome");
    assert_eq!(notification.notification_id, notification_id());
    assert!(notification.template_data.is_none());

    // Finalize through the production wrapper to verify the claim identity round trip
    db.update_notification(&notification, None).await?;

    Ok(())
}
