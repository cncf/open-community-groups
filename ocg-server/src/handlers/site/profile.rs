//! HTTP handlers for shareable user profile cards.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::Uri,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{error::HandlerError, site::not_found},
    router::PUBLIC_SHARED_CACHE_HEADERS,
    templates::{PageId, auth::User, site::profile::Page},
};

/// Renders a public profile card by username.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(username): Path<String>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (site_settings, profile) = tokio::try_join!(
        db.get_site_settings(),
        db.get_public_user_profile_by_username(&username)
    )?;
    let Some(profile) = profile else {
        return not_found::render(site_settings);
    };

    let template = Page {
        base_url: server_cfg.base_url,
        path: uri.path().to_string(),
        page_id: PageId::SiteHome,
        profile,
        site_settings,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}
