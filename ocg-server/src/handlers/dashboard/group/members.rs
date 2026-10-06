//! HTTP handlers for the members section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{
            CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm, ValidatedQuery,
        },
    },
    services::notifications::enqueue::{
        GroupCustomNotificationOutcome, enqueue_tracked_group_custom_notification,
    },
    templates::dashboard::group::members,
    types::{
        dashboard::group::members::GroupMembersFilters,
        notifications::{CustomNotificationContent, GroupCustomNotificationInput},
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/group?tab=members";
const PARTIAL_URL: &str = "/dashboard/group/members";

// Pages handlers.

/// Displays the list of group members.
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

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Sends a custom notification to all group members.
#[instrument(skip_all)]
pub(crate) async fn send_group_custom_notification(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(content): ValidatedForm<CustomNotificationContent>,
) -> Result<impl IntoResponse, HandlerError> {
    // Enqueue the custom notification for the group audience with its audit entry
    let outcome = enqueue_tracked_group_custom_notification(
        db.as_ref(),
        &server_cfg,
        &GroupCustomNotificationInput {
            actor_user_id: user.user_id,
            community_id,
            content,
            group_id,
        },
    )
    .await?;

    // Reject empty audiences so stale pages cannot report a false success
    match outcome {
        GroupCustomNotificationOutcome::NoRecipients => Err(HandlerError::Rejected(
            "no group members can receive this email".to_string(),
        )),
        GroupCustomNotificationOutcome::Sent(_) => Ok(StatusCode::NO_CONTENT),
    }
}

// Helpers.

/// Prepares the members list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(GroupMembersFilters, members::ListPage), HandlerError> {
    // Fetch group members
    let filters: GroupMembersFilters = ValidatedQuery::parse(raw_query)?;
    let (can_manage_members, group, results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user_id,
            GroupPermission::MembersWrite
        ),
        db.get_group_summary(community_id, group_id),
        db.list_group_members(group_id, &filters)
    )?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = members::ListPage {
        can_manage_members,
        default_notification_subject: group.name,
        members: results.members,
        navigation_links,
        total: results.total,
        offset: filters.offset,
    };

    Ok((filters, template))
}
