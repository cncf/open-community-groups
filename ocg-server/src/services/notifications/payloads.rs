//! Notification payload builders.

use anyhow::{Result, anyhow};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DBOperations, auth::EmailVerificationNotification,
        dashboard::group::EventCohostNotificationData,
    },
    templates::notifications::{
        CommunityCustom, EmailVerification, EventAttendanceCanceled, EventCanceled,
        EventCohostEmailEvent, EventCohostInvitation, EventCohostRemovalReason, EventCohostRemoved,
        EventCohostResponded, EventCustom, EventPaidConfigured, EventPaidConfiguredItem,
        EventPublished, EventRefundApproved, EventRefundRejected, EventRescheduled,
        EventWaitlistJoined, EventWaitlistLeft, EventWelcome, GroupCustom, InboxMessageReceived,
        InboxReplyReceived, SpeakerWelcome,
    },
    types::{
        community::CommunitySummary,
        event::{EventCohostStatus, EventSummary},
        group::GroupSummary,
        inbox::{InboxConversation, InboxMessage},
        notifications::CustomNotificationContent,
        site::SiteSettings,
    },
    util::{
        base_url_without_trailing_slash, build_event_calendar_attachment, build_event_page_link,
        build_user_dashboard_events_link,
    },
};

use super::{NewNotification, NotificationKind};

#[cfg(test)]
mod tests;

/// Builds the content of a community custom notification sent to group teams.
pub(crate) fn build_community_custom_notification(
    community: &CommunitySummary,
    content: &CustomNotificationContent,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> CommunityCustom {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    CommunityCustom {
        body: content.body.clone(),
        community_display_name: community.display_name.clone(),
        link: format!("{base_url}/{}", community.name),
        subject: content.subject.clone(),
        theme: site_settings.theme.clone(),
    }
}

/// Builds the email verification notification payload required by password
/// sign-up.
///
/// The verification code is generated here and stored by the database together
/// with the serialized template data.
pub(crate) async fn build_email_verification_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
) -> Result<EmailVerificationNotification> {
    // Require a base URL before loading any template context
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    if base_url.is_empty() {
        return Err(anyhow!("base URL is required to send verification email"));
    }

    // Build the template data from the current site theme
    let code = Uuid::new_v4();
    let site_settings = db.get_site_settings().await?;
    let template_data = serde_json::to_value(EmailVerification {
        link: format!("{base_url}/verify-email/{code}"),
        theme: site_settings.theme,
    })?;

    Ok(EmailVerificationNotification {
        code,
        template_data,
    })
}

