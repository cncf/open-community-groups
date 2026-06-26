//! HTTP handlers for the public privacy policy page.

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
    templates::{PageId, auth::User, site::privacy},
};

/// Handler that renders the public privacy policy page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let template = privacy::Page {
        page_id: PageId::SitePrivacy,
        path: uri.path().to_string(),
        site_settings: db.get_site_settings().await?,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)))
}
