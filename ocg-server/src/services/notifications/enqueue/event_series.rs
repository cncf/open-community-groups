//! Event series notification enqueue workflows.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use anyhow::Result;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DBOperations,
    templates::notifications::{
        EventSeriesCanceled, EventSeriesNotificationItem, EventSeriesPublished,
        SpeakerSeriesWelcome,
    },
    types::{
        event::{EventCohostGroup, EventFull, EventSummary},
        notifications::{NewNotification, NotificationKind},
        site::SiteSettings,
    },
    util::{base_url_without_trailing_slash, build_event_page_link},
};

use super::group_audience_ids;

/// Enqueues one aggregate cancellation notification per recipient event set.
pub(crate) async fn enqueue_event_series_canceled_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<()> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let mut recipient_events: HashMap<Uuid, Vec<EventSeriesNotificationItem>> = HashMap::new();

    // Build recipient event lists for each canceled occurrence
    for event_id in event_ids {
        // Fetch event full and affected user IDs for this canceled occurrence
        let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, *event_id),
            db.list_event_attendees_ids(group_id, *event_id, false),
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
            group_ids: vec![],
            kind: NotificationKind::EventSeriesCanceled,
            recipients: group.recipients,
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

/// Enqueues aggregate publish notifications to the owner and co-host
/// audiences and to the speakers.
///
/// Each recipient is notified at most once per occurrence: speakers first,
/// then the owner audience, then the co-host audiences ordered by name.
/// Recipients who turned off new events, or muted a group an occurrence
/// names, are filtered per occurrence before the notifications are bundled.
pub(crate) async fn enqueue_event_series_published_notifications(
    db: &dyn DBOperations,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<()> {
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);

    // Fetch the owner audience shared by all published occurrences
    let owner_audience = group_audience_ids(db, group_id).await?;

    // Build recipient event lists for each published occurrence
    let mut cohost_audiences: HashMap<Uuid, Vec<Uuid>> = HashMap::new();
    let mut cohost_events: BTreeMap<(String, Uuid), RecipientEvents> = BTreeMap::new();
    let mut covered: HashSet<(Uuid, Uuid)> = HashSet::new();
    let mut member_events: RecipientEvents = HashMap::new();
    let mut occurrence_group_ids: HashMap<Uuid, Vec<Uuid>> = HashMap::new();
    let mut speaker_events: RecipientEvents = HashMap::new();
    for event_id in event_ids {
        let event_full = db.get_event_full(community_id, group_id, *event_id).await?;

        // Test events in a series should stay out of publication broadcasts
        if event_full.test_event {
            continue;
        }
        let event = event_series_notification_item(base_url, &event_full);

        // Map speakers to the occurrence first so they only get their own email
        for speaker_id in event_full.speakers_ids() {
            covered.insert((speaker_id, *event_id));
            speaker_events.entry(speaker_id).or_default().push(event.clone());
        }

        // Keep the audience members who accept emails naming this occurrence
        let audience = load_event_series_occurrence_audience(
            db,
            group_id,
            &event_full,
            &owner_audience,
            &mut cohost_audiences,
            &covered,
        )
        .await?;
        occurrence_group_ids.insert(*event_id, audience.group_ids);

        // Map eligible owner audience members not covered for this occurrence
        for member_id in &owner_audience {
            if audience.eligible.contains(member_id) && covered.insert((*member_id, *event_id)) {
                member_events.entry(*member_id).or_default().push(event.clone());
            }
        }

        // Map each eligible co-host audience member, skipping recipients
        // already covered for this occurrence
        for (cohost, cohost_audience) in audience.cohost_audiences {
            let recipient_events = cohost_events
                .entry((cohost.name.clone(), cohost.group_id))
                .or_default();
            for member_id in cohost_audience {
                if audience.eligible.contains(&member_id) && covered.insert((member_id, *event_id))
                {
                    recipient_events.entry(member_id).or_default().push(event.clone());
                }
            }
        }
    }
    cohost_events.retain(|_, recipient_events| !recipient_events.is_empty());

    // If there are no notification recipients, we are done
    if member_events.is_empty() && cohost_events.is_empty() && speaker_events.is_empty() {
        return Ok(());
    }

    // Enqueue owner audience notifications about the published event series
    let site_settings = db.get_site_settings().await?;
    for group in group_recipients_by_events(member_events) {
        enqueue_event_series_published_group(
            db,
            group,
            None,
            &occurrence_group_ids,
            &site_settings,
        )
        .await?;
    }

    // Enqueue co-host audience notifications, never combining co-host groups
    for ((cohost_group_name, _), recipient_events) in cohost_events {
        for group in group_recipients_by_events(recipient_events) {
            enqueue_event_series_published_group(
                db,
                group,
                Some(cohost_group_name.clone()),
                &occurrence_group_ids,
                &site_settings,
            )
            .await?;
        }
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
            group_ids: vec![],
            kind: NotificationKind::SpeakerSeriesWelcome,
            recipients: group.recipients,
            template_data: Some(serde_json::to_value(&template_data)?),
        };
        db.enqueue_notification(&notification).await?;
    }

    Ok(())
}

