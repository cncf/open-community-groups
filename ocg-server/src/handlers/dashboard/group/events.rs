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
use serde::Deserialize;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, MeetingsConfig, PaymentsConfig},
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
            EventCanceled, EventPublished, EventRescheduled, EventSeriesCanceled,
            EventSeriesNotificationItem, EventSeriesPublished, EventWaitlistPromoted, SpeakerSeriesWelcome,
            SpeakerWelcome,
        },
    },
    types::{
        event::{EventFull, EventSummary},
        pagination::{self, NavigationLinks},
        payments::GroupPaymentRecipient,
        permissions::GroupPermission,
    },
    util::{build_event_calendar_attachment, build_event_page_link},
};

mod recurrence;

#[cfg(test)]
mod tests;

use recurrence::build_recurring_event_payloads;

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
    State(payments_cfg): State<Option<PaymentsConfig>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch template data concurrently
    let meetings_enabled = meetings_cfg.as_ref().is_some_and(MeetingsConfig::meetings_enabled);
    let meetings_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let sponsor_filters: GroupSponsorsFilters = serde_qs_config().deserialize_str("")?;
    let (
        can_manage_events,
        categories,
        event_kinds,
        payment_currency_codes,
        payment_recipient,
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
        db.list_event_categories(community_id),
        db.list_event_kinds(),
        db.list_payment_currency_codes(),
        db.get_group_payment_recipient(community_id, group_id),
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
        payments_enabled: payments_cfg.is_some(),
        payment_currency_codes,
        payments_ready: payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref()),
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
    State(payments_cfg): State<Option<PaymentsConfig>>,
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
        payment_currency_codes,
        payment_recipient,
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
        db.list_payment_currency_codes(),
        db.get_group_payment_recipient(community_id, group_id),
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
        payments_enabled: payments_cfg.is_some(),
        payment_currency_codes,
        payments_ready: payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref()),
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    State(payments_cfg): State<Option<crate::config::PaymentsConfig>>,
    ValidatedFormQs(event): ValidatedFormQs<Event>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare and validate the event payload
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let event_payload = build_event_payload(&event)?;
    if event_payload_uses_ticketing(&event_payload) {
        ensure_ticketing_ready(&db, community_id, group_id, payments_cfg.as_ref()).await?;
    }

    // Create either a single event or a linked recurring event series
    if let Some(recurring_event_payloads) = build_recurring_event_payloads(&event, &event_payload)
        .map_err(|err| HandlerError::Deserialization(err.to_string()))?
    {
        db.add_event_series(
            user.user_id,
            group_id,
            &recurring_event_payloads.events,
            &recurring_event_payloads.recurrence,
            &cfg_max_participants,
        )
        .await?;
    } else {
        db.add_event(user.user_id, group_id, &event_payload, &cfg_max_participants)
            .await?;
    }

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

/// Cancels an event (sets canceled=true).
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn cancel(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Load summaries before canceling so notification eligibility uses prior state
    let event_ids = event_action_ids(&db, group_id, event_id, query.scope).await?;
    let mut events = Vec::with_capacity(event_ids.len());
    for event_id in &event_ids {
        events.push(db.get_event_summary(community_id, group_id, *event_id).await?);
    }

    // Mark the selected event or the whole linked series as canceled
    match query.scope {
        EventActionScope::Series => {
            db.cancel_event_series_events(user.user_id, group_id, &event_ids)
                .await?;
        }
        EventActionScope::This => db.cancel_event(user.user_id, group_id, event_id).await?,
    }

    // Notify related users about canceled events that were future published
    let events_to_notify: Vec<EventSummary> = events
        .into_iter()
        .filter(|event| {
            matches!(
                (event.published, event.canceled, event.starts_at),
                (true, false, Some(starts_at)) if starts_at > Utc::now()
            )
        })
        .collect();
    match (query.scope, events_to_notify.as_slice()) {
        // Multiple notifiable events
        (EventActionScope::Series, [_, _, ..]) => {
            let event_ids: Vec<Uuid> = events_to_notify.iter().map(|event| event.event_id).collect();
            notify_events_canceled(
                &db,
                &notifications_manager,
                &server_cfg,
                community_id,
                group_id,
                &event_ids,
            )
            .await?;
        }
        // Single notifiable event
        (_, [event]) => {
            notify_event_canceled(
                &db,
                &notifications_manager,
                &server_cfg,
                community_id,
                group_id,
                event.event_id,
            )
            .await?;
        }
        _ => {}
    }

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Location",
            r#"{"path":"/dashboard/group?tab=events", "target":"body"}"#,
        )],
    ))
}

