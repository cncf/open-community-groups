use std::sync::Arc;

use anyhow::anyhow;
use serde_json::json;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    config::{EmailConfig, SmtpConfig},
    db::{DynDB, mock::MockDB},
};

use super::{
    Attachment, DeliveryWorker, DynEmailSender, EnqueueWorker, MockEmailSender, NewNotification,
    Notification, NotificationKind, NotificationsManager, PgNotificationsManager,
};

#[tokio::test]
async fn test_notifications_manager_enqueue() {
    // Setup identifiers and data structures
    let recipient = Uuid::new_v4();
    let expected_recipients = vec![recipient];
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::EmailVerification,
        recipients: expected_recipients.clone(),
        template_data: Some(sample_email_verification_template_data()),
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_notification()
        .times(1)
        .withf(move |notif| {
            notif.kind.to_string() == NotificationKind::EmailVerification.to_string()
                && notif.recipients == expected_recipients
                && notif.template_data.is_some()
                && notif.attachments.is_empty()
        })
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Execute enqueue call
    let manager = PgNotificationsManager { db: db.clone() };
    manager.enqueue(&notification).await.unwrap();
}

#[tokio::test]
async fn test_enqueue_worker_enqueue_due_notifications() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders()
        .times(1)
        .withf(|base_url| base_url == "https://example.test")
        .returning(|_| Ok(2));
    let db: DynDB = Arc::new(db);

    // Setup worker and enqueue due notifications
    let worker = EnqueueWorker {
        db,
        base_url: "https://example.test".to_string(),
        cancellation_token: CancellationToken::new(),
    };
    let enqueued = worker.enqueue_due_notifications().await.unwrap();

    // Check result matches expectations
    assert_eq!(enqueued, 2);
}

#[tokio::test]
async fn test_enqueue_worker_enqueue_due_notifications_error() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders()
        .times(1)
        .withf(|base_url| base_url == "https://example.test")
        .returning(|_| Err(anyhow!("enqueue error")));
    let db: DynDB = Arc::new(db);

    // Setup worker and enqueue due notifications
    let worker = EnqueueWorker {
        db,
        base_url: "https://example.test".to_string(),
        cancellation_token: CancellationToken::new(),
    };
    let err = worker.enqueue_due_notifications().await.unwrap_err();

    // Check error matches expectations
    assert!(err.to_string().contains("enqueue error"));
}

#[tokio::test]
async fn test_enqueue_worker_run_stops_on_cancellation_after_enqueue_error() {
    // Setup cancellation token
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_mock = cancellation_token.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders()
        .times(1)
        .withf(|base_url| base_url == "https://example.test")
        .returning(move |_| {
            cancellation_token_for_mock.cancel();
            Err(anyhow!("enqueue error"))
        });
    let db: DynDB = Arc::new(db);

    // Setup worker and execute loop
    let worker = EnqueueWorker {
        db,
        base_url: "https://example.test".to_string(),
        cancellation_token: cancellation_token.clone(),
    };
    worker.run().await;

    // Check cancellation state
    assert!(cancellation_token.is_cancelled());
}

