//! HTTP handlers for the public about page.

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
    templates::{PageId, auth::User, site::about},
};

/// Handler that renders the public about page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let template = about::Page {
        page_id: PageId::SiteAbout,
        path: uri.path().to_string(),
        site_settings: db.get_site_settings().await?,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)))
}
