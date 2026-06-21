//! HTTP handlers for user upcoming events.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{
        DynNotificationsManager,
        helpers::{
            build_event_attendance_canceled_notification,
            build_event_waitlist_promoted_notification, build_event_welcome_notification,
            should_send_waitlist_promoted_notification,
        },
    },
    templates::dashboard::user::events,
    types::{
        event::EventAttendanceStatus,
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
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the alliance from the dashboard route
    let alliance_id = db
        .get_alliance_id_by_name(&alliance_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Validate the row still represents cancelable attendance
    let attendance = db.get_event_attendance(alliance_id, event_id, user.user_id).await?;
    match attendance.status {
        EventAttendanceStatus::Attendee => {}
        EventAttendanceStatus::RegistrationQuestionsPending => {
            // Pending registrations on ticketed events are owned by the checkout hold flow
            let event = db.get_event_summary_by_id(alliance_id, event_id).await?;
            if event.is_ticketed() {
                return Err(anyhow::anyhow!(
                    "pending registrations on ticketed events cannot be canceled from My Events"
                )
                .into());
            }
        }
        _ => {
            return Err(anyhow::anyhow!(
                "only attendee or pending registration attendance can be canceled from My Events"
            )
            .into());
        }
    }

    // Cancel the user's attendance and collect any waitlist promotions
    let leave_result = db.leave_event(alliance_id, event_id, user.user_id).await?;

    // Load notification context after cancellation succeeds
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(alliance_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load user dashboard attendance cancellation notification context");
            return Ok((
                StatusCode::NO_CONTENT,
                [("HX-Trigger", "refresh-user-dashboard-content")],
            ));
        }
    };

    // Confirm the canceled attendance to the user
    match build_event_attendance_canceled_notification(
        &event,
        user.user_id,
        &server_cfg,
        &site_settings,
    ) {
        Ok(notification) => {
            if let Err(err) = notifications_manager.enqueue(&notification).await {
                warn!(error = %err, "failed to enqueue event attendance cancellation notification");
            }
        }
        Err(err) => {
            warn!(error = %err, "failed to build event attendance cancellation notification");
        }
    }

    // Notify users promoted off the waitlist after a spot opens up
    if should_send_waitlist_promoted_notification(&event, &leave_result.promoted_user_ids) {
        match build_event_waitlist_promoted_notification(
            &event,
            leave_result.promoted_user_ids,
            &server_cfg,
            &site_settings,
        ) {
            Ok(notification) => {
                if let Err(err) = notifications_manager.enqueue(&notification).await {
                    warn!(error = %err, "failed to enqueue waitlist promotion notification");
                }
            }
            Err(err) => {
                warn!(error = %err, "failed to build waitlist promotion notification");
            }
        }
    }

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
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<RequiredQuestionnaireAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the alliance from the dashboard route
    let alliance_id = db
        .get_alliance_id_by_name(&alliance_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Persist answers and detect first-time registration completion
    let became_confirmed = db
        .submit_event_registration_answers(
            user.user_id,
            alliance_id,
            event_id,
            &input.registration_answers,
        )
        .await?;

    // Notify only when registration transitioned from pending to confirmed
    if !became_confirmed {
        return Ok((
            StatusCode::NO_CONTENT,
            [("HX-Trigger", "refresh-user-dashboard-content")],
        )
            .into_response());
    }

    // Send the regular welcome notification after a pending registration becomes complete
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(alliance_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event welcome notification context");
            return Ok((
                StatusCode::NO_CONTENT,
                [("HX-Trigger", "refresh-user-dashboard-content")],
            )
                .into_response());
        }
    };
    match build_event_welcome_notification(&event, user.user_id, &server_cfg, &site_settings, false)
    {
        Ok(notification) => {
            if let Err(err) = notifications_manager.enqueue(&notification).await {
                warn!(error = %err, "failed to enqueue event welcome notification after questionnaire answers");
            }
        }
        Err(err) => {
            warn!(error = %err, "failed to build event welcome notification after questionnaire answers");
        }
    }

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
