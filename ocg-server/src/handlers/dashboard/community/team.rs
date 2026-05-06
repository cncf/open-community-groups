//! HTTP handlers for managing community team members in the dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderMap, HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        auth::log_out_for_stale_dashboard_context,
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::dashboard::community::team::{self, CommunityTeamFilters},
    templates::notifications::CommunityTeamInvitation,
    types::{
        community::CommunityRole,
        pagination::{self, NavigationLinks},
        permissions::CommunityPermission,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/community?tab=team";
const PARTIAL_URL: &str = "/dashboard/community/team";

// Pages handlers.

/// Displays the list of community team members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        community_id,
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

/// Adds a user to the community team.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(member): ValidatedForm<NewTeamMember>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add team member to database
    db.add_community_team_member(user.user_id, community_id, member.user_id, &member.role)
        .await?;

    // Enqueue invitation email notification
    let (community, site_settings) =
        tokio::try_join!(db.get_community_summary(community_id), db.get_site_settings())?;
    let template_data = CommunityTeamInvitation {
        community_name: community.display_name,
        link: format!(
            "{}/dashboard/user?tab=invitations",
            server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url)
        ),
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::CommunityTeamInvitation,
        recipients: vec![member.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Deletes a user from the community team.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    mut auth_session: AuthSession,
    headers: HeaderMap,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let Some(user) = auth_session.user.clone() else {
        return Err(HandlerError::Auth("user not logged in".to_string()));
    };

    // Remove team member from database
    db.delete_community_team_member(user.user_id, community_id, user_id)
        .await?;

    // Log out when the user removed their own community access
    if user_id == user.user_id {
        return log_out_for_stale_dashboard_context(&mut auth_session, &headers).await;
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    )
        .into_response())
}

/// Updates a user role in the community team.
#[instrument(skip_all, err)]
pub(crate) async fn update_role(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<NewTeamRole>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update team member role in database
    db.update_community_team_member_role(user.user_id, community_id, user_id, &input.role)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

// Types.

/// Data needed to add a new team member.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct NewTeamMember {
    #[garde(skip)]
    role: CommunityRole,
    #[garde(skip)]
    user_id: Uuid,
}

/// Data needed to update a team member role.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct NewTeamRole {
    #[garde(skip)]
    role: CommunityRole,
}

// Helpers.

/// Prepares the team list page and filters for the community dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(CommunityTeamFilters, team::ListPage), HandlerError> {
    // Fetch team members
    let filters: CommunityTeamFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (results, roles, can_manage_team) = tokio::try_join!(
        db.list_community_team_members(community_id, &filters),
        db.list_community_roles(),
        db.user_has_community_permission(&community_id, &user_id, CommunityPermission::TeamWrite)
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
