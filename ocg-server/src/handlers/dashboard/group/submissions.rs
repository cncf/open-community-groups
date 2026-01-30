//! HTTP handlers for event CFS submissions in the group dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        dashboard::group::submissions::{self, CfsSubmissionUpdate, CfsSubmissionsFilters},
        notifications::CfsSubmissionUpdated,
        pagination::{self, NavigationLinks},
    },
    util::build_event_page_link,
};

// Pages handlers.

/// Displays the CFS submissions list for an event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event submissions (checking event belongs to group)
    let filters: CfsSubmissionsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (_event, statuses, submissions) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id), // ensure event belongs to group
        db.list_cfs_submission_statuses_for_review(),
        db.list_event_cfs_submissions(event_id, &filters)
    )?;

    // Prepare template
    let base_path = format!("/dashboard/group/events/{event_id}/submissions");
    let navigation_links =
        NavigationLinks::from_filters(&filters, submissions.total, &base_path, &base_path)?;
    let refresh_url = pagination::build_url(&base_path, &filters)?;
    let template = submissions::ListPage {
        event_id,
        statuses,
        submissions: submissions.submissions,
        navigation_links,
        refresh_url,
        total: submissions.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok(Html(template.render()?))
}

// Action handlers.

/// Updates a CFS submission for an event.
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn update(
    auth_session: AuthSession,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((event_id, cfs_submission_id)): Path<(Uuid, Uuid)>,
    ValidatedForm(update): ValidatedForm<CfsSubmissionUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let reviewer = auth_session.user.expect("user to be logged in");

    // Ensure event belongs to the group
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Update submission in database
    db.update_cfs_submission(reviewer.user_id, event_id, cfs_submission_id, &update)
        .await?;

    // Enqueue notification to submission author
    let (notification_data, site_settings) = tokio::try_join!(
        db.get_cfs_submission_notification_data(event_id, cfs_submission_id),
        db.get_site_settings(),
    )?;
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = build_event_page_link(base_url, &event);
    let template_data = CfsSubmissionUpdated {
        action_required_message: notification_data.action_required_message,
        event,
        link,
        status_name: notification_data.status_name,
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::CfsSubmissionUpdated,
        recipients: vec![notification_data.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-submissions")],
    ))
}
