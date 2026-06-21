//! HTTP handlers for managing alliance team members in the dashboard.

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
        extractors::{CurrentUser, SelectedAllianceId, ValidatedForm},
    },
    router::serde_qs_config,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::dashboard::alliance::team::{self, AllianceTeamFilters},
    templates::notifications::AllianceTeamInvitation,
    types::{
        alliance::AllianceRole,
        pagination::{self, NavigationLinks},
        permissions::AlliancePermission,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/alliance?tab=team";
const PARTIAL_URL: &str = "/dashboard/alliance/team";

// Pages handlers.

/// Displays the list of alliance team members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        alliance_id,
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

/// Adds a user to the alliance team.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    ValidatedForm(member): ValidatedForm<NewTeamMember>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add team member to database
    db.add_alliance_team_member(user.user_id, alliance_id, member.user_id, &member.role)
        .await?;

    // Enqueue invitation email notification
    let (alliance, site_settings) = tokio::try_join!(
        db.get_alliance_summary(alliance_id),
        db.get_site_settings()
    )?;
    let template_data = AllianceTeamInvitation {
        alliance_name: alliance.display_name,
        link: format!(
            "{}/dashboard/user?tab=invitations",
            server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url)
        ),
        theme: site_settings.theme,
    };
    let notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::AllianceTeamInvitation,
        recipients: vec![member.user_id],
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Deletes a user from the alliance team.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    mut auth_session: AuthSession,
    headers: HeaderMap,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let Some(user) = auth_session.user.clone() else {
        return Err(HandlerError::Auth("user not logged in".to_string()));
    };

    // Remove team member from database
    db.delete_alliance_team_member(user.user_id, alliance_id, user_id)
        .await?;

    // Log out when the user removed their own alliance access
    if user_id == user.user_id {
        return log_out_for_stale_dashboard_context(&mut auth_session, &headers).await;
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    )
        .into_response())
}

/// Updates a user role in the alliance team.
#[instrument(skip_all, err)]
pub(crate) async fn update_role(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<NewTeamRole>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update team member role in database
    db.update_alliance_team_member_role(user.user_id, alliance_id, user_id, &input.role)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

// Types.

/// Data needed to add a new team member.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct NewTeamMember {
    #[garde(skip)]
    role: AllianceRole,
    #[garde(skip)]
    user_id: Uuid,
}

/// Data needed to update a team member role.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct NewTeamRole {
    #[garde(skip)]
    role: AllianceRole,
}

// Helpers.

/// Prepares the team list page and filters for the alliance dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(AllianceTeamFilters, team::ListPage), HandlerError> {
    // Fetch team members
    let filters: AllianceTeamFilters = serde_qs_config().deserialize_str(raw_query)?;
    let (results, roles, can_manage_team) = tokio::try_join!(
        db.list_alliance_team_members(alliance_id, &filters),
        db.list_alliance_roles(),
        db.user_has_alliance_permission(&alliance_id, &user_id, AlliancePermission::TeamWrite)
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
