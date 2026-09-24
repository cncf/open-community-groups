//! HTTP handlers for the co-hosts section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedQuery},
    },
    services::events::{DynEventsManager, EventCohostActionInput},
    templates::dashboard::group::cohosts,
    types::{
        dashboard::group::cohosts::CohostedEventsFilters,
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial.
const DASHBOARD_URL: &str = "/dashboard/group?tab=cohosts";
const PARTIAL_URL: &str = "/dashboard/group/cohosts";

/// HTMX event that refreshes the co-hosted events list.
const REFRESH_TRIGGER: &str = "refresh-group-cohosts";

// Pages handlers.

/// Displays the events the selected group was invited to co-host.
#[instrument(skip_all)]
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

    // Keep browser navigation on the full dashboard URL
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// JSON handlers.

/// Lists the groups of a community that can be invited to co-host events.
#[instrument(skip_all)]
pub(crate) async fn group_options(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedQuery(query): ValidatedQuery<CohostGroupOptionsQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the community groups, excluding the selected group
    let groups = db.list_cohost_group_options(query.community_id, group_id).await?;

    Ok(Json(groups))
}

// Actions handlers.

/// Approves a pending co-hosting invitation for the selected group.
#[instrument(skip_all)]
pub(crate) async fn approve(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(invitation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Record the approval and notify the owner group
    events_manager
        .approve_cohosting(&action_input(user.user_id, group_id, invitation_id))
        .await?;

    Ok(refresh_response())
}

/// Withdraws an approved co-hosting for the selected group.
#[instrument(skip_all)]
pub(crate) async fn cancel(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(invitation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Record the withdrawal and notify the owner group
    events_manager
        .cancel_cohosting(&action_input(user.user_id, group_id, invitation_id))
        .await?;

    Ok(refresh_response())
}

/// Rejects a pending co-hosting invitation for the selected group.
#[instrument(skip_all)]
pub(crate) async fn reject(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(events_manager): State<DynEventsManager>,
    Path(invitation_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Record the rejection and notify the owner group
    events_manager
        .reject_cohosting(&action_input(user.user_id, group_id, invitation_id))
        .await?;

    Ok(refresh_response())
}

// Helpers.

/// Prepares the co-hosted events list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(CohostedEventsFilters, cohosts::ListPage), HandlerError> {
    // Parse and validate list filters
    let filters: CohostedEventsFilters = ValidatedQuery::parse(raw_query)?;

    // Load co-hosted events and action permissions
    let (can_manage_cohosts, results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user_id,
            GroupPermission::SettingsWrite
        ),
        db.list_group_cohosted_events(group_id, &filters)
    )?;

    // Build pagination links and the template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let refresh_url = pagination::build_url(PARTIAL_URL, &filters)?;
    let template = cohosts::ListPage {
        can_manage_cohosts,
        events: results.events,
        navigation_links,
        refresh_url,
        total: results.total,

        offset: filters.offset,
    };

    Ok((filters, template))
}

/// Builds the manager input for a co-hosting action.
fn action_input(
    actor_user_id: Uuid,
    group_id: Uuid,
    invitation_id: Uuid,
) -> EventCohostActionInput {
    EventCohostActionInput {
        actor_user_id,
        cohost_group_id: group_id,
        invitation_id,
    }
}

/// Returns the empty response that refreshes the co-hosted events list.
fn refresh_response() -> impl IntoResponse {
    (StatusCode::NO_CONTENT, [("HX-Trigger", REFRESH_TRIGGER)])
}

// Types.

/// Query parameters for the co-host group options lookup.
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub(crate) struct CohostGroupOptionsQuery {
    /// Community whose groups are listed.
    #[garde(skip)]
    pub community_id: Uuid,
}
