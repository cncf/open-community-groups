//! HTTP handlers for managing events in the group dashboard.

use std::collections::{HashMap, HashSet};

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use chrono::{TimeDelta, Utc};
use garde::Validate;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, MeetingsConfig},
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    router::serde_qs_config,
    services::{
        meetings::MeetingProvider,
        notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    },
    templates::{
        dashboard::group::{
            events::{self, Event, EventsListFilters, EventsTab},
            sponsors::GroupSponsorsFilters,
        },
        notifications::{
            EventCanceled, EventPublished, EventRescheduled, EventWaitlistPromoted, SpeakerWelcome,
        },
    },
    types::{
        event::EventSummary,
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
    util::{build_event_calendar_attachment, build_event_page_link},
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/group?tab=events";
const PARTIAL_URL: &str = "/dashboard/group/events";

// Minimum shift required to notify a reschedule.
const MIN_RESCHEDULE_SHIFT: TimeDelta = TimeDelta::minutes(15);

// Pages handlers.

/// Displays the page to add a new event.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch template data concurrently
    let meetings_enabled = meetings_cfg.as_ref().is_some_and(MeetingsConfig::meetings_enabled);
    let meetings_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let sponsor_filters: GroupSponsorsFilters = serde_qs_config().deserialize_str("")?;
    let (can_manage_events, categories, event_kinds, session_kinds, sponsors, timezones) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.list_event_categories(community_id),
        db.list_event_kinds(),
        db.list_session_kinds(),
        db.list_group_sponsors(group_id, &sponsor_filters, true),
        db.list_timezones()
    )?;

    // Prepare template
    let template = events::AddPage {
        can_manage_events,
        categories,
        event_kinds,
        group_id,
        meetings_enabled,
        meetings_max_participants,
        session_kinds,
        sponsors: sponsors.sponsors,
        timezones,
    };

    Ok(Html(template.render()?))
}

/// Displays the list of events for the group dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        community_id,
        group_id,
        user.user_id,
        raw_query.as_deref().unwrap_or_default(),
    )
    .await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Displays the page to update an existing event.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let meetings_enabled = meetings_cfg.as_ref().is_some_and(MeetingsConfig::meetings_enabled);
    let meetings_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let sponsor_filters: GroupSponsorsFilters = serde_qs_config().deserialize_str("")?;
    let (
        can_manage_events,
        event,
        approved_submissions,
        categories,
        cfs_statuses,
        event_kinds,
        session_kinds,
        sponsors,
        timezones,
    ) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_full(community_id, group_id, event_id),
        db.list_event_approved_cfs_submissions(event_id),
        db.list_event_categories(community_id),
        db.list_cfs_submission_statuses_for_review(),
        db.list_event_kinds(),
        db.list_session_kinds(),
        db.list_group_sponsors(group_id, &sponsor_filters, true),
        db.list_timezones(),
    )?;
    let template = events::UpdatePage {
        approved_submissions,
        can_manage_events,
        categories,
        cfs_submission_statuses: cfs_statuses,
        current_user_id: user.user_id,
        event,
        event_kinds,
        group_id,
        meetings_enabled,
        meetings_max_participants,
        session_kinds,
        sponsors: sponsors.sponsors,
        timezones,
    };

    Ok(Html(template.render()?))
}

// JSON handlers.

/// Returns full event details in JSON format.
#[instrument(skip_all, err)]
pub(crate) async fn details(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    let event = db.get_event_full(community_id, group_id, event_id).await?;

    Ok(Json(event).into_response())
}

// Actions handlers.

/// Adds a new event to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    ValidatedFormQs(event): ValidatedFormQs<Event>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add event to database
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    db.add_event(user.user_id, group_id, &event, &cfg_max_participants)
        .await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

