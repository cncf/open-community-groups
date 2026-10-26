use std::{sync::Arc, time::Duration};

use anyhow::anyhow;
use chrono::{DateTime, Utc};
use mockall::Sequence;
use serde::de::DeserializeOwned;
use serde_json::json;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    config::{EmailConfig, SmtpConfig},
    db::{DynDB, mock::MockDB},
    templates::notifications::EventReminder,
    test_util::normalize_whitespace,
};

use super::{
    Attachment, DELIVERY_MAX_CLAIMS, DELIVERY_PROCESSING_TIMEOUT, DELIVERY_REQUEUE_BASE_DELAY,
    DELIVERY_REQUEUE_MAX_DELAY, DELIVERY_SEND_MAX_ATTEMPTS, DeliveryOutcome,
    DeliveryRecoveryWorker, DeliveryWorker, EmailDeliveryError, EmailSender, EnqueueWorker,
    LettreEmailSender, MockEmailSender, NewNotification, Notification, NotificationKind,
    NotificationsManager, PgNotificationsManager, SmtpErrorKind,
};

/// Deployment base URL used by notification rendering tests.
const TEST_BASE_URL: &str = "https://example.test";

#[tokio::test]
async fn test_notifications_manager_enqueue() {
    // Setup identifiers and data structures
    let recipient = Uuid::new_v4();
    let expected_recipients = vec![recipient];
    let notification = NewNotification {
        attachments: vec![],
        group_ids: vec![],
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
                && notif.template_data == Some(sample_email_verification_template_data())
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
    db.expect_enqueue_due_event_reminders().times(1).returning(|| Ok(2));
    db.expect_enqueue_due_event_survey_notifications()
        .times(1)
        .returning(|| Ok(3));

    // Enqueue due notifications
    let enqueued = sample_enqueue_worker(db).enqueue_due_notifications().await.unwrap();

    // Check both jobs are counted
    assert_eq!(enqueued, 5);
}

#[tokio::test]
async fn test_enqueue_worker_enqueue_due_notifications_returns_first_error_when_both_jobs_fail() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders()
        .times(1)
        .returning(|| Err(anyhow!("reminders error")));
    db.expect_enqueue_due_event_survey_notifications()
        .times(1)
        .returning(|| Err(anyhow!("surveys error")));

    // Enqueue due notifications
    let err = sample_enqueue_worker(db)
        .enqueue_due_notifications()
        .await
        .unwrap_err();

    // Check the reminders error is returned
    assert_eq!(err.to_string(), "reminders error");
}

#[tokio::test]
async fn test_enqueue_worker_enqueue_due_notifications_runs_reminders_when_surveys_fail() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders().times(1).returning(|| Ok(2));
    db.expect_enqueue_due_event_survey_notifications()
        .times(1)
        .returning(|| Err(anyhow!("surveys error")));

    // Enqueue due notifications
    let err = sample_enqueue_worker(db)
        .enqueue_due_notifications()
        .await
        .unwrap_err();

    // Check the surveys error is returned after the reminders job ran
    assert_eq!(err.to_string(), "surveys error");
}

#[tokio::test]
async fn test_enqueue_worker_enqueue_due_notifications_runs_surveys_when_reminders_fail() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_enqueue_due_event_reminders()
        .times(1)
        .returning(|| Err(anyhow!("reminders error")));
    db.expect_enqueue_due_event_survey_notifications()
        .times(1)
        .returning(|| Ok(3));

    // Enqueue due notifications
    let err = sample_enqueue_worker(db)
        .enqueue_due_notifications()
        .await
        .unwrap_err();

    // Check the reminders error is returned after the surveys job ran
    assert_eq!(err.to_string(), "reminders error");
}

#[tokio::test]
async fn test_delivery_recovery_worker_mark_stale_processing_notifications_unknown() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_mark_stale_processing_notifications_unknown()
        .times(1)
        .withf(|timeout| *timeout == DELIVERY_PROCESSING_TIMEOUT)
        .returning(|_| Ok(2));
    let db: DynDB = Arc::new(db);

    // Setup worker and recover stale processing notifications
    let worker = DeliveryRecoveryWorker {
        cancellation_token: CancellationToken::new(),
        db,
    };
    let recovered = worker.mark_stale_processing_notifications_unknown().await.unwrap();

    // Check result matches expectations
    assert_eq!(recovered, 2);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_sends_pending_notification() {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;
    let recipient = notification.email.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |notif, err| notif.notification_id == notification_id && err.is_none())
        .returning(|_, _| Ok(()));

    // Setup email sender mock expecting the rendered message
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .withf(move |message| {
            let formatted = String::from_utf8(message.formatted()).unwrap();
            message
                .envelope()
                .to()
                .iter()
                .any(|rcpt| rcpt.to_string() == recipient)
                && formatted.contains("Subject: Verify your email address")
        })
        .returning(|_| Box::pin(async { Ok::<(), EmailDeliveryError>(()) }));

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_sends_pending_notification_with_attachment() {
    // Setup identifiers and data structures
    let notification = Notification {
        attachments: vec![Attachment {
            content_type: "text/calendar".to_string(),
            data: b"BEGIN:VCALENDAR".to_vec(),
            file_name: "event.ics".to_string(),
        }],
        ..sample_pending_notification()
    };
    let notification_id = notification.notification_id;
    let recipient = notification.email.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |notif, err| notif.notification_id == notification_id && err.is_none())
        .returning(|_, _| Ok(()));

    // Setup email sender mock expecting the recipient and the attachment part
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .withf(move |message| {
            let formatted = String::from_utf8(message.formatted()).unwrap();
            message
                .envelope()
                .to()
                .iter()
                .any(|rcpt| rcpt.to_string() == recipient)
                && formatted.contains("Content-Type: multipart/mixed")
                && formatted.contains("Content-Type: text/calendar")
                && formatted.contains("Content-Disposition: attachment; filename=\"event.ics\"")
        })
        .returning(|_| Box::pin(async { Ok::<(), EmailDeliveryError>(()) }));

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_no_pending_notifications() {
    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification().times(1).returning(|| Ok(None));

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().never();

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(!delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_records_render_error() {
    // Setup a claimed notification whose content cannot be rendered
    let notification = Notification {
        template_data: None,
        ..sample_pending_notification()
    };
    let notification_id = notification.notification_id;

    // Setup database mock: the render failure is a terminal delivery outcome
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |notif, err| {
            notif.notification_id == notification_id
                && err.as_deref() == Some("missing template data")
        })
        .returning(|_, _| Ok(()));
    db.expect_mark_notification_delivery_unknown().never();
    db.expect_release_notification().never();
    db.expect_requeue_notification().never();

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().never();

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check the claim was consumed without sending
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_records_send_error() {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |notif, err| {
            notif.notification_id == notification_id && err.as_deref() == Some("delivery error")
        })
        .returning(|_, _| Ok(()));

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().times(1).returning(|_| {
        Box::pin(async { Err(EmailDeliveryError::Terminal(anyhow!("delivery error"))) })
    });

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_records_unknown_send_error() {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_mark_notification_delivery_unknown()
        .times(1)
        .withf(move |notif, err| {
            notif.notification_id == notification_id
                && err == "network error: connection reset by peer"
        })
        .returning(|_, _| Ok(()));
    db.expect_requeue_notification().never();
    db.expect_update_notification().never();

    // Setup email sender mock: an unknown outcome is never retried
    let mut es = MockEmailSender::new();
    es.expect_send().times(1).returning(|_| {
        Box::pin(async {
            Err(EmailDeliveryError::Unknown(anyhow!(
                "network error: connection reset by peer"
            )))
        })
    });

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test(start_paused = true)]
async fn test_delivery_worker_deliver_notification_releases_claim_when_cancelled_during_retry_pause()
 {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;

    // Setup database mock: shutdown is not a delivery outcome
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_release_notification()
        .times(1)
        .withf(move |notif| notif.notification_id == notification_id)
        .returning(|_| Ok(()));
    db.expect_mark_notification_delivery_unknown().never();
    db.expect_requeue_notification().never();
    db.expect_update_notification().never();

    // Setup email sender mock failing once with a retryable error
    let mut es = MockEmailSender::new();
    es.expect_send().times(1).returning(|_| {
        Box::pin(async {
            Err(EmailDeliveryError::Retryable(anyhow!(
                "Connection error: smtp unavailable"
            )))
        })
    });

    // Request shutdown while the worker waits to retry
    let worker = sample_delivery_worker(db, es);
    let shutdown_token = worker.cancellation_token.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(1)).await;
        shutdown_token.cancel();
    });

    // Deliver notification
    let delivered = worker.deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test(start_paused = true)]
