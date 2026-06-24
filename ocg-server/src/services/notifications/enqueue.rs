//! Notification enqueue workflows.

use std::collections::{HashMap, HashSet};

use anyhow::Result;
use chrono::{TimeDelta, Utc};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DBOperations,
    services::notifications::{
        NewNotification, NotificationKind,
        payloads::{
            build_event_attendance_canceled_notification, build_event_canceled_notification,
            build_event_published_notification, build_event_rescheduled_notification,
            build_event_waitlist_promoted_notification, build_event_welcome_notification,
            build_speaker_welcome_notification, should_send_waitlist_promoted_notification,
        },
    },
    templates::notifications::{
        EventSeriesCanceled, EventSeriesNotificationItem, EventSeriesPublished,
        SpeakerSeriesWelcome,
    },
    types::event::{EventFull, EventSummary},
    util::build_event_page_link,
};

/// Minimum shift required to notify a reschedule.
const MIN_RESCHEDULE_SHIFT: TimeDelta = TimeDelta::minutes(15);

/// Enqueues notifications required by event attendance cancellation.
pub(crate) async fn enqueue_event_attendance_cancellation_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    event_id: Uuid,
    canceled_user_id: Uuid,
    promoted_user_ids: Vec<Uuid>,
) -> Result<()> {
    // Fetch notification context after the attendance mutation
    let (site_settings, event) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(alliance_id, event_id)
    )?;

    // Confirm the canceled attendance to the attendee
    let notification = build_event_attendance_canceled_notification(
        &event,
        canceled_user_id,
        server_cfg,
        &site_settings,
    )?;
    db.enqueue_notification(&notification).await?;

    // Skip promotion notifications when no attendee was promoted
    if promoted_user_ids.is_empty()
        || !should_send_waitlist_promoted_notification(&event, &promoted_user_ids)
    {
        return Ok(());
    }

    // Build and enqueue the waitlist promotion notification
    let notification = build_event_waitlist_promoted_notification(
        &event,
        promoted_user_ids,
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
    alliance_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
) -> Result<()> {
    // Fetch event full and attendee IDs concurrently
    let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
        db.get_event_full(alliance_id, group_id, event_id),
        db.list_event_attendees_ids(group_id, event_id),
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

/// Enqueues event-published notifications to group members, team members, and speakers.
pub(crate) async fn enqueue_event_published_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
) -> Result<()> {
    // Fetch event full and group member IDs concurrently
    let (event_full, group_member_ids, team_member_ids) = tokio::try_join!(
        db.get_event_full(alliance_id, group_id, event_id),
        db.list_group_members_ids(group_id),
        db.list_group_team_members_ids(group_id)
    )?;

    // Test events are reachable by direct link but should not broadcast publication
    if event_full.test_event {
        return Ok(());
    }

    // Combine group members and team members
    let mut recipients = group_member_ids;
    recipients.extend(team_member_ids);
    recipients.sort();
    recipients.dedup();

    // Extract speaker IDs
    let speaker_ids = event_full.speakers_ids();
    let has_speakers = !speaker_ids.is_empty();

    // Filter out speakers because they get a separate notification
    let recipients: Vec<Uuid> = recipients
        .into_iter()
        .filter(|id| !speaker_ids.contains(id))
        .collect();
    let has_members = !recipients.is_empty();

    if !has_members && !has_speakers {
        return Ok(());
    }

    // Prepare common notification data
    let site_settings = db.get_site_settings().await?;
    let event_summary = EventSummary::from(&event_full);

    // Enqueue group member notifications about the published event
    if has_members {
        let notification = build_event_published_notification(
            &event_summary,
            recipients,
            server_cfg,
            &site_settings,
        )?;
        db.enqueue_notification(&notification).await?;
    }

    // Enqueue speaker notifications about being added to the event
    if has_speakers {
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
pub(crate) async fn enqueue_event_rescheduled_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
    before: &EventSummary,
) -> Result<()> {
    // Past or test events should not broadcast reschedules
    if before.is_past() || before.test_event {
        return Ok(());
    }

    // Fetch updated event summary to compare start times and detect reschedule
    let after = db.get_event_summary(alliance_id, group_id, event_id).await?;
    let should_notify = match (before.published, before.starts_at, after.starts_at) {
        (true, Some(b_starts_at), Some(a_starts_at)) if a_starts_at > Utc::now() => {
            (a_starts_at - b_starts_at).abs() >= MIN_RESCHEDULE_SHIFT
        }
        _ => false,
    };
    if !should_notify {
        return Ok(());
    }

    // Fetch event full and attendee IDs concurrently
    let (event_full, attendee_ids) = tokio::try_join!(
        db.get_event_full(alliance_id, group_id, event_id),
        db.list_event_attendees_ids(group_id, event_id)
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

/// Enqueues one aggregate cancellation notification per recipient event set.
pub(crate) async fn enqueue_event_series_canceled_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<()> {
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let mut recipient_events: HashMap<Uuid, Vec<EventSeriesNotificationItem>> = HashMap::new();

    // Build recipient event lists for each canceled occurrence
    for event_id in event_ids {
        // Fetch event full and affected user IDs for this canceled occurrence
        let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
            db.get_event_full(alliance_id, group_id, *event_id),
            db.list_event_attendees_ids(group_id, *event_id),
            db.list_event_waitlist_ids(group_id, *event_id)
        )?;

        // Test events in a series should stay out of cancellation broadcasts
        if event_full.test_event {
            continue;
        }

        // Map each recipient to the canceled occurrence relevant to them
        let event = event_series_notification_item(base_url, &event_full);
        let speaker_ids = event_full.speakers_ids();
        let recipients = attendee_ids
            .into_iter()
            .chain(waitlist_ids)
            .chain(speaker_ids)
            .collect::<HashSet<_>>();

        for recipient in recipients {
            recipient_events.entry(recipient).or_default().push(event.clone());
        }
    }

    // If there are no notification recipients, we are done
    if recipient_events.is_empty() {
        return Ok(());
    }

    // Build and enqueue grouped cancellation notifications
    let site_settings = db.get_site_settings().await?;
    for group in group_recipients_by_events(recipient_events) {
        let Some(group_name) = group.events.first().map(|event| event.event.group_name.clone())
        else {
            continue;
        };
        let template_data = EventSeriesCanceled {
            event_count: group.events.len(),
            events: group.events,
            group_name,
            theme: site_settings.theme.clone(),
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventSeriesCanceled,
            recipients: group.recipients,
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

/// Enqueues aggregate publish notifications to members/team and speakers.
pub(crate) async fn enqueue_event_series_published_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<()> {
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);

    // Fetch member recipients shared by all published occurrences
    let (group_member_ids, team_member_ids) = tokio::try_join!(
        db.list_group_members_ids(group_id),
        db.list_group_team_members_ids(group_id)
    )?;
    let mut member_ids = group_member_ids;
    member_ids.extend(team_member_ids);
    member_ids.sort();
    member_ids.dedup();

    // Build recipient event lists for each published occurrence
    let mut member_events: HashMap<Uuid, Vec<EventSeriesNotificationItem>> = HashMap::new();
    let mut speaker_events: HashMap<Uuid, Vec<EventSeriesNotificationItem>> = HashMap::new();
    for event_id in event_ids {
        // Map members and speakers to the published occurrence relevant to them
        let event_full = db.get_event_full(alliance_id, group_id, *event_id).await?;

        // Test events in a series should stay out of publication broadcasts
        if event_full.test_event {
            continue;
        }
        let event = event_series_notification_item(base_url, &event_full);
        let speaker_ids = event_full.speakers_ids();
        let speaker_set: HashSet<Uuid> = speaker_ids.iter().copied().collect();

        for speaker_id in speaker_ids {
            speaker_events.entry(speaker_id).or_default().push(event.clone());
        }

        for member_id in &member_ids {
            if !speaker_set.contains(member_id) {
                member_events.entry(*member_id).or_default().push(event.clone());
            }
        }
    }

    // If there are no notification recipients, we are done
    if member_events.is_empty() && speaker_events.is_empty() {
        return Ok(());
    }

    // Enqueue group member notifications about the published event series
    let site_settings = db.get_site_settings().await?;
    for group in group_recipients_by_events(member_events) {
        let Some(alliance_display_name) = group
            .events
            .first()
            .map(|event| event.event.alliance_display_name.clone())
        else {
            continue;
        };
        let Some(group_name) = group.events.first().map(|event| event.event.group_name.clone())
        else {
            continue;
        };
        let template_data = EventSeriesPublished {
            alliance_display_name,
            event_count: group.events.len(),
            events: group.events,
            group_name,
            theme: site_settings.theme.clone(),
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventSeriesPublished,
            recipients: group.recipients,
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        db.enqueue_notification(&notification).await?;
    }

    // Enqueue speaker notifications about being added to the event series
    for group in group_recipients_by_events(speaker_events) {
        let Some(group_name) = group.events.first().map(|event| event.event.group_name.clone())
        else {
            continue;
        };
        let template_data = SpeakerSeriesWelcome {
            event_count: group.events.len(),
            events: group.events,
            group_name,
            theme: site_settings.theme.clone(),
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::SpeakerSeriesWelcome,
            recipients: group.recipients,
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

/// Enqueues waitlist promotion notifications when an update opens capacity.
pub(crate) async fn enqueue_event_waitlist_promoted_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
    before: &EventSummary,
    promoted_user_ids: Vec<Uuid>,
) -> Result<()> {
    if promoted_user_ids.is_empty() || before.test_event {
        return Ok(());
    }

    // Fetch notification context and updated event summary concurrently
    let (site_settings, event) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary(alliance_id, group_id, event_id)
    )?;
    if !should_send_waitlist_promoted_notification(&event, &promoted_user_ids) {
        return Ok(());
    }

    // Build and enqueue the waitlist promotion notification
    let notification = build_event_waitlist_promoted_notification(
        &event,
        promoted_user_ids,
        server_cfg,
        &site_settings,
    )?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

/// Enqueues the event welcome notification after attendance becomes confirmed.
pub(crate) async fn enqueue_event_welcome_notification(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    event_id: Uuid,
    user_id: Uuid,
    include_dashboard_link: bool,
) -> Result<()> {
    // Fetch notification context after the attendance mutation
    let (site_settings, event) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(alliance_id, event_id)
    )?;

    // Build and enqueue the attendee welcome notification
    let notification = build_event_welcome_notification(
        &event,
        user_id,
        server_cfg,
        &site_settings,
        include_dashboard_link,
    )?;
    db.enqueue_notification(&notification).await?;

    Ok(())
}

// Types.

/// Recipient group sharing the same event list for one aggregate notification.
struct EventSeriesNotificationGroup {
    /// Events included in the notification.
    events: Vec<EventSeriesNotificationItem>,
    /// Recipients that should receive the notification.
    recipients: Vec<Uuid>,
}

// Helpers.

/// Builds one aggregate notification item from full event data.
fn event_series_notification_item(
    base_url: &str,
    event_full: &EventFull,
) -> EventSeriesNotificationItem {
    let event = EventSummary::from(event_full);
    let link = build_event_page_link(base_url, &event);

    EventSeriesNotificationItem { event, link }
}

/// Groups recipients by the exact event list relevant to them.
fn group_recipients_by_events(
    recipient_events: HashMap<Uuid, Vec<EventSeriesNotificationItem>>,
) -> Vec<EventSeriesNotificationGroup> {
    let mut groups: HashMap<Vec<Uuid>, EventSeriesNotificationGroup> = HashMap::new();

    // Build groups keyed by each recipient's relevant event ids
    for (recipient, events) in recipient_events {
        let key = events.iter().map(|event| event.event.event_id).collect::<Vec<_>>();
        let group = groups.entry(key).or_insert_with(|| EventSeriesNotificationGroup {
            events,
            recipients: Vec::new(),
        });
        group.recipients.push(recipient);
    }

    // Normalize recipient and group ordering for deterministic notifications
    let mut groups = groups.into_values().collect::<Vec<_>>();
    for group in &mut groups {
        group.recipients.sort();
        group.recipients.dedup();
    }
    groups.sort_by(|left, right| {
        left.events
            .first()
            .map(|event| event.event.event_id)
            .cmp(&right.events.first().map(|event| event.event.event_id))
    });
    groups
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use chrono::{Duration, Utc};
    use serde_json::from_value;

    use crate::{
        config::HttpServerConfig,
        db::mock::MockDB,
        handlers::tests::{
            sample_event_full, sample_event_summary, sample_site_settings,
            sample_template_user_with_id,
        },
        services::notifications::{NewNotification, NotificationKind},
        templates::notifications::{
            EventRescheduled, EventSeriesCanceled, EventSeriesPublished, SpeakerSeriesWelcome,
            SpeakerWelcome,
        },
        types::event::{EventFull, EventSummary, Speaker},
    };

    use super::*;

    #[tokio::test]
    #[allow(clippy::too_many_lines)]
    async fn test_enqueue_event_series_canceled_notifications_groups_by_recipient_event_set() {
        // Setup identifiers and data structures
        let alliance_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let related_event_id = Uuid::new_v4();
        let test_event_id = Uuid::new_v4();
        let shared_recipient_id = Uuid::new_v4();
        let event_recipient_id = Uuid::new_v4();
        let related_event_recipient_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
        let test_event_recipient_id = Uuid::new_v4();
        let event = sample_event_full_with_speakers(alliance_id, event_id, group_id, &[speaker_id]);
        let related_event =
            sample_event_full_with_speakers(alliance_id, related_event_id, group_id, &[]);
        let test_event = EventFull {
            test_event: true,
            ..sample_event_full_with_speakers(alliance_id, test_event_id, group_id, &[])
        };
        let notifications = Arc::new(Mutex::new(Vec::new()));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == alliance_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![shared_recipient_id, event_recipient_id]));
        db.expect_list_event_waitlist_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(|_, _| Ok(vec![]));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| {
                *cid == alliance_id && *gid == group_id && *eid == related_event_id
            })
            .returning(move |_, _, _| Ok(related_event.clone()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == related_event_id)
            .returning(move |_, _| Ok(vec![shared_recipient_id]));
        db.expect_list_event_waitlist_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == related_event_id)
            .returning(move |_, _| Ok(vec![related_event_recipient_id]));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| {
                *cid == alliance_id && *gid == group_id && *eid == test_event_id
            })
            .returning(move |_, _, _| Ok(test_event.clone()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == test_event_id)
            .returning(move |_, _| Ok(vec![test_event_recipient_id]));
        db.expect_list_event_waitlist_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == test_event_id)
            .returning(|_, _| Ok(vec![]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        let notifications_for_mock = notifications.clone();
        db.expect_enqueue_notification()
            .times(3)
            .returning(move |notification| {
                notifications_for_mock
                    .lock()
                    .expect("notifications lock not to be poisoned")
                    .push(notification.clone());
                Ok(())
            });

        // Run the workflow
        enqueue_event_series_canceled_notifications(
            &db,
            &sample_server_cfg(),
            alliance_id,
            group_id,
            &[event_id, related_event_id, test_event_id],
        )
        .await
        .unwrap();

        // Check notifications match recipient event sets
        let notifications = notifications
            .lock()
            .expect("notifications lock not to be poisoned")
            .clone();
        assert_eq!(notifications.len(), 3);
        let groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
            .iter()
            .filter(|notification| {
                matches!(notification.kind, NotificationKind::EventSeriesCanceled)
            })
            .map(|notification| {
                let template: EventSeriesCanceled =
                    from_value(notification.template_data.clone().expect("template data to exist"))
                        .expect("series canceled notification to deserialize");
                let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
                (notification.recipients.clone(), event_ids)
            })
            .collect();
        assert_recipient_event_group_exists(
            &groups,
            &[shared_recipient_id],
            &[event_id, related_event_id],
        );
        assert_recipient_event_group_exists(
            &groups,
            &[event_recipient_id, speaker_id],
            &[event_id],
        );
        assert_recipient_event_group_exists(
            &groups,
            &[related_event_recipient_id],
            &[related_event_id],
        );
        assert!(
            !groups
                .iter()
                .any(|(recipients, _)| recipients.contains(&test_event_recipient_id))
        );
    }

    #[tokio::test]
    #[allow(clippy::too_many_lines)]
    async fn test_enqueue_event_series_published_notifications_groups_members_and_speakers() {
        // Setup identifiers and data structures
        let alliance_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let related_event_id = Uuid::new_v4();
        let member_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
        let related_event_speaker_id = Uuid::new_v4();
        let team_member_id = Uuid::new_v4();
        let event = sample_event_full_with_speakers(alliance_id, event_id, group_id, &[speaker_id]);
        let related_event = sample_event_full_with_speakers(
            alliance_id,
            related_event_id,
            group_id,
            &[speaker_id, related_event_speaker_id],
        );
        let notifications = Arc::new(Mutex::new(Vec::new()));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id, speaker_id]));
        db.expect_list_group_team_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![team_member_id, member_id]));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == alliance_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| {
                *cid == alliance_id && *gid == group_id && *eid == related_event_id
            })
            .returning(move |_, _, _| Ok(related_event.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        let notifications_for_mock = notifications.clone();
        db.expect_enqueue_notification()
            .times(3)
            .returning(move |notification| {
                notifications_for_mock
                    .lock()
                    .expect("notifications lock not to be poisoned")
                    .push(notification.clone());
                Ok(())
            });

        // Run the workflow
        enqueue_event_series_published_notifications(
            &db,
            &sample_server_cfg(),
            alliance_id,
            group_id,
            &[event_id, related_event_id],
        )
        .await
        .unwrap();

        // Check notifications match member and speaker event sets
        let notifications = notifications
            .lock()
            .expect("notifications lock not to be poisoned")
            .clone();
        assert_eq!(notifications.len(), 3);
        let member_groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
            .iter()
            .filter(|notification| {
                matches!(notification.kind, NotificationKind::EventSeriesPublished)
            })
            .map(|notification| {
                let template: EventSeriesPublished =
                    from_value(notification.template_data.clone().expect("template data to exist"))
                        .expect("series published notification to deserialize");
                let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
                (notification.recipients.clone(), event_ids)
            })
            .collect();
        assert_recipient_event_group_exists(
            &member_groups,
            &[member_id, team_member_id],
            &[event_id, related_event_id],
        );
        let speaker_groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
            .iter()
            .filter(|notification| {
                matches!(notification.kind, NotificationKind::SpeakerSeriesWelcome)
            })
            .map(|notification| {
                let template: SpeakerSeriesWelcome =
                    from_value(notification.template_data.clone().expect("template data to exist"))
                        .expect("speaker series notification to deserialize");
                let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
                (notification.recipients.clone(), event_ids)
            })
            .collect();
        assert_recipient_event_group_exists(
            &speaker_groups,
            &[speaker_id],
            &[event_id, related_event_id],
        );
        assert_recipient_event_group_exists(
            &speaker_groups,
            &[related_event_speaker_id],
            &[related_event_id],
        );
    }

    #[tokio::test]
    async fn test_enqueue_event_published_notifications_sends_members_and_speakers_separately() {
        // Setup identifiers and data structures
        let alliance_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let member_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
        let speaker_member_id = Uuid::new_v4();
        let team_member_id = Uuid::new_v4();
        let event = sample_event_full_with_speakers(
            alliance_id,
            event_id,
            group_id,
            &[speaker_id, speaker_member_id],
        );
        let notifications = Arc::new(Mutex::new(Vec::new()));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == alliance_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_list_group_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![member_id, speaker_member_id]));
        db.expect_list_group_team_members_ids()
            .times(1)
            .withf(move |gid| *gid == group_id)
            .returning(move |_| Ok(vec![team_member_id, member_id]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        let notifications_for_mock = notifications.clone();
        db.expect_enqueue_notification()
            .times(2)
            .returning(move |notification| {
                notifications_for_mock
                    .lock()
                    .expect("notifications lock not to be poisoned")
                    .push(notification.clone());
                Ok(())
            });

        // Run the workflow
        enqueue_event_published_notifications(
            &db,
            &sample_server_cfg(),
            alliance_id,
            group_id,
            event_id,
        )
        .await
        .unwrap();

        // Check notifications split member and speaker audiences
        let notifications = notifications
            .lock()
            .expect("notifications lock not to be poisoned")
            .clone();
        assert_eq!(notifications.len(), 2);
        let member_notification =
            find_notification(&notifications, &NotificationKind::EventPublished);
        assert_eq!(
            sorted_ids(member_notification.recipients.clone()),
            sorted_ids(vec![member_id, team_member_id])
        );
        let speaker_notification =
            find_notification(&notifications, &NotificationKind::SpeakerWelcome);
        assert_eq!(
            sorted_ids(speaker_notification.recipients.clone()),
            sorted_ids(vec![speaker_id, speaker_member_id])
        );
        let _: SpeakerWelcome = from_value(
            speaker_notification
                .template_data
                .clone()
                .expect("template data to exist"),
        )
        .expect("speaker notification to deserialize");
    }

    #[tokio::test]
    async fn test_enqueue_event_rescheduled_notification_skips_small_shift() {
        // Setup identifiers and data structures
        let alliance_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let before = sample_future_event_summary(event_id, group_id);
        let after = EventSummary {
            starts_at: before.starts_at.map(|starts_at| starts_at + Duration::minutes(10)),
            ..before.clone()
        };

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == alliance_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(after.clone()));

        // Run the workflow
        enqueue_event_rescheduled_notification(
            &db,
            &sample_server_cfg(),
            alliance_id,
            group_id,
            event_id,
            &before,
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn test_enqueue_event_rescheduled_notification_sends_to_attendees_and_speakers() {
        // Setup identifiers and data structures
        let attendee_id = Uuid::new_v4();
        let alliance_id = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let speaker_id = Uuid::new_v4();
        let before = sample_future_event_summary(event_id, group_id);
        let after = EventSummary {
            starts_at: before.starts_at.map(|starts_at| starts_at + Duration::minutes(30)),
            ..before.clone()
        };
        let event = sample_event_full_with_speakers(alliance_id, event_id, group_id, &[speaker_id]);
        let notifications = Arc::new(Mutex::new(Vec::new()));

        // Setup database mock
        let mut db = MockDB::new();
        db.expect_get_event_summary()
            .times(1)
            .withf(move |cid, gid, eid| *cid == alliance_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(after.clone()));
        db.expect_get_event_full()
            .times(1)
            .withf(move |cid, gid, eid| *cid == alliance_id && *gid == group_id && *eid == event_id)
            .returning(move |_, _, _| Ok(event.clone()));
        db.expect_list_event_attendees_ids()
            .times(1)
            .withf(move |gid, eid| *gid == group_id && *eid == event_id)
            .returning(move |_, _| Ok(vec![attendee_id, speaker_id]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));
        let notifications_for_mock = notifications.clone();
        db.expect_enqueue_notification()
            .times(1)
            .returning(move |notification| {
                notifications_for_mock
                    .lock()
                    .expect("notifications lock not to be poisoned")
                    .push(notification.clone());
                Ok(())
            });

        // Run the workflow
        enqueue_event_rescheduled_notification(
            &db,
            &sample_server_cfg(),
            alliance_id,
            group_id,
            event_id,
            &before,
        )
        .await
        .unwrap();

        // Check notification matches recipient selection
        let notifications = notifications
            .lock()
            .expect("notifications lock not to be poisoned")
            .clone();
        assert_eq!(notifications.len(), 1);
        let notification = find_notification(&notifications, &NotificationKind::EventRescheduled);
        assert_eq!(
            sorted_ids(notification.recipients.clone()),
            sorted_ids(vec![attendee_id, speaker_id])
        );
        let template: EventRescheduled =
            from_value(notification.template_data.clone().expect("template data to exist"))
                .expect("event rescheduled notification to deserialize");
        assert_eq!(template.event.event_id, event_id);
    }

    // Helpers.

    /// Asserts that a recipient group exists for the exact event ids.
    fn assert_recipient_event_group_exists(
        groups: &[(Vec<Uuid>, Vec<Uuid>)],
        recipients: &[Uuid],
        event_ids: &[Uuid],
    ) {
        let recipients = sorted_ids(recipients.to_vec());
        assert!(
            groups.iter().any(|(actual_recipients, actual_event_ids)| {
                sorted_ids(actual_recipients.clone()) == recipients && actual_event_ids == event_ids
            }),
            "expected notification group for recipients {recipients:?} and events {event_ids:?}"
        );
    }

    /// Finds the first captured notification of the expected kind.
    fn find_notification<'a>(
        notifications: &'a [NewNotification],
        expected_kind: &NotificationKind,
    ) -> &'a NewNotification {
        notifications
            .iter()
            .find(|notification| notification.kind.to_string() == expected_kind.to_string())
            .expect("notification to exist")
    }

    /// Builds a sample full event with the provided event-level speakers.
    fn sample_event_full_with_speakers(
        alliance_id: Uuid,
        event_id: Uuid,
        group_id: Uuid,
        speaker_ids: &[Uuid],
    ) -> EventFull {
        EventFull {
            speakers: speaker_ids
                .iter()
                .copied()
                .map(|user_id| Speaker {
                    featured: false,
                    user: sample_template_user_with_id(user_id),
                })
                .collect(),
            ..sample_event_full(alliance_id, event_id, group_id)
        }
    }

    /// Builds a published event summary safely in the future.
    fn sample_future_event_summary(event_id: Uuid, group_id: Uuid) -> EventSummary {
        let starts_at = Utc::now() + Duration::hours(1);
        EventSummary {
            ends_at: Some(starts_at + Duration::hours(1)),
            starts_at: Some(starts_at),
            ..sample_event_summary(event_id, group_id)
        }
    }

    /// Builds server config with a stable public base URL.
    fn sample_server_cfg() -> HttpServerConfig {
        HttpServerConfig {
            base_url: "https://example.test/".to_string(),
            ..Default::default()
        }
    }

    /// Sorts identifiers for order-independent assertions.
    fn sorted_ids(mut ids: Vec<Uuid>) -> Vec<Uuid> {
        ids.sort();
        ids
    }
}
