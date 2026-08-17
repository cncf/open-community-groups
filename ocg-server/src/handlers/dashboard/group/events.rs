//! HTTP handlers for managing events in the group dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, Query, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use chrono::Utc;
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, MeetingsConfig, PaymentsConfig},
    db::{DBExt, DBOperations, DynDB},
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    router::serde_qs_config,
    services::{
        meetings::MeetingProvider,
        notifications::enqueue::{
            enqueue_event_canceled_notification, enqueue_event_paid_configured_notifications,
            enqueue_event_published_notifications, enqueue_event_rescheduled_notification,
            enqueue_event_series_canceled_notifications,
            enqueue_event_series_published_notifications,
        },
        payments::{AutomaticTaxReadinessError, DynPaymentsManager},
    },
    templates::dashboard::group::{
        events::{self, Event, EventsListFilters, EventsTab},
        sponsors::GroupSponsorsFilters,
    },
    types::{
        event::{EventFull, EventSummary},
        pagination::{self, NavigationLinks},
        payments::{
            PaymentConfigurationValidation, TicketTaxBehavior, TicketTaxCalculationMode,
            TicketVenue,
        },
        permissions::GroupPermission,
    },
};

use super::payments_ready;

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
        meetings_max_participants,
        payments_enabled: payments_cfg.is_some(),
        payment_currency_codes,
        payments_ready: payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref()),
        session_kinds,
        sponsors: sponsors.sponsors,
        timezones,
        payment_recipient,
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
        meetings_max_participants,
        payments_enabled: payments_cfg.is_some(),
        payment_currency_codes,
        payments_ready: payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref()),
        session_kinds,
        sponsors: sponsors.sponsors,
        timezones,
        payment_recipient,
    };

    Ok(Html(template.render()?))
}

// JSON handlers.

/// Checks a saved event's venue with the configured automatic-tax provider.
#[instrument(skip_all, err)]
pub(crate) async fn automatic_tax_readiness(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_manager): State<DynPaymentsManager>,
    Path(event_id): Path<Uuid>,
) -> Result<axum::response::Response, HandlerError> {
    // Load only persisted event and sponsor data for this explicit check
    let (event, payment_recipient) = tokio::try_join!(
        db.get_event_full(community_id, group_id, event_id),
        db.get_group_payment_recipient(community_id, group_id),
    )?;
    let Some(payment_recipient) = payment_recipient else {
        return Ok(automatic_tax_error_response(
            &AutomaticTaxReadinessError::FiscalSponsorNotReady(
                "configure a fiscal sponsor before checking automatic tax".to_string(),
            ),
        ));
    };

    match payments_manager
        .ensure_automatic_tax_readiness(&payment_recipient, &event_venue(&event))
        .await
    {
        Ok(readiness) => Ok(Json(AutomaticTaxReadinessResponse {
            cached: readiness.cached,
            state_code: readiness.state_code,
            status: "ready",
        })
        .into_response()),
        Err(readiness_error) => Ok(automatic_tax_error_response(&readiness_error)),
    }
}

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

