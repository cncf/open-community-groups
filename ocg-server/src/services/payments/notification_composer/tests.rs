use std::sync::Arc;

use serde_json::to_value;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{mock::MockDB, payments::CompletedEventPurchase},
    services::notifications::MockNotificationsManager,
    templates::notifications::{
        EventRefundApproved, EventRefundRejected, EventRefundRequested, EventWelcome,
    },
    types::{
        event::EventSummary, notifications::NotificationKind, site::SiteSettings,
        tests::sample_event_summary,
    },
};

use super::PaymentsNotificationComposer;

/// Public event link built for `sample_event_summary`.
const SAMPLE_EVENT_LINK: &str = "/test-community/group/def5678/event/ghi9abc";

#[tokio::test]
async fn test_build_refund_approval_template_data_returns_expected_payload() {
    for external_payment in [false, true] {
        // Setup identifiers and notification context
        let community_id = Uuid::new_v4();
        let event = sample_event_summary(Uuid::new_v4());
        let mut db = MockDB::new();
        expect_event_notification_context(&mut db, community_id, &event);

        // Build the template payload
        let composer = sample_notification_composer(db, MockNotificationsManager::new());
        let template_data = composer
            .build_refund_approval_template_data(community_id, event.event_id, external_payment)
            .await
            .expect("refund approval template data to be built");

        // Check the payload marks where the refund was returned
        assert_eq!(
            template_data,
            to_value(&EventRefundApproved {
                event: event.clone(),
                external_payment,
                link: SAMPLE_EVENT_LINK.to_string(),
                theme: SiteSettings::default().theme,
            })
            .unwrap(),
            "external_payment: {external_payment}"
        );
    }
}

#[tokio::test]
async fn test_build_refund_request_template_data_returns_expected_payload() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let event = sample_event_summary(Uuid::new_v4());
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, &event);

    // Build the template payload
    let composer = sample_notification_composer(db, MockNotificationsManager::new());
    let template_data = composer
        .build_refund_request_template_data(community_id, event.event_id)
        .await
        .expect("refund request template data to be built");

    // Check result matches expectations
    assert_eq!(
        template_data,
        to_value(&EventRefundRequested {
            event,
            link: "/dashboard/group?tab=refunds".to_string(),
            theme: SiteSettings::default().theme,
        })
        .unwrap()
    );
}

#[tokio::test]
async fn test_enqueue_checkout_completed_notification_omits_dashboard_cancel_guidance() {
    // Setup identifiers, notification context, and expected payload
    let community_id = Uuid::new_v4();
    let event = sample_event_summary(Uuid::new_v4());
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventWelcome {
        event: event.clone(),
        link: SAMPLE_EVENT_LINK.to_string(),
        theme: SiteSettings::default().theme,

        dashboard_link: None,
    })
    .unwrap();
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, &event);

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            notification.attachments.len() == 1
                && matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref() == Some(&expected_template_data)
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Enqueue the checkout completed welcome notification
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_checkout_completed_notification(CompletedEventPurchase {
            community_id,
            event_id: event.event_id,
            user_id,

            transitioned: None,
        })
        .await;
}

#[tokio::test]
async fn test_enqueue_event_welcome_notification_enqueues_expected_payload() {
    // Setup identifiers, notification context, and expected payload
    let community_id = Uuid::new_v4();
    let event = sample_event_summary(Uuid::new_v4());
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventWelcome {
        event: event.clone(),
        link: SAMPLE_EVENT_LINK.to_string(),
        theme: SiteSettings::default().theme,

        dashboard_link: Some("/dashboard/user?tab=events".to_string()),
    })
    .unwrap();
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, &event);

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            notification.attachments.len() == 1
                && matches!(notification.kind, NotificationKind::EventWelcome)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref() == Some(&expected_template_data)
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Enqueue the welcome notification
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_event_welcome_notification(community_id, event.event_id, user_id)
        .await;
}

#[tokio::test]
async fn test_enqueue_event_welcome_notification_skips_enqueue_when_context_fails() {
    // Setup a notification context that cannot be loaded
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow::anyhow!("context unavailable")));

    // Forbid enqueueing a notification without its context
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Enqueue the welcome notification on a best-effort basis
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_event_welcome_notification(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4())
        .await;
}

#[tokio::test]
async fn test_enqueue_event_welcome_notification_swallows_enqueue_failure() {
    // Setup the notification context and a failing enqueue
    let community_id = Uuid::new_v4();
    let event = sample_event_summary(Uuid::new_v4());
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, &event);
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow::anyhow!("queue unavailable")) }));

    // Enqueue the welcome notification on a best-effort basis
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_event_welcome_notification(community_id, event.event_id, Uuid::new_v4())
        .await;
}

#[tokio::test]
async fn test_enqueue_refund_rejection_notification_enqueues_expected_payload() {
    // Setup identifiers, notification context, and expected payload
    let community_id = Uuid::new_v4();
    let event = sample_event_summary(Uuid::new_v4());
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventRefundRejected {
        event: event.clone(),
        link: SAMPLE_EVENT_LINK.to_string(),
        rejection_reason: "Outside the refund policy window".to_string(),
        theme: SiteSettings::default().theme,
    })
    .unwrap();
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, &event);

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            notification.attachments.is_empty()
                && matches!(notification.kind, NotificationKind::EventRefundRejected)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref() == Some(&expected_template_data)
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Enqueue the refund rejection notification
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_refund_rejection_notification(
            community_id,
            event.event_id,
            user_id,
            "Outside the refund policy window",
        )
        .await;
}

#[tokio::test]
async fn test_enqueue_refund_rejection_notification_skips_enqueue_when_context_fails() {
    // Setup a notification context that cannot be loaded
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id().never();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow::anyhow!("context unavailable")));

    // Forbid enqueueing a notification without its context
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Enqueue the rejection notification on a best-effort basis
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_refund_rejection_notification(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            "Not eligible",
        )
        .await;
}

#[tokio::test]
async fn test_enqueue_refund_rejection_notification_swallows_enqueue_failure() {
    // Setup the notification context and a failing enqueue
    let community_id = Uuid::new_v4();
    let event = sample_event_summary(Uuid::new_v4());
    let mut db = MockDB::new();
    expect_event_notification_context(&mut db, community_id, &event);
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow::anyhow!("queue unavailable")) }));

    // Enqueue the rejection notification on a best-effort basis
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_refund_rejection_notification(
            community_id,
            event.event_id,
            Uuid::new_v4(),
            "Not eligible",
        )
        .await;
}

// Helpers.

/// Expects the event summary and default site settings for one notification.
fn expect_event_notification_context(db: &mut MockDB, community_id: Uuid, event: &EventSummary) {
    let event = event.clone();
    let event_id = event.event_id;
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(SiteSettings::default()));
}

/// Create a payments notification composer with mock dependencies.
fn sample_notification_composer(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
) -> PaymentsNotificationComposer {
    PaymentsNotificationComposer::new(
        Arc::new(db),
        Arc::new(notifications_manager),
        HttpServerConfig::default(),
    )
}
