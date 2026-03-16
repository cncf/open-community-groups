//! HTTP handlers for user upcoming events.

use askama::Template;
use axum::{
    extract::{RawQuery, State},
    http::HeaderName,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    router::serde_qs_config,
    templates::dashboard::user::events,
    types::pagination::{self, NavigationLinks},
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Returns the upcoming events list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch upcoming events.
    let filters: events::UserEventsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let results = db.list_user_events(user.user_id, &filters).await?;

    // Prepare template.
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        results.total,
        "/dashboard/user?tab=events",
        "/dashboard/user/events",
    )?;
    let template = events::ListPage {
        events: results.events,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    // Prepare response headers.
    let url = pagination::build_url("/dashboard/user?tab=events", &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}
