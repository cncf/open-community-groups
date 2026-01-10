//! HTTP handlers for the global site home page.

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
    templates::{PageId, auth::User, site::home},
};

/// Handler that renders the global site home page.
#[instrument(skip_all, err)]
pub(crate) async fn page(State(db): State<DynDB>, uri: Uri) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (site_settings, stats, communities) = tokio::try_join!(
        db.get_site_settings(),
        db.get_site_home_stats(),
        db.list_communities()
    )?;
    let template = home::Page {
        communities,
        page_id: PageId::SiteHome,
        path: uri.path().to_string(),
        site_settings,
        stats,
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::minutes(10), &[])?;

    Ok((headers, Html(template.render()?)))
}
