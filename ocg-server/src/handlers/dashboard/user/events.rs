//! HTTP handlers for user upcoming events.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, PaymentsConfig},
    db::{DBExt, DynDB},
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::enqueue::enqueue_event_attendance_cancellation_notifications,
    templates::dashboard::user::events,
    types::{
        event::EventEnrollmentStatus,
        pagination::{self, NavigationLinks},
        questionnaire::RequiredQuestionnaireAnswersForm,
    },
};

#[cfg(test)]
mod tests;

/// URL used by the full dashboard page.
const DASHBOARD_URL: &str = "/dashboard/user?tab=events";

/// URL used by the events tab partial.
const PARTIAL_URL: &str = "/dashboard/user/events";

// Pages handlers.

/// Returns the upcoming events list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, user.user_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Cancels the current user's event attendance from the dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn cancel_attendance(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path((community_name, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Validate the row still represents cancelable attendance
    let enrollment = db.get_event_enrollment(community_id, event_id, user.user_id).await?;
    if enrollment.status != EventEnrollmentStatus::Attendee {
        return Err(
            anyhow::anyhow!("only attendee attendance can be canceled from My Events").into(),
        );
    }

    // Cancel attendance and enqueue required notifications
    let payment_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);
    let required_notification_server_cfg = server_cfg.clone();
    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Cancel attendance
                tx.leave_event(community_id, event_id, user.user_id, payment_provider)
                    .await?;

                // Enqueue required cancellation notifications before committing
                enqueue_event_attendance_cancellation_notifications(
                    tx,
                    &required_notification_server_cfg,
                    community_id,
                    event_id,
                    user.user_id,
                )
                .await?;

                Ok(())
            })
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Submits registration question answers from the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn submit_registration_answers(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((community_name, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<RequiredQuestionnaireAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Persist answers; checkout retains ownership of pending confirmation
    let registration_answers = input.registration_answers;
    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                tx.submit_event_registration_answers(
                    user.user_id,
                    community_id,
                    event_id,
                    &registration_answers,
                )
                .await?;

                Ok(())
            })
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    )
        .into_response())
}

// Helpers.

/// Prepares the events list page and filters for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(events::UserEventsFilters, events::ListPage), HandlerError> {
    // Fetch upcoming events
    let filters: events::UserEventsFilters = serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;
    let results = db.list_user_events(user_id, &filters).await?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = events::ListPage {
        events: results.events,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok((filters, template))
}
