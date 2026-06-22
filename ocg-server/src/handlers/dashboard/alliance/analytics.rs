//! HTTP handlers for the alliance analytics page.

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedAllianceId},
    templates::dashboard::alliance::analytics,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the alliance analytics dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let stats = db.get_alliance_stats(alliance_id).await?;
    let page = analytics::Page { stats };

    Ok(Html(page.render()?))
}
