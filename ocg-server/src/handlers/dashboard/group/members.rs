//! HTTP handlers for the members section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedGroupId},
    templates::dashboard::group::members,
};

// Pages handlers.

/// Displays the list of group members.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let members = db.list_group_members(group_id).await?;
    let template = members::ListPage { members };

    Ok(Html(template.render()?))
}
