//! HTTP handlers for event CFS submissions in the group dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    router::serde_qs_config,
    services::notifications::{
        DynNotificationsManager, best_effort::enqueue_cfs_submission_updated_best_effort,
    },
    templates::dashboard::group::submissions,
    types::{
        dashboard::group::submissions::{
            CfsSubmissionUpdate, CfsSubmissionsFilters, CfsSubmissionsSort,
        },
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the CFS submissions list for an event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event submissions (checking event belongs to group)
    let filters: CfsSubmissionsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    filters.validate()?;
    let (can_manage_events, _event, labels, submissions) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id), // ensure event belongs to group
        db.list_event_cfs_labels(event_id),
        db.list_event_cfs_submissions(event_id, &filters)
    )?;

    // Prepare template
    let base_path = format!("/dashboard/group/events/{event_id}/submissions");
    let navigation_links =
        NavigationLinks::from_filters(&filters, submissions.total, &base_path, &base_path)?;
    let refresh_url = pagination::build_url(&base_path, &filters)?;
    let template = submissions::ListPage {
        can_manage_events,
        event_cfs_labels: labels,
        event_id,
        submissions: submissions.submissions,
        navigation_links,
        refresh_url,
        selected_event_cfs_label_ids: filters.label_ids.clone(),
        sort: filters.sort.unwrap_or(CfsSubmissionsSort::CreatedDesc).to_string(),
        total: submissions.total,
    };

    Ok(Html(template.render()?))
}

// Action handlers.

/// Updates a CFS submission for an event.
#[allow(clippy::too_many_arguments)]
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(reviewer): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((event_id, cfs_submission_id)): Path<(Uuid, Uuid)>,
    ValidatedFormQs(update): ValidatedFormQs<CfsSubmissionUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Ensure event belongs to the group
    let event = db.get_event_summary(community_id, group_id, event_id).await?;

    // Update submission in database
    let should_notify = db
        .update_cfs_submission(reviewer.user_id, event_id, cfs_submission_id, &update)
        .await?;

    // Enqueue notification to submission author best-effort
    if should_notify {
        enqueue_cfs_submission_updated_best_effort(
            db.as_ref(),
            &notifications_manager,
            &server_cfg,
            reviewer.user_id,
            cfs_submission_id,
            event,
        )
        .await;
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-submissions")],
    ))
}