async fn test_delivery_worker_deliver_notification_requeues_retryable_send_error() {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_requeue_notification()
        .times(1)
        .withf(
            move |notif, err, base_retry_after, max_retry_after, max_delivery_attempts| {
                notif.notification_id == notification_id
                    && err == "Connection error: smtp unavailable"
                    && *base_retry_after == DELIVERY_REQUEUE_BASE_DELAY
                    && *max_retry_after == DELIVERY_REQUEUE_MAX_DELAY
                    && *max_delivery_attempts == DELIVERY_MAX_CLAIMS
            },
        )
        .returning(|_, _, _, _, _| Ok(()));
    db.expect_update_notification().never();

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().times(DELIVERY_SEND_MAX_ATTEMPTS).returning(|_| {
        Box::pin(async {
            Err(EmailDeliveryError::Retryable(anyhow!(
                "Connection error: smtp unavailable"
            )))
        })
    });

    // Setup worker and deliver notification
    let delivered = sample_delivery_worker(db, es).deliver_notification().await.unwrap();

    // Check result matches expectations
    assert!(delivered);
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_returns_unknown_update_error() {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_mark_notification_delivery_unknown()
        .times(1)
        .withf(move |notif, err| {
            notif.notification_id == notification_id
                && err == "network error: connection reset by peer"
        })
        .returning(|_, _| Err(anyhow!("unknown update error")));
    db.expect_requeue_notification().never();
    db.expect_update_notification().never();

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().times(1).returning(|_| {
        Box::pin(async {
            Err(EmailDeliveryError::Unknown(anyhow!(
                "network error: connection reset by peer"
            )))
        })
    });

    // Setup worker and deliver notification
    let err = sample_delivery_worker(db, es)
        .deliver_notification()
        .await
        .unwrap_err();

    // Check the persistence error is propagated
    assert_eq!(err.to_string(), "unknown update error");
}

#[tokio::test]
async fn test_delivery_worker_deliver_notification_returns_update_error() {
    // Setup identifiers and data structures
    let notification = sample_pending_notification();
    let notification_id = notification.notification_id;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_claim_pending_notification()
        .times(1)
        .returning(move || Ok(Some(notification.clone())));
    db.expect_update_notification()
        .times(1)
        .withf(move |notif, err| notif.notification_id == notification_id && err.is_none())
        .returning(|_, _| Err(anyhow!("update error")));

    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send()
        .times(1)
        .returning(|_| Box::pin(async { Ok::<(), EmailDeliveryError>(()) }));

    // Setup worker and deliver notification
    let err = sample_delivery_worker(db, es)
        .deliver_notification()
        .await
        .unwrap_err();

    // Check the persistence error is propagated
    assert_eq!(err.to_string(), "update error");
}

#[test]
fn test_delivery_worker_prepare_content_badge_awarded() {
    // Setup atomic database-enqueued template data with relative URLs
    let template_data = json!({
        "badge": {
            "criteria": "Attend the event",
            "description": "Recognizes participation",
            "image_file_name": "badge.png",
            "issuer": {
                "community_id": "00000000-0000-0000-0000-000000000001",
                "community_name": "Test Community",
                "group_id": "00000000-0000-0000-0000-000000000002",
                "group_name": "Test Group"
            },
            "name": "Participant"
        },
        "dashboard_url": "/dashboard/user?tab=badges",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content with deployment-specific URL context
    let (subject, body) = render(NotificationKind::BadgeAwarded, template_data);

    // Check badge content and links are rendered from the typed template
    assert_eq!(subject, "[Test Group] You earned the Participant badge");
    assert!(body.contains("Recognizes participation"));
    assert!(body.contains("Attend the event"));
    assert!(body.contains("Test Group"));
    assert!(body.contains("https://example.test/dashboard/user?tab=badges"));
    assert!(body.contains("https://example.test/images/badges/badge.png"));
}

#[test]
fn test_delivery_worker_prepare_content_badge_revoked_omits_reason() {
    // Setup atomic database-enqueued template data with a relative dashboard URL
    let template_data = json!({
        "badge_name": "Participant",
        "dashboard_url": "/dashboard/user?tab=badges",
        "group_name": "Test Group",
        "revocation_reason": "private audit detail",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content with deployment-specific URL context
    let (subject, body) = render(NotificationKind::BadgeRevoked, template_data);

    // Check the public typed fields render without the private revocation reason
    assert_eq!(subject, "[Test Group] Your Participant badge was revoked");
    assert!(body.contains("permanently revoked"));
    assert!(body.contains("Contact Test Group"));
    assert!(body.contains("https://example.test/dashboard/user?tab=badges"));
    assert!(!body.contains("private audit detail"));
}

#[test]
fn test_delivery_worker_prepare_content_cfs_submission_updated() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::CfsSubmissionUpdated,
        sample_cfs_submission_updated_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] Submission update: Reminder Event"
    );
    assert!(body.contains("Reminder Event"));
}

#[test]
fn test_delivery_worker_prepare_content_community_custom() {
    // Setup template data
    let template_data = json!({
        "body": "Custom community body",
        "community_display_name": "Test Community",
        "link": "https://example.test/test-community",
        "subject": "Custom community subject",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content
    let (subject, body) = render(NotificationKind::CommunityCustom, template_data);

    // Check content matches expectations
    assert_eq!(subject, "Custom community subject");
    assert!(body.contains("Custom community body"));
    assert!(body.contains("Visit community page"));
    assert!(body.contains("https://example.test/test-community"));
    assert!(
        body.contains("You received this email because you're on the team of one or more groups")
    );
    assert!(body.contains("Test Community community"));
}

#[test]
fn test_delivery_worker_prepare_content_community_team_invitation() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::CommunityTeamInvitation,
        sample_community_team_invitation_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Test Community] You have been invited to join a community team"
    );
    assert!(body.contains("Test Community"));
}

#[test]
fn test_delivery_worker_prepare_content_email_verification() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EmailVerification,
        sample_email_verification_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "Verify your email address");
    assert!(body.contains("Verify your email"));
    assert!(body.contains("https://example.test/verify"));
}

#[test]
fn test_delivery_worker_prepare_content_event_admission_offer_canceled() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventAdmissionOfferCanceled,
        sample_event_admission_offer_canceled_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Enrollment Group] Your event offer was canceled");
    assert!(body.contains("Enrollment Event"));
    assert!(body.contains("General admission"));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_admission_offer_created() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventAdmissionOfferCreated,
        sample_event_admission_offer_created_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Enrollment Group] You have a new event offer");
    assert!(body.contains("Complete the required registration questions"));
    assert!(body.contains("General admission"));
    assert!(body.contains("USD 25.00"));
    assert!(body.contains("No charge or registration has occurred"));
    assert!(body.contains("price is finalized when you first claim"));
    assert!(body.contains("Sep 04, 2030 at 06:00 CEST"));
    assert!(body.contains(
        "https://example.test/dashboard/user?tab=invitations#event-offer-11111111-1111-1111-1111-111111111111"
    ));
}

