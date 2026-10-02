//! Contract tests for the `DBNotifications` functions.

use anyhow::{Context, Result};
use chrono::Utc;

use crate::{
    db::notifications::DBNotifications,
    types::notifications::{NewNotification, NotificationKind},
};

use super::helpers::*;

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

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_notification_filters_all_group_scoped_recipients() -> Result<()> {
    // Setup the contract database and a dedicated muted recipient
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;

    // Enqueue a group-mutable notification where every recipient opted out by group mute
    db.enqueue_notification(&NewNotification {
        attachments: vec![],
        group_ids: vec![subgroup_id()],
        kind: NotificationKind::GroupCustom,
        recipients: vec![notification_preferences_user_id()],

        template_data: Some(serde_json::json!({
            "body": "Muted contract announcement",
            "subject": "Muted contract announcement"
        })),
    })
    .await?;

    // Check the enqueue accepted the request without writing filtered notifications
    let notification_count: i64 = client
        .query_one(
            "select count(*)
            from notification
            where kind = 'group-custom'
            and user_id = $1::uuid",
            &[&notification_preferences_user_id()],
        )
        .await?
        .get(0);
    assert_eq!(notification_count, 0);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_filter_notification_recipient_ids_preserves_eligible_order() -> Result<()> {
    // Setup the contract database and ordered recipient candidates
    let db = contract_tests_db()?;
    let recipients = vec![
        notification_preferences_user_id(),
        notification_eligible_user_id(),
        organizer_id(),
    ];

    // Filter group-scoped recipients through the production wrapper
    let filtered = db
        .filter_notification_recipient_ids(
            &NotificationKind::GroupCustom,
            &recipients,
            &[subgroup_id()],
        )
        .await?;

    // Check muted recipients are removed without reordering the eligible users
    assert_eq!(
        filtered,
        vec![notification_eligible_user_id(), organizer_id()]
    );

    Ok(())
}