/// Builds an event attendance cancellation notification.
pub(crate) fn build_event_attendance_canceled_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventAttendanceCanceled {
        dashboard_link: build_user_dashboard_events_link(base_url),
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
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
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventCanceled {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        group_ids: vec![],
        kind: NotificationKind::EventCanceled,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds a co-hosting invitation notification for one co-host group.
///
/// Every item must belong to the same co-host group.
pub(super) fn build_event_cohost_invitation_notification(
    items: &[EventCohostNotificationData],
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    // Require common group context before building the aggregate payload
    let first_item = items
        .first()
        .ok_or_else(|| anyhow!("co-hosting invitation requires at least one event"))?;

    // Snapshot the invited group, the owner group, and the events
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventCohostInvitation {
        cohost_community_display_name: first_item.cohost_community_display_name.clone(),
        cohost_group_name: first_item.cohost_group_name.clone(),
        events: items.iter().map(cohost_email_event).collect(),
        link: build_group_dashboard_cohosts_link(base_url),
        owner_community_display_name: first_item.owner_community_display_name.clone(),
        owner_group_name: first_item.owner_group_name.clone(),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::EventCohostInvitation,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds a notification telling a co-host group its co-hosting ended.
///
/// Every item must belong to the same co-host group.
pub(super) fn build_event_cohost_removed_notification(
    items: &[EventCohostNotificationData],
    reason: EventCohostRemovalReason,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    // Require common group context before building the aggregate payload
    let first_item = items
        .first()
        .ok_or_else(|| anyhow!("co-hosting removal requires at least one event"))?;

    // Deleted events are no longer listed in the dashboard, so omit the link
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let link = (reason != EventCohostRemovalReason::EventDeleted)
        .then(|| build_group_dashboard_cohosts_link(base_url));

    // Snapshot the co-host group, the owner group, and the events
    let template_data = EventCohostRemoved {
        cohost_group_name: first_item.cohost_group_name.clone(),
        events: items.iter().map(cohost_email_event).collect(),
        owner_community_display_name: first_item.owner_community_display_name.clone(),
        owner_group_name: first_item.owner_group_name.clone(),
        reason,
        theme: site_settings.theme.clone(),

        link,
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::EventCohostRemoved,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds a notification telling the owner group a co-host responded.
pub(super) fn build_event_cohost_responded_notification(
    item: &EventCohostNotificationData,
    status: EventCohostStatus,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventCohostResponded {
        cohost_community_display_name: item.cohost_community_display_name.clone(),
        cohost_group_name: item.cohost_group_name.clone(),
        event: cohost_email_event(item),
        link: format!("{base_url}/dashboard/group?tab=events"),
        owner_group_name: item.owner_group_name.clone(),
        status,
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::EventCohostResponded,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds the content of an organizer-authored event custom notification.
pub(crate) fn build_event_custom_notification(
    event: &EventSummary,
    content: &CustomNotificationContent,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> EventCustom {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    EventCustom {
        body: content.body.clone(),
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        subject: content.subject.clone(),
        theme: site_settings.theme.clone(),
    }
}

/// Builds a paid event configuration notification for community admins.
pub(super) fn build_event_paid_configured_notification(
    events: &[EventSummary],
    recipients: Vec<Uuid>,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    // Require common event context before building the aggregate payload
    let first_event = events
        .first()
        .ok_or_else(|| anyhow!("paid event notification requires at least one event"))?;

    // Snapshot only the event details needed by the admin notification
    let events = events
        .iter()
        .map(|event| EventPaidConfiguredItem {
            event_id: event.event_id,
            name: event.name.clone(),
            timezone: event.timezone,

            has_external_payment: event.has_external_payment,
            starts_at: event.starts_at,
        })
        .collect::<Vec<_>>();
    let template_data = EventPaidConfigured {
        community_display_name: first_event.community_display_name.clone(),
        event_count: events.len(),
        events,
        group_name: first_event.group_name.clone(),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::EventPaidConfigured,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds an event publication notification.
///
/// `cohost_group_name` is set for the copy sent to a co-host group's audience.
/// `group_ids` lists every group the email names: the owner group and all
/// approved co-hosts.
pub(crate) fn build_event_published_notification(
    event: &EventSummary,
    cohost_group_name: Option<&str>,
    group_ids: Vec<Uuid>,
    recipients: Vec<Uuid>,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventPublished {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),

        cohost_group_name: cohost_group_name.map(ToString::to_string),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        group_ids,
        kind: NotificationKind::EventPublished,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds template data for an approved event refund.
pub(crate) fn build_event_refund_approved_template_data(
    event: &EventSummary,
    external_payment: bool,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<serde_json::Value> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventRefundApproved {
        event: event.clone(),
        external_payment,
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    serde_json::to_value(&template_data).map_err(Into::into)
}

/// Builds an event refund rejection notification.
pub(crate) fn build_event_refund_rejected_notification(
    event: &EventSummary,
    recipient_user_id: Uuid,
    rejection_reason: &str,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventRefundRejected {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        rejection_reason: rejection_reason.to_string(),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
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
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventRescheduled {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        group_ids: vec![],
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
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventWaitlistJoined {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
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
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventWaitlistLeft {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::EventWaitlistLeft,
        recipients: vec![recipient_user_id],
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
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let dashboard_link = include_dashboard_link.then(|| build_user_dashboard_events_link(base_url));
    let template_data = EventWelcome {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),

        dashboard_link,
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        group_ids: vec![],
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
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = SpeakerWelcome {
        event: event.clone(),
        link: build_event_page_link(base_url, event),
        theme: site_settings.theme.clone(),
    };

    Ok(NewNotification {
        attachments: vec![build_event_calendar_attachment(base_url, event)],
        group_ids: vec![],
        kind: NotificationKind::SpeakerWelcome,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds the content of an organizer-authored group custom notification.
pub(crate) fn build_group_custom_notification(
    group: &GroupSummary,
    content: &CustomNotificationContent,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
) -> GroupCustom {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    GroupCustom {
        body: content.body.clone(),
        group: group.clone(),
        link: format!(
            "{}/{}/group/{}",
            base_url,
            group.community_name,
            group.public_slug()
        ),
        subject: content.subject.clone(),
        theme: site_settings.theme.clone(),
    }
}

/// Builds the notification telling group team members that a user wrote to
/// the group inbox. The link opens the conversation in the group dashboard
/// when its group is selected; the email names the group because the link
/// cannot select it.
pub(crate) fn build_inbox_message_received_notification(
    conversation: &InboxConversation,
    message: &InboxMessage,
    recipients: Vec<Uuid>,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    // Resolve the name shown for the user who wrote the message
    let author = message
        .author
        .as_ref()
        .ok_or_else(|| anyhow!("inbox message author not found"))?;

    // Snapshot the message and its group context
    let template_data = InboxMessageReceived {
        body: message.body.clone(),
        community_display_name: conversation.community_display_name.clone(),
        group_name: conversation.group_name.clone(),
        link: format!(
            "/dashboard/group?tab=inbox&conversation_id={}",
            conversation.inbox_conversation_id
        ),
        sender_name: author.name.clone().unwrap_or_else(|| author.username.clone()),
        theme: site_settings.theme.clone(),

        event_name: conversation.event.as_ref().map(|event| event.name.clone()),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::InboxMessageReceived,
        recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

/// Builds the notification telling the user of a conversation that the group
/// replied. The link opens the conversation in the user dashboard.
pub(crate) fn build_inbox_reply_received_notification(
    conversation: &InboxConversation,
    message: &InboxMessage,
    site_settings: &SiteSettings,
) -> Result<NewNotification> {
    // Resolve the user who receives the reply
    let user = conversation
        .user
        .as_ref()
        .ok_or_else(|| anyhow!("inbox conversation user not found"))?;

    // Snapshot the reply and its group context
    let template_data = InboxReplyReceived {
        body: message.body.clone(),
        community_display_name: conversation.community_display_name.clone(),
        group_name: conversation.group_name.clone(),
        link: format!(
            "/dashboard/user?tab=inbox&conversation_id={}",
            conversation.inbox_conversation_id
        ),
        theme: site_settings.theme.clone(),

        event_name: conversation.event.as_ref().map(|event| event.name.clone()),
    };

    Ok(NewNotification {
        attachments: vec![],
        group_ids: vec![],
        kind: NotificationKind::InboxReplyReceived,
        recipients: vec![user.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    })
}

// Helpers.

/// Returns the link to the co-hosts section of the group dashboard.
fn build_group_dashboard_cohosts_link(base_url: &str) -> String {
    format!("{base_url}/dashboard/group?tab=cohosts")
}

/// Snapshots the event details shown in co-hosting notifications.
fn cohost_email_event(item: &EventCohostNotificationData) -> EventCohostEmailEvent {
    EventCohostEmailEvent {
        name: item.event_name.clone(),
        timezone: item.timezone,

        starts_at: item.starts_at,
    }
}