#[test]
fn test_delivery_worker_prepare_content_event_admission_offer_created_without_rsvp_flag() {
    // Setup a queued payload created before RSVP classification was persisted
    let mut template_data = sample_event_admission_offer_created_template_data();
    remove_keys(&mut template_data, &["is_simple_rsvp"]);

    // Prepare the legacy notification payload
    let (subject, body) = render(NotificationKind::EventAdmissionOfferCreated, template_data);

    // Check legacy payloads retain ticket-offer wording
    assert_eq!(subject, "[Enrollment Group] You have a new event offer");
    assert!(body.contains("General admission"));
}

#[test]
fn test_delivery_worker_prepare_content_event_admission_offer_created_without_ticket_for_rsvp() {
    // Setup a simple-RSVP organizer offer
    let mut template_data = sample_event_admission_offer_created_template_data();
    template_data["amount_minor"] = serde_json::Value::Null;
    template_data["currency_code"] = serde_json::Value::Null;
    template_data["is_simple_rsvp"] = json!(true);
    template_data["registration_questions_required"] = json!(false);
    template_data["ticket_title"] = serde_json::Value::Null;

    // Prepare the RSVP notification
    let (subject, body) = render(NotificationKind::EventAdmissionOfferCreated, template_data);

    // Check neutral subject and RSVP-specific body copy
    assert_eq!(subject, "[Enrollment Group] You have a new event offer");
    assert!(body.contains("Event offer"));
    assert!(body.contains("No charge or registration has occurred"));
    assert!(!body.contains("Your assigned ticket"));
    assert!(!body.contains("price is finalized when you first claim"));
}

#[test]
fn test_delivery_worker_prepare_content_event_admission_offer_declined() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventAdmissionOfferDeclined,
        sample_event_admission_offer_declined_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Enrollment Group] Event offer declined");
    assert!(body.contains("Example Recipient"));
    assert!(body.contains("General admission"));
    assert!(body.contains("https://example.test/dashboard/group?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_attendance_canceled() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventAttendanceCanceled,
        sample_event_attendance_canceled_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Attendance canceled");
    assert!(body.contains("Your attendance for"));
    assert!(body.contains("Reminder Event"));
    assert!(body.contains("Open My Events"));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_canceled() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventCanceled,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Event canceled");
    assert!(body.contains("Reminder Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_cohost_invitation() {
    // Setup template data
    let template_data = json!({
        "cohost_community_display_name": "Cohost Community",
        "cohost_group_name": "Cohost Group",
        "events": [
            {"name": "Co-hosted One", "starts_at": 1_914_724_800, "timezone": "UTC"},
            {"name": "Co-hosted Two", "timezone": "UTC"}
        ],
        "link": "https://example.test/dashboard/group?tab=cohosts",
        "owner_community_display_name": "Owner Community",
        "owner_group_name": "Owner Group",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content
    let (subject, body) = render(NotificationKind::EventCohostInvitation, template_data);

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Cohost Group] Owner Group invited your group to co-host"
    );
    assert!(body.contains("Co-hosted One"));
    assert!(body.contains("Co-hosted Two"));
    assert!(body.contains("Each event is approved separately."));
    assert!(body.contains("https://example.test/dashboard/group?tab=cohosts"));
    assert!(body.contains("your group gets no access to it"));
}

#[test]
fn test_delivery_worker_prepare_content_event_cohost_removed_for_deleted_events() {
    // Setup template data
    let template_data = json!({
        "cohost_group_name": "Cohost Group",
        "events": [{"name": "Deleted Event", "timezone": "UTC"}],
        "owner_community_display_name": "Owner Community",
        "owner_group_name": "Owner Group",
        "reason": "event-deleted",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content
    let (subject, body) = render(NotificationKind::EventCohostRemoved, template_data);

    // Check content matches expectations
    assert_eq!(subject, "[Cohost Group] Co-hosted events deleted");
    assert!(body.contains("Deleted Event"));
    assert!(body.contains("deleted"));
    assert!(!body.contains("View co-hosted events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_cohost_removed_by_organizer() {
    // Setup template data
    let template_data = json!({
        "cohost_group_name": "Cohost Group",
        "events": [{"name": "Removed Event", "timezone": "UTC"}],
        "link": "https://example.test/dashboard/group?tab=cohosts",
        "owner_community_display_name": "Owner Community",
        "owner_group_name": "Owner Group",
        "reason": "removed",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content
    let (subject, body) = render(NotificationKind::EventCohostRemoved, template_data);

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Cohost Group] Your group was removed as a co-host"
    );
    assert!(body.contains("Removed Event"));
    assert!(body.contains("View co-hosted events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_cohost_responded() {
    // Setup template data
    let template_data = json!({
        "cohost_community_display_name": "Cohost Community",
        "cohost_group_name": "Cohost Group",
        "event": {"name": "Owner Event", "starts_at": 1_914_724_800, "timezone": "UTC"},
        "link": "https://example.test/dashboard/group?tab=events",
        "owner_group_name": "Owner Group",
        "status": "rejected",
        "theme": {"primary_color": "#000000"}
    });

    // Prepare content
    let (subject, body) = render(NotificationKind::EventCohostResponded, template_data);

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Owner Group] Cohost Group declined co-hosting Owner Event"
    );
    assert!(body.contains("rejected co-hosting"));
    assert!(body.contains("once every co-host has responded"));
}

#[test]
fn test_delivery_worker_prepare_content_event_custom() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventCustom,
        sample_event_custom_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "Custom event subject");
    assert!(body.contains("Custom event subject"));
    assert!(body.contains("Custom event body"));
    assert!(body.contains("You received this email notification because you're a member of"));
    assert!(body.contains("Notification Group"));
    assert!(body.contains("Test Community community"));
}

#[test]
fn test_delivery_worker_prepare_content_event_custom_legacy_template_data() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventCustom,
        sample_event_custom_legacy_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "Custom event title");
    assert!(body.contains("Custom event title"));
    assert!(body.contains("Custom event body"));
}

#[test]
fn test_delivery_worker_prepare_content_event_invitation() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventInvitation,
        sample_event_invitation_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] You have been invited to an event"
    );
    assert!(body.contains("Invitation Event"));
    assert!(body.contains("Review invitation"));
    assert!(body.contains("LF SSO"));
    assert!(body.contains("primary email configured on your LF account"));
    assert!(body.contains("https://example.test/dashboard/user?tab=invitations"));
}

#[test]
fn test_delivery_worker_prepare_content_event_paid_configured_plural() {
    // Prepare an aggregate paid event notification
    let (subject, body) = render(
        NotificationKind::EventPaidConfigured,
        sample_event_paid_configured_template_data(2),
    );

    // Check plural subject and link-free admin copy
    assert_eq!(subject, "[Notification Group] Paid events configured");
    assert!(body.contains("Paid Event One"));
    assert!(body.contains("Paid Event Two"));
    assert!(body.contains("January  1, 2021"));
    assert!(!body.contains("January  1, 2020"));
    assert!(body.contains("you're an admin of the Test Community community"));
    assert!(!body.contains("href="));
}

#[test]
fn test_delivery_worker_prepare_content_event_paid_configured_singular() {
    // Prepare a single paid event notification
    let (subject, body) = render(
        NotificationKind::EventPaidConfigured,
        sample_event_paid_configured_template_data(1),
    );

    // Check singular subject and event details
    assert_eq!(subject, "[Notification Group] Paid event configured");
    assert!(body.contains("Paid Event One"));
    assert!(!body.contains("Paid Event Two"));
}