/// Deletes an event from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Delete the selected event or the whole linked series
    match query.scope {
        EventActionScope::Series => {
            let event_ids = event_action_ids(&db, group_id, event_id, query.scope).await?;
            db.delete_event_series_events(user.user_id, group_id, &event_ids)
                .await?;
        }
        EventActionScope::This => db.delete_event(user.user_id, group_id, event_id).await?,
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Publishes an event (sets published=true and records publication metadata).
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn publish(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope and target event ids
    let query = parse_event_action_query(raw_query.as_deref())?;
    let event_ids = match query.scope {
        EventActionScope::Series => db.list_event_series_publishable_event_ids(group_id, event_id).await?,
        EventActionScope::This => vec![event_id],
    };
    let configured_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);

    // Load event summaries before publishing so notification decisions match prior state
    let mut events = Vec::with_capacity(event_ids.len());
    for event_id in &event_ids {
        events.push(db.get_event_summary(community_id, group_id, *event_id).await?);
    }

    // Publish the selected event or the whole linked series
    match query.scope {
        EventActionScope::Series => {
            db.publish_event_series_events(user.user_id, configured_provider, group_id, &event_ids)
                .await?;
        }
        EventActionScope::This => {
            db.publish_event(user.user_id, configured_provider, group_id, event_id)
                .await?;
        }
    }

    // Notify related users about published events that were future drafts
    let events_to_notify: Vec<EventSummary> = events
        .into_iter()
        .filter(|event| {
            matches!(
                (event.published, event.starts_at),
                (false, Some(starts_at)) if starts_at > Utc::now()
            )
        })
        .collect();
    match (query.scope, events_to_notify.as_slice()) {
        // Multiple notifiable events
        (EventActionScope::Series, [_, _, ..]) => {
            let event_ids: Vec<Uuid> = events_to_notify.iter().map(|event| event.event_id).collect();
            notify_events_published(
                &db,
                &notifications_manager,
                &server_cfg,
                community_id,
                group_id,
                &event_ids,
            )
            .await?;
        }
        // Single notifiable event
        (_, [event]) => {
            notify_event_published(
                &db,
                &notifications_manager,
                &server_cfg,
                community_id,
                group_id,
                event.event_id,
            )
            .await?;
        }
        _ => {}
    }

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
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Unpublish the selected event or the whole linked series
    match query.scope {
        EventActionScope::Series => {
            let event_ids = event_action_ids(&db, group_id, event_id, query.scope).await?;
            db.unpublish_event_series_events(user.user_id, group_id, &event_ids)
                .await?;
        }
        EventActionScope::This => db.unpublish_event(user.user_id, group_id, event_id).await?,
    }

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
    State(payments_cfg): State<Option<crate::config::PaymentsConfig>>,
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
    let event_json = build_event_payload(&event)?;
    if event_payload_uses_ticketing(&event_json) {
        ensure_ticketing_ready(&db, community_id, group_id, payments_cfg.as_ref()).await?;
    }
    let promoted_user_ids = db
        .update_event(
            user.user_id,
            group_id,
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

// Types.

/// Query parameters accepted by cancel/delete actions.
#[derive(Debug, Default, Deserialize)]
struct EventActionQuery {
    /// Selected action scope.
    #[serde(default)]
    scope: EventActionScope,
}

/// Event management action scope requested by the dashboard.
#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
enum EventActionScope {
    /// Apply the action to the linked event series.
    Series,
    /// Apply the action only to the selected event.
    #[default]
    This,
}

/// Recipient group sharing the same event list for one aggregate notification.
struct EventSeriesNotificationGroup {
    /// Events included in the notification.
    events: Vec<EventSeriesNotificationItem>,
    /// Recipients that should receive the notification.
    recipients: Vec<Uuid>,
}

// Helpers.

/// Builds the database payload for an event form.
fn build_event_payload(event: &Event) -> Result<serde_json::Value, HandlerError> {
    event
        .to_db_payload()
        .map_err(|err| HandlerError::Deserialization(err.to_string()))
}

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

/// Ensures that ticketing can be used for the event by checking payments configuration and group setup.
async fn ensure_ticketing_ready(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    payments_cfg: Option<&PaymentsConfig>,
) -> Result<(), HandlerError> {
    // Require a configured server payments provider before enabling ticketing
    let Some(payments_cfg) = payments_cfg else {
        return Err(HandlerError::Database(
            "payments are not configured on this server".to_string(),
        ));
    };

    // Require a group recipient that matches the configured payments provider
    let payment_recipient = db.get_group_payment_recipient(community_id, group_id).await?;
    if payment_recipient.is_none() {
        return Err(HandlerError::Database(
            "configure a payments recipient in group settings first".to_string(),
        ));
    }

    if !payments_ready(payment_recipient.as_ref(), Some(payments_cfg)) {
        return Err(HandlerError::Database(
            "configure a payments recipient for this server's payments provider first".to_string(),
        ));
    }

    Ok(())
}

/// Resolves the event identifiers affected by a dashboard event action.
async fn event_action_ids(
    db: &DynDB,
    group_id: Uuid,
    event_id: Uuid,
    scope: EventActionScope,
) -> Result<Vec<Uuid>, HandlerError> {
    if scope == EventActionScope::This {
        return Ok(vec![event_id]);
    }

    let event_ids = db.list_event_series_event_ids(group_id, event_id).await?;
    if event_ids.is_empty() {
        Ok(vec![event_id])
    } else {
        Ok(event_ids)
    }
}

/// Checks if the event payload includes ticket types, indicating that ticketing is used.
fn event_payload_uses_ticketing(event_payload: &serde_json::Value) -> bool {
    event_payload
        .get("ticket_types")
        .and_then(serde_json::Value::as_array)
        .is_some_and(|ticket_types| !ticket_types.is_empty())
}

/// Parses dashboard event action query parameters.
fn parse_event_action_query(raw_query: Option<&str>) -> Result<EventActionQuery, HandlerError> {
    Ok(serde_qs_config().deserialize_str(raw_query.unwrap_or_default())?)
}

/// Checks whether group payments are ready for ticketed events.
fn payments_ready(
    payment_recipient: Option<&GroupPaymentRecipient>,
    payments_cfg: Option<&PaymentsConfig>,
) -> bool {
    matches!(
        (payment_recipient, payments_cfg),
        (Some(payment_recipient), Some(payments_cfg))
            if payment_recipient.provider == payments_cfg.provider()
    )
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

    // Prepare pagination links for each events tab
    let mut past_filters = filters.clone();
    past_filters.events_tab = Some(EventsTab::Past);
    let mut upcoming_filters = filters.clone();
    upcoming_filters.events_tab = Some(EventsTab::Upcoming);
    let past_navigation_links =
        NavigationLinks::from_filters(&past_filters, events.past.total, DASHBOARD_URL, PARTIAL_URL)?;
    let upcoming_navigation_links = NavigationLinks::from_filters(
        &upcoming_filters,
        events.upcoming.total,
        DASHBOARD_URL,
        PARTIAL_URL,
    )?;

    // Prepare template
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

// Notifications helpers.

/// Builds one aggregate notification item from full event data.
fn event_series_notification_item(base_url: &str, event_full: &EventFull) -> EventSeriesNotificationItem {
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

/// Sends the event-canceled notification to attendees, waitlist users, and speakers.
async fn notify_event_canceled(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
) -> Result<(), HandlerError> {
    // Fetch event full and attendee IDs concurrently
    let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
        db.get_event_full(community_id, group_id, event_id),
        db.list_event_attendees_ids(group_id, event_id),
        db.list_event_waitlist_ids(group_id, event_id)
    )?;

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

    Ok(())
}

/// Sends event-published notifications to group members, team members, and speakers.
async fn notify_event_published(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_id: Uuid,
) -> Result<(), HandlerError> {
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
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let event_summary = EventSummary::from(&event_full);
    let link = build_event_page_link(base_url, &event_summary);
    let calendar_ics = build_event_calendar_attachment(base_url, &event_summary);

    // Notify group members about the published event
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

    Ok(())
}

/// Sends one aggregate cancellation notification per recipient event set.
async fn notify_events_canceled(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<(), HandlerError> {
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let mut recipient_events: HashMap<Uuid, Vec<EventSeriesNotificationItem>> = HashMap::new();

    // Build recipient event lists for each canceled occurrence
    for event_id in event_ids {
        // Fetch event full and affected user IDs for this canceled occurrence
        let (event_full, attendee_ids, waitlist_ids) = tokio::try_join!(
            db.get_event_full(community_id, group_id, *event_id),
            db.list_event_attendees_ids(group_id, *event_id),
            db.list_event_waitlist_ids(group_id, *event_id)
        )?;

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

    // If there are no recipients to notify, we are done
    if recipient_events.is_empty() {
        return Ok(());
    }

    // Build and enqueue grouped cancellation notifications
    let site_settings = db.get_site_settings().await?;
    for group in group_recipients_by_events(recipient_events) {
        let Some(group_name) = group.events.first().map(|event| event.event.group_name.clone()) else {
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
        notifications_manager.enqueue(&notification).await?;
    }

    Ok(())
}

/// Sends aggregate publish notifications to members/team and speakers.
async fn notify_events_published(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    community_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<(), HandlerError> {
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
        let event_full = db.get_event_full(community_id, group_id, *event_id).await?;
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

    // If there are no recipients to notify, we are done
    if member_events.is_empty() && speaker_events.is_empty() {
        return Ok(());
    }

    // Notify group members about the published event series
    let site_settings = db.get_site_settings().await?;
    for group in group_recipients_by_events(member_events) {
        let Some(group_name) = group.events.first().map(|event| event.event.group_name.clone()) else {
            continue;
        };
        let template_data = EventSeriesPublished {
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
        notifications_manager.enqueue(&notification).await?;
    }

    // Notify speakers about being added to the event series
    for group in group_recipients_by_events(speaker_events) {
        let Some(group_name) = group.events.first().map(|event| event.event.group_name.clone()) else {
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
        notifications_manager.enqueue(&notification).await?;
    }

    Ok(())
}
