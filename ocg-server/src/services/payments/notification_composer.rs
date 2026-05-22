//! Payment notification composition helpers.

use anyhow::Result;
use serde_json::Value;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, payments::CompletedEventPurchase},
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::notifications::{
        EventRefundApproved, EventRefundRejected, EventRefundRequested, EventWelcome,
    },
    util::{build_event_calendar_attachment, build_event_page_link, build_user_dashboard_events_link},
};

#[cfg(test)]
mod tests;

/// Composes and enqueues notifications for payments workflows.
#[derive(Clone)]
pub(super) struct PaymentsNotificationComposer {
    db: DynDB,
    notifications_manager: DynNotificationsManager,
    server_cfg: HttpServerConfig,
}

impl PaymentsNotificationComposer {
    /// Create a new payments notification composer.
    pub(super) fn new(
        db: DynDB,
        notifications_manager: DynNotificationsManager,
        server_cfg: HttpServerConfig,
    ) -> Self {
        Self {
            db,
            notifications_manager,
            server_cfg,
        }
    }

    /// Build the notification template payload for a refund request.
    pub(super) async fn build_refund_request_template_data(
        &self,
        community_id: Uuid,
        event_id: Uuid,
    ) -> Result<Value> {
        // Load the event summary and site theme used by the refund request template
        let (event, site_settings) = tokio::try_join!(
            self.db.get_event_summary_by_id(community_id, event_id),
            self.db.get_site_settings(),
        )?;

        // Point organizers to the full group dashboard events tab
        let base_url = self
            .server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&self.server_cfg.base_url);
        let link = format!("{base_url}/dashboard/group?tab=events");

        serde_json::to_value(&EventRefundRequested {
            event,
            link,
            theme: site_settings.theme,
        })
        .map_err(Into::into)
    }

    /// Enqueue the attendee welcome notification for a completed provider checkout.
    pub(super) async fn enqueue_checkout_completed_notification(
        &self,
        completed_purchase: CompletedEventPurchase,
    ) {
        self.enqueue_event_welcome_notification_with_self_service(
            completed_purchase.community_id,
            completed_purchase.event_id,
            completed_purchase.user_id,
            EventWelcomeSelfService::EventPageRefund,
        )
        .await;
    }

    /// Enqueue the attendee welcome notification with dashboard cancellation guidance.
    pub(super) async fn enqueue_event_welcome_notification(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) {
        self.enqueue_event_welcome_notification_with_self_service(
            community_id,
            event_id,
            user_id,
            EventWelcomeSelfService::DashboardCancellation,
        )
        .await;
    }

    /// Enqueue the attendee welcome notification with context-specific self-service guidance.
    async fn enqueue_event_welcome_notification_with_self_service(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        self_service: EventWelcomeSelfService,
    ) {
        // Skip notification delivery when the event context cannot be loaded
        let Some((event, site_settings)) = self
            .load_event_notification_context(community_id, event_id, "event welcome")
            .await
        else {
            return;
        };

        // Build the attendee-facing welcome notification and calendar attachment
        let base_url = self.base_url();
        let dashboard_link = match self_service {
            EventWelcomeSelfService::DashboardCancellation => {
                Some(build_user_dashboard_events_link(base_url))
            }
            EventWelcomeSelfService::EventPageRefund => None,
        };
        let link = build_event_page_link(base_url, &event);
        let notification = NewNotification {
            attachments: vec![build_event_calendar_attachment(base_url, &event)],
            kind: NotificationKind::EventWelcome,
            recipients: vec![user_id],
            template_data: serde_json::to_value(&EventWelcome {
                event,
                link,
                theme: site_settings.theme,

                dashboard_link,
            })
            .ok(),
        };

        self.enqueue_notification(&notification, "event welcome").await;
    }

    /// Enqueue the attendee notification for an approved refund request.
    pub(super) async fn enqueue_refund_approval_notification(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) {
        // Skip notification delivery when the event context cannot be loaded
        let Some((event, site_settings)) = self
            .load_event_notification_context(community_id, event_id, "refund approval")
            .await
        else {
            return;
        };

        // Build the attendee-facing refund approval notification
        let link = build_event_page_link(self.base_url(), &event);
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventRefundApproved,
            recipients: vec![user_id],
            template_data: serde_json::to_value(&EventRefundApproved {
                event,
                link,
                theme: site_settings.theme,
            })
            .ok(),
        };

        self.enqueue_notification(&notification, "refund approval").await;
    }

    /// Enqueue the attendee notification for a rejected refund request.
    pub(super) async fn enqueue_refund_rejection_notification(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
    ) {
        // Skip notification delivery when the event context cannot be loaded
        let Some((event, site_settings)) = self
            .load_event_notification_context(community_id, event_id, "refund rejection")
            .await
        else {
            return;
        };

        // Build the attendee-facing refund rejection notification
        let link = build_event_page_link(self.base_url(), &event);
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventRefundRejected,
            recipients: vec![user_id],
            template_data: serde_json::to_value(&EventRefundRejected {
                event,
                link,
                theme: site_settings.theme,
            })
            .ok(),
        };

        self.enqueue_notification(&notification, "refund rejection").await;
    }

    /// Returns the configured base URL without a trailing slash.
    fn base_url(&self) -> &str {
        self.server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&self.server_cfg.base_url)
    }

    /// Enqueues a notification and logs failures without interrupting the caller.
    async fn enqueue_notification(&self, notification: &NewNotification, notification_kind: &str) {
        // Log and swallow enqueue failures so the main payments flow can continue
        if let Err(err) = self.notifications_manager.enqueue(notification).await {
            warn!(error = %err, "failed to enqueue {notification_kind} notification");
        }
    }

    /// Loads the shared event and site settings used by payments notifications.
    async fn load_event_notification_context(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        notification_kind: &str,
    ) -> Option<(
        crate::types::event::EventSummary,
        crate::types::site::SiteSettings,
    )> {
        // Load the shared event and site context required by payments notifications
        match tokio::try_join!(
            self.db.get_event_summary_by_id(community_id, event_id),
            self.db.get_site_settings(),
        ) {
            Ok(context) => Some(context),
            Err(err) => {
                warn!(error = %err, "failed to load {notification_kind} notification context");
                None
            }
        }
    }
}

/// Self-service guidance shown in event welcome notifications.
#[derive(Debug, Clone, Copy)]
enum EventWelcomeSelfService {
    /// Attendees can cancel from the My Events dashboard.
    DashboardCancellation,
    /// Attendees currently manage paid ticket refunds from the event page.
    EventPageRefund,
}
