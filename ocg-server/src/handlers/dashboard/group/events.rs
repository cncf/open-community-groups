//! HTTP handlers for managing events in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, Query, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::{error, instrument};
use uuid::Uuid;

use crate::{
    config::{MeetingsConfig, PaymentsConfig},
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    router::serde_qs_config,
    services::{
        events::{
            AddEventInput, AutomaticTaxCheckError, DynEventsManager, EventActionInput,
            UpdateEventInput,
        },
        payments::AutomaticTaxReadinessError,
    },
    templates::dashboard::group::events,
    types::{
        dashboard::group::{
            events::{EventActionScope, EventInput, EventsListFilters, EventsTab},
            sponsors::GroupSponsorsFilters,
        },
        pagination::{self, NavigationLinks},
        payments::TicketTaxBehavior,
        permissions::GroupPermission,
    },
};

use super::payments_ready;

#[cfg(test)]
mod tests;

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
    let meetings_max_participants = meetings_cfg
        .as_ref()
        .map(MeetingsConfig::max_participants_by_provider)
        .unwrap_or_default();
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
        external_payments,
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
        db.list_timezones(),
        db.get_group_external_payments_context(community_id, group_id)
    )?;

    // Prepare template
    let template = events::AddPage {
        can_manage_events,
        categories,
        event_kinds,
        external_payments,
        group_id,
        meetings_enabled,
        meetings_max_participants,
        payment_currency_codes,
        payments_ready: payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref()),
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
    let meetings_max_participants = meetings_cfg
        .as_ref()
        .map(MeetingsConfig::max_participants_by_provider)
        .unwrap_or_default();
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
        external_payments,
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
        db.get_group_external_payments_context(community_id, group_id),
    )?;
    let template = events::UpdatePage {
        approved_submissions,
        can_manage_events,
        categories,
        cfs_submission_statuses: cfs_statuses,
        current_user_id: user.user_id,
        event,
        event_kinds,
        external_payments,
        meetings_enabled,
        meetings_max_participants,
        payment_currency_codes,
        payments_ready: payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref()),
        session_kinds,
        sponsors: sponsors.sponsors,
        timezones,
    };

    Ok(Html(template.render()?))
}

// JSON handlers.

/// Checks a saved event's venue with the configured automatic-tax provider.
#[instrument(skip_all, err)]
pub(crate) async fn automatic_tax_readiness(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(event_id): Path<Uuid>,
) -> Result<axum::response::Response, HandlerError> {
    // Check the persisted venue against the provider
    match events_manager
        .check_automatic_tax_readiness(community_id, group_id, event_id)
        .await
    {
        Ok(readiness) => Ok(Json(AutomaticTaxReadinessResponse {
            cached: readiness.cached,
            state_code: readiness.state_code,
            status: "ready",
        })
        .into_response()),
        Err(AutomaticTaxCheckError::Readiness(readiness_error)) => {
            Ok(automatic_tax_error_response(&readiness_error))
        }
        Err(AutomaticTaxCheckError::Other(err)) => Err(HandlerError::from(err)),
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
    State(events_manager): State<DynEventsManager>,
    Query(query): Query<TaxRatesQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Return active rates matching the requested inclusive or exclusive behavior
    let rates = events_manager
        .list_tax_rates(community_id, group_id, query.tax_behavior)
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
    State(events_manager): State<DynEventsManager>,
    ValidatedFormQs(event): ValidatedFormQs<EventInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Create the event or event series with its required notifications
    let event_ids = events_manager
        .add(&AddEventInput {
            actor_user_id: user.user_id,
            community_id,
            event,
            group_id,
        })
        .await?;

    // Reload the update editor so later saves update the created event
    let event_id = event_ids.first().copied().ok_or_else(|| {
        HandlerError::Other(anyhow::anyhow!("created event without an identifier"))
    })?;

    Ok((StatusCode::CREATED, event_editor_location_header(event_id)).into_response())
}

/// Cancels an event (sets canceled=true).
#[instrument(skip_all, err)]
pub(crate) async fn cancel(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Cancel the event or series with its required notifications
    events_manager
        .cancel(&EventActionInput {
            actor_user_id: user.user_id,
            community_id,
            event_id,
            group_id,
            scope: query.scope,
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Delete the selected event or the whole linked series
    events_manager
        .delete(&EventActionInput {
            actor_user_id: user.user_id,
            community_id,
            event_id,
            group_id,
            scope: query.scope,
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Publishes an event (sets published=true and records publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn publish(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Publish the event or series with its validations and notifications
    events_manager
        .publish(&EventActionInput {
            actor_user_id: user.user_id,
            community_id,
            event_id,
            group_id,
            scope: query.scope,
        })
        .await?;

    // Stay on the editor when requested; otherwise refresh the events list
    if query.return_to.as_deref() == Some("editor") {
        Ok((
            StatusCode::NO_CONTENT,
            event_editor_location_header(event_id),
        )
            .into_response())
    } else {
        Ok((
            StatusCode::NO_CONTENT,
            [("HX-Trigger", "refresh-group-dashboard-table")],
        )
            .into_response())
    }
}

/// Unpublishes an event (sets published=false and clears publication metadata).
#[instrument(skip_all, err)]
pub(crate) async fn unpublish(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve action scope
    let query = parse_event_action_query(raw_query.as_deref())?;

    // Unpublish the selected event or the whole linked series
    events_manager
        .unpublish(&EventActionInput {
            actor_user_id: user.user_id,
            community_id,
            event_id,
            group_id,
            scope: query.scope,
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates an existing event's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(event_id): Path<Uuid>,
    ValidatedFormQs(event): ValidatedFormQs<EventInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the event with its validations and required notifications
    events_manager
        .update(&UpdateEventInput {
            actor_user_id: user.user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await?;

    // Reload the update editor so the form receives server-assigned identifiers
    Ok((
        StatusCode::NO_CONTENT,
        event_editor_location_header(event_id),
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

/// Query parameters accepted by event management actions.
#[derive(Debug, Default, Deserialize)]
struct EventActionQuery {
    /// Optional post-action destination. Only `editor` reloads the event editor.
    #[serde(default, rename = "return")]
    return_to: Option<String>,
    /// Selected action scope.
    #[serde(default)]
    scope: EventActionScope,
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
        past_offset: filters.past_offset,
        upcoming_offset: filters.upcoming_offset,
    };

    Ok((filters, template))
}

/// Builds the HTMX location header that reloads the event editor fragment.
fn event_editor_location_header(event_id: Uuid) -> [(HeaderName, String); 1] {
    [(
        HeaderName::from_static("hx-location"),
        event_editor_location_json(event_id),
    )]
}

/// Builds the HTMX location JSON that reloads the event editor fragment.
fn event_editor_location_json(event_id: Uuid) -> String {
    format!(
        r##"{{"path":"/dashboard/group/events/{event_id}/update", "target":"#dashboard-content", "push":"false"}}"##
    )
}

/// Parses dashboard event action query parameters.
fn parse_event_action_query(raw_query: Option<&str>) -> Result<EventActionQuery, HandlerError> {
    Ok(serde_qs_config().deserialize_str(raw_query.unwrap_or_default())?)
}
