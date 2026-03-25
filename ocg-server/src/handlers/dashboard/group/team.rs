//! HTTP handlers for managing group team members in the dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::dashboard::group::team::{self, GroupTeamFilters},
    templates::notifications::GroupTeamInvitation,
    types::{
        group::GroupRole,
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/group?tab=team";
const PARTIAL_URL: &str = "/dashboard/group/team";

// Pages handlers.

/// Displays the list of group team members.
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

// Actions handlers.

/// Adds a user to the group team.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(member): ValidatedForm<NewTeamMember>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add team member to database using provided role
    db.add_group_team_member(user.user_id, group_id, member.user_id, &member.role)
        .await?;

    // Enqueue invitation email notification
    let (site_settings, group) = tokio::try_join!(
        db.get_site_settings(),
        db.get_group_summary(community_id, group_id)
    )?;
    let template_data = GroupTeamInvitation {
        group,
        link: format!(
            "{}/dashboard/user?tab=invitations",
            server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url)
        ),
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::GroupTeamInvitation,
        recipients: vec![member.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Deletes a user from the group team.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Remove team member from database
    db.delete_group_team_member(user.user_id, group_id, user_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates a user role in the group team.
#[instrument(skip_all, err)]
pub(crate) async fn update_role(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<NewTeamRole>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update team member role in database
    db.update_group_team_member_role(user.user_id, group_id, user_id, &input.role)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

// Types.

/// Data needed to add a new team member.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct NewTeamMember {
    /// Team role.
    #[garde(skip)]
    role: GroupRole,
    /// User identifier.
    #[garde(skip)]
    user_id: Uuid,
}

/// Data needed to update a team member role.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct NewTeamRole {
    #[garde(skip)]
    role: GroupRole,
}

// Helpers.

/// Prepares the team list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(GroupTeamFilters, team::ListPage), HandlerError> {
    // Fetch group team members
    let filters: GroupTeamFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (results, roles, can_manage_team) = tokio::try_join!(
        db.list_group_team_members(group_id, &filters),
        db.list_group_roles(),
        db.user_has_group_permission(&community_id, &group_id, &user_id, GroupPermission::TeamWrite)
    )?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = team::ListPage {
        can_manage_team,
        members: results.members,
        navigation_links,
        roles,
        total: results.total,
        total_accepted: results.total_accepted,
        total_admins_accepted: results.total_admins_accepted,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok((filters, template))
}