#[test]
fn test_delivery_worker_prepare_content_event_paid_configured_without_start() {
    // Setup paid event notification without an event start
    let mut template_data = sample_event_paid_configured_template_data(1);
    remove_keys(&mut template_data["events"][0], &["starts_at"]);

    // Prepare content
    let (subject, body) = render(NotificationKind::EventPaidConfigured, template_data);

    // Check the optional start is omitted without blocking delivery
    assert_eq!(subject, "[Notification Group] Paid event configured");
    assert!(body.contains("Paid Event One"));
    assert!(!body.contains("January"));
}

#[test]
fn test_delivery_worker_prepare_content_event_published() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventPublished,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] New event published");
    assert!(body.contains("You received this email notification because you're a member of"));
    assert!(body.contains("Notification Group"));
    assert!(body.contains("Test Community community"));
}

#[test]
fn test_delivery_worker_prepare_content_event_published_for_cohost_audience() {
    // Setup a co-host copy of the notification with credited co-hosts
    let mut template_data = sample_event_reminder_template_data();
    template_data["cohost_group_name"] = json!("Cohost Group");
    template_data["event"]["cohosts"] = json!([{
        "community_display_name": "Cohost Community",
        "community_name": "cohost-community",
        "group_id": "33333333-3333-3333-3333-333333333333",
        "logo_url": "https://example.com/cohost.png",
        "name": "Cohost Group",
        "slug": "cohost-group"
    }]);

    // Prepare content
    let (subject, body) = render(NotificationKind::EventPublished, template_data);

    // Check content matches expectations
    assert_eq!(subject, "[Cohost Group] New event published");
    assert!(body.contains("Co-hosted by: Cohost Group"));
    assert!(body.contains("which co-hosts this event with Notification Group"));
}

#[test]
fn test_delivery_worker_prepare_content_event_refund_approved() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventRefundApproved,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Refund approved");
    assert!(body.contains("Reminder Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_refund_rejected() {
    // Setup notification with attendee-visible organizer text
    let mut template_data = sample_event_reminder_template_data();
    template_data["rejection_reason"] = json!("Not eligible\n<script>alert('xss')</script>");

    // Prepare content
    let (subject, body) = render(NotificationKind::EventRefundRejected, template_data);

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Refund request update");
    assert!(body.contains("Reminder Event"));
    assert!(body.contains("Not eligible"));
    assert!(body.contains("&#60;script&#62;alert(&#39;xss&#39;)&#60;/script&#62;"));
    assert!(!body.contains("<script>"));
}

#[test]
fn test_delivery_worker_prepare_content_event_refund_requested() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventRefundRequested,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Refund requested");
    assert!(body.contains("Reminder Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventReminder,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] Reminder: Reminder Event starts in 24 hours"
    );
    assert!(body.contains("Reminder Event"));
    assert!(body.contains("Use your registration name when joining."));
    assert!(body.contains("If you can no longer attend"));
    assert!(
        body.contains(
            "You received this email notification because you're attending or speaking at"
        )
    );
    assert!(body.contains("Notification Group"));
    assert!(body.contains("Test Community community"));
    assert!(body.contains(
        "https://example.test/test-community/group/notification-group/event/reminder-event"
    ));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder_legacy_template_data() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventReminder,
        sample_event_reminder_legacy_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] Reminder: Reminder Event starts in 24 hours"
    );
    assert!(body.contains("Reminder Event"));
    assert!(body.contains(
        "https://example.test/test-community/group/notification-group/event/reminder-event"
    ));
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder_legacy_zip_code_template_data() {
    // Setup a legacy payload using the old zip code key
    let template_data = sample_event_reminder_legacy_zip_code_template_data();

    // Prepare content
    let (subject, body) = render(NotificationKind::EventReminder, template_data.clone());

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] Reminder: Reminder Event starts in 24 hours"
    );
    assert!(body.contains("Reminder Event"));

    // Check the legacy zip code key reads into the venue zip code
    let template: EventReminder = serde_json::from_value(template_data).unwrap();
    assert_eq!(template.event.venue_zip_code.as_deref(), Some("10001"));
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder_relative_links() {
    // Setup a reminder payload with links stored relative to the site root
    let mut template_data = sample_event_reminder_template_data();
    template_data["dashboard_link"] = json!("/dashboard/user?tab=events");
    template_data["link"] = json!("/test-community/group/notification-group/event/reminder-event");

    // Prepare content
    let (subject, body) = render(NotificationKind::EventReminder, template_data);

    // Check the links are completed with the deployment base URL
    assert_eq!(
        subject,
        "[Notification Group] Reminder: Reminder Event starts in 24 hours"
    );
    assert!(body.contains(
        "https://example.test/test-community/group/notification-group/event/reminder-event"
    ));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_reminder_speaker_only() {
    // Setup a reminder for a speaker, who has no attendance to cancel
    let mut template_data = sample_event_reminder_template_data();
    template_data["show_attendance_cancellation_copy"] = json!(false);

    // Prepare content
    let (subject, body) = render(NotificationKind::EventReminder, template_data);

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] Reminder: Reminder Event starts in 24 hours"
    );
    assert!(body.contains("You can review this event from the My Events section"));
    assert!(!body.contains("If you can no longer attend"));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_rescheduled() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventRescheduled,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Event rescheduled");
    assert!(body.contains("Reminder Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_series_canceled() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventSeriesCanceled,
        sample_event_series_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Events canceled");
    assert!(body.contains("2 events from"));
    assert!(body.contains("Series Event One"));
    assert!(body.contains("Series Event Two"));
}

#[test]
fn test_delivery_worker_prepare_content_event_series_published() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventSeriesPublished,
        sample_event_series_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] New events published");
    assert!(body.contains("2 new events"));
    assert!(body.contains("Series Event One"));
    assert!(body.contains("Series Event Two"));
    assert!(body.contains("You received this email notification because you're a member of"));
    assert!(body.contains("Notification Group"));
    assert!(body.contains("Test Community community"));
}

#[test]
fn test_delivery_worker_prepare_content_event_series_published_for_cohost_audience() {
    // Setup a co-host copy of the aggregate notification
    let mut template_data = sample_event_series_template_data();
    template_data["cohost_group_name"] = json!("Cohost Group");

    // Prepare content
    let (subject, body) = render(NotificationKind::EventSeriesPublished, template_data);

    // Check content matches expectations
    assert_eq!(subject, "[Cohost Group] New events published");
    assert!(body.contains("which co-hosts these events with Notification Group"));
}

#[test]
fn test_delivery_worker_prepare_content_event_survey_opened() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventSurveyOpened,
        sample_event_survey_opened_template_data(),
    );

    // Check content matches expectations
    let body = normalize_whitespace(&body);
    assert_eq!(
        subject,
        "[Notification Group] Share your feedback on Survey Event"
    );
    assert!(body.contains("feedback in the <strong>Session feedback</strong> survey"));
    assert!(body.contains("This survey is anonymous"));
    assert!(!body.contains("Organizers will see your name"));
    assert!(body.contains("until <strong>Sep 11, 2030 at 06:00 CEST</strong>"));
    assert!(body.contains("Answer survey"));
    assert!(body.contains(
        "https://example.test/dashboard/user?tab=surveys&#38;event_survey_id=55555555-5555-5555-5555-555555555555"
    ));
    assert!(body.contains(
        "You received this email notification because you registered for Survey Event, an \
         event from Notification Group in the Test Community community."
    ));
}

#[test]
fn test_delivery_worker_prepare_content_event_survey_opened_identified_without_optional_fields() {
    // Setup an identified survey payload without a closing date
    let mut template_data = sample_event_survey_opened_template_data();
    template_data["anonymous"] = json!(false);
    remove_keys(&mut template_data, &["closes_at"]);

    // Prepare content
    let (subject, body) = render(NotificationKind::EventSurveyOpened, template_data);

    // Check content matches expectations
    let body = normalize_whitespace(&body);
    assert_eq!(
        subject,
        "[Notification Group] Share your feedback on Survey Event"
    );
    assert!(body.contains("Organizers will see your name next to your answers."));
    assert!(!body.contains("This survey is anonymous"));
    assert!(body.contains("You can edit your answers until the survey closes."));
    assert!(!body.contains("CEST"));
}