#[tokio::test]
async fn test_enqueue_worker_run_stops_on_cancellation_after_enqueue_success() {
    // Setup cancellation token
    let cancellation_token = CancellationToken::new();
    let cancellation_token_for_mock = cancellation_token.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders()
        .times(1)
        .withf(|base_url| base_url == "https://example.test")
        .returning(move |_| {
            cancellation_token_for_mock.cancel();
            Ok(1)
        });
    let db: DynDB = Arc::new(db);

    // Setup worker and execute loop
    let worker = EnqueueWorker {
        db,
        base_url: "https://example.test".to_string(),
        cancellation_token: cancellation_token.clone(),
    };
    worker.run().await;

    // Check cancellation state
    assert!(cancellation_token.is_cancelled());
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_sends_pending_notification() {
    // Setup identifiers and data structures
    let client_id = Uuid::new_v4();
    let notification = Notification {
        attachments: vec![],
        email: "notify@example.test".to_string(),
        kind: NotificationKind::EmailVerification,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_email_verification_template_data()),
    };
    let notification_id = notification.notification_id;
    let recipient = notification.email.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_tx_begin().times(1).returning(move || Ok(client_id));
    db.expect_get_pending_notification()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(move |_| Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |cid, notif, err| {
            *cid == client_id && notif.notification_id == notification_id && err.is_none()
        })
        .returning(|_, _, _| Ok(()));
    db.expect_tx_commit()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .withf(move |message| {
            message
                .envelope()
                .to()
                .iter()
                .any(|rcpt| rcpt.to_string() == recipient)
        })
        .returning(|_| Box::pin(async { Ok::<(), anyhow::Error>(()) }));
    let es: DynEmailSender = Arc::new(es);

    // Setup worker and deliver notification
    let mut worker = DeliveryWorker {
        db,
        cfg: sample_email_config(None),
        cancellation_token: CancellationToken::new(),
        email_sender: es,
    };
    let delivered = worker.deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_sends_pending_notification_with_attachment() {
    // Setup identifiers and data structures
    let client_id = Uuid::new_v4();
    let attachments = vec![Attachment {
        content_type: "text/calendar".to_string(),
        data: b"BEGIN:VCALENDAR".to_vec(),
        file_name: "event.ics".to_string(),
    }];
    let notification = Notification {
        attachments: attachments.clone(),
        email: "notify@example.test".to_string(),
        kind: NotificationKind::EmailVerification,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_email_verification_template_data()),
    };
    let notification_id = notification.notification_id;
    let recipient = notification.email.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_tx_begin().times(1).returning(move || Ok(client_id));
    db.expect_get_pending_notification()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(move |_| Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |cid, notif, err| {
            *cid == client_id && notif.notification_id == notification_id && err.is_none()
        })
        .returning(|_, _, _| Ok(()));
    db.expect_tx_commit()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .withf(move |message| {
            message
                .envelope()
                .to()
                .iter()
                .any(|rcpt| rcpt.to_string() == recipient)
        })
        .returning(|_| Box::pin(async { Ok::<(), anyhow::Error>(()) }));
    let es: DynEmailSender = Arc::new(es);

    // Setup worker and deliver notification
    let mut worker = DeliveryWorker {
        db,
        cfg: sample_email_config(None),
        cancellation_token: CancellationToken::new(),
        email_sender: es,
    };
    let delivered = worker.deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_no_pending_notifications() {
    // Setup identifiers and data structures
    let client_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_tx_begin().times(1).returning(move || Ok(client_id));
    db.expect_get_pending_notification()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(|_| Ok(None));
    db.expect_tx_rollback()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().never();
    let es: DynEmailSender = Arc::new(es);

    // Setup worker and deliver notification
    let mut worker = DeliveryWorker {
        db,
        cfg: sample_email_config(None),
        cancellation_token: CancellationToken::new(),
        email_sender: es,
    };
    let delivered = worker.deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(!delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_records_send_error() {
    // Setup identifiers and data structures
    let client_id = Uuid::new_v4();
    let notification = Notification {
        attachments: vec![],
        email: "notify@example.test".to_string(),
        kind: NotificationKind::EmailVerification,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_email_verification_template_data()),
    };
    let notification_id = notification.notification_id;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_tx_begin().times(1).returning(move || Ok(client_id));
    db.expect_get_pending_notification()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(move |_| Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |cid, notif, err| {
            *cid == client_id
                && notif.notification_id == notification_id
                && err.as_deref() == Some("delivery error")
        })
        .returning(|_, _, _| Ok(()));
    db.expect_tx_commit()
        .times(1)
        .withf(move |cid| *cid == client_id)
        .returning(|_| Ok(()));
    let db: DynDB = Arc::new(db);

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("delivery error")) }));
    let es: DynEmailSender = Arc::new(es);

    // Setup worker and deliver notification
    let mut worker = DeliveryWorker {
        db,
        cfg: sample_email_config(None),
        cancellation_token: CancellationToken::new(),
        email_sender: es,
    };
    let delivered = worker.deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[test]
fn test_delivery_worker_prepare_content_email_verification() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EmailVerification,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_email_verification_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "Verify your email address");
    assert!(body.contains("Verify your email"));
    assert!(body.contains("https://example.test/verify"));
}

#[test]
fn test_delivery_worker_prepare_content_event_custom() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventCustom,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_custom_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "Notification Group: Custom Event");
    assert!(body.contains("Custom event body"));
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventReminder,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_reminder_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "Reminder: Reminder Event starts in 24 hours");
    assert!(body.contains("Reminder Event"));
    assert!(
        body.contains("https://example.test/test-community/group/notification-group/event/reminder-event")
    );
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder_legacy_template_data() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventReminder,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_reminder_legacy_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "Reminder: Reminder Event starts in 24 hours");
    assert!(body.contains("Reminder Event"));
    assert!(
        body.contains("https://example.test/test-community/group/notification-group/event/reminder-event")
    );
}

#[test]
fn test_delivery_worker_prepare_content_event_series_canceled() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventSeriesCanceled,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_series_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "Events canceled");
    assert!(body.contains("2 events from"));
    assert!(body.contains("Series Event One"));
    assert!(body.contains("Series Event Two"));
}

#[test]
fn test_delivery_worker_prepare_content_event_series_published() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventSeriesPublished,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_series_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "New events published");
    assert!(body.contains("2 new events"));
    assert!(body.contains("Series Event One"));
    assert!(body.contains("Series Event Two"));
}

