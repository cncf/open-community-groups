//! Contract tests for the `DBNotifications` functions.

use anyhow::{Context, Result};
use chrono::Utc;

use crate::{
    db::notifications::{
        CommunityCustomNotificationEnqueue, CustomNotificationScope, CustomNotificationTracking,
        DBNotifications,
    },
    types::{
        dashboard::community::contact::CommunityContactFilters,
        group::GroupRole,
        notifications::{NewNotification, NotificationKind},
    },
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
async fn db_contracts_enqueue_tracked_community_custom_notification_enqueues_and_audits()
-> Result<()> {
    // Setup the contract database and admin-only filters
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;
    let subject = "Contract community contact";

    // Enqueue the community notification through the production wrapper
    let count = db
        .enqueue_tracked_community_custom_notification(CommunityCustomNotificationEnqueue {
            body: "Hello group teams".to_string(),
            community_id: contact_community_id(),
            created_by: contact_manager_id(),
            filters: CommunityContactFilters {
                roles: vec![GroupRole::Admin],
                ..Default::default()
            },
            subject: subject.to_string(),
            template_data: serde_json::json!({ "subject": subject }),
        })
        .await?;

    // Check only the verified admin of an active group was notified
    assert_eq!(count, 1);
    let recipients: Vec<uuid::Uuid> = client
        .query(
            "select n.user_id
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.kind = 'community-custom'
            and ntd.data->>'subject' = $1::text",
            &[&subject],
        )
        .await?
        .iter()
        .map(|row| row.get(0))
        .collect();
    assert_eq!(recipients, vec![contact_admin_id()]);

    // Check the custom notification is tracked against the community
    let tracked_community_id: Option<uuid::Uuid> = client
        .query_one(
            "select community_id from custom_notification where subject = $1::text",
            &[&subject],
        )
        .await?
        .get(0);
    assert_eq!(tracked_community_id, Some(contact_community_id()));

    // Check the audit row describes the recipients and filters by name
    let audit = client
        .query_one(
            "select community_id, details, resource_id, resource_type
            from audit_log
            where action = 'community_custom_notification_sent'
            and details->>'subject' = $1::text",
            &[&subject],
        )
        .await?;
    assert_eq!(
        audit.get::<_, Option<uuid::Uuid>>("community_id"),
        Some(contact_community_id())
    );
    assert_eq!(
        audit.get::<_, serde_json::Value>("details"),
        serde_json::json!({
            "group_categories": "All",
            "recipient_count": 1,
            "regions": "All",
            "roles": ["Admin"],
            "subject": subject,
        })
    );
    assert_eq!(
        audit.get::<_, uuid::Uuid>("resource_id"),
        contact_community_id()
    );
    assert_eq!(audit.get::<_, String>("resource_type"), "community");

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_tracked_community_custom_notification_rejects_foreign_filters()
-> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Enqueue with a group category of another community
    let err = db
        .enqueue_tracked_community_custom_notification(CommunityCustomNotificationEnqueue {
            body: "Hello".to_string(),
            community_id: contact_community_id(),
            created_by: contact_manager_id(),
            filters: CommunityContactFilters {
                group_category_ids: vec![group_category_id()],
                ..Default::default()
            },
            subject: "Contract foreign contact".to_string(),
            template_data: serde_json::json!({}),
        })
        .await
        .expect_err("foreign category should be rejected");

    // Check the user-facing rejection is raised
    assert_eq!(
        ocg01_message(&err).as_deref(),
        Some("group category not found")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_tracked_community_custom_notification_rejects_zero_recipients()
-> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Enqueue with filters no seat matches together
    let err = db
        .enqueue_tracked_community_custom_notification(CommunityCustomNotificationEnqueue {
            body: "Hello".to_string(),
            community_id: contact_community_id(),
            created_by: contact_manager_id(),
            filters: CommunityContactFilters {
                group_category_ids: vec![contact_category_b_id()],
                roles: vec![GroupRole::Admin],
                ..Default::default()
            },
            subject: "Contract empty contact".to_string(),
            template_data: serde_json::json!({}),
        })
        .await
        .expect_err("empty audience should be rejected");

    // Check the user-facing rejection is raised
    assert_eq!(
        ocg01_message(&err).as_deref(),
        Some("no group team members match the selected filters")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_tracked_custom_notification_tracks_group_scope() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;
    let subject = "Contract group scope";

    // Enqueue a group notification through the production wrapper
    db.enqueue_tracked_custom_notification(
        &NewNotification {
            attachments: vec![],
            group_ids: vec![contact_group_a_id()],
            kind: NotificationKind::GroupCustom,
            recipients: vec![contact_manager_id()],

            template_data: Some(serde_json::json!({ "subject": subject })),
        },
        CustomNotificationTracking {
            body: "Hello group".to_string(),
            created_by: contact_admin_id(),
            recipient_count: 1,
            scope: CustomNotificationScope::Group {
                community_id: contact_community_id(),
                group_id: contact_group_a_id(),
            },
            subject: subject.to_string(),
        },
    )
    .await?;

    // Check the custom notification is tracked against the group only
    let tracked = client
        .query_one(
            "select community_id, event_id, group_id
            from custom_notification
            where subject = $1::text",
            &[&subject],
        )
        .await?;
    assert_eq!(tracked.get::<_, Option<uuid::Uuid>>("community_id"), None);
    assert_eq!(tracked.get::<_, Option<uuid::Uuid>>("event_id"), None);
    assert_eq!(
        tracked.get::<_, Option<uuid::Uuid>>("group_id"),
        Some(contact_group_a_id())
    );

    // Check the audit row carries the community of the group
    let audit = client
        .query_one(
            "select community_id, group_id
            from audit_log
            where action = 'group_custom_notification_sent'
            and details->>'subject' = $1::text",
            &[&subject],
        )
        .await?;
    assert_eq!(
        audit.get::<_, Option<uuid::Uuid>>("community_id"),
        Some(contact_community_id())
    );
    assert_eq!(
        audit.get::<_, Option<uuid::Uuid>>("group_id"),
        Some(contact_group_a_id())
    );

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