/// Cancels an event (sets canceled=true).
#[instrument(skip_all, err)]
pub(crate) async fn cancel(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before canceling
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Mark event as canceled in database
    db.cancel_event(user.user_id, group_id, event_id).await?;

    // Notify attendees and speakers about canceled event
    let should_notify = matches!(
        (event.published, event.canceled, event.starts_at),
        (true, false, Some(starts_at)) if starts_at > Utc::now()
    );
    if should_notify {
        // Fetch event full and attendee IDs concurrently
        let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, event_id),
            db.list_event_attendees_ids(group_id, event_id),
            db.list_event_waitlist_ids(group_id, event_id)
        )?;

        // Combine attendee and speaker IDs (deduplicated)
        let speaker_ids = event_full.speakers_ids();
        let recipients: Vec<Uuid> = attendee_ids
            .into_iter()
            .chain(waitlist_ids)
            .chain(speaker_ids)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();

        if !recipients.is_empty() {
            let site_settings = db.get_site_settings().await?;
            let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
            let event_summary = EventSummary::from(&event_full);
            let link = build_event_page_link(base_url, &event_summary);
            let calendar_ics = build_event_calendar_attachment(base_url, &event_summary);
            let template_data = EventCanceled {
                event: event_summary,
                link,
                theme: site_settings.theme,
            };
            let notification = NewNotification {
                attachments: vec![calendar_ics],
                kind: NotificationKind::EventCanceled,
                recipients,
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await?;
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
        )],
    ))
}

