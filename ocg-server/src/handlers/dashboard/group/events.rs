//! HTTP handlers for managing events in the group dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use chrono::Utc;
use garde::Validate;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, MeetingsConfig, PaymentsConfig},
    db::{DBExt, DBOperations, DynDB},
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId, ValidatedFormQs},
    },
    router::serde_qs_config,
    services::{
        meetings::MeetingProvider,
        notifications::enqueue::{
            enqueue_event_canceled_notification, enqueue_event_published_notifications,
            enqueue_event_rescheduled_notification, enqueue_event_series_canceled_notifications,
            enqueue_event_series_published_notifications,
            enqueue_event_waitlist_promoted_notification,
        },
    },
    templates::dashboard::group::{
        events::{self, Event, EventsListFilters, EventsTab},
        sponsors::GroupSponsorsFilters,
    },
    types::{
        event::EventSummary,
        pagination::{self, NavigationLinks},
        payments::GroupPaymentRecipient,
        permissions::GroupPermission,
    },
};

mod recurrence;

#[cfg(test)]
mod tests;

use recurrence::RecurringEventPayloads;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/group?tab=events";
const PARTIAL_URL: &str = "/dashboard/group/events";

// Pages handlers.

/// Displays the page to add a new event.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
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
            &alliance_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.list_event_categories(alliance_id),
        db.list_event_kinds(),
        db.list_payment_currency_codes(),
        db.get_group_payment_recipient(alliance_id, group_id),
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        alliance_id,
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

/// Renders a database-free preview from the submitted event editor state.
#[instrument(skip_all, err)]
pub(crate) async fn preview(
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let input: events::preview::Input = serde_qs_de
        .deserialize_str(&body)
        .map_err(|err| HandlerError::Deserialization(err.to_string()))?;
    let template = events::preview::Page {
        event: input.into(),
    };

    Ok(Html(template.render()?))
}

/// Displays the page to update an existing event.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
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
            &alliance_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_full(alliance_id, group_id, event_id),
        db.list_event_approved_cfs_submissions(event_id),
        db.list_event_categories(alliance_id),
        db.list_cfs_submission_statuses_for_review(),
        db.list_event_kinds(),
        db.list_payment_currency_codes(),
        db.get_group_payment_recipient(alliance_id, group_id),
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    let event = db.get_event_full(alliance_id, group_id, event_id).await?;

    Ok(Json(event).into_response())
}

// Actions handlers.

