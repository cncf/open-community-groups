//! HTTP handlers for user upcoming events.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use serde_json::to_value;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
        notifications::enqueue_attendance_canceled_notification,
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::user::events,
        notifications::{EventWaitlistPromoted, EventWelcome},
    },
    types::{
        event::EventAttendanceStatus,
        pagination::{self, NavigationLinks},
        questionnaire::RequiredQuestionnaireAnswersForm,
    },
    util::{build_event_calendar_attachment, build_event_page_link, build_user_dashboard_events_link},
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
    Path((community_name, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Validate the row still represents active attendee attendance
    let attendance = db.get_event_attendance(community_id, event_id, user.user_id).await?;
    if attendance.status != EventAttendanceStatus::Attendee {
        return Err(anyhow::anyhow!("only attendee attendance can be canceled from My Events").into());
    }

    // Cancel the user's attendance and collect any waitlist promotions
    let leave_result = db.leave_event(community_id, event_id, user.user_id).await?;

    // Load notification context after cancellation succeeds
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id)
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
    if let Err(err) = enqueue_attendance_canceled_notification(
        &event,
        &notifications_manager,
        user.user_id,
        &server_cfg,
        &site_settings,
    )
    .await
    {
        warn!(error = %err, "failed to enqueue event attendance cancellation notification");
    }

    // Notify users promoted off the waitlist after a spot opens up
    if !leave_result.promoted_user_ids.is_empty() && !event.test_event {
        let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
        let template_data = EventWaitlistPromoted {
            event: event.clone(),
            has_registration_questions: event.has_registration_questions,
            link: build_event_page_link(base_url, &event),
            theme: site_settings.theme,
            dashboard_link: Some(build_user_dashboard_events_link(base_url)),
        };
        let notification = NewNotification {
            attachments: vec![build_event_calendar_attachment(base_url, &event)],
            kind: NotificationKind::EventWaitlistPromoted,
            recipients: leave_result.promoted_user_ids,
            template_data: Some(to_value(&template_data)?),
        };
        if let Err(err) = notifications_manager.enqueue(&notification).await {
            warn!(error = %err, "failed to enqueue waitlist promotion notification");
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
    Path((community_name, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<RequiredQuestionnaireAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Persist answers and detect first-time registration completion
    let became_confirmed = db
        .submit_event_registration_answers(user.user_id, community_id, event_id, &input.registration_answers)
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
        db.get_event_summary_by_id(community_id, event_id)
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
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let calendar_ics = build_event_calendar_attachment(base_url, &event);
    let link = build_event_page_link(base_url, &event);
    let template_data = EventWelcome {
        event,
        link,
        theme: site_settings.theme,

        dashboard_link: None,
    };
    let notification = NewNotification {
        attachments: vec![calendar_ics],
        kind: NotificationKind::EventWelcome,
        recipients: vec![user.user_id],
        template_data: Some(to_value(&template_data)?),
    };
    if let Err(err) = notifications_manager.enqueue(&notification).await {
        warn!(error = %err, "failed to enqueue event welcome notification after questionnaire answers");
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
