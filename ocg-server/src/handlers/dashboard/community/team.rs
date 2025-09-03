//! HTTP handlers for managing community team members in the dashboard.

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
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::community::team,
};

// Pages handlers.

/// Displays the list of community team members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let members = db.list_community_team_members(community_id).await?;
    let template = team::ListPage { members };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a user to the community team.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Form(form): Form<NewTeamMember>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add team member to database
    db.add_community_team_member(community_id, form.user_id).await?;

    Ok((StatusCode::CREATED, [("HX-Trigger", "refresh-team-table")]).into_response())
}

/// Deletes a user from the community team.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Path(user_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Remove team member from database
    db.delete_community_team_member(community_id, user_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-team-table")]).into_response())
}

// Types.

/// Form payload for adding a community team member.
#[derive(Debug, Deserialize)]
pub(crate) struct NewTeamMember {
    user_id: Uuid,
}