#[test]
fn test_delivery_worker_prepare_content_speaker_series_welcome() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::SpeakerSeriesWelcome,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_series_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "You're speaking at upcoming events");
    assert!(body.contains("2 events with"));
    assert!(body.contains("Series Event One"));
    assert!(body.contains("Series Event Two"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_joined() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventWaitlistJoined,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_waitlist_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "You joined the waiting list");
    assert!(body.contains("You have been added to the waiting list"));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_left() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventWaitlistLeft,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_waitlist_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "You left the waiting list");
    assert!(body.contains("You have left the waiting list"));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_promoted() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EventWaitlistPromoted,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_event_waitlist_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "You moved off the waiting list");
    assert!(body.contains("you are now registered"));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_group_custom() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::GroupCustom,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_group_custom_template_data()),
    };

    // Prepare content
    let (subject, body) = DeliveryWorker::prepare_content(&notification).unwrap();

    // Check content matches expectations
    assert_eq!(subject, "Hello Group");
    assert!(body.contains("Custom group body"));
}

#[test]
fn test_delivery_worker_prepare_content_missing_data() {
    // Setup notification
    let notification = Notification {
        attachments: vec![],
        email: "user@example.test".to_string(),
        kind: NotificationKind::EmailVerification,
        notification_id: Uuid::new_v4(),
        template_data: None,
    };

    // Prepare content and expect an error
    let err = DeliveryWorker::prepare_content(&notification).unwrap_err();

    // Check error message
    assert!(err.to_string().contains("missing template data"));
}

#[tokio::test]
async fn test_delivery_worker_send_email_allows_whitelisted_recipient() {
    // Setup email config and sender mock
    let cfg = sample_email_config(Some(vec!["notify@example.test".to_string()]));
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .withf(|message| {
            message
                .envelope()
                .to()
                .iter()
                .any(|rcpt| rcpt.to_string() == "notify@example.test")
        })
        .returning(|_| Box::pin(async { Ok::<(), anyhow::Error>(()) }));
    let es: DynEmailSender = Arc::new(es);

    // Setup worker and send email
    let worker = sample_delivery_worker(cfg, es);
    worker
        .send_email(
            "notify@example.test",
            "Subject line",
            "<p>Body content</p>".to_string(),
            &[],
        )
        .await
        .unwrap();
}

#[tokio::test]
async fn test_delivery_worker_send_email_blocks_non_whitelisted_recipient() {
    // Setup email config and sender mock
    let cfg = sample_email_config(Some(vec!["notify@example.test".to_string()]));
    let mut es = MockEmailSender::new();
    es.expect_send().never();
    let es: DynEmailSender = Arc::new(es);

    // Setup worker and send email
    let worker = sample_delivery_worker(cfg, es);
    worker
        .send_email(
            "other@example.test",
            "Subject line",
            "<p>Body content</p>".to_string(),
            &[],
        )
        .await
        .unwrap();
}

// Helpers.

/// Create a sample email configuration with an optional recipients whitelist.
fn sample_email_config(rcpts_whitelist: Option<Vec<String>>) -> EmailConfig {
    EmailConfig {
        from_address: "no-reply@example.test".to_string(),
        from_name: "Open Community Groups".to_string(),
        smtp: SmtpConfig {
            host: "smtp.example.test".to_string(),
            port: 587,
            username: "user".to_string(),
            password: "pass".to_string(),
        },

        rcpts_whitelist,
    }
}

/// Create a sample worker with mock dependencies.
fn sample_delivery_worker(cfg: EmailConfig, email_sender: DynEmailSender) -> DeliveryWorker {
    let db: DynDB = Arc::new(MockDB::new());

    DeliveryWorker {
        db,
        cfg,
        cancellation_token: CancellationToken::new(),
        email_sender,
    }
}

