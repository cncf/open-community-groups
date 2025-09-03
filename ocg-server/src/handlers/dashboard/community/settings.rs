//! HTTP handlers for community settings management.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
    templates::dashboard::community::settings::{self, CommunityUpdate},
};

// Pages handlers.

/// Displays the page to update community settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let community = db.get_community(community_id).await?;
    let template = settings::UpdatePage { community };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates community settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    body: String,
) -> Result<impl IntoResponse, HandlerError> {
    // Get community update information from body
    let community_update: CommunityUpdate =
        match serde_qs_de.deserialize_str(&body).map_err(anyhow::Error::new) {
            Ok(update) => update,
            Err(e) => return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response()),
        };

    // Update community in database
    db.update_community(community_id, &community_update).await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}
