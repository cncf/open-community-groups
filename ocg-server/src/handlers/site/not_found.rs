//! HTTP handlers for the global site not found page.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Response},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    templates::{PageId, auth::User, site::not_found::Page},
    types::site::SiteSettings,
};

/// Stable template path for not found pages.
const NOT_FOUND_PATH: &str = "/404";

// Pages handlers.

/// Handler that renders the global site not found page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>) -> Result<Response, HandlerError> {
    // Load site settings
    let site_settings = db.get_site_settings().await?;

    // Render not found page
    render(site_settings)
}

// Helpers.

/// Renders the global site not found page.
#[instrument(skip_all, err)]
pub(crate) fn render(site_settings: SiteSettings) -> Result<Response, HandlerError> {
    // Prepare template
    let template = Page {
        page_id: PageId::SiteNotFound,
        path: NOT_FOUND_PATH.to_string(),
        site_settings,
        user: User::default(),
    };

    // Prepare response headers
    let headers = extend_public_shared_cache_headers(&[
        ("X-OCG-Not-Found", "true"),
        ("HX-Retarget", "body"),
        ("HX-Reswap", "innerHTML"),
    ])?;

    Ok((StatusCode::NOT_FOUND, headers, Html(template.render()?)).into_response())
}