/// Sample template payload for email verification notifications.
fn sample_email_verification_template_data() -> serde_json::Value {
    json!({
        "link": "https://example.test/verify",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for custom event notifications.
fn sample_event_custom_template_data() -> serde_json::Value {
    json!({
        "title": "Custom event title",
        "body": "Custom event body",
        "event": {
            "canceled": false,
            "community_display_name": "Test Community",
            "community_name": "test-community",
            "event_id": "11111111-1111-1111-1111-111111111111",
            "group_category_name": "Community",
            "group_name": "Notification Group",
            "group_slug": "notification-group",
            "kind": "virtual",
            "logo_url": "https://example.com/logo.png",
            "name": "Custom Event",
            "published": true,
            "slug": "custom-event",
            "timezone": "UTC",
            "waitlist_count": 0,
            "waitlist_enabled": false
        },
        "link": "https://example.test/test-community/group/notification-group/event/custom-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample legacy payload for event reminder notifications without waitlist data.
fn sample_event_reminder_legacy_template_data() -> serde_json::Value {
    json!({
        "event": {
            "canceled": false,
            "community_display_name": "Test Community",
            "community_name": "test-community",
            "event_id": "11111111-1111-1111-1111-111111111111",
            "group_category_name": "Community",
            "group_name": "Notification Group",
            "group_slug": "notification-group",
            "kind": "hybrid",
            "logo_url": "https://example.com/logo.png",
            "name": "Reminder Event",
            "published": true,
            "slug": "reminder-event",
            "starts_at": 1_914_724_800,
            "timezone": "UTC",
            "venue_name": "Conference Hall"
        },
        "link": "https://example.test/test-community/group/notification-group/event/reminder-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for event reminder notifications.
fn sample_event_reminder_template_data() -> serde_json::Value {
    json!({
        "event": {
            "canceled": false,
            "community_display_name": "Test Community",
            "community_name": "test-community",
            "event_id": "11111111-1111-1111-1111-111111111111",
            "group_category_name": "Community",
            "group_name": "Notification Group",
            "group_slug": "notification-group",
            "kind": "hybrid",
            "logo_url": "https://example.com/logo.png",
            "name": "Reminder Event",
            "published": true,
            "slug": "reminder-event",
            "starts_at": 1_914_724_800,
            "timezone": "UTC",
            "venue_name": "Conference Hall",
            "waitlist_count": 0,
            "waitlist_enabled": false
        },
        "link": "https://example.test/test-community/group/notification-group/event/reminder-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for aggregate event series notifications.
fn sample_event_series_template_data() -> serde_json::Value {
    json!({
        "event_count": 2,
        "events": [
            {
                "event": {
                    "canceled": false,
                    "community_display_name": "Test Community",
                    "community_name": "test-community",
                    "event_id": "11111111-1111-1111-1111-111111111111",
                    "group_category_name": "Community",
                    "group_name": "Notification Group",
                    "group_slug": "notification-group",
                    "kind": "hybrid",
                    "logo_url": "https://example.com/logo.png",
                    "name": "Series Event One",
                    "published": true,
                    "slug": "series-event-one",
                    "starts_at": 1_914_724_800,
                    "timezone": "UTC",
                    "venue_name": "Conference Hall",
                    "waitlist_count": 0,
                    "waitlist_enabled": false
                },
                "link": "https://example.test/test-community/group/notification-group/event/series-event-one"
            },
            {
                "event": {
                    "canceled": false,
                    "community_display_name": "Test Community",
                    "community_name": "test-community",
                    "event_id": "22222222-2222-2222-2222-222222222222",
                    "group_category_name": "Community",
                    "group_name": "Notification Group",
                    "group_slug": "notification-group",
                    "kind": "hybrid",
                    "logo_url": "https://example.com/logo.png",
                    "name": "Series Event Two",
                    "published": true,
                    "slug": "series-event-two",
                    "starts_at": 1_915_329_600,
                    "timezone": "UTC",
                    "venue_name": "Conference Hall",
                    "waitlist_count": 0,
                    "waitlist_enabled": false
                },
                "link": "https://example.test/test-community/group/notification-group/event/series-event-two"
            }
        ],
        "group_name": "Notification Group",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for event waitlist notifications.
fn sample_event_waitlist_template_data() -> serde_json::Value {
    json!({
        "event": {
            "canceled": false,
            "community_display_name": "Test Community",
            "community_name": "test-community",
            "event_id": "11111111-1111-1111-1111-111111111111",
            "group_category_name": "Community",
            "group_name": "Notification Group",
            "group_slug": "notification-group",
            "kind": "virtual",
            "logo_url": "https://example.com/logo.png",
            "name": "Waitlist Event",
            "published": true,
            "slug": "waitlist-event",
            "starts_at": 1_914_724_800,
            "timezone": "UTC",
            "waitlist_count": 3,
            "waitlist_enabled": true
        },
        "link": "https://example.test/test-community/group/notification-group/event/waitlist-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for custom group notifications.
fn sample_group_custom_template_data() -> serde_json::Value {
    json!({
        "title": "Custom group title",
        "body": "Custom group body",
        "group": {
            "active": true,
            "category": {
                "group_category_id": "22222222-2222-2222-2222-222222222222",
                "name": "Sample Category",
                "normalized_name": "sample-category"
            },
            "community_display_name": "Test Community",
            "community_name": "test-community",
            "created_at": 1,
            "group_id": "33333333-3333-3333-3333-333333333333",
            "logo_url": "https://example.com/logo.png",
            "name": "Hello Group",
            "slug": "hello-group"
        },
        "link": "https://example.test/test-community/group/hello-group",
        "theme": {
            "primary_color": "#000000"
        }
    })
}
