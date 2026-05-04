//! HTTP handlers for the global site not found page.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Response},
};
use chrono::Duration;
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, prepare_headers},
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
    let headers = prepare_headers(Duration::minutes(15), &[])?;

    Ok((StatusCode::NOT_FOUND, headers, Html(template.render()?)).into_response())
}
