//! HTTP handlers for the global site stats page.

use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use chrono::Duration;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, prepare_headers},
    templates::{PageId, auth::User, site::stats},
};

#[cfg(test)]
mod tests;

// Page handlers.

/// Handler that renders the global site stats page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (site_settings, stats) = tokio::try_join!(db.get_site_settings(), db.get_site_stats())?;
    let template = stats::Page {
        page_id: PageId::SiteStats,
        path: uri.path().to_string(),
        site_settings,
        stats,
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(6), &[])?;

    Ok((headers, Html(template.render()?)))
}
