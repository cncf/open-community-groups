//! HTTP handlers for listing alliance members in the dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{RawQuery, State},
    http::HeaderName,
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedAllianceId},
    router::serde_qs_config,
    templates::{alliance::AllianceMembersFilters, dashboard::alliance::members},
    types::pagination::{self, NavigationLinks},
};

const DASHBOARD_URL: &str = "/dashboard/alliance?tab=members";
const PARTIAL_URL: &str = "/dashboard/alliance/members";

/// Displays members across all groups in the selected alliance.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let (filters, template) =
        prepare_list_page(&db, alliance_id, raw_query.as_deref().unwrap_or_default()).await?;

    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Prepares the alliance members list page and filters.
#[instrument(skip(db), err)]
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    raw_query: &str,
) -> Result<(AllianceMembersFilters, members::ListPage)> {
    let filters: AllianceMembersFilters = serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;

    let output = db.list_alliance_members(alliance_id, &filters).await?;
    let navigation_links =
        NavigationLinks::from_filters(&filters, output.total, DASHBOARD_URL, PARTIAL_URL)?;

    let template = members::ListPage {
        members: output.members,
        navigation_links,
        total: output.total,
        limit: filters.limit,
        offset: filters.offset,
        query: filters.query.clone(),
    };

    Ok((filters, template))
}