#[test]
fn test_delivery_worker_prepare_content_event_ticket_request_approved() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventTicketRequestApproved,
        sample_event_ticket_offer_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Enrollment Group] Your event request was approved"
    );
    assert!(body.contains("approved your request"));
    assert!(body.contains("General admission"));
    assert!(body.contains("USD 25.00"));
    assert!(body.contains("No charge or registration has occurred"));
    assert!(body.contains("price is finalized when you first claim"));
    assert!(body.contains("Sep 04, 2030 at 06:00 CEST"));
    assert!(body.contains(
        "https://example.test/dashboard/user?tab=invitations#event-offer-11111111-1111-1111-1111-111111111111"
    ));
}

#[test]
fn test_delivery_worker_prepare_content_event_ticket_request_approved_without_rsvp_flag() {
    // Setup a queued payload created before RSVP classification was persisted
    let mut template_data = sample_event_ticket_offer_template_data();
    remove_keys(&mut template_data, &["is_simple_rsvp"]);

    // Prepare the legacy notification payload
    let (subject, body) = render(NotificationKind::EventTicketRequestApproved, template_data);

    // Check legacy payloads retain ticket-specific body copy
    assert_eq!(
        subject,
        "[Enrollment Group] Your event request was approved"
    );
    assert!(body.contains("General admission"));
}

#[test]
fn test_delivery_worker_prepare_content_event_ticket_request_approved_without_ticket_for_rsvp() {
    // Setup a simple-RSVP approval payload
    let mut template_data = sample_free_event_ticket_offer_template_data();
    template_data["is_simple_rsvp"] = json!(true);

    // Prepare the RSVP notification
    let (subject, body) = render(NotificationKind::EventTicketRequestApproved, template_data);

    // Check neutral subject and RSVP-specific body copy
    assert_eq!(
        subject,
        "[Enrollment Group] Your event request was approved"
    );
    assert!(body.contains("Event request approved"));
    assert!(!body.contains("General admission"));
    assert!(!body.contains("price is finalized when you first claim"));
}

#[test]
fn test_delivery_worker_prepare_content_event_ticket_waitlist_offer() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventTicketWaitlistOffer,
        sample_free_event_ticket_offer_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Enrollment Group] A place is available for you");
    assert!(body.contains("A seat opened"));
    assert!(body.contains("General admission"));
    assert!(body.contains("<strong>Free</strong>"));
    assert!(body.contains("No charge or registration has occurred"));
    assert!(body.contains("price is finalized when you first claim"));
    assert!(body.contains("Sep 04, 2030 at 06:00 CEST"));
    assert!(body.contains(
        "https://example.test/dashboard/user?tab=invitations#event-offer-11111111-1111-1111-1111-111111111111"
    ));
}

#[test]
fn test_delivery_worker_prepare_content_event_ticket_waitlist_offer_without_rsvp_flag() {
    // Setup a queued payload created before RSVP classification was persisted
    let mut template_data = sample_free_event_ticket_offer_template_data();
    remove_keys(&mut template_data, &["is_simple_rsvp"]);

    // Prepare the legacy notification payload
    let (subject, body) = render(NotificationKind::EventTicketWaitlistOffer, template_data);

    // Check legacy payloads retain ticket-specific body copy
    assert_eq!(subject, "[Enrollment Group] A place is available for you");
    assert!(body.contains("General admission"));
}

#[test]
fn test_delivery_worker_prepare_content_event_ticket_waitlist_offer_without_ticket_for_rsvp() {
    // Setup a simple-RSVP waitlist payload
    let mut template_data = sample_free_event_ticket_offer_template_data();
    template_data["is_simple_rsvp"] = json!(true);

    // Prepare the RSVP notification
    let (subject, body) = render(NotificationKind::EventTicketWaitlistOffer, template_data);

    // Check neutral subject and RSVP-specific body copy
    assert_eq!(subject, "[Enrollment Group] A place is available for you");
    assert!(body.contains("Place available"));
    assert!(!body.contains("General admission"));
    assert!(!body.contains("price is finalized when you first claim"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_joined() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventWaitlistJoined,
        sample_event_waitlist_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] You joined the waiting list");
    assert!(body.contains("You have been added to the waiting list"));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_left() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventWaitlistLeft,
        sample_event_waitlist_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] You left the waiting list");
    assert!(body.contains("You have left the waiting list"));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_promoted() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventWaitlistPromoted,
        sample_event_waitlist_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] You moved off the waiting list"
    );
    assert!(body.contains("You are now registered"));
    assert!(body.contains("View event"));
    assert!(!body.contains("Open My Events"));
    assert!(body.contains("Use the waiting room display name from your ticket."));
    assert!(body.contains("Please find attached an .ics file containing the event details."));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_waitlist_promoted_with_registration_questions() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventWaitlistPromoted,
        sample_event_waitlist_template_data_with_registration_questions(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] You moved off the waiting list"
    );
    assert!(body.contains("Open My Events"));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
    assert!(!body.contains(
        "https://example.test/test-community/group/notification-group/event/waitlist-event"
    ));
    assert!(!body.contains("https://example.test/waitlist-event/live"));
    assert!(!body.contains("Use the waiting room display name from your ticket."));
    assert!(!body.contains("Please find attached an .ics file containing the event details."));
    assert!(body.contains("Waitlist Event"));
}

#[test]
fn test_delivery_worker_prepare_content_event_welcome_omits_dashboard_cancellation_guidance() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::EventWelcome,
        sample_event_welcome_template_data(None),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Welcome to the event");
    assert!(body.contains("Welcome Event"));
    assert!(!body.contains("cancel your attendance from the My"));
    assert!(!body.contains("Open My Events"));
}

#[test]
fn test_delivery_worker_prepare_content_event_welcome_renders_dashboard_cancellation_guidance() {
    // Setup template data
    let template_data =
        sample_event_welcome_template_data(Some("https://example.test/dashboard/user?tab=events"));

    // Prepare content
    let (subject, body) = render(NotificationKind::EventWelcome, template_data);

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] Welcome to the event");
    assert!(body.contains("cancel your attendance from the My"));
    assert!(body.contains("Open My Events"));
    assert!(body.contains("https://example.test/dashboard/user?tab=events"));
}

#[test]
fn test_delivery_worker_prepare_content_footer_points_to_notification_preferences() {
    // Prepare content
    let (_, body) = render(
        NotificationKind::EventPublished,
        sample_event_reminder_template_data(),
    );

    // Check the footer explains where preferences are managed
    let body = normalize_whitespace(&body);
    assert!(body.contains(
        "You can choose which optional emails you receive, and mute specific groups, from the \
         Notifications section of your user dashboard."
    ));
    assert!(!body.contains("Profile section"));
}

#[test]
fn test_delivery_worker_prepare_content_group_custom() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::GroupCustom,
        sample_group_custom_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "Custom group subject");
    assert!(body.contains("Custom group subject"));
    assert!(body.contains("Custom group body"));
    assert!(body.contains("You received this email notification because you're a member of"));
    assert!(body.contains("Hello Group"));
    assert!(body.contains("Test Community community"));
}

#[test]
fn test_delivery_worker_prepare_content_group_custom_legacy_template_data() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::GroupCustom,
        sample_group_custom_legacy_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "Custom group title");
    assert!(body.contains("Custom group title"));
    assert!(body.contains("Custom group body"));
}

#[test]
fn test_delivery_worker_prepare_content_group_team_invitation() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::GroupTeamInvitation,
        sample_group_custom_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Hello Group] You have been invited to join a group team"
    );
    assert!(body.contains("Hello Group"));
}

