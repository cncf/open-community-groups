//! HTTP handlers for the event page.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use garde::Validate;
use serde::Deserialize;
use serde_json::{json, to_value};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        extractors::{CurrentUser, ValidatedFormQs},
        prepare_headers, request_matches_site,
    },
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        PageId,
        auth::User,
        event::{CfsModal, CheckInPage, Page},
        notifications::EventWelcome,
    },
    util::{build_event_calendar_attachment, build_event_page_link},
    validation::MAX_LEN_EVENT_LABELS_PER_SUBMISSION,
};

use super::{error::HandlerError, extractors::CommunityId};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the event page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, group_slug, event_slug)): Path<(String, String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (event, site_settings) = tokio::try_join!(
        db.get_event_full_by_slug(community_id, &group_slug, &event_slug),
        db.get_site_settings()
    )?;
    let template = Page {
        event,
        page_id: PageId::Event,
        path: uri.path().to_string(),
        site_settings,
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the check-in page.
#[instrument(skip_all, err)]
pub(crate) async fn check_in_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get site settings and event details
    let (event, site_settings, (user_is_attendee, user_is_checked_in), check_in_window_open) = tokio::try_join!(
        db.get_event_summary_by_id(community_id, event_id),
        db.get_site_settings(),
        db.is_event_attendee(community_id, event_id, user.user_id),
        db.is_event_check_in_window_open(community_id, event_id),
    )?;

    let template = CheckInPage {
        check_in_window_open,
        event,
        page_id: PageId::CheckIn,
        path: uri.path().to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
        user_is_attendee,
        user_is_checked_in,
    };

    Ok(Html(template.render()?))
}

/// Handler that renders the CFS submission modal.
#[instrument(skip_all, err)]
pub(crate) async fn cfs_modal(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user_id = auth_session.user.as_ref().map(|user| user.user_id);
    let user = User::from_session(auth_session).await?;

    // Get event details, labels and user's session proposals
    let (event, labels, session_proposals) = tokio::try_join!(
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_cfs_labels(event_id),
        async {
            if let Some(user_id) = user_id {
                db.list_user_session_proposals_for_cfs_event(user_id, event_id).await
            } else {
                Ok(vec![])
            }
        }
    )?;

    // Prepare template
    let template = CfsModal {
        event,
        labels,
        session_proposals,
        user,
        notice: None,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Handler for attending an event.
#[instrument(skip_all)]
pub(crate) async fn attend_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Attend event
    db.attend_event(community_id, event_id, user.user_id).await?;

    // Enqueue welcome to event notification
    let (site_settings, event) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id),
    )?;
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = build_event_page_link(base_url, &event);
    let calendar_ics = build_event_calendar_attachment(base_url, &event);
    let template_data = EventWelcome {
        link,
        event,
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![calendar_ics],
        kind: NotificationKind::EventWelcome,
        recipients: vec![user.user_id],
        template_data: Some(to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking event attendance status.
#[instrument(skip_all)]
pub(crate) async fn attendance_status(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check attendance and check-in status
    let (is_attendee, is_checked_in) = db.is_event_attendee(community_id, event_id, user.user_id).await?;

    Ok(Json(json!({
        "is_attendee": is_attendee,
        "is_checked_in": is_checked_in
    })))
}

/// Handler that marks the authenticated attendee as checked in.
#[instrument(skip_all)]
pub(crate) async fn check_in(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check in event (bypass_window = false for user self check-in)
    db.check_in_event(community_id, event_id, user.user_id, false).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for leaving an event.
#[instrument(skip_all)]
pub(crate) async fn leave_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave event
    db.leave_event(community_id, event_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for submitting a CFS proposal to an event.
#[instrument(skip_all, err)]
pub(crate) async fn submit_cfs_submission(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
    ValidatedFormQs(input): ValidatedFormQs<CfsSubmissionInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user_id = auth_session
        .user
        .as_ref()
        .map(|user| user.user_id)
        .expect("user to be logged in");
    let user = User::from_session(auth_session).await?;

    // Add CFS submission to database
    db.add_cfs_submission(
        community_id,
        event_id,
        user_id,
        input.session_proposal_id,
        &input.label_ids,
    )
    .await?;

    // Prepare template
    let (event, labels, session_proposals) = tokio::try_join!(
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_cfs_labels(event_id),
        db.list_user_session_proposals_for_cfs_event(user_id, event_id),
    )?;
    let template = CfsModal {
        event,
        labels,
        session_proposals,
        user,
        notice: Some("Submission received. We'll review it soon.".to_string()),
    };

    Ok(Html(template.render()?))
}

/// Tracks an event page view.
#[instrument(skip_all)]
pub(crate) async fn track_view(
    headers: HeaderMap,
    State(activity_tracker): State<DynActivityTracker>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker.track(Activity::EventView { event_id }).await?;
    }

    Ok(StatusCode::NO_CONTENT)
}

// Types.

#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CfsSubmissionInput {
    #[serde(default)]
    #[garde(length(max = MAX_LEN_EVENT_LABELS_PER_SUBMISSION))]
    label_ids: Vec<Uuid>,
    #[garde(skip)]
    session_proposal_id: Uuid,
}
