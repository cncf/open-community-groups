//! Notification enqueue workflows.

use std::collections::{BTreeMap, HashSet};

use anyhow::{Result, anyhow};
use chrono::{DateTime, TimeDelta, Utc};
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DBOperations,
        dashboard::group::{EventCohostNotificationData, EventCohostRef, EventCohostResponse},
        inbox::PostedInboxMessage,
        notifications::CustomNotificationTracking,
    },
    services::notifications::{
        load_event_notification_context,
        payloads::{
            build_event_attendance_canceled_notification, build_event_canceled_notification,
            build_event_cohost_invitation_notification, build_event_cohost_removed_notification,
            build_event_cohost_responded_notification, build_event_paid_configured_notification,
            build_event_published_notification, build_event_rescheduled_notification,
            build_inbox_message_received_notification, build_inbox_reply_received_notification,
            build_speaker_welcome_notification,
        },
    },
    templates::notifications::{EventCohostRemovalReason, EventCustom, GroupCustom},
    types::{
        event::{EventCohostStatus, EventSummary},
        inbox::{InboxConversation, InboxMessage},
        notifications::{
            EventCustomNotificationInput, GroupCustomNotificationInput, NewNotification,
            NotificationKind,
        },
    },
    util::{base_url_without_trailing_slash, build_event_page_link},
};

mod event_series;

pub(crate) use event_series::{
    enqueue_event_series_canceled_notifications, enqueue_event_series_published_notifications,
};

#[cfg(test)]
mod tests;

/// Minimum shift required to notify a reschedule.
const MIN_RESCHEDULE_SHIFT: TimeDelta = TimeDelta::minutes(15);

/// Enqueues notifications required by event attendance cancellation.
pub(crate) async fn enqueue_event_attendance_cancellation_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    event_id: Uuid,
    canceled_user_id: Uuid,
) -> Result<()> {
    // Fetch notification context after the attendance mutation
    let (event, site_settings) =
        load_event_notification_context(db, community_id, event_id).await?;

    // Confirm the canceled attendance to the attendee
    let notification = build_event_attendance_canceled_notification(
        &event,
        canceled_user_id,
        server_cfg,
        &site_settings,
    )?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues the event-canceled notification for attendees, waitlist users, and speakers.
pub(crate) async fn enqueue_event_canceled_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
) -> Result<()> {
    // Fetch event full and attendee IDs concurrently
    let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
        db.get_event_full(community_id, group_id, event_id),
        db.list_event_attendees_ids(group_id, event_id, false),
        db.list_event_waitlist_ids(group_id, event_id)
    )?;

    // Test events are reachable by direct link but should not broadcast cancellations
    if event_full.test_event {
        return Ok(());
    }

    // Combine attendee, waitlist, and speaker IDs
    let speaker_ids = event_full.speakers_ids();
    let recipients: Vec<Uuid> = attendee_ids
        .into_iter()
        .chain(waitlist_ids)
        .chain(speaker_ids)
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();

    if recipients.is_empty() {
        return Ok(());
    }

    // Build and enqueue the cancellation notification
    let site_settings = db.get_site_settings().await?;
    let event_summary = EventSummary::from(&event_full);
    let notification =
        build_event_canceled_notification(&event_summary, recipients, server_cfg, &site_settings)?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues one co-hosting invitation per co-host group to its admins.