#[test]
fn test_delivery_worker_prepare_content_group_welcome() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::GroupWelcome,
        sample_group_custom_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Hello Group] Welcome to the group");
    assert!(body.contains("Hello Group"));
}

#[test]
fn test_delivery_worker_prepare_content_inbox_message_received() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::InboxMessageReceived,
        sample_inbox_message_received_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Inbox Group] New message from Uma User");
    assert!(body.contains("Is there parking &#60;nearby&#62;?"));
    assert!(body.contains("about <strong>Inbox Event</strong>"));
    assert!(body.contains("select Inbox Group first if you manage"));
    assert!(body.contains("Messages sent to this email"));
    assert!(body.contains(
        "https://example.test/dashboard/group?tab=inbox&#38;conversation_id=44444444-4444-4444-4444-444444444444"
    ));
    assert!(body.contains("View conversation"));
}

#[test]
fn test_delivery_worker_prepare_content_inbox_message_received_without_event() {
    // Setup notification without the removed event
    let mut template_data = sample_inbox_message_received_template_data();
    remove_keys(&mut template_data, &["event_name"]);

    // Prepare content
    let (subject, body) = render(NotificationKind::InboxMessageReceived, template_data);

    // Check content matches expectations
    assert_eq!(subject, "[Inbox Group] New message from Uma User");
    assert!(body.contains("Is there parking &#60;nearby&#62;?"));
    assert!(!body.contains("Inbox Event"));
}

#[test]
fn test_delivery_worker_prepare_content_inbox_reply_received() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::InboxReplyReceived,
        sample_inbox_reply_received_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Inbox Group] New reply to your message");
    assert!(body.contains("Yes, there is a car park."));
    assert!(body.contains("about <strong>Inbox Event</strong>"));
    assert!(body.contains("To continue the conversation, use the Inbox in your dashboard."));
    assert!(body.contains(
        "https://example.test/dashboard/user?tab=inbox&#38;conversation_id=44444444-4444-4444-4444-444444444444"
    ));
}

#[test]
fn test_delivery_worker_prepare_content_missing_data() {
    // Setup notification without template data
    let notification = Notification {
        template_data: None,
        ..sample_pending_notification()
    };

    // Prepare content and expect an error
    let err = DeliveryWorker::prepare_content(&notification, TEST_BASE_URL).unwrap_err();

    // Check error message
    assert_eq!(err.to_string(), "missing template data");
}

#[test]
fn test_delivery_worker_prepare_content_speaker_series_welcome() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::SpeakerSeriesWelcome,
        sample_event_series_template_data(),
    );

    // Check content matches expectations
    assert_eq!(
        subject,
        "[Notification Group] You're speaking at upcoming events"
    );
    assert!(body.contains("2 events with"));
    assert!(body.contains("Join five minutes early for speaker setup."));
    assert!(body.contains("Series Event One"));
    assert!(body.contains("Series Event Two"));
}

#[test]
fn test_delivery_worker_prepare_content_speaker_welcome() {
    // Prepare content
    let (subject, body) = render(
        NotificationKind::SpeakerWelcome,
        sample_event_reminder_template_data(),
    );

    // Check content matches expectations
    assert_eq!(subject, "[Notification Group] You're speaking at an event");
    assert!(body.contains("Reminder Event"));
}

#[tokio::test]
async fn test_delivery_worker_send_email_allows_whitelisted_recipient() {
    // Setup email sender mock
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
        .returning(|_| Box::pin(async { Ok::<(), EmailDeliveryError>(()) }));

    // Setup worker with a recipients whitelist and send email
    let worker = DeliveryWorker {
        cfg: sample_email_config(Some(vec!["notify@example.test".to_string()])),
        ..sample_delivery_worker(MockDB::new(), es)
    };
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
    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().never();

    // Setup worker with a recipients whitelist and send email
    let worker = DeliveryWorker {
        cfg: sample_email_config(Some(vec!["notify@example.test".to_string()])),
        ..sample_delivery_worker(MockDB::new(), es)
    };
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

#[tokio::test]
async fn test_delivery_worker_send_email_rejects_invalid_recipient_as_terminal() {
    // Setup email sender mock
    let mut es = MockEmailSender::new();
    es.expect_send().never();

    // Setup worker and send an invalid message
    let worker = sample_delivery_worker(MockDB::new(), es);
    let err = worker
        .send_email(
            "invalid recipient",
            "Subject line",
            "<p>Body content</p>".to_string(),
            &[],
        )
        .await
        .unwrap_err();

    // Check message construction failures are terminal
    assert!(matches!(err, EmailDeliveryError::Terminal(_)));
}

#[tokio::test(start_paused = true)]
async fn test_delivery_worker_send_email_retries_transient_send_error() {
    // Setup email sender mock
    let mut es = MockEmailSender::new();
    let mut seq = Sequence::new();
    es.expect_send().times(1).in_sequence(&mut seq).returning(|_| {
        Box::pin(async {
            Err(EmailDeliveryError::Retryable(anyhow!(
                "Connection error: received fatal alert: UnexpectedMessage"
            )))
        })
    });
    es.expect_send()
        .times(1)
        .in_sequence(&mut seq)
        .returning(|_| Box::pin(async { Ok(()) }));

    // Setup worker and send email
    let worker = sample_delivery_worker(MockDB::new(), es);
    let outcome = worker
        .send_email_with_retries(
            "notify@example.test",
            "Subject line",
            "<p>Body content</p>".to_string(),
            &[],
        )
        .await
        .unwrap();

    // Check the retried send completed
    assert_eq!(outcome, DeliveryOutcome::Delivered);
}

#[test]
fn test_email_delivery_error_classifies_smtp_kinds() {
    // Setup every SMTP failure kind with its safe recovery action
    let cases = [
        (SmtpErrorKind::Client, "terminal"),
        (SmtpErrorKind::Connection, "retryable"),
        (SmtpErrorKind::Permanent, "terminal"),
        (SmtpErrorKind::Tls, "terminal"),
        (SmtpErrorKind::Transient, "retryable"),
        (SmtpErrorKind::TransportShutdown, "retryable"),
        (SmtpErrorKind::Unknown, "unknown"),
    ];

    // Check each kind maps to its recovery action and keeps the source error
    for (kind, expected) in cases {
        let err = EmailDeliveryError::from_smtp_kind(kind, anyhow!("smtp failure"));
        let action = match &err {
            EmailDeliveryError::Retryable(_) => "retryable",
            EmailDeliveryError::Terminal(_) => "terminal",
            EmailDeliveryError::Unknown(_) => "unknown",
        };
        assert_eq!(action, expected, "{kind:?}");
        assert_eq!(err.to_string(), "smtp failure", "{kind:?}");
    }
}

#[tokio::test]
async fn test_lettre_email_sender_classifies_stalled_delivery_as_unknown() {
    // Setup an SMTP endpoint that accepts connections and never sends its greeting
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        // Keep every accepted connection open without writing a response
        let mut connections = Vec::new();
        loop {
            let (stream, _) = listener.accept().await.unwrap();
            connections.push(stream);
        }
    });

    // Setup a sender with a one second delivery deadline against that endpoint
    let mut cfg = sample_email_config(None);
    cfg.smtp.host = address.ip().to_string();
    cfg.smtp.port = address.port();
    cfg.smtp.send_timeout_secs = 1;
    let sender = LettreEmailSender::new(&cfg).unwrap();
    let message = lettre::Message::builder()
        .from("no-reply@example.test".parse().unwrap())
        .to("user@example.test".parse().unwrap())
        .subject("Deadline")
        .body("Hello".to_string())
        .unwrap();

    // Send the message, bounding the test itself
    let result = tokio::time::timeout(Duration::from_secs(5), sender.send(message))
        .await
        .expect("send to return within the configured deadline");
    server.abort();

    // Check the stalled attempt follows the unknown-outcome path
    let err = result.expect_err("stalled server to fail the delivery");
    assert!(matches!(&err, EmailDeliveryError::Unknown(_)), "{err}");
    assert_eq!(
        err.to_string(),
        "smtp delivery attempt exceeded the 1s deadline"
    );
}