// Types.

/// Events relevant to each recipient of an aggregate notification.
type RecipientEvents = HashMap<Uuid, Vec<EventSeriesNotificationItem>>;

/// Recipient group sharing the same event list for one aggregate notification.
struct EventSeriesNotificationGroup {
    /// Events included in the notification.
    events: Vec<EventSeriesNotificationItem>,
    /// Recipients that should receive the notification.
    recipients: Vec<Uuid>,
}

/// Audiences of one published series occurrence after preference filtering.
struct EventSeriesOccurrenceAudience<'a> {
    /// Approved co-hosts ordered by name, each with its audience.
    cohost_audiences: Vec<(&'a EventCohostGroup, Vec<Uuid>)>,
    /// Audience members who accept an email naming the occurrence's groups.
    eligible: HashSet<Uuid>,
    /// Owner and approved co-host groups named by the occurrence.
    group_ids: Vec<Uuid>,
}

// Helpers.

/// Enqueues one aggregate event series publication notification.
///
/// The notification names the union of the groups of its occurrences. Every
/// bundled occurrence already passed the per-occurrence filter for these
/// recipients, so the final enqueue check agrees with it.
async fn enqueue_event_series_published_group(
    db: &dyn DBOperations,
    group: EventSeriesNotificationGroup,
    cohost_group_name: Option<String>,
    occurrence_group_ids: &HashMap<Uuid, Vec<Uuid>>,
    site_settings: &SiteSettings,
) -> Result<()> {
    // Resolve the shared owner context from the first event
    let Some(first_event) = group.events.first() else {
        return Ok(());
    };
    let community_display_name = first_event.event.community_display_name.clone();
    let group_name = first_event.event.group_name.clone();

    // Collect the groups named by the bundled occurrences
    let group_ids: Vec<Uuid> = group
        .events
        .iter()
        .filter_map(|event| occurrence_group_ids.get(&event.event.event_id))
        .flatten()
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();

    // Build and enqueue the notification
    let template_data = EventSeriesPublished {
        community_display_name,
        event_count: group.events.len(),
        events: group.events,
        group_name,
        theme: site_settings.theme.clone(),

        cohost_group_name,
    };
    let notification = NewNotification {
        attachments: vec![],
        group_ids,
        kind: NotificationKind::EventSeriesPublished,
        recipients: group.recipients,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    db.enqueue_notification(&notification).await?;

    Ok(())
}

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

/// Loads the audiences of one published series occurrence and keeps the
/// members who accept an email naming its owner and approved co-host groups.
///
/// Co-host audiences are cached across occurrences. Recipients already covered
/// for the occurrence, such as its speakers, are not checked.
async fn load_event_series_occurrence_audience<'a>(
    db: &dyn DBOperations,
    group_id: Uuid,
    event_full: &'a EventFull,
    owner_audience: &[Uuid],
    cohost_audiences_cache: &mut HashMap<Uuid, Vec<Uuid>>,
    covered: &HashSet<(Uuid, Uuid)>,
) -> Result<EventSeriesOccurrenceAudience<'a>> {
    // Load each approved co-host audience (see the single-event helper for
    // why `cohosts` only holds approved co-hosts here)
    let mut cohosts = event_full.cohosts.iter().collect::<Vec<_>>();
    cohosts
        .sort_by(|left, right| left.name.cmp(&right.name).then(left.group_id.cmp(&right.group_id)));
    let mut cohost_audiences = Vec::with_capacity(cohosts.len());
    for cohost in cohosts {
        let audience = if let Some(audience) = cohost_audiences_cache.get(&cohost.group_id) {
            audience.clone()
        } else {
            let audience = group_audience_ids(db, cohost.group_id).await?;
            cohost_audiences_cache.insert(cohost.group_id, audience.clone());
            audience
        };
        cohost_audiences.push((cohost, audience));
    }

    // Collect the groups the occurrence names and its uncovered candidates
    let group_ids: Vec<Uuid> = std::iter::once(group_id)
        .chain(cohost_audiences.iter().map(|(cohost, _)| cohost.group_id))
        .collect();
    let mut seen_candidates = HashSet::new();
    let candidates: Vec<Uuid> = owner_audience
        .iter()
        .chain(cohost_audiences.iter().flat_map(|(_, audience)| audience))
        .copied()
        .filter(|id| !covered.contains(&(*id, event_full.event_id)) && seen_candidates.insert(*id))
        .collect();

    // Keep the candidates who accept an email naming those groups
    let eligible: HashSet<Uuid> = db
        .filter_notification_recipient_ids(
            &NotificationKind::EventSeriesPublished,
            &candidates,
            &group_ids,
        )
        .await?
        .into_iter()
        .collect();

    Ok(EventSeriesOccurrenceAudience {
        cohost_audiences,
        eligible,
        group_ids,
    })
}
