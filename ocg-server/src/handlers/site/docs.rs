//! HTTP handlers for the global site docs page.

use askama::Template;
use axum::{
    extract::State,
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::error::HandlerError,
    router::PUBLIC_SHARED_CACHE_HEADERS,
    templates::{PageId, auth::User, site::docs},
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the documentation page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let site_settings = db.get_site_settings().await?;
    let template = docs::Page {
        page_id: PageId::SiteDocs,
        path: uri.path().to_string(),
        site_settings,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)))
}