/// Lists active fiscal-sponsor Stripe Tax Rates for an event tax behavior.
#[instrument(skip_all, err)]
pub(crate) async fn tax_rates(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_manager): State<DynPaymentsManager>,
    Query(query): Query<TaxRatesQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load and validate the connected fiscal sponsor that owns the rates
    let recipient = db
        .get_group_payment_recipient(community_id, group_id)
        .await?
        .ok_or_else(|| {
            HandlerError::Database(
                "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
            )
        })?;
    payments_manager.validate_fiscal_sponsor(&recipient, false).await?;

    // Return active rates matching the requested inclusive or exclusive behavior
    let rates = payments_manager
        .list_tax_rates(&recipient, query.tax_behavior)
        .await?;

    Ok(Json(rates))
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
    State(payments_manager): State<DynPaymentsManager>,
    ValidatedFormQs(event): ValidatedFormQs<Event>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare and validate the event payload
    let cfg_max_participants = build_meetings_max_participants(meetings_cfg.as_ref());
    let payment_provider = payments_manager.configured_provider();
    let mut event_payload = build_event_payload(&event)?;
    let is_paid_capable = is_event_payload_paid_capable(&event_payload);
    let has_manual_tax_selection = event.tax_calculation_mode == TicketTaxCalculationMode::Manual
        && event
            .manual_tax_rate_ids
            .as_ref()
            .is_some_and(|rate_ids| !rate_ids.is_empty());

    // Validate the group fiscal sponsor with the provider before persisting a
    // paid event, embedding the validated recipient in the payload so the
    // database can verify it did not change before committing
    if (payment_provider.is_some() && is_paid_capable) || has_manual_tax_selection {
        let payment_validation = validate_group_fiscal_sponsor(
            db.as_ref(),
            &payments_manager,
            community_id,
            group_id,
            event.manual_tax_rate_ids.as_deref().unwrap_or_default(),
            event.tax_behavior,
            event.tax_calculation_mode,
        )
        .await?;
        bind_payment_validation(&mut event_payload, &payment_validation)?;
    }
    let recurring_event_payloads = RecurringEventPayloads::from_event(&event, &event_payload)
        .map_err(|err| HandlerError::Deserialization(err.to_string()))?;

    // Persist the events and required notifications atomically
    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Create either a single event or a linked recurring event series
                let event_ids = if let Some(recurring_event_payloads) = recurring_event_payloads {
                    tx.add_event_series(
                        user.user_id,
                        group_id,
                        &recurring_event_payloads.events,
                        &recurring_event_payloads.recurrence,
                        &cfg_max_participants,
                        payment_provider,
                    )
                    .await?
                } else {
                    vec![
                        tx.add_event(
                            user.user_id,
                            group_id,
                            &event_payload,
                            &cfg_max_participants,
                            payment_provider,
                        )
                        .await?,
                    ]
                };

                // Enqueue required admin notifications before committing paid events
                if is_paid_capable {
                    enqueue_event_paid_configured_notifications(
                        tx,
                        community_id,
                        group_id,
                        &event_ids,
                    )
                    .await?;
                }

                Ok(())
            })
        })
        .await?;

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
                // Resolve and lock cancellation targets before attendance can change
                let event_ids = cancel_event_action_ids(tx, group_id, event_id, scope).await?;
                tx.lock_events_for_cancellation(group_id, &event_ids).await?;

                // Load summaries while locks preserve notification eligibility and recipients
                let mut events = Vec::with_capacity(event_ids.len());
                for event_id in &event_ids {
                    events.push(tx.get_event_summary(community_id, group_id, *event_id).await?);
                }

                // Snapshot and enqueue cancellation recipients before attendance is deactivated
                let events_to_notify: Vec<EventSummary> = events
                    .into_iter()
                    .filter(|event| {
                        event.published && !event.canceled && !event.test_event && !event.is_past()
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
                            community_id,
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
                            community_id,
                            group_id,
                            event.event_id,
                        )
                        .await?;
                    }
                    _ => {}
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_manager): State<DynPaymentsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;
    let scope = query.scope;

    // Validate the group fiscal sponsor with the provider before publishing
    // paid events, passing the validated recipient to the database so it can
    // verify it did not change before committing
    let payment_provider = payments_manager.configured_provider();
    let payment_validation = if payment_provider.is_some() {
        let event_ids = match scope {
            EventActionScope::Series => {
                db.list_event_series_publishable_event_ids(group_id, event_id).await?
            }
            EventActionScope::This => vec![event_id],
        };
        validate_publish_fiscal_sponsor(
            db.as_ref(),
            &payments_manager,
            community_id,
            group_id,
            &event_ids,
        )
        .await?
    } else {
        None
    };

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
                    events.push(tx.get_event_summary(community_id, group_id, *event_id).await?);
                }

                // Publish the selected event or the whole linked series
                match scope {
                    EventActionScope::Series => {
                        tx.publish_event_series_events(
                            user.user_id,
                            group_id,
                            &event_ids,
                            payment_provider,
                            payment_validation.clone(),
                        )
                        .await?;
                    }
                    EventActionScope::This => {
                        tx.publish_event(
                            user.user_id,
                            group_id,
                            event_id,
                            payment_provider,
                            payment_validation.clone(),
                        )
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
                            community_id,
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
                            community_id,
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(meetings_cfg): State<Option<MeetingsConfig>>,
    State(payments_manager): State<DynPaymentsManager>,
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
    let payment_provider = payments_manager.configured_provider();
    let mut event_json = build_event_payload(&event)?;

    // Validate the group fiscal sponsor with the provider when the update
    // changes the ticketing configuration, embedding the validated recipient
    // in the payload so the database can verify it did not change before
    // committing
    let ticketing_configuration_changed = if payment_provider.is_some() {
        db.event_ticketing_configuration_changed(community_id, group_id, event_id, &event_json)
            .await?
    } else {
        false
    };
    let has_manual_tax_selection = event.tax_calculation_mode == TicketTaxCalculationMode::Manual
        && event
            .manual_tax_rate_ids
            .as_ref()
            .is_some_and(|rate_ids| !rate_ids.is_empty());
    if ticketing_configuration_changed || has_manual_tax_selection {
        let payment_validation = validate_group_fiscal_sponsor(
            db.as_ref(),
            &payments_manager,
            community_id,
            group_id,
            event.manual_tax_rate_ids.as_deref().unwrap_or_default(),
            event.tax_behavior,
            event.tax_calculation_mode,
        )
        .await?;
        bind_payment_validation(&mut event_json, &payment_validation)?;
    }

    // Revalidate provider location readiness before changing a published automatic-tax event
    if ticketing_configuration_changed
        && event.tax_calculation_mode == TicketTaxCalculationMode::Automatic
        && is_event_payload_paid_capable(&event_json)
    {
        let persisted_event = db.get_event_full(community_id, group_id, event_id).await?;
        if persisted_event.published {
            let payment_recipient = db
                .get_group_payment_recipient(community_id, group_id)
                .await?
                .ok_or_else(|| {
                HandlerError::Database(
                    "configure a fiscal sponsor before updating this published event".to_string(),
                )
            })?;
            payments_manager
                .ensure_automatic_tax_readiness(&payment_recipient, &event_form_venue(&event))
                .await
                .map_err(automatic_tax_handler_error)?;
        }
    }

    // Persist the update and required notifications atomically
    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Load prior state before mutating to drive notification decisions
                let before = tx.get_event_summary(community_id, group_id, event_id).await?;

                // Update event in database
                let requires_paid_notification = tx
                    .update_event(
                        user.user_id,
                        group_id,
                        event_id,
                        &event_json,
                        &cfg_max_participants,
                        payment_provider,
                    )
                    .await?;

                // Enqueue required admin notification after entering the notifiable paid state
                if requires_paid_notification {
                    enqueue_event_paid_configured_notifications(
                        tx,
                        community_id,
                        group_id,
                        &[event_id],
                    )
                    .await?;
                }

                // Enqueue required reschedule notifications before committing
                enqueue_event_rescheduled_notification(
                    tx,
                    &server_cfg,
                    community_id,
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

/// Organizer-correctable automatic-tax readiness response.
#[derive(Debug, Serialize)]
struct AutomaticTaxReadinessErrorResponse {
    /// Stable machine-readable failure code.
    code: &'static str,
    /// Form fields associated with the failure.
    fields: Vec<String>,
    /// Organizer-facing explanation.
    message: String,
    /// Stable readiness status.
    status: &'static str,
}

/// Successful automatic-tax readiness response.
#[derive(Debug, Serialize)]
struct AutomaticTaxReadinessResponse {
    /// Whether an existing matching performance location was reused.
    cached: bool,
    /// ISO subdivision code sent to the provider, when available.
    state_code: Option<String>,
    /// Stable readiness status.
    status: &'static str,
}

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

/// Query parameters accepted by the Tax Rate listing endpoint.
#[derive(Debug, Deserialize)]
pub(crate) struct TaxRatesQuery {
    /// Inclusive or exclusive rate behavior requested by the event form.
    tax_behavior: TicketTaxBehavior,
}

// Helpers.

/// Converts a readiness failure into the explicit JSON endpoint contract.
fn automatic_tax_error_response(error: &AutomaticTaxReadinessError) -> axum::response::Response {
    if error.is_correctable() {
        let body = AutomaticTaxReadinessErrorResponse {
            code: error.code(),
            fields: error.fields(),
            message: error.to_string(),
            status: "not_ready",
        };
        return (StatusCode::UNPROCESSABLE_ENTITY, Json(body)).into_response();
    }

    error!(error = %error, "automatic-tax readiness provider failure");
    (
        StatusCode::BAD_GATEWAY,
        Json(AutomaticTaxReadinessErrorResponse {
            code: "provider_unavailable",
            fields: Vec::new(),
            message: "The automatic-tax provider is temporarily unavailable. Try again later."
                .to_string(),
            status: "not_ready",
        }),
    )
        .into_response()
}

/// Converts readiness failures used by event mutations into handler responses.
pub(super) fn automatic_tax_handler_error(error: AutomaticTaxReadinessError) -> HandlerError {
    if error.is_correctable() {
        HandlerError::Database(error.to_string())
    } else {
        HandlerError::Other(anyhow::Error::new(error))
    }
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
    filters.validate()?;
    let (can_manage_events, events) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
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

/// Embeds provider validation into the payload committed after database locking.
fn bind_payment_validation(
    event: &mut serde_json::Value,
    payment_validation: &PaymentConfigurationValidation,
) -> Result<(), HandlerError> {
    let event = event.as_object_mut().ok_or_else(|| {
        HandlerError::Deserialization("event payload must be an object".to_string())
    })?;
    event.insert(
        "_payment_validation".to_string(),
        serde_json::to_value(payment_validation)
            .map_err(|err| HandlerError::Deserialization(err.to_string()))?,
    );

    Ok(())
}

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
        && let Some(zoom) = &cfg.zoom
    {
        map.insert(MeetingProvider::Zoom, zoom.max_participants);
    }
    map
}

/// Resolves the non-completed event identifiers affected by cancellation.
async fn cancel_event_action_ids(
    db: &dyn DBOperations,
    group_id: Uuid,
    event_id: Uuid,
    scope: EventActionScope,
) -> Result<Vec<Uuid>> {
    if scope == EventActionScope::This {
        return Ok(vec![event_id]);
    }

    let event_ids = db.list_event_series_cancelable_event_ids(group_id, event_id).await?;
    if event_ids.is_empty() {
        Ok(vec![event_id])
    } else {
        Ok(event_ids)
    }
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

/// Builds the normalized provider venue from a submitted dashboard event.
fn event_form_venue(event: &Event) -> TicketVenue {
    TicketVenue {
        address: event.venue_address.clone().unwrap_or_default(),
        city: event.venue_city.clone().unwrap_or_default(),
        country_code: event.venue_country_code.clone().unwrap_or_default(),
        name: event.venue_name.clone().unwrap_or_default(),
        zip_code: event.venue_zip_code.clone().unwrap_or_default(),

        state_code: event.venue_state_code.clone(),
        state_name: event.venue_state_name.clone(),
    }
}

/// Builds the normalized provider venue from a persisted event.
pub(super) fn event_venue(event: &EventFull) -> TicketVenue {
    TicketVenue {
        address: event.venue_address.clone().unwrap_or_default(),
        city: event.venue_city.clone().unwrap_or_default(),
        country_code: event.venue_country_code.clone().unwrap_or_default(),
        name: event.venue_name.clone().unwrap_or_default(),
        zip_code: event.venue_zip_code.clone().unwrap_or_default(),

        state_code: event.venue_state_code.clone(),
        state_name: event.venue_state_name.clone(),
    }
}

/// Returns whether a normalized event payload contains any positive ticket price.
fn is_event_payload_paid_capable(event: &serde_json::Value) -> bool {
    event
        .get("ticket_types")
        .and_then(serde_json::Value::as_array)
        .is_some_and(|ticket_types| {
            ticket_types.iter().any(|ticket_type| {
                ticket_type
                    .get("price_windows")
                    .and_then(serde_json::Value::as_array)
                    .is_some_and(|price_windows| {
                        price_windows.iter().any(|price_window| {
                            price_window
                                .get("amount_minor")
                                .and_then(serde_json::Value::as_i64)
                                .is_some_and(|amount_minor| amount_minor > 0)
                        })
                    })
            })
        })
}

/// Parses dashboard event action query parameters.
fn parse_event_action_query(raw_query: Option<&str>) -> Result<EventActionQuery, HandlerError> {
    Ok(serde_qs_config().deserialize_str(raw_query.unwrap_or_default())?)
}

/// Validates the configured group sponsor before paid event configuration is persisted.
async fn validate_group_fiscal_sponsor(
    db: &dyn DBOperations,
    payments_manager: &DynPaymentsManager,
    community_id: Uuid,
    group_id: Uuid,
    manual_tax_rate_ids: &[String],
    tax_behavior: TicketTaxBehavior,
    tax_calculation_mode: TicketTaxCalculationMode,
) -> Result<PaymentConfigurationValidation, HandlerError> {
    // Load the current recipient before validating its provider configuration
    let payment_recipient = db.get_group_payment_recipient(community_id, group_id).await?;

    // Validate sponsor readiness and any manual Tax Rate selection
    if let Some(recipient) = payment_recipient.as_ref() {
        payments_manager
            .validate_fiscal_sponsor(
                recipient,
                tax_calculation_mode == TicketTaxCalculationMode::Automatic,
            )
            .await?;

        // Recheck manual rate ownership and display behavior
        if tax_calculation_mode == TicketTaxCalculationMode::Manual {
            payments_manager
                .validate_tax_rates(recipient, manual_tax_rate_ids, tax_behavior)
                .await?;
        }
    } else if tax_calculation_mode == TicketTaxCalculationMode::Manual
        && !manual_tax_rate_ids.is_empty()
    {
        // Reject manual Tax Rate selections without a connected sponsor
        return Err(HandlerError::Database(
            "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
        ));
    }

    // Bind the validated configuration to the pending database mutation
    Ok(PaymentConfigurationValidation {
        require_automatic_tax: tax_calculation_mode == TicketTaxCalculationMode::Automatic,

        expected_payment_recipient: payment_recipient.clone(),
        manual_tax_rate_ids: Some(manual_tax_rate_ids.to_vec()),
        tax_behavior: Some(tax_behavior),
        tax_calculation_mode: Some(tax_calculation_mode),
        validated_payment_recipient: payment_recipient,
    })
}

/// Validates the selected sponsor against every paid event about to be published.
async fn validate_publish_fiscal_sponsor(
    db: &dyn DBOperations,
    payments_manager: &DynPaymentsManager,
    community_id: Uuid,
    group_id: Uuid,
    event_ids: &[Uuid],
) -> Result<Option<PaymentConfigurationValidation>, HandlerError> {
    let mut events = Vec::new();
    let mut paid_events = Vec::new();
    let mut require_automatic_tax = false;

    // Load each event and aggregate the strongest paid sponsor readiness need
    for event_id in event_ids {
        let event = db.get_event_full(community_id, group_id, *event_id).await?;
        if event.is_paid_capable() {
            require_automatic_tax |=
                event.tax_calculation_mode == TicketTaxCalculationMode::Automatic;
            paid_events.push(event.clone());
        }
        events.push(event);
    }

    // Select manual-tax events whose rates must be revalidated
    let manual_events = events
        .iter()
        .filter(|event| {
            event.tax_calculation_mode == TicketTaxCalculationMode::Manual
                && (event.is_paid_capable() || !event.manual_tax_rate_ids.is_empty())
        })
        .collect::<Vec<_>>();

    // Skip provider validation when the publish set has no applicable tax state
    if paid_events.is_empty() && manual_events.is_empty() {
        return Ok(None);
    }

    // Validate the sponsor once, then recheck every applicable manual selection
    let payment_recipient = db.get_group_payment_recipient(community_id, group_id).await?;
    if let Some(recipient) = payment_recipient.as_ref() {
        payments_manager
            .validate_fiscal_sponsor(recipient, require_automatic_tax)
            .await?;
        for event in paid_events
            .iter()
            .filter(|event| event.tax_calculation_mode == TicketTaxCalculationMode::Automatic)
        {
            payments_manager
                .ensure_automatic_tax_readiness(recipient, &event_venue(event))
                .await
                .map_err(automatic_tax_handler_error)?;
        }
        for event in manual_events {
            payments_manager
                .validate_tax_rates(recipient, &event.manual_tax_rate_ids, event.tax_behavior)
                .await?;
        }
    } else if paid_events
        .iter()
        .any(|event| event.tax_calculation_mode == TicketTaxCalculationMode::Automatic)
    {
        return Err(HandlerError::Database(
            "configure a fiscal sponsor before publishing this automatic-tax event".to_string(),
        ));
    } else if events.iter().any(|event| {
        event.tax_calculation_mode == TicketTaxCalculationMode::Manual
            && !event.manual_tax_rate_ids.is_empty()
    }) {
        return Err(HandlerError::Database(
            "configure a fiscal sponsor before selecting Stripe Tax Rates".to_string(),
        ));
    }

    let Some(first_event) = paid_events.first() else {
        return Ok(None);
    };
    Ok(Some(PaymentConfigurationValidation {
        require_automatic_tax,

        expected_payment_recipient: payment_recipient.clone(),
        manual_tax_rate_ids: Some(first_event.manual_tax_rate_ids.clone()),
        tax_behavior: Some(first_event.tax_behavior),
        tax_calculation_mode: Some(first_event.tax_calculation_mode),
        validated_payment_recipient: payment_recipient,
    }))
}
