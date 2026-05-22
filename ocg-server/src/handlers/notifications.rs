//! Handler-layer notification helpers.

use anyhow::Result;
use serde_json::to_value;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::notifications::EventAttendanceCanceled,
    types::{event::EventSummary, site::SiteSettings},
    util::{build_event_page_link, build_user_dashboard_events_link},
};

/// Enqueues a generic attendance cancellation confirmation notification.
pub(crate) async fn enqueue_attendance_canceled_notification(
    event: &EventSummary,
    notifications_manager: &DynNotificationsManager,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<()> {
    // Link preparation
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);

    // Template data
    let template_data = EventAttendanceCanceled {
        dashboard_link: build_user_dashboard_events_link(base_url),
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    // Notification enqueue
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventAttendanceCanceled,
        recipients: vec![recipient_user_id],
        template_data: Some(to_value(&template_data)?),
    };

    notifications_manager.enqueue(&notification).await
}

/// Attempts to send an attendance cancellation confirmation without failing the caller.
pub(crate) async fn try_enqueue_attendance_canceled_notification(
    event: &EventSummary,
    notifications_manager: &DynNotificationsManager,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) {
    if let Err(err) = enqueue_attendance_canceled_notification(
        event,
        notifications_manager,
        recipient_user_id,
        server_cfg,
        site_settings,
    )
    .await
    {
        warn!(error = %err, "failed to enqueue event attendance cancellation notification");
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use anyhow::anyhow;
    use serde_json::from_value;
    use uuid::Uuid;

    use crate::{
        config::HttpServerConfig,
        handlers::tests::{sample_event_summary, sample_site_settings},
        services::notifications::{DynNotificationsManager, MockNotificationsManager, NotificationKind},
        templates::notifications::EventAttendanceCanceled,
    };

    use super::*;

    #[tokio::test]
    async fn test_enqueue_attendance_canceled_notification_enqueues_expected_payload() {
        // Setup identifiers and notification context
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let recipient_user_id = Uuid::new_v4();
        let event = sample_event_summary(event_id, group_id);
        let site_settings = sample_site_settings();
        let site_settings_for_notification = site_settings.clone();
        let server_cfg = sample_server_cfg();

        // Setup notifications manager mock
        let mut notifications_manager = MockNotificationsManager::new();
        notifications_manager
            .expect_enqueue()
            .times(1)
            .withf(move |notification| {
                matches!(notification.kind, NotificationKind::EventAttendanceCanceled)
                    && notification.attachments.is_empty()
                    && notification.recipients == vec![recipient_user_id]
                    && notification.template_data.as_ref().is_some_and(|value| {
                        from_value::<EventAttendanceCanceled>(value.clone()).is_ok_and(|template| {
                            template.dashboard_link == "https://example.test/dashboard/user?tab=events"
                                && template.event.event_id == event_id
                                && template.link
                                    == "https://example.test/test-community/group/def5678/event/ghi9abc"
                                && template.theme.primary_color
                                    == site_settings_for_notification.theme.primary_color
                        })
                    })
            })
            .returning(|_| Box::pin(async { Ok(()) }));
        let notifications_manager: DynNotificationsManager = Arc::new(notifications_manager);

        // Enqueue the notification
        let result = enqueue_attendance_canceled_notification(
            &event,
            &notifications_manager,
            recipient_user_id,
            &server_cfg,
            &site_settings,
        )
        .await;

        // Check the helper succeeds
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_try_enqueue_attendance_canceled_notification_swallows_enqueue_errors() {
        // Setup identifiers and notification context
        let event = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());
        let recipient_user_id = Uuid::new_v4();
        let server_cfg = sample_server_cfg();
        let site_settings = sample_site_settings();

        // Setup notifications manager mock
        let mut notifications_manager = MockNotificationsManager::new();
        notifications_manager
            .expect_enqueue()
            .times(1)
            .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
        let notifications_manager: DynNotificationsManager = Arc::new(notifications_manager);

        // Try enqueueing and verify the caller is not failed
        try_enqueue_attendance_canceled_notification(
            &event,
            &notifications_manager,
            recipient_user_id,
            &server_cfg,
            &site_settings,
        )
        .await;
    }

    // Helpers.

    fn sample_server_cfg() -> HttpServerConfig {
        HttpServerConfig {
            base_url: "https://example.test/".to_string(),
            ..Default::default()
        }
    }
}
