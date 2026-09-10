//! Best-effort notification helpers.
//!
//! Best-effort notifications run after the core operation has committed. They
//! load their context, build their payload, and enqueue it, logging any failure
//! together with the identifiers needed to reconstruct it. They never fail or
//! undo the operation that triggered them.

use anyhow::Result;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DBOperations,
    services::notifications::{DynNotificationsManager, load_event_notification_context},
    templates::notifications::{
        CfsSubmissionUpdated, CommunityTeamInvitation, GroupTeamInvitation,
    },
    types::{
        event::EventSummary,
        notifications::{NewNotification, NotificationKind},
        site::SiteSettings,
    },
    util::base_url_without_trailing_slash,
};

#[cfg(test)]
mod tests;

/// Enqueues the speaker notification for a reviewed CFS submission best-effort.
///
/// The submission author and status are loaded together with the site
/// settings; the caller supplies the event the submission belongs to. Failures
/// are logged with the submission identifiers and swallowed.
pub(crate) async fn enqueue_cfs_submission_updated_best_effort(
    db: &dyn DBOperations,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    reviewer_id: Uuid,
    cfs_submission_id: Uuid,
    event: EventSummary,
) {
    let event_id = event.event_id;
    if let Err(err) = async {
        // Load the submission author, status, and site context
        let (notification_data, site_settings) = tokio::try_join!(
            db.get_cfs_submission_notification_data(event_id, cfs_submission_id),
            db.get_site_settings(),
        )?;

        // Build the notification with its user dashboard link
        let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
        let template_data = CfsSubmissionUpdated {
            action_required_message: notification_data.action_required_message,
            event,
            link: format!("{base_url}/dashboard/user?tab=submissions"),
            status_name: notification_data.status_name,
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::CfsSubmissionUpdated,
            recipients: vec![notification_data.user_id],
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        notifications_manager.enqueue(&notification).await
    }
    .await
    {
        warn!(
            error = %err,
            %event_id,
            %cfs_submission_id,
            %reviewer_id,
            "failed to enqueue CFS submission update notification"
        );
    }
}

/// Enqueues the community team invitation notification best-effort.
///
/// The community summary and site settings are loaded, and the invitation is
/// addressed to the invited user. Failures are logged with the community and
/// user identifiers and swallowed.
pub(crate) async fn enqueue_community_team_invitation_best_effort(
    db: &dyn DBOperations,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    user_id: Uuid,
) {
    if let Err(err) = async {
        // Load the community and site context
        let (community, site_settings) = tokio::try_join!(
            db.get_community_summary(community_id),
            db.get_site_settings()
        )?;

        // Build the notification with its invitations dashboard link
        let template_data = CommunityTeamInvitation {
            community_name: community.display_name,
            link: format!(
                "{}/dashboard/user?tab=invitations",
                base_url_without_trailing_slash(&server_cfg.base_url)
            ),
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::CommunityTeamInvitation,
            recipients: vec![user_id],
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        notifications_manager.enqueue(&notification).await
    }
    .await
    {
        warn!(
            error = %err,
            %community_id,
            %user_id,
            "failed to enqueue community team invitation notification"
        );
    }
}

/// Enqueues the group team invitation notification best-effort.
///
/// The group summary and site settings are loaded, and the invitation is
/// addressed to the invited user. Failures are logged with the community,
/// group, and user identifiers and swallowed.
pub(crate) async fn enqueue_group_team_invitation_best_effort(
    db: &dyn DBOperations,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) {
    if let Err(err) = async {
        // Load the group and site context
        let (site_settings, group) = tokio::try_join!(
            db.get_site_settings(),
            db.get_group_summary(community_id, group_id)
        )?;

        // Build the notification with its invitations dashboard link
        let template_data = GroupTeamInvitation {
            group,
            link: format!(
                "{}/dashboard/user?tab=invitations",
                base_url_without_trailing_slash(&server_cfg.base_url)
            ),
            theme: site_settings.theme,
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::GroupTeamInvitation,
            recipients: vec![user_id],
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        notifications_manager.enqueue(&notification).await
    }
    .await
    {
        warn!(
            error = %err,
            %community_id,
            %group_id,
            %user_id,
            "failed to enqueue group team invitation notification"
        );
    }
}

/// Enqueues an event notification best-effort after the triggering operation
/// committed.
///
/// The event summary and site settings are loaded, handed to `build` together
/// with the server configuration, and the resulting notification is enqueued.
/// Context loading, payload building, and enqueue failures are logged with the
/// event identifiers and swallowed.
pub(crate) async fn enqueue_event_notification_best_effort<F>(
    db: &dyn DBOperations,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    event_id: Uuid,
    build: F,
) where
    F: FnOnce(&EventSummary, &HttpServerConfig, &SiteSettings) -> Result<NewNotification>,
{
    // Load the event and site context the payload builder needs
    let (event, site_settings) =
        match load_event_notification_context(db, community_id, event_id).await {
            Ok(context) => context,
            Err(err) => {
                warn!(
                    error = %err,
                    %community_id,
                    %event_id,
                    "failed to load event notification context"
                );
                return;
            }
        };

    // Build the notification payload
    let notification = match build(&event, server_cfg, &site_settings) {
        Ok(notification) => notification,
        Err(err) => {
            warn!(
                error = %err,
                %community_id,
                %event_id,
                "failed to build event notification"
            );
            return;
        }
    };

    // Enqueue the notification, logging delivery queue failures
    if let Err(err) = notifications_manager.enqueue(&notification).await {
        warn!(
            error = %err,
            %community_id,
            %event_id,
            kind = ?notification.kind,
            "failed to enqueue event notification"
        );
    }
}