/// Publishes an event (sets published=true and records publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn publish(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before publishing
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Mark event as published in database
    db.publish_event(user.user_id, group_id, event_id).await?;

    // Notify group members and speakers about published event
    let should_notify = matches!(
        (event.published, event.starts_at),
        (false, Some(starts_at)) if starts_at > Utc::now()
    );
    if should_notify {
        // Fetch event full and group member IDs concurrently
        let (event_full, group_member_ids, team_member_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, event_id),
            db.list_group_members_ids(group_id),
            db.list_group_team_members_ids(group_id)
        )?;

        // Combine group members and team members
        let mut recipients = group_member_ids;
        recipients.extend(team_member_ids);
        recipients.sort();
        recipients.dedup();

        // Extract speaker IDs
        let speaker_ids = event_full.speakers_ids();
        let has_speakers = !speaker_ids.is_empty();

        // Filter out speakers from member IDs (they get a separate notification)
        let recipients: Vec<Uuid> = recipients
            .into_iter()
            .filter(|id| !speaker_ids.contains(id))
            .collect();
        let has_members = !recipients.is_empty();

        if has_members || has_speakers {
            // Prepare common data for notifications
            let site_settings = db.get_site_settings().await?;
            let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
            let event_summary = EventSummary::from(&event_full);
            let link = build_event_page_link(base_url, &event_summary);
            let calendar_ics = build_event_calendar_attachment(base_url, &event_summary);

            // Notify group members about published event
            if has_members {
                let template_data = EventPublished {
                    event: event_summary.clone(),
                    link: link.clone(),
                    theme: site_settings.theme.clone(),
                };
                let notification = NewNotification {
                    attachments: vec![calendar_ics.clone()],
                    kind: NotificationKind::EventPublished,
                    recipients,
                    template_data: Some(serde_json::to_value(&template_data)?),
                };
                notifications_manager.enqueue(&notification).await?;
            }

            // Notify speakers about being added to the event
            if has_speakers {
                let template_data = SpeakerWelcome {
                    event: event_summary,
                    link,
                    theme: site_settings.theme,
                };
                let notification = NewNotification {
                    attachments: vec![calendar_ics],
                    kind: NotificationKind::SpeakerWelcome,
                    recipients: speaker_ids,
                    template_data: Some(serde_json::to_value(&template_data)?),
                };
                notifications_manager.enqueue(&notification).await?;
            }
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Deletes an event from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete event from database (soft delete)
    db.delete_event(user.user_id, group_id, event_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Unpublishes an event (sets published=false and clears publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn unpublish(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark event as unpublished in database
    db.unpublish_event(user.user_id, group_id, event_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates an existing event's information in the database.
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(serde_qs_de): State<serde_qs::Config>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Load event summary before update to detect reschedule and if it is past
    let before = db.get_event_summary(community_id, group_id, event_id).await?;

    // Deserialize and validate provided event
    let event: Event = serde_qs_de
        .deserialize_str(&body)
        .map_err(|e| HandlerError::Deserialization(e.to_string()))?;
    event.validate()?;

    // Update event in database
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let event_json = serde_json::to_value(&event)?;
    let promoted_user_ids = db
        .update_event(
            group_id,
            user.user_id,
            event_id,
            &event_json,
            &cfg_max_participants,
        )
        .await?;

    // Notify users promoted from the waitlist when the update opens capacity
    if !promoted_user_ids.is_empty() {
        // Fetch notification context and updated event summary concurrently
        match tokio::try_join!(
            db.get_site_settings(),
            db.get_event_summary(community_id, group_id, event_id),
        ) {
            Ok((site_settings, event)) => {
                // Build and enqueue the waitlist promotion notification
                let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
                let link = build_event_page_link(base_url, &event);
                let calendar_ics = build_event_calendar_attachment(base_url, &event);
                let template_data = EventWaitlistPromoted {
                    event,
                    link,
                    theme: site_settings.theme,
                };
                let notification = NewNotification {
                    attachments: vec![calendar_ics],
                    kind: NotificationKind::EventWaitlistPromoted,
                    recipients: promoted_user_ids,
                    template_data: Some(serde_json::to_value(&template_data)?),
                };
                if let Err(err) = notifications_manager.enqueue(&notification).await {
                    warn!(error = %err, "failed to enqueue waitlist promotion notification");
                }
            }
            Err(err) => {
                warn!(error = %err, "failed to load event notification context after event update");
            }
        }
    }

    // Notify attendees and speakers if event was rescheduled (only if not past)
    if !before.is_past() {
        // Fetch updated event summary to compare start times and detect reschedule
        let after = db.get_event_summary(community_id, group_id, event_id).await?;
        let should_notify = match (before.published, before.starts_at, after.starts_at) {
            (true, Some(b_starts_at), Some(a_starts_at)) if a_starts_at > Utc::now() => {
                (a_starts_at - b_starts_at).abs() >= MIN_RESCHEDULE_SHIFT
            }
            _ => false,
        };

        if should_notify {
            // Fetch event full and attendee IDs concurrently
            let (event_full, attendee_ids) = tokio::try_join!(
                db.get_event_full(community_id, group_id, event_id),
                db.list_event_attendees_ids(group_id, event_id)
            )?;

            // Combine attendee and speaker IDs (deduplicated)
            let speaker_ids = event_full.speakers_ids();
            let recipients: Vec<Uuid> = attendee_ids
                .into_iter()
                .chain(speaker_ids)
                .collect::<HashSet<_>>()
                .into_iter()
                .collect();

            if !recipients.is_empty() {
                let site_settings = db.get_site_settings().await?;
                let base = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
                let event_summary = EventSummary::from(&event_full);
                let link = build_event_page_link(base, &event_summary);
                let calendar_ics = build_event_calendar_attachment(base, &event_summary);
                let template_data = EventRescheduled {
                    event: event_summary,
                    link,
                    theme: site_settings.theme,
                };
                let notification = NewNotification {
                    attachments: vec![calendar_ics],
                    kind: NotificationKind::EventRescheduled,
                    recipients,
                    template_data: Some(serde_json::to_value(&template_data)?),
                };
                notifications_manager.enqueue(&notification).await?;
            }
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

// Helpers.

/// Builds a `HashMap` of meeting provider to max participants from config.
fn build_meetings_max_participants(meetings_cfg: Option<&MeetingsConfig>) -> HashMap<MeetingProvider, i32> {
    let mut map = HashMap::new();
    if let Some(cfg) = meetings_cfg
        && let Some(zoom) = &cfg.zoom
    {
        map.insert(MeetingProvider::Zoom, zoom.max_participants);
    }
    map
}

/// Prepares the events list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(EventsListFilters, events::ListPage), HandlerError> {
    // Fetch group's past and upcoming events
    let filters: EventsListFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (can_manage_events, events) = tokio::try_join!(
        db.user_has_group_permission(&community_id, &group_id, &user_id, GroupPermission::EventsWrite),
        db.list_group_events(group_id, &filters)
    )?;
    let mut past_filters = filters.clone();
    past_filters.events_tab = Some(EventsTab::Past);
    let mut upcoming_filters = filters.clone();
    upcoming_filters.events_tab = Some(EventsTab::Upcoming);

    // Prepare template
    let past_navigation_links =
        NavigationLinks::from_filters(&past_filters, events.past.total, DASHBOARD_URL, PARTIAL_URL)?;
    let upcoming_navigation_links = NavigationLinks::from_filters(
        &upcoming_filters,
        events.upcoming.total,
        DASHBOARD_URL,
        PARTIAL_URL,
    )?;
    let template = events::ListPage {
        can_manage_events,
        events,
        events_tab: filters.current_tab(),
        past_navigation_links,
        upcoming_navigation_links,
        limit: filters.limit,
        past_offset: filters.past_offset,
        upcoming_offset: filters.upcoming_offset,
    };

    Ok((filters, template))
}
