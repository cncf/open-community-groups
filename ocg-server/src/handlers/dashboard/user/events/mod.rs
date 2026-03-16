//! HTTP handlers for user upcoming events.

use askama::Template;
use axum::{
    extract::{RawQuery, State},
    http::HeaderName,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    router::serde_qs_config,
    templates::dashboard::user::events,
    types::pagination::{self, NavigationLinks},
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/user?tab=events";
const PARTIAL_URL: &str = "/dashboard/user/events";

// Pages handlers.

/// Returns the upcoming events list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, user.user_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Prepare response headers.
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Helpers.

/// Prepares the events list page and filters for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(events::UserEventsFilters, events::ListPage), HandlerError> {
    // Fetch upcoming events
    let filters: events::UserEventsFilters = serde_qs_config().deserialize_str(raw_query)?;
    let results = db.list_user_events(user_id, &filters).await?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = events::ListPage {
        events: results.events,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok((filters, template))
}