pub(crate) async fn enqueue_event_cohost_invitation_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    invitations: &[EventCohostRef],
) -> Result<()> {
    // Load the invitation content grouped by co-host group
    let groups = load_cohost_notification_groups(db, invitations).await?;
    if groups.is_empty() {
        return Ok(());
    }

    // Enqueue one combined invitation per co-host group with admins
    let site_settings = db.get_site_settings().await?;
    for (cohost_group_id, items) in groups {
        let recipients = db.list_group_admin_ids(cohost_group_id).await?;
        if recipients.is_empty() {
            warn!(%cohost_group_id, "no group admins to notify about co-hosting invitation");
            continue;
        }
        let notification = build_event_cohost_invitation_notification(
            &items,
            recipients,
            server_cfg,
            &site_settings,
        )?;
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

/// Enqueues one co-hosting removal notification per co-host group to its admins.
pub(crate) async fn enqueue_event_cohost_removed_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    reason: EventCohostRemovalReason,
    refs: &[EventCohostRef],
) -> Result<()> {
    // Load the removal content grouped by co-host group
    let groups = load_cohost_notification_groups(db, refs).await?;
    if groups.is_empty() {
        return Ok(());
    }

    // Enqueue one combined notification per co-host group with admins
    let site_settings = db.get_site_settings().await?;
    for (cohost_group_id, items) in groups {
        let recipients = db.list_group_admin_ids(cohost_group_id).await?;
        if recipients.is_empty() {
            warn!(%cohost_group_id, %reason, "no group admins to notify about co-hosting removal");
            continue;
        }
        let notification = build_event_cohost_removed_notification(
            &items,
            reason,
            recipients,
            server_cfg,
            &site_settings,
        )?;
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

/// Enqueues the notification telling the owner group's admins that a co-host responded.
pub(crate) async fn enqueue_event_cohost_responded_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    response: &EventCohostResponse,
    status: EventCohostStatus,
) -> Result<()> {
    // Resolve the owner group's admins before loading the content
    let recipients = db.list_group_admin_ids(response.owner_group_id).await?;
    if recipients.is_empty() {
        warn!(
            owner_group_id = %response.owner_group_id,
            invitation_id = %response.invitation_id,
            "no group admins to notify about co-hosting response"
        );
        return Ok(());
    }

    // Load the response content
    let reference = EventCohostRef {
        cohost_group_id: response.cohost_group_id,
        event_id: response.event_id,
        invitation_id: response.invitation_id,
    };
    let item = db
        .get_event_cohost_notification_data(&[reference])
        .await?
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("co-hosting notification data not found"))?;

    // Build and enqueue the required owner notification
    let site_settings = db.get_site_settings().await?;
    let notification = build_event_cohost_responded_notification(
        &item,
        status,
        recipients,
        server_cfg,
        &site_settings,
    )?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues one aggregate paid event configuration notification to community admins.
pub(crate) async fn enqueue_event_paid_configured_notifications(
    db: &dyn DBOperations,
    community_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<()> {
    if event_ids.is_empty() {
        return Ok(());
    }

    // Resolve required recipients before loading event and theme data
    let recipients = db.list_community_admin_ids(community_id).await?;
    if recipients.is_empty() {
        return Ok(());
    }

    // Load persisted event details and exclude test events from the aggregate
    let mut events = Vec::with_capacity(event_ids.len());
    for event_id in event_ids {
        let event = db.get_event_summary(community_id, group_id, *event_id).await?;
        if !event.test_event {
            events.push(event);
        }
    }
    if events.is_empty() {
        return Ok(());
    }

    // Build and enqueue the required admin notification
    let site_settings = db.get_site_settings().await?;
    let notification =
        build_event_paid_configured_notification(&events, recipients, &site_settings)?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues event-published notifications to the owner and co-host audiences
/// and to the speakers.
pub(crate) async fn enqueue_event_published_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
) -> Result<()> {
    // Fetch the event and the owner group audience concurrently
    let (event_full, owner_audience) = tokio::try_join!(
        db.get_event_full(community_id, group_id, event_id),
        group_audience_ids(db, group_id)
    )?;

    // Test events are reachable by direct link but should not broadcast publication
    if event_full.test_event {
        return Ok(());
    }

    // Every copy names the owner group and all approved co-hosts, so each copy
    // has the same eligibility and the de-duplication below cannot drop an
    // eligible recipient
    let event_group_ids: Vec<Uuid> = std::iter::once(group_id)
        .chain(event_full.cohosts.iter().map(|cohost| cohost.group_id))
        .collect();

    // Speakers get a separate notification, so they are covered first
    let speaker_ids = event_full.speakers_ids();
    let mut covered: HashSet<Uuid> = speaker_ids.iter().copied().collect();

    // Keep owner audience members not covered yet
    let owner_recipients: Vec<Uuid> =
        owner_audience.into_iter().filter(|id| covered.insert(*id)).collect();

    // Add each co-host audience, skipping recipients already covered. A
    // published, non-canceled event only exposes approved co-hosts in its
    // public projection, so `cohosts` is the approved co-host list here
    let mut cohosts = event_full.cohosts.iter().collect::<Vec<_>>();
    cohosts
        .sort_by(|left, right| left.name.cmp(&right.name).then(left.group_id.cmp(&right.group_id)));
    let mut cohost_recipients = Vec::new();
    for cohost in cohosts {
        let recipients: Vec<Uuid> = group_audience_ids(db, cohost.group_id)
            .await?
            .into_iter()
            .filter(|id| covered.insert(*id))
            .collect();
        if !recipients.is_empty() {
            cohost_recipients.push((cohost.name.clone(), recipients));
        }
    }

    // Skip the remaining work when nobody has to be notified
    if owner_recipients.is_empty() && cohost_recipients.is_empty() && speaker_ids.is_empty() {
        return Ok(());
    }

    // Prepare common notification data
    let site_settings = db.get_site_settings().await?;
    let event_summary = EventSummary::from(&event_full);

    // Enqueue owner audience notifications about the published event
    if !owner_recipients.is_empty() {
        let notification = build_event_published_notification(
            &event_summary,
            None,
            event_group_ids.clone(),
            owner_recipients,
            server_cfg,
            &site_settings,
        )?;
        db.enqueue_notification(&notification).await?;
    }

    // Enqueue one notification per co-host audience about the published event
    for (cohost_group_name, recipients) in cohost_recipients {
        let notification = build_event_published_notification(
            &event_summary,
            Some(&cohost_group_name),
            event_group_ids.clone(),
            recipients,
            server_cfg,
            &site_settings,
        )?;
        db.enqueue_notification(&notification).await?;
    }

    // Enqueue speaker notifications about being added to the event
    if !speaker_ids.is_empty() {
        let notification = build_speaker_welcome_notification(
            &event_summary,
            speaker_ids,
            server_cfg,
            &site_settings,
        )?;
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

/// Enqueues reschedule notifications when an update moves a future published event.
///
/// `now` is the instant the caller read once for the whole operation; past and
/// test events, and events that end up in the past, do not notify.
pub(crate) async fn enqueue_event_rescheduled_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
    before: &EventSummary,
    now: DateTime<Utc>,
) -> Result<()> {
    // Past or test events should not broadcast reschedules
    if before.is_past_at(now) || before.test_event {
        return Ok(());
    }

    // Fetch updated event summary to compare start times and detect reschedule
    let after = db.get_event_summary(community_id, group_id, event_id).await?;
    let should_notify = match (before.published, before.starts_at, after.starts_at) {
        (true, Some(b_starts_at), Some(a_starts_at)) if a_starts_at > now => {
            (a_starts_at - b_starts_at).abs() >= MIN_RESCHEDULE_SHIFT
        }
        _ => false,
    };
    if !should_notify {
        return Ok(());
    }

    // Fetch event full and attendee IDs concurrently
    let (event_full, attendee_ids) = tokio::try_join!(
        db.get_event_full(community_id, group_id, event_id),
        db.list_event_attendees_ids(group_id, event_id, false)
    )?;

    // Combine attendee and speaker IDs
    let speaker_ids = event_full.speakers_ids();
    let recipients: Vec<Uuid> = attendee_ids
        .into_iter()
        .chain(speaker_ids)
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();
    if recipients.is_empty() {
        return Ok(());
    }

    // Build and enqueue the reschedule notification
    let site_settings = db.get_site_settings().await?;
    let event_summary = EventSummary::from(&event_full);
    let notification = build_event_rescheduled_notification(
        &event_summary,
        recipients,
        server_cfg,
        &site_settings,
    )?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues the email telling group team members that a user wrote to the
/// group inbox. Required: it runs in the caller's transaction and its failure
/// rolls the message back.
pub(crate) async fn enqueue_inbox_message_received_notification(
    db: &dyn DBOperations,
    posted: &PostedInboxMessage,
) -> Result<()> {
    // Load the conversation, the group team members to email and the site theme
    let (conversation, recipient_ids, site_settings) = tokio::try_join!(
        db.get_group_inbox_conversation(posted.group_id, posted.inbox_conversation_id),
        db.list_inbox_recipient_ids(posted.group_id),
        db.get_site_settings()
    )?;
    let conversation = conversation.ok_or_else(|| anyhow!("inbox conversation not found"))?;
    let message = find_inbox_message(&conversation, posted.inbox_message_id)?;

    // Never email the author of the message
    let author_user_id = message.author.as_ref().map(|author| author.user_id);
    let recipients: Vec<Uuid> = recipient_ids
        .into_iter()
        .filter(|user_id| Some(*user_id) != author_user_id)
        .collect();

    // Keep the message when the group has nobody to email; the open badge still shows it
    if recipients.is_empty() {
        warn!(
            group_id = %posted.group_id,
            inbox_conversation_id = %posted.inbox_conversation_id,
            inbox_message_id = %posted.inbox_message_id,
            "inbox message has no recipient to notify"
        );
        return Ok(());
    }

    // Build and enqueue the notification
    let notification = build_inbox_message_received_notification(
        &conversation,
        message,
        recipients,
        &site_settings,
    )?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues the email telling the user of a conversation that the group
/// replied. Required: it runs in the caller's transaction and its
/// failure rolls the reply back.
pub(crate) async fn enqueue_inbox_reply_received_notification(
    db: &dyn DBOperations,
    posted: &PostedInboxMessage,
) -> Result<()> {
    // Load the conversation and the site theme
    let (conversation, site_settings) = tokio::try_join!(
        db.get_group_inbox_conversation(posted.group_id, posted.inbox_conversation_id),
        db.get_site_settings()
    )?;
    let conversation = conversation.ok_or_else(|| anyhow!("inbox conversation not found"))?;
    let message = find_inbox_message(&conversation, posted.inbox_message_id)?;

    // Build and enqueue the notification for the conversation user
    let notification =
        build_inbox_reply_received_notification(&conversation, message, &site_settings)?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues an organizer-authored event notification with its tracking record.
///
/// The caller resolves the recipients; the notification content and the
/// tracking entry are built here so no caller constructs the database-owned
/// tracking type.
pub(crate) async fn enqueue_tracked_event_custom_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    input: &EventCustomNotificationInput,
) -> Result<()> {
    // Load the event and site context for the notification content
    let (event, site_settings) =
        load_event_notification_context(db, input.community_id, input.event_id).await?;

    // Build the notification with its event page link
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = EventCustom {
        body: input.body.clone(),
        link: build_event_page_link(base_url, &event),
        event,
        subject: input.subject.clone(),
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        group_ids: vec![input.group_id],
        kind: NotificationKind::EventCustom,
        recipients: input.recipients.clone(),
        template_data: Some(serde_json::to_value(&template_data)?),
    };

    // Enqueue the notification together with its audit record
    db.enqueue_tracked_custom_notification(
        &notification,
        CustomNotificationTracking {
            body: input.body.clone(),
            created_by: input.actor_user_id,
            event_id: Some(input.event_id),
            group_id: Some(input.group_id),
            recipient_count: input.recipients.len(),
            subject: input.subject.clone(),
        },
    )
    .await
}

/// Enqueues an organizer-authored group notification with its tracking record.
///
/// The caller resolves the recipients; the notification content and the
/// tracking entry are built here so no caller constructs the database-owned
/// tracking type.
pub(crate) async fn enqueue_tracked_group_custom_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    input: &GroupCustomNotificationInput,
) -> Result<()> {
    // Load the group and site context for the notification content
    let (site_settings, group) = tokio::try_join!(
        db.get_site_settings(),
        db.get_group_summary(input.community_id, input.group_id)
    )?;

    // Build the notification with its group page link
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let template_data = GroupCustom {
        body: input.body.clone(),
        link: format!(
            "{}/{}/group/{}",
            base_url,
            group.community_name,
            group.public_slug()
        ),
        group,
        subject: input.subject.clone(),
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        group_ids: vec![input.group_id],
        kind: NotificationKind::GroupCustom,
        recipients: input.recipients.clone(),
        template_data: Some(serde_json::to_value(&template_data)?),
    };

    // Enqueue the notification together with its audit record
    db.enqueue_tracked_custom_notification(
        &notification,
        CustomNotificationTracking {
            body: input.body.clone(),
            created_by: input.actor_user_id,
            event_id: None,
            group_id: Some(input.group_id),
            recipient_count: input.recipients.len(),
            subject: input.subject.clone(),
        },
    )
    .await
}

// Helpers.

/// Returns the message with the given identifier from a conversation thread.
fn find_inbox_message(
    conversation: &InboxConversation,
    inbox_message_id: Uuid,
) -> Result<&InboxMessage> {
    conversation
        .messages
        .iter()
        .find(|message| message.inbox_message_id == inbox_message_id)
        .ok_or_else(|| anyhow!("inbox message not found"))
}

/// Returns the members and accepted team members of a group, deduplicated.
async fn group_audience_ids(db: &dyn DBOperations, group_id: Uuid) -> Result<Vec<Uuid>> {
    let (member_ids, team_member_ids) = tokio::try_join!(
        db.list_group_members_ids(group_id),
        db.list_group_team_members_ids(group_id)
    )?;
    let mut audience = member_ids;
    audience.extend(team_member_ids);
    audience.sort();
    audience.dedup();

    Ok(audience)
}

/// Loads co-hosting notification content grouped by co-host group.
///
/// Groups are ordered by identifier and events by start time, so combined
/// notifications are deterministic.
async fn load_cohost_notification_groups(
    db: &dyn DBOperations,
    refs: &[EventCohostRef],
) -> Result<BTreeMap<Uuid, Vec<EventCohostNotificationData>>> {
    if refs.is_empty() {
        return Ok(BTreeMap::new());
    }

    // Group the loaded content by co-host group
    let mut groups: BTreeMap<Uuid, Vec<EventCohostNotificationData>> = BTreeMap::new();
    for item in db.get_event_cohost_notification_data(refs).await? {
        groups.entry(item.cohost_group_id).or_default().push(item);
    }

    // Order each group's events by start time
    for items in groups.values_mut() {
        items.sort_by(|left, right| {
            left.starts_at
                .cmp(&right.starts_at)
                .then(left.event_id.cmp(&right.event_id))
        });
    }

    Ok(groups)
}
