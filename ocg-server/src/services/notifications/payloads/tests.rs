use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    templates::notifications::{
        EventAttendanceCanceled, EventCanceled, EventPaidConfigured, EventPublished,
        EventRefundApproved, EventRefundRejected, EventRescheduled, EventWaitlistJoined,
        EventWaitlistLeft, EventWelcome, InboxMessageReceived, InboxReplyReceived, SpeakerWelcome,
    },
    types::{
        notifications::NotificationKind,
        tests::{
            sample_community_summary, sample_event_summary, sample_group_summary,
            sample_inbox_conversation, sample_site_settings,
        },
    },
};

use super::*;

#[test]
fn test_build_community_custom_notification_returns_expected_content() {
    // Setup data structures
    let community = sample_community_summary(Uuid::new_v4());
    let site_settings = sample_site_settings();

    // Build notification content
    let template = build_community_custom_notification(
        &community,
        &sample_content("Community Update", "Hello, group teams!"),
        &sample_server_cfg(),
        &site_settings,
    );

    // Check content matches expectations
    assert_eq!(template.body, "Hello, group teams!");
    assert_eq!(template.community_display_name, "Test");
    assert_eq!(template.link, "https://example.test/test");
    assert_eq!(template.subject, "Community Update");
    assert_eq!(
        template.theme.primary_color,
        site_settings.theme.primary_color
    );
}

