//! Common HTTP handlers shared across different dashboards.

use std::collections::HashMap;

use anyhow::Result;
use axum::{
    Json,
    extract::{Query, State},
    response::IntoResponse,
};
use reqwest::StatusCode;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CommunityId},
};

/// Searches for users by query.
#[instrument(skip_all, err)]
pub(crate) async fn search_user(
    CommunityId(community_id): CommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get search query from query parameters
    let Some(q) = query.get("q") else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };

    // Search users in the database
    let users = db.search_user(community_id, q).await?;

    Ok(Json(users).into_response())
}