#[test]
fn test_lettre_email_sender_uses_starttls_for_submission_port() {
    // Setup email config
    let cfg = sample_email_config(None);

    // Build transport configuration
    let builder = LettreEmailSender::transport_builder(&cfg).unwrap();
    let debug = format!("{builder:?}");

    // Check configured port and TLS mode
    assert!(debug.contains("port: 587"), "{debug}");
    assert!(debug.contains("tls: Required"), "{debug}");
}

#[test]
fn test_lettre_email_sender_uses_wrapper_tls_for_submissions_port() {
    // Setup email config
    let mut cfg = sample_email_config(None);
    cfg.smtp.port = 465;

    // Build transport configuration
    let builder = LettreEmailSender::transport_builder(&cfg).unwrap();
    let debug = format!("{builder:?}");

    // Check configured port and TLS mode
    assert!(debug.contains("port: 465"), "{debug}");
    assert!(debug.contains("tls: Wrapper"), "{debug}");
}

// Helpers.

/// Remove the given keys from a JSON object fixture.
fn remove_keys(value: &mut serde_json::Value, keys: &[&str]) {
    let object = value.as_object_mut().expect("fixture to be a JSON object");
    for key in keys {
        object.remove(*key);
    }
}

/// Render a claimed notification of the given kind with the test base URL.
///
/// Returns the email subject and HTML body.
fn render(kind: NotificationKind, template_data: serde_json::Value) -> (String, String) {
    let notification = Notification {
        kind,
        template_data: Some(template_data),
        ..sample_pending_notification()
    };
    DeliveryWorker::prepare_content(&notification, TEST_BASE_URL)
        .expect("notification content to render")
}

/// Sample template payload for CFS submission update notifications.
fn sample_cfs_submission_updated_template_data() -> serde_json::Value {
    let mut payload = sample_event_reminder_template_data();
    payload["status_name"] = json!("Accepted");
    payload
}

