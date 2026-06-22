//! HTTP handlers for the public landscape page.

use askama::Template;
use axum::{
    extract::{RawQuery, State},
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    router::serde_qs_config,
    templates::{PageId, auth::User, site::landscape},
    types::{landscape::LandscapeFilters, pagination::NavigationLinks},
};

const LANDSCAPE_URL: &str = "/landscape";

/// Render the public landscape listing page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let filters = parse_filters(raw_query.as_deref().unwrap_or_default())?;
    let output = db.search_landscape_entries(&filters).await?;
    let site_settings = db.get_site_settings().await?;
    let navigation_links =
        NavigationLinks::from_filters(&filters, output.total, LANDSCAPE_URL, LANDSCAPE_URL)?;

    let template = landscape::Page {
        page_id: PageId::SiteLandscape,
        path: LANDSCAPE_URL.to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
        filters,
        entries: output.entries,
        total: output.total,
        navigation_links,
    };

    Ok((
        extend_public_shared_cache_headers(&[])?,
        Html(template.render()?),
    ))
}

fn parse_filters(raw_query: &str) -> Result<LandscapeFilters, HandlerError> {
    let filters: LandscapeFilters = if raw_query.is_empty() {
        LandscapeFilters::default()
    } else {
        serde_qs_config().deserialize_str(raw_query)?
    };
    filters.validate()?;
    Ok(filters)
}