#[test]
fn test_build_event_attendance_canceled_notification_returns_expected_payload() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let recipient_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let site_settings = sample_site_settings();
    let server_cfg = sample_server_cfg();

    // Build notification
    let notification = build_event_attendance_canceled_notification(
        &event,
        recipient_user_id,
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");

    // Check notification matches expectations
    assert!(notification.attachments.is_empty());
    assert!(matches!(
        notification.kind,
        NotificationKind::EventAttendanceCanceled
    ));
    assert_eq!(notification.recipients, vec![recipient_user_id]);
    let template: EventAttendanceCanceled =
        serde_json::from_value(notification.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(
        template.dashboard_link,
        "https://example.test/dashboard/user?tab=events"
    );
    assert_eq!(
        template.link,
        "https://example.test/test-community/group/def5678/event/ghi9abc"
    );
    assert_eq!(template.event.event_id, event_id);
    assert_eq!(
        template.theme.primary_color,
        site_settings.theme.primary_color
    );
}

#[test]
fn test_build_event_calendar_notifications_return_expected_payload() {
    // Setup identifiers and data structures
    let cohost_group_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let owner_group_id = Uuid::new_v4();
    let recipient_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, owner_group_id);
    let site_settings = sample_site_settings();
    let server_cfg = sample_server_cfg();

    // Build notifications
    let canceled = build_event_canceled_notification(
        &event,
        vec![recipient_user_id],
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");
    let published = build_event_published_notification(
        &event,
        None,
        vec![owner_group_id, cohost_group_id],
        vec![recipient_user_id],
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");
    let rescheduled = build_event_rescheduled_notification(
        &event,
        vec![recipient_user_id],
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");
    let speaker = build_speaker_welcome_notification(
        &event,
        vec![recipient_user_id],
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");

    // Check notifications match expectations
    assert_eq!(canceled.attachments.len(), 1);
    assert!(matches!(canceled.kind, NotificationKind::EventCanceled));
    let canceled_template: EventCanceled =
        serde_json::from_value(canceled.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(canceled_template.event.event_id, event_id);

    assert_eq!(published.attachments.len(), 1);
    assert_eq!(published.group_ids, vec![owner_group_id, cohost_group_id]);
    assert!(matches!(published.kind, NotificationKind::EventPublished));
    let published_template: EventPublished =
        serde_json::from_value(published.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(published_template.event.event_id, event_id);

    assert_eq!(rescheduled.attachments.len(), 1);
    assert!(matches!(
        rescheduled.kind,
        NotificationKind::EventRescheduled
    ));
    let rescheduled_template: EventRescheduled =
        serde_json::from_value(rescheduled.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(rescheduled_template.event.event_id, event_id);

    assert_eq!(speaker.attachments.len(), 1);
    assert!(matches!(speaker.kind, NotificationKind::SpeakerWelcome));
    let speaker_template: SpeakerWelcome =
        serde_json::from_value(speaker.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(speaker_template.event.event_id, event_id);
}

#[test]
fn test_build_event_custom_notification_returns_expected_content() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, Uuid::new_v4());
    let site_settings = sample_site_settings();

    // Build notification content
    let template = build_event_custom_notification(
        &event,
        &sample_content("Event Update", "Hello, event attendees!"),
        &sample_server_cfg(),
        &site_settings,
    );

    // Check content matches expectations
    assert_eq!(template.body, "Hello, event attendees!");
    assert_eq!(template.event.event_id, event_id);
    assert_eq!(
        template.link,
        "https://example.test/test-community/group/def5678/event/ghi9abc"
    );
    assert_eq!(template.subject, "Event Update");
    assert_eq!(
        template.theme.primary_color,
        site_settings.theme.primary_color
    );
}

#[test]
fn test_build_event_paid_configured_notification_rejects_empty_events() {
    let err = build_event_paid_configured_notification(
        &[],
        vec![Uuid::new_v4()],
        &sample_site_settings(),
    )
    .expect_err("empty events to be rejected");

    assert_eq!(
        err.to_string(),
        "paid event notification requires at least one event"
    );
}

#[test]
fn test_build_event_paid_configured_notification_returns_expected_payload() {
    // Setup ordered events and recipients
    let event_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let recipient_user_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut related_event = sample_event_summary(related_event_id, group_id);
    related_event.has_external_payment = true;
    let events = vec![sample_event_summary(event_id, group_id), related_event];
    let site_settings = sample_site_settings();

    // Build the aggregate notification
    let notification =
        build_event_paid_configured_notification(&events, vec![recipient_user_id], &site_settings)
            .expect("notification to be built");

    // Check the minimal serialized payload
    assert!(notification.attachments.is_empty());
    assert!(matches!(
        notification.kind,
        NotificationKind::EventPaidConfigured
    ));
    assert_eq!(notification.recipients, vec![recipient_user_id]);
    let template: EventPaidConfigured =
        serde_json::from_value(notification.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(template.event_count, 2);
    assert_eq!(template.events[0].event_id, event_id);
    assert!(!template.events[0].has_external_payment);
    assert_eq!(template.events[1].event_id, related_event_id);
    assert!(template.events[1].has_external_payment);
    assert_eq!(template.group_name, events[0].group_name);
    assert_eq!(
        template.theme.primary_color,
        site_settings.theme.primary_color
    );
}

#[test]
fn test_build_event_refund_notifications_return_expected_payload() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let recipient_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, Uuid::new_v4());
    let site_settings = sample_site_settings();
    let server_cfg = sample_server_cfg();

    // Build notifications
    let approved =
        build_event_refund_approved_template_data(&event, false, &server_cfg, &site_settings)
            .expect("template data to be built");
    let rejected = build_event_refund_rejected_notification(
        &event,
        recipient_user_id,
        "Outside the refund policy window",
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");

    // Check notifications match expectations
    let approved_template: EventRefundApproved =
        serde_json::from_value(approved).expect("template data to deserialize");
    assert_eq!(approved_template.event.event_id, event_id);
    assert!(!approved_template.external_payment);

    assert!(rejected.attachments.is_empty());
    assert!(matches!(
        rejected.kind,
        NotificationKind::EventRefundRejected
    ));
    assert_eq!(rejected.recipients, vec![recipient_user_id]);
    let rejected_template: EventRefundRejected =
        serde_json::from_value(rejected.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(rejected_template.event.event_id, event_id);
    assert_eq!(
        rejected_template.rejection_reason,
        "Outside the refund policy window"
    );
}

#[test]
fn test_build_event_refund_approved_external_payment_payload() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, Uuid::new_v4());
    let site_settings = sample_site_settings();
    let server_cfg = sample_server_cfg();

    // Build an external refund-approval payload
    let approved =
        build_event_refund_approved_template_data(&event, true, &server_cfg, &site_settings)
            .expect("template data to be built");

    // Check the payload marks the refund as returned outside OCG
    let approved_template: EventRefundApproved =
        serde_json::from_value(approved).expect("template data to deserialize");
    assert_eq!(approved_template.event.event_id, event_id);
    assert!(approved_template.external_payment);
}

#[test]
fn test_build_event_waitlist_joined_and_left_notifications_return_expected_payload() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let recipient_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, Uuid::new_v4());
    let site_settings = sample_site_settings();
    let server_cfg = sample_server_cfg();

    // Build notifications
    let joined = build_event_waitlist_joined_notification(
        &event,
        recipient_user_id,
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");
    let left = build_event_waitlist_left_notification(
        &event,
        recipient_user_id,
        &server_cfg,
        &site_settings,
    )
    .expect("notification to be built");

    // Check notifications match expectations
    assert!(joined.attachments.is_empty());
    assert!(matches!(joined.kind, NotificationKind::EventWaitlistJoined));
    assert_eq!(joined.recipients, vec![recipient_user_id]);
    let joined_template: EventWaitlistJoined =
        serde_json::from_value(joined.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(joined_template.event.event_id, event_id);
    assert_eq!(
        joined_template.link,
        "https://example.test/test-community/group/def5678/event/ghi9abc"
    );

    assert!(left.attachments.is_empty());
    assert!(matches!(left.kind, NotificationKind::EventWaitlistLeft));
    assert_eq!(left.recipients, vec![recipient_user_id]);
    let left_template: EventWaitlistLeft =
        serde_json::from_value(left.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(left_template.event.event_id, event_id);
    assert_eq!(
        left_template.link,
        "https://example.test/test-community/group/def5678/event/ghi9abc"
    );
}
#[test]
fn test_build_event_welcome_notification_returns_expected_payload() {
    // Setup identifiers and data structures
    let event_id = Uuid::new_v4();
    let recipient_user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, Uuid::new_v4());
    let site_settings = sample_site_settings();
    let server_cfg = sample_server_cfg();

    // Build notification
    let notification = build_event_welcome_notification(
        &event,
        recipient_user_id,
        &server_cfg,
        &site_settings,
        true,
    )
    .expect("notification to be built");

    // Check notification matches expectations
    assert_eq!(notification.attachments.len(), 1);
    assert!(matches!(notification.kind, NotificationKind::EventWelcome));
    assert_eq!(notification.recipients, vec![recipient_user_id]);
    let template: EventWelcome =
        serde_json::from_value(notification.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(
        template.dashboard_link.as_deref(),
        Some("https://example.test/dashboard/user?tab=events")
    );
    assert_eq!(template.event.event_id, event_id);
    assert_eq!(
        template.link,
        "https://example.test/test-community/group/def5678/event/ghi9abc"
    );
    assert_eq!(
        template.theme.primary_color,
        site_settings.theme.primary_color
    );
}
#[test]
fn test_build_group_custom_notification_returns_expected_content() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let mut group = sample_group_summary(group_id);
    group.slug_pretty = Some("pretty-group".to_string());
    let site_settings = sample_site_settings();

    // Build notification content
    let template = build_group_custom_notification(
        &group,
        &sample_content("Important Update", "Hello, group members!"),
        &sample_server_cfg(),
        &site_settings,
    );

    // Check content matches expectations
    assert_eq!(template.body, "Hello, group members!");
    assert_eq!(template.group.group_id, group_id);
    assert_eq!(
        template.link,
        format!(
            "https://example.test/test-community/group/{}",
            group.public_slug()
        )
    );
    assert_eq!(template.subject, "Important Update");
    assert_eq!(
        template.theme.primary_color,
        site_settings.theme.primary_color
    );
}

#[test]
fn test_build_inbox_message_received_notification_returns_expected_payload() {
    // Setup the conversation, its first message and the recipients
    let conversation = sample_inbox_conversation(Uuid::new_v4());
    let message = conversation.messages[0].clone();
    let recipient_user_id = Uuid::new_v4();
    let site_settings = sample_site_settings();

    // Build notification
    let notification = build_inbox_message_received_notification(
        &conversation,
        &message,
        vec![recipient_user_id],
        &site_settings,
    )
    .expect("notification to be built");

    // Check notification matches expectations
    assert!(notification.attachments.is_empty());
    assert!(matches!(
        notification.kind,
        NotificationKind::InboxMessageReceived
    ));
    assert_eq!(notification.recipients, vec![recipient_user_id]);
    let template: InboxMessageReceived =
        serde_json::from_value(notification.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(template.body, "When do doors open?");
    assert_eq!(template.community_display_name, "Test Community");
    assert_eq!(template.group_name, "Test Group");
    assert_eq!(
        template.link,
        format!(
            "/dashboard/group?tab=inbox&conversation_id={}",
            conversation.inbox_conversation_id
        )
    );
    assert_eq!(template.sender_name, "Inbox User");
    assert_eq!(template.event_name.as_deref(), Some("Test Event"));
}

#[test]
fn test_build_inbox_message_received_notification_uses_username_without_name() {
    // Setup a message whose author has no display name
    let conversation = sample_inbox_conversation(Uuid::new_v4());
    let mut message = conversation.messages[0].clone();
    message.author.as_mut().unwrap().name = None;

    // Build notification
    let notification = build_inbox_message_received_notification(
        &conversation,
        &message,
        vec![Uuid::new_v4()],
        &sample_site_settings(),
    )
    .expect("notification to be built");

    // Check the sender falls back to the username
    let template: InboxMessageReceived =
        serde_json::from_value(notification.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(template.sender_name, "inbox-user");
}

#[test]
fn test_build_inbox_reply_received_notification_returns_expected_payload() {
    // Setup the conversation and a reply without event
    let mut conversation = sample_inbox_conversation(Uuid::new_v4());
    conversation.event = None;
    let user_id = conversation.user.as_ref().unwrap().user_id;
    let message = conversation.messages[0].clone();

    // Build notification
    let notification =
        build_inbox_reply_received_notification(&conversation, &message, &sample_site_settings())
            .expect("notification to be built");

    // Check notification matches expectations
    assert!(matches!(
        notification.kind,
        NotificationKind::InboxReplyReceived
    ));
    assert_eq!(notification.recipients, vec![user_id]);
    let template: InboxReplyReceived =
        serde_json::from_value(notification.template_data.expect("template data to exist"))
            .expect("template data to deserialize");
    assert_eq!(template.group_name, "Test Group");
    assert_eq!(
        template.link,
        format!(
            "/dashboard/user?tab=inbox&conversation_id={}",
            conversation.inbox_conversation_id
        )
    );
    assert_eq!(template.event_name, None);
}

// Helpers.

/// Returns custom notification content with the given subject and body.
fn sample_content(subject: &str, body: &str) -> CustomNotificationContent {
    CustomNotificationContent {
        body: body.to_string(),
        subject: subject.to_string(),
    }
}

fn sample_server_cfg() -> HttpServerConfig {
    HttpServerConfig {
        base_url: "https://example.test/".to_string(),
        ..Default::default()
    }
}
