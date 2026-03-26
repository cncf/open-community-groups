//! HTTP handlers for community dashboard audit logs.

use anyhow::Result;
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
    handlers::{error::HandlerError, extractors::SelectedCommunityId},
    router::serde_qs_config,
    templates::dashboard::audit::{AuditLogFilters, AuditScope, ListPage},
    types::pagination::{self, NavigationLinks},
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/community?tab=logs";
const PARTIAL_URL: &str = "/dashboard/community/logs";

// Pages handlers.

/// Displays the community audit logs list.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, community_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Helpers.

/// Prepares the audit logs list page for the community dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    raw_query: &str,
) -> Result<(AuditLogFilters, ListPage), HandlerError> {
    // Fetch audit log rows
    let filters: AuditLogFilters = serde_qs_config().deserialize_str(raw_query)?;
    let results = db.list_community_audit_logs(community_id, &filters).await?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = ListPage::new(AuditScope::Community, &filters, results, navigation_links);

    Ok((filters, template))
}
