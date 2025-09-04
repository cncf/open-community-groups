//! HTTP handlers for managing group team members in the dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_extra::extract::Form;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedGroupId},
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::dashboard::group::team,
    templates::notifications::GroupTeamInvitation,
};

// Pages handlers.

/// Displays the list of group team members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let members = db.list_group_team_members(group_id).await?;
    let template = team::ListPage { members };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a user to the group team.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedGroupId(group_id): SelectedGroupId,
    State(cfg): State<HttpServerConfig>,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    Form(member): Form<NewTeamMember>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add team member to database
    db.add_group_team_member(group_id, member.user_id).await?;

    // Enqueue invitation email notification
    let template_data = GroupTeamInvitation {
        link: format!(
            "{}/dashboard/user?tab=invitations",
            cfg.base_url.strip_suffix('/').unwrap_or(&cfg.base_url)
        ),
    };
    let notification = NewNotification {
        kind: NotificationKind::GroupTeamInvitation,
        user_id: member.user_id,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    notifications_manager.enqueue(&notification).await?;

    Ok((StatusCode::CREATED, [("HX-Trigger", "refresh-team-table")]).into_response())
}

/// Deletes a user from the group team.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Remove team member from database
    db.delete_group_team_member(group_id, user_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-team-table")]).into_response())
}

/// Updates a user role in the group team.
#[instrument(skip_all, err)]
pub(crate) async fn update_role(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
    Form(input): Form<NewTeamRole>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update team member role in database
    db.update_group_team_member_role(group_id, user_id, &input.role)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-team-table")]).into_response())
}

// Types.

/// Data needed to add a new team member.
#[derive(Debug, Deserialize)]
pub(crate) struct NewTeamMember {
    user_id: Uuid,
}

/// Data needed to update a team member role.
#[derive(Debug, Deserialize)]
pub(crate) struct NewTeamRole {
    role: String,
}
