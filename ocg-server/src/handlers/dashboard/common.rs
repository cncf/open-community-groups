//! Common HTTP handlers shared across different dashboards.

use anyhow::Result;
use axum::{Json, extract::State, response::IntoResponse};
use garde::Validate;
use serde::Deserialize;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::ValidatedQuery},
    types::user::UserSearchResult,
};

#[cfg(test)]
mod tests;

/// Minimum user search query length, in Unicode code points after trimming;
/// mirrored in `static/js/common/users/user-search-field.js`.
const USER_SEARCH_MIN_QUERY_CHARS: usize = 2;

/// Searches for users by query.
#[instrument(skip_all)]
pub(crate) async fn search_user(
    State(db): State<DynDB>,
    ValidatedQuery(query): ValidatedQuery<SearchUserQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Skip searches too short to be selective
    if query.q.trim().chars().count() < USER_SEARCH_MIN_QUERY_CHARS {
        return Ok(Json(Vec::<UserSearchResult>::new()).into_response());
    }

    // Search users in the database
    let users = db.search_user(&query.q).await?;

    Ok(Json(users).into_response())
}

// Types.

/// Query parameters accepted by the user search endpoint.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct SearchUserQuery {
    /// Search text entered by the user.
    #[garde(skip)]
    q: String,
}
