use std::sync::Arc;

use serde_json::to_value;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::mock::MockDB,
    services::notifications::{MockNotificationsManager, NotificationKind},
    templates::notifications::{
        EventRefundApproved, EventRefundRejected, EventRefundRequested, EventWelcome,
    },
    types::{
        event::{EventKind, EventSummary},
        site::SiteSettings,
    },
};

use super::PaymentsNotificationComposer;

#[tokio::test]
async fn build_refund_request_template_data_returns_expected_payload() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let site_settings = SiteSettings::default();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Build the template payload
    let composer = sample_notification_composer(db, MockNotificationsManager::new());
    let template_data = composer
        .build_refund_request_template_data(community_id, event_id)
        .await
        .expect("refund request template data to be built");

    // Check result matches expectations
    assert_eq!(
        template_data,
        to_value(&EventRefundRequested {
            event: sample_event_summary(event_id),
            link: "/dashboard/group?tab=events".to_string(),
            theme: SiteSettings::default().theme,
        })
        .unwrap()
    );
}

#[tokio::test]
async fn enqueue_event_welcome_notification_enqueues_expected_payload() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let site_settings = SiteSettings::default();
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventWelcome {
        event: sample_event_summary(event_id),
        link: "/community/group/group/event/event".to_string(),
        theme: SiteSettings::default().theme,
    })
    .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

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
        .enqueue_event_welcome_notification(community_id, event_id, user_id)
        .await;
}

#[tokio::test]
async fn enqueue_refund_approval_notification_enqueues_expected_payload() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let site_settings = SiteSettings::default();
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventRefundApproved {
        event: sample_event_summary(event_id),
        link: "/community/group/group/event/event".to_string(),
        theme: SiteSettings::default().theme,
    })
    .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            notification.attachments.is_empty()
                && matches!(notification.kind, NotificationKind::EventRefundApproved)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref() == Some(&expected_template_data)
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Enqueue the refund approval notification
    let composer = sample_notification_composer(db, notifications_manager);
    composer
        .enqueue_refund_approval_notification(community_id, event_id, user_id)
        .await;
}

#[tokio::test]
async fn enqueue_refund_rejection_notification_enqueues_expected_payload() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let site_settings = SiteSettings::default();
    let user_id = Uuid::new_v4();
    let expected_template_data = to_value(&EventRefundRejected {
        event: sample_event_summary(event_id),
        link: "/community/group/group/event/event".to_string(),
        theme: SiteSettings::default().theme,
    })
    .unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

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
        .enqueue_refund_rejection_notification(community_id, event_id, user_id)
        .await;
}

// Helpers.

/// Create a sample event summary.
fn sample_event_summary(event_id: Uuid) -> EventSummary {
    EventSummary {
        attendee_approval_required: false,
        canceled: false,
        community_display_name: "Community".to_string(),
        community_name: "community".to_string(),
        event_id,
        group_category_name: "Technology".to_string(),
        group_name: "Group".to_string(),
        group_slug: "group".to_string(),
        has_related_events: false,
        kind: EventKind::default(),
        logo_url: "https://example.test/logo.png".to_string(),
        name: "Event".to_string(),
        published: true,
        slug: "event".to_string(),
        timezone: chrono_tz::UTC,
        waitlist_count: 0,
        waitlist_enabled: false,
        capacity: None,
        description_short: None,
        ends_at: None,
        event_series_id: None,
        latitude: None,
        longitude: None,
        meeting_join_url: None,
        meeting_password: None,
        meeting_provider: None,
        payment_currency_code: None,
        popover_html: None,
        remaining_capacity: None,
        starts_at: None,
        ticket_types: None,
        venue_address: None,
        venue_city: None,
        venue_country_code: None,
        venue_country_name: None,
        venue_name: None,
        venue_state: None,
        zip_code: None,
    }
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
