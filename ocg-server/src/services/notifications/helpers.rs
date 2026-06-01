//! Notification composition helpers.
//!
//! Prefer builders here for Rust-created event notification payloads when they
//! share event links, calendar attachments, dashboard links, or template shape.

use anyhow::Result;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    templates::notifications::{
        EventAttendanceCanceled, EventCanceled, EventInvitation, EventPublished,
        EventRefundApproved, EventRefundRejected, EventRescheduled, EventWaitlistJoined,
        EventWaitlistLeft, EventWaitlistPromoted, EventWelcome, SpeakerWelcome,
    },
    types::{event::EventSummary, site::SiteSettings},
    util::{
        build_event_calendar_attachment, build_event_page_link, build_user_dashboard_events_link,
    },
};

use super::{NewNotification, NotificationKind};

/// Builds an event attendance cancellation notification.
pub(crate) fn build_event_attendance_canceled_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventAttendanceCanceled {
        dashboard_link: build_user_dashboard_events_link(base_url),
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventAttendanceCanceled,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event cancellation notification.
pub(crate) fn build_event_canceled_notification(
    event: &EventSummary,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventCanceled {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        kind: NotificationKind::EventCanceled,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an organizer-created event invitation notification.
pub(crate) fn build_event_invitation_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let link = if event.has_registration_questions {
        build_user_dashboard_events_link(base_url)
    } else {
        format!("{base_url}/dashboard/user?tab=invitations")
    };
    let template_data = EventInvitation {
        event: event.clone(),
        has_registration_questions: event.has_registration_questions,
        link,
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventInvitation,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event publication notification.
pub(crate) fn build_event_published_notification(
    event: &EventSummary,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventPublished {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        kind: NotificationKind::EventPublished,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event refund approval notification.
pub(crate) fn build_event_refund_approved_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventRefundApproved {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventRefundApproved,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event refund rejection notification.
pub(crate) fn build_event_refund_rejected_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventRefundRejected {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventRefundRejected,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event rescheduled notification.
pub(crate) fn build_event_rescheduled_notification(
    event: &EventSummary,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventRescheduled {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        kind: NotificationKind::EventRescheduled,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event waitlist joined notification.
pub(crate) fn build_event_waitlist_joined_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventWaitlistJoined {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventWaitlistJoined,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event waitlist left notification.
pub(crate) fn build_event_waitlist_left_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = EventWaitlistLeft {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventWaitlistLeft,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event waitlist promotion notification.
pub(crate) fn build_event_waitlist_promoted_notification(
    event: &EventSummary,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let attachments = if event.has_registration_questions {
        vec![]
    } else {
        vec![build_event_calendar_attachment(base_url, event)]
    };
    let template_data = EventWaitlistPromoted {
        event: event.clone(),
        has_registration_questions: event.has_registration_questions,
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),

        dashboard_link: Some(build_user_dashboard_events_link(base_url)),
    };

    Ok(NewNotification {
        attachments,
        kind: NotificationKind::EventWaitlistPromoted,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event welcome notification.
pub(crate) fn build_event_welcome_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
    include_dashboard_link: bool,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let dashboard_link = include_dashboard_link.then(|| build_user_dashboard_events_link(base_url));
    let template_data = EventWelcome {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),

        dashboard_link,
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        kind: NotificationKind::EventWelcome,
        recipients: vec![recipient_user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds a speaker welcome notification.
pub(crate) fn build_speaker_welcome_notification(
    event: &EventSummary,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = notification_base_url(server_cfg);
    let template_data = SpeakerWelcome {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        kind: NotificationKind::SpeakerWelcome,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Returns the configured base URL without a trailing slash.
fn notification_base_url(server_cfg: &HttpServerConfig) -> &str {
    server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url)
}

/// Returns whether waitlist promotion notifications should be sent.
pub(crate) fn should_send_waitlist_promoted_notification(
    event: &EventSummary,
    recipients: &[Uuid],
) -> bool {
    !recipients.is_empty() && !event.test_event
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use crate::{
        config::HttpServerConfig,
        handlers::tests::{sample_event_summary, sample_site_settings},
        services::notifications::NotificationKind,
        templates::notifications::{
            EventAttendanceCanceled, EventCanceled, EventInvitation, EventPublished,
            EventRefundApproved, EventRefundRejected, EventRescheduled, EventWaitlistJoined,
            EventWaitlistLeft, EventWaitlistPromoted, EventWelcome, SpeakerWelcome,
        },
    };

    use super::*;

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
        let event_id = Uuid::new_v4();
        let recipient_user_id = Uuid::new_v4();
        let event = sample_event_summary(event_id, Uuid::new_v4());
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
    fn test_build_event_invitation_notification_returns_expected_payload() {
        // Setup identifiers and data structures
        let event_id = Uuid::new_v4();
        let recipient_user_id = Uuid::new_v4();
        let mut event = sample_event_summary(event_id, Uuid::new_v4());
        event.has_registration_questions = true;
        let site_settings = sample_site_settings();
        let server_cfg = sample_server_cfg();

        // Build notification
        let notification = build_event_invitation_notification(
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
            NotificationKind::EventInvitation
        ));
        assert_eq!(notification.recipients, vec![recipient_user_id]);
        let template: EventInvitation =
            serde_json::from_value(notification.template_data.expect("template data to exist"))
                .expect("template data to deserialize");
        assert_eq!(template.event.event_id, event_id);
        assert!(template.has_registration_questions);
        assert_eq!(
            template.link,
            "https://example.test/dashboard/user?tab=events"
        );
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
        let approved = build_event_refund_approved_notification(
            &event,
            recipient_user_id,
            &server_cfg,
            &site_settings,
        )
        .expect("notification to be built");
        let rejected = build_event_refund_rejected_notification(
            &event,
            recipient_user_id,
            &server_cfg,
            &site_settings,
        )
        .expect("notification to be built");

        // Check notifications match expectations
        assert!(approved.attachments.is_empty());
        assert!(matches!(
            approved.kind,
            NotificationKind::EventRefundApproved
        ));
        assert_eq!(approved.recipients, vec![recipient_user_id]);
        let approved_template: EventRefundApproved =
            serde_json::from_value(approved.template_data.expect("template data to exist"))
                .expect("template data to deserialize");
        assert_eq!(approved_template.event.event_id, event_id);

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
    fn test_build_event_waitlist_promoted_notification_includes_calendar_for_confirmed_promotion() {
        // Setup identifiers and data structures
        let event_id = Uuid::new_v4();
        let recipient_user_id = Uuid::new_v4();
        let event = sample_event_summary(event_id, Uuid::new_v4());
        let site_settings = sample_site_settings();
        let server_cfg = sample_server_cfg();

        // Build notification
        let notification = build_event_waitlist_promoted_notification(
            &event,
            vec![recipient_user_id],
            &server_cfg,
            &site_settings,
        )
        .expect("notification to be built");

        // Check notification matches expectations
        assert_eq!(notification.attachments.len(), 1);
        assert!(matches!(
            notification.kind,
            NotificationKind::EventWaitlistPromoted
        ));
        assert_eq!(notification.recipients, vec![recipient_user_id]);
        let template: EventWaitlistPromoted =
            serde_json::from_value(notification.template_data.expect("template data to exist"))
                .expect("template data to deserialize");
        assert_eq!(
            template.dashboard_link.as_deref(),
            Some("https://example.test/dashboard/user?tab=events")
        );
        assert_eq!(template.event.event_id, event_id);
        assert!(!template.has_registration_questions);
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
    fn test_build_event_waitlist_promoted_notification_omits_calendar_for_pending_questions() {
        // Setup identifiers and data structures
        let event_id = Uuid::new_v4();
        let recipient_user_id = Uuid::new_v4();
        let mut event = sample_event_summary(event_id, Uuid::new_v4());
        event.has_registration_questions = true;
        let site_settings = sample_site_settings();
        let server_cfg = sample_server_cfg();

        // Build notification
        let notification = build_event_waitlist_promoted_notification(
            &event,
            vec![recipient_user_id],
            &server_cfg,
            &site_settings,
        )
        .expect("notification to be built");

        // Check notification matches expectations
        assert!(notification.attachments.is_empty());
        assert!(matches!(
            notification.kind,
            NotificationKind::EventWaitlistPromoted
        ));
        assert_eq!(notification.recipients, vec![recipient_user_id]);
        let template: EventWaitlistPromoted =
            serde_json::from_value(notification.template_data.expect("template data to exist"))
                .expect("template data to deserialize");
        assert_eq!(
            template.dashboard_link.as_deref(),
            Some("https://example.test/dashboard/user?tab=events")
        );
        assert_eq!(template.event.event_id, event_id);
        assert!(template.has_registration_questions);
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
    fn test_should_send_waitlist_promoted_notification_accepts_real_recipients() {
        // Setup data
        let event = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());

        // Check notification should be sent
        assert!(should_send_waitlist_promoted_notification(
            &event,
            &[Uuid::new_v4()]
        ));
    }

    #[test]
    fn test_should_send_waitlist_promoted_notification_requires_recipients() {
        // Setup data
        let event = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());

        // Check notification should be skipped
        assert!(!should_send_waitlist_promoted_notification(&event, &[]));
    }

    #[test]
    fn test_should_send_waitlist_promoted_notification_skips_test_events() {
        // Setup data
        let mut event = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());
        event.test_event = true;

        // Check notification should be skipped
        assert!(!should_send_waitlist_promoted_notification(
            &event,
            &[Uuid::new_v4()]
        ));
    }

    // Helpers.

    fn sample_server_cfg() -> HttpServerConfig {
        HttpServerConfig {
            base_url: "https://example.test/".to_string(),
            ..Default::default()
        }
    }
}