/// Sample template payload for community team invitation notifications.
fn sample_community_team_invitation_template_data() -> serde_json::Value {
    json!({
        "community_name": "Test Community",
        "link": "https://example.test/dashboard/user?tab=invitations",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Create a deterministic delivery claim timestamp.
fn sample_delivery_claimed_at() -> DateTime<Utc> {
    DateTime::from_timestamp(1_735_689_600, 0).unwrap()
}

/// Create a delivery worker with mock dependencies and no recipients whitelist.
fn sample_delivery_worker(db: MockDB, email_sender: MockEmailSender) -> DeliveryWorker {
    DeliveryWorker {
        base_url: TEST_BASE_URL.to_string(),
        cancellation_token: CancellationToken::new(),
        cfg: sample_email_config(None),
        db: Arc::new(db),
        email_sender: Arc::new(email_sender),
    }
}

/// Create a sample email configuration with an optional recipients whitelist.
fn sample_email_config(rcpts_whitelist: Option<Vec<String>>) -> EmailConfig {
    EmailConfig {
        from_address: "no-reply@example.test".to_string(),
        from_name: "Open Community Groups".to_string(),
        smtp: SmtpConfig {
            host: "smtp.example.test".to_string(),
            password: "pass".to_string(),
            port: 587,
            username: "user".to_string(),

            connect_timeout_secs: 10,
            send_timeout_secs: 30,
        },

        rcpts_whitelist,
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

/// Create a sample enqueue worker with a mock database.
fn sample_enqueue_worker(db: MockDB) -> EnqueueWorker {
    EnqueueWorker {
        cancellation_token: CancellationToken::new(),
        db: Arc::new(db),
    }
}

/// Sample template payload for canceled event admission offer notifications.
fn sample_event_admission_offer_canceled_template_data() -> serde_json::Value {
    json!({
        "dashboard_url": "/dashboard/user?tab=events",
        "event_name": "Enrollment Event",
        "group_name": "Enrollment Group",
        "theme": {
            "primary_color": "#000000"
        },
        "ticket_title": "General admission"
    })
}

/// Sample template payload for newly created event admission offer notifications.
fn sample_event_admission_offer_created_template_data() -> serde_json::Value {
    json!({
        "amount_minor": 2_500,
        "currency_code": "USD",
        "dashboard_url": "/dashboard/user?tab=invitations#event-offer-11111111-1111-1111-1111-111111111111",
        "event_name": "Enrollment Event",
        "expires_at": 1_914_724_800,
        "group_name": "Enrollment Group",
        "is_simple_rsvp": false,
        "registration_questions_required": true,
        "theme": {
            "primary_color": "#000000"
        },
        "ticket_title": "General admission",
        "timezone": "Europe/Madrid"
    })
}

/// Sample template payload for declined event admission offer notifications.
fn sample_event_admission_offer_declined_template_data() -> serde_json::Value {
    json!({
        "dashboard_url": "/dashboard/group?tab=events",
        "event_name": "Enrollment Event",
        "group_name": "Enrollment Group",
        "recipient_name": "Example Recipient",
        "theme": {
            "primary_color": "#000000"
        },
        "ticket_title": "General admission"
    })
}

/// Sample template payload for event attendance cancellation notifications.
fn sample_event_attendance_canceled_template_data() -> serde_json::Value {
    json!({
        "dashboard_link": "https://example.test/dashboard/user?tab=events",
        "event": sample_event_json("Reminder Event", "reminder-event", "hybrid"),
        "link": "https://example.test/test-community/group/notification-group/event/reminder-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for custom event notifications.
fn sample_event_custom_template_data() -> serde_json::Value {
    let mut event = sample_event_json("Custom Event", "custom-event", "virtual");
    remove_keys(&mut event, &["starts_at", "venue_name"]);
    json!({
        "subject": "Custom event subject",
        "body": "Custom event body",
        "event": event,
        "link": "https://example.test/test-community/group/notification-group/event/custom-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample legacy payload for custom event notifications, which named the subject `title`.
fn sample_event_custom_legacy_template_data() -> serde_json::Value {
    let mut payload = sample_event_custom_template_data();
    remove_keys(&mut payload, &["subject"]);
    payload["title"] = json!("Custom event title");
    payload
}

/// Sample template payload for event invitation notifications.
fn sample_event_invitation_template_data() -> serde_json::Value {
    let mut event = sample_event_json("Invitation Event", "invitation-event", "virtual");
    remove_keys(&mut event, &["starts_at", "venue_name"]);
    json!({
        "event": event,
        "has_registration_questions": false,
        "link": "https://example.test/dashboard/user?tab=invitations",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample event JSON shared by the event notification payloads, as stored by
/// the database: an in-person or hybrid event in UTC with no waitlist.
fn sample_event_json(name: &str, slug: &str, kind: &str) -> serde_json::Value {
    json!({
        "canceled": false,
        "community_display_name": "Test Community",
        "community_name": "test-community",
        "event_id": "11111111-1111-1111-1111-111111111111",
        "group_category_name": "Community",
        "group_name": "Notification Group",
        "group_slug": "notification-group",
        "kind": kind,
        "logo_url": "https://example.com/logo.png",
        "name": name,
        "published": true,
        "slug": slug,
        "starts_at": 1_914_724_800,
        "timezone": "UTC",
        "venue_name": "Conference Hall",
        "waitlist_count": 0,
        "waitlist_enabled": false
    })
}

/// Sample template payload for paid event configuration notifications.
fn sample_event_paid_configured_template_data(event_count: usize) -> serde_json::Value {
    // Build the first configured event payload
    let mut events = vec![json!({
        "event_id": "11111111-1111-1111-1111-111111111111",
        "name": "Paid Event One",
        "timezone": "UTC",

        "starts_at": 1_609_495_200
    })];

    // Add a second event for plural delivery scenarios
    if event_count > 1 {
        events.push(json!({
            "event_id": "22222222-2222-2222-2222-222222222222",
            "name": "Paid Event Two",
            "timezone": "UTC",

            "starts_at": 1_609_581_600
        }));
    }

    // Build the aggregate notification payload
    json!({
        "community_display_name": "Test Community",
        "event_count": event_count,
        "events": events,
        "group_name": "Notification Group",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample legacy payload for event reminder notifications, queued before
/// waitlist data, join instructions, and the dashboard link existed.
fn sample_event_reminder_legacy_template_data() -> serde_json::Value {
    let mut payload = sample_event_reminder_template_data();
    remove_keys(&mut payload, &["dashboard_link"]);
    remove_keys(
        &mut payload["event"],
        &[
            "meeting_join_instructions",
            "waitlist_count",
            "waitlist_enabled",
        ],
    );
    payload
}

/// Sample legacy payload for event reminder notifications with the old zip
/// code key, queued before join instructions and the dashboard link existed.
fn sample_event_reminder_legacy_zip_code_template_data() -> serde_json::Value {
    let mut payload = sample_event_reminder_template_data();
    remove_keys(&mut payload, &["dashboard_link"]);
    remove_keys(&mut payload["event"], &["meeting_join_instructions"]);
    payload["event"]["zip_code"] = json!("10001");
    payload
}

/// Sample template payload for event reminder notifications.
fn sample_event_reminder_template_data() -> serde_json::Value {
    let mut event = sample_event_json("Reminder Event", "reminder-event", "hybrid");
    event["meeting_join_instructions"] = json!("Use your registration name when joining.");
    json!({
        "show_attendance_cancellation_copy": true,
        "event": event,
        "dashboard_link": "https://example.test/dashboard/user?tab=events",
        "link": "https://example.test/test-community/group/notification-group/event/reminder-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for aggregate event series notifications.
fn sample_event_series_template_data() -> serde_json::Value {
    let mut first_event = sample_event_json("Series Event One", "series-event-one", "hybrid");
    first_event["meeting_join_instructions"] = json!("Join five minutes early for speaker setup.");
    let mut second_event = sample_event_json("Series Event Two", "series-event-two", "hybrid");
    second_event["event_id"] = json!("22222222-2222-2222-2222-222222222222");
    second_event["starts_at"] = json!(1_915_329_600);
    json!({
        "community_display_name": "Test Community",
        "event_count": 2,
        "events": [
            {
                "event": first_event,
                "link": "https://example.test/test-community/group/notification-group/event/series-event-one"
            },
            {
                "event": second_event,
                "link": "https://example.test/test-community/group/notification-group/event/series-event-two"
            }
        ],
        "group_name": "Notification Group",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for opened event survey notifications, as stored
/// literally by `enqueue_due_event_survey_notifications`.
fn sample_event_survey_opened_template_data() -> serde_json::Value {
    let mut event = sample_event_json("Survey Event", "survey-event", "in-person");
    event["timezone"] = json!("Europe/Madrid");
    json!({
        "anonymous": true,
        "event": event,
        "link": "/dashboard/user?tab=surveys&event_survey_id=55555555-5555-5555-5555-555555555555",
        "survey_title": "Session feedback",
        "theme": {
            "primary_color": "#000000"
        },

        "closes_at": 1_915_329_600
    })
}

/// Sample template payload for approved and waitlisted ticket offer notifications.
fn sample_event_ticket_offer_template_data() -> serde_json::Value {
    json!({
        "amount_minor": 2_500,
        "currency_code": "USD",
        "dashboard_url": "/dashboard/user?tab=invitations#event-offer-11111111-1111-1111-1111-111111111111",
        "event_name": "Enrollment Event",
        "expires_at": 1_914_724_800,
        "group_name": "Enrollment Group",
        "is_simple_rsvp": false,
        "theme": {
            "primary_color": "#000000"
        },
        "ticket_title": "General admission",
        "timezone": "Europe/Madrid"
    })
}

/// Sample free template payload for a waitlisted ticket offer notification.
fn sample_free_event_ticket_offer_template_data() -> serde_json::Value {
    let mut template_data = sample_event_ticket_offer_template_data();
    template_data["amount_minor"] = json!(0);
    template_data["currency_code"] = serde_json::Value::Null;
    template_data
}

/// Sample template payload for event waitlist notifications.
fn sample_event_waitlist_template_data() -> serde_json::Value {
    let mut event = sample_event_json("Waitlist Event", "waitlist-event", "virtual");
    remove_keys(&mut event, &["venue_name"]);
    event["meeting_join_instructions"] =
        json!("Use the waiting room display name from your ticket.");
    event["meeting_join_url"] = json!("https://example.test/waitlist-event/live");
    event["waitlist_count"] = json!(3);
    event["waitlist_enabled"] = json!(true);
    json!({
        "event": event,
        "dashboard_link": "https://example.test/dashboard/user?tab=events",
        "has_registration_questions": false,
        "link": "https://example.test/test-community/group/notification-group/event/waitlist-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for event waitlist notifications with registration questions.
fn sample_event_waitlist_template_data_with_registration_questions() -> serde_json::Value {
    let mut payload = sample_event_waitlist_template_data();
    payload["has_registration_questions"] = json!(true);
    payload
}

/// Sample template payload for event welcome notifications.
fn sample_event_welcome_template_data(dashboard_link: Option<&str>) -> serde_json::Value {
    json!({
        "dashboard_link": dashboard_link,
        "event": sample_event_json("Welcome Event", "welcome-event", "hybrid"),
        "link": "https://example.test/test-community/group/notification-group/event/welcome-event",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for custom group notifications.
fn sample_group_custom_template_data() -> serde_json::Value {
    json!({
        "subject": "Custom group subject",
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

/// Sample legacy payload for custom group notifications, which named the subject `title`.
fn sample_group_custom_legacy_template_data() -> serde_json::Value {
    let mut payload = sample_group_custom_template_data();
    remove_keys(&mut payload, &["subject"]);
    payload["title"] = json!("Custom group title");
    payload
}

/// Sample template payload for inbox message notifications.
fn sample_inbox_message_received_template_data() -> serde_json::Value {
    json!({
        "body": "Is there parking <nearby>?",
        "community_display_name": "Inbox Community",
        "event_name": "Inbox Event",
        "group_name": "Inbox Group",
        "link": "/dashboard/group?tab=inbox&conversation_id=44444444-4444-4444-4444-444444444444",
        "sender_name": "Uma User",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Sample template payload for inbox reply notifications.
fn sample_inbox_reply_received_template_data() -> serde_json::Value {
    json!({
        "body": "Yes, there is a car park.",
        "community_display_name": "Inbox Community",
        "event_name": "Inbox Event",
        "group_name": "Inbox Group",
        "link": "/dashboard/user?tab=inbox&conversation_id=44444444-4444-4444-4444-444444444444",
        "theme": {
            "primary_color": "#000000"
        }
    })
}

/// Create a claimed email verification notification ready for delivery.
fn sample_pending_notification() -> Notification {
    Notification {
        attachments: vec![],
        delivery_claimed_at: sample_delivery_claimed_at(),
        email: "notify@example.test".to_string(),
        kind: NotificationKind::EmailVerification,
        notification_id: Uuid::new_v4(),
        template_data: Some(sample_email_verification_template_data()),
    }
}

/// Deserializes the template data of a notification.
pub(super) fn template_of<T: DeserializeOwned>(notification: &NewNotification) -> T {
    serde_json::from_value(notification.template_data.clone().expect("template data to exist"))
        .expect("template data to deserialize")
}