/// Adds a new event to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
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
        ensure_ticketing_ready(&db, alliance_id, group_id, payments_cfg.as_ref()).await?;
    }

    // Create either a single event or a linked recurring event series
    if let Some(recurring_event_payloads) =
        RecurringEventPayloads::from_event(&event, &event_payload)
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
        db.add_event(
            user.user_id,
            group_id,
            &event_payload,
            &cfg_max_participants,
        )
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;
    let scope = query.scope;

    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Load summaries before canceling so notification eligibility uses prior state
                let event_ids = event_action_ids(tx, group_id, event_id, scope).await?;
                let mut events = Vec::with_capacity(event_ids.len());
                for event_id in &event_ids {
                    events.push(tx.get_event_summary(alliance_id, group_id, *event_id).await?);
                }

                // Mark the selected event or the whole linked series as canceled
                match scope {
                    EventActionScope::Series => {
                        tx.cancel_event_series_events(user.user_id, group_id, &event_ids)
                            .await?;
                    }
                    EventActionScope::This => {
                        tx.cancel_event(user.user_id, group_id, event_id).await?;
                    }
                }

                // Enqueue cancellation notifications for future published events
                let events_to_notify: Vec<EventSummary> = events
                    .into_iter()
                    .filter(|event| {
                        matches!(
                            (event.published, event.canceled, event.starts_at),
                            (true, false, Some(starts_at))
                                if !event.test_event && starts_at > Utc::now()
                        )
                    })
                    .collect();
                match (scope, events_to_notify.as_slice()) {
                    // Multiple notifiable events
                    (EventActionScope::Series, [_, _, ..]) => {
                        let event_ids: Vec<Uuid> =
                            events_to_notify.iter().map(|event| event.event_id).collect();
                        enqueue_event_series_canceled_notifications(
                            tx,
                            &server_cfg,
                            alliance_id,
                            group_id,
                            &event_ids,
                        )
                        .await?;
                    }
                    // Single notifiable event
                    (_, [event]) => {
                        enqueue_event_canceled_notification(
                            tx,
                            &server_cfg,
                            alliance_id,
                            group_id,
                            event.event_id,
                        )
                        .await?;
                    }
                    _ => {}
                }

                Ok(())
            })
        })
        .await?;

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
            let event_ids = event_action_ids(db.as_ref(), group_id, event_id, query.scope).await?;
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;
    let scope = query.scope;
    let configured_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);

    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Resolve target event ids and load prior state before publishing
                let event_ids = match scope {
                    EventActionScope::Series => {
                        tx.list_event_series_publishable_event_ids(group_id, event_id).await?
                    }
                    EventActionScope::This => vec![event_id],
                };
                let mut events = Vec::with_capacity(event_ids.len());
                for event_id in &event_ids {
                    events.push(tx.get_event_summary(alliance_id, group_id, *event_id).await?);
                }

                // Publish the selected event or the whole linked series
                match scope {
                    EventActionScope::Series => {
                        tx.publish_event_series_events(
                            user.user_id,
                            configured_provider,
                            group_id,
                            &event_ids,
                        )
                        .await?;
                    }
                    EventActionScope::This => {
                        tx.publish_event(user.user_id, configured_provider, group_id, event_id)
                            .await?;
                    }
                }

                // Enqueue required publish notifications before committing
                let events_to_notify: Vec<EventSummary> = events
                    .into_iter()
                    .filter(|event| {
                        matches!(
                            (event.published, event.starts_at),
                            (false, Some(starts_at)) if !event.test_event && starts_at > Utc::now()
                        )
                    })
                    .collect();
                match (scope, events_to_notify.as_slice()) {
                    // Multiple notifiable events
                    (EventActionScope::Series, [_, _, ..]) => {
                        let event_ids: Vec<Uuid> =
                            events_to_notify.iter().map(|event| event.event_id).collect();
                        enqueue_event_series_published_notifications(
                            tx,
                            &server_cfg,
                            alliance_id,
                            group_id,
                            &event_ids,
                        )
                        .await?;
                    }
                    // Single notifiable event
                    (_, [event]) => {
                        enqueue_event_published_notifications(
                            tx,
                            &server_cfg,
                            alliance_id,
                            group_id,
                            event.event_id,
                        )
                        .await?;
                    }
                    _ => {}
                }

                Ok(())
            })
        })
        .await?;

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
            let event_ids = event_action_ids(db.as_ref(), group_id, event_id, query.scope).await?;
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
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    State(payments_cfg): State<Option<crate::config::PaymentsConfig>>,
    State(serde_qs_de): State<serde_qs::Config>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Deserialize and validate provided event
    let event: Event = serde_qs_de
        .deserialize_str(&body)
        .map_err(|e| HandlerError::Deserialization(e.to_string()))?;
    event.validate()?;

    // Prepare update payload and ticketing prerequisites
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let event_json = build_event_payload(&event)?;
    if event_payload_uses_ticketing(&event_json) {
        ensure_ticketing_ready(&db, alliance_id, group_id, payments_cfg.as_ref()).await?;
    }

    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Load prior state before mutating to drive notification decisions
                let before = tx.get_event_summary(alliance_id, group_id, event_id).await?;

                // Update event in database
                let promoted_user_ids = tx
                    .update_event(
                        user.user_id,
                        group_id,
                        event_id,
                        &event_json,
                        &cfg_max_participants,
                    )
                    .await?;

                // Enqueue required waitlist promotion notifications before committing
                enqueue_event_waitlist_promoted_notification(
                    tx,
                    &server_cfg,
                    alliance_id,
                    group_id,
                    event_id,
                    &before,
                    promoted_user_ids,
                )
                .await?;

                // Enqueue required reschedule notifications before committing
                enqueue_event_rescheduled_notification(
                    tx,
                    &server_cfg,
                    alliance_id,
                    group_id,
                    event_id,
                    &before,
                )
                .await?;

                Ok(())
            })
        })
        .await?;

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

// Helpers.

/// Builds the database payload for an event form.
fn build_event_payload(event: &Event) -> Result<serde_json::Value, HandlerError> {
    event
        .to_db_payload()
        .map_err(|err| HandlerError::Deserialization(err.to_string()))
}

/// Builds a `HashMap` of meeting provider to max participants from config.
fn build_meetings_max_participants(
    meetings_cfg: Option<&MeetingsConfig>,
) -> HashMap<MeetingProvider, i32> {
    let mut map = HashMap::new();
    if let Some(cfg) = meetings_cfg
        && let Some(google_meet) = &cfg.google_meet
    {
        map.insert(MeetingProvider::GoogleMeet, google_meet.max_participants);
    }
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
    alliance_id: Uuid,
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
    let payment_recipient = db.get_group_payment_recipient(alliance_id, group_id).await?;
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
    db: &dyn DBOperations,
    group_id: Uuid,
    event_id: Uuid,
    scope: EventActionScope,
) -> Result<Vec<Uuid>> {
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
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(EventsListFilters, events::ListPage), HandlerError> {
    // Fetch group's past and upcoming events
    let filters: EventsListFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (can_manage_events, events) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::EventsWrite
        ),
        db.list_group_events(group_id, &filters)
    )?;

    // Prepare pagination links for each events tab
    let mut past_filters = filters.clone();
    past_filters.events_tab = Some(EventsTab::Past);
    let mut upcoming_filters = filters.clone();
    upcoming_filters.events_tab = Some(EventsTab::Upcoming);
    let past_navigation_links = NavigationLinks::from_filters(
        &past_filters,
        events.past.total,
        DASHBOARD_URL,
        PARTIAL_URL,
    )?;
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
