//! HTTP handlers for managing alliance landscape entries.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, ValidatedFormQs},
    },
    router::serde_qs_config,
    templates::dashboard::alliance::landscape,
    types::{
        landscape::{DashboardLandscapeFilters, LandscapeEntryInput},
        pagination::{self, NavigationLinks},
        permissions::AlliancePermission,
    },
};

const DASHBOARD_URL: &str = "/dashboard/alliance?tab=landscape";
const PARTIAL_URL: &str = "/dashboard/alliance/landscape";

/// Displays the list of landscape entries for the alliance dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let (filters, template) = prepare_list_page(
        &db,
        alliance_id,
        user.user_id,
        raw_query.as_deref().unwrap_or_default(),
    )
    .await?;

    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Adds a new landscape entry.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    ValidatedFormQs(input): ValidatedFormQs<LandscapeEntryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.add_landscape_entry(user.user_id, alliance_id, &input).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Updates an existing landscape entry.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(entry_id): Path<Uuid>,
    ValidatedFormQs(input): ValidatedFormQs<LandscapeEntryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_landscape_entry(user.user_id, alliance_id, entry_id, &input)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Deletes a landscape entry.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(entry_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.delete_landscape_entry(user.user_id, alliance_id, entry_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Publishes a landscape entry.
#[instrument(skip_all, err)]
pub(crate) async fn publish(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(entry_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_landscape_entry_published(user.user_id, alliance_id, entry_id, true)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Unpublishes a landscape entry.
#[instrument(skip_all, err)]
pub(crate) async fn unpublish(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(entry_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_landscape_entry_published(user.user_id, alliance_id, entry_id, false)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Prepares the landscape list page and filters for the alliance dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(DashboardLandscapeFilters, landscape::ListPage), HandlerError> {
    let filters: DashboardLandscapeFilters = if raw_query.is_empty() {
        DashboardLandscapeFilters::default()
    } else {
        serde_qs_config().deserialize_str(raw_query)?
    };
    filters.validate()?;

    let (can_manage_landscape, output) = tokio::try_join!(
        db.user_has_alliance_permission(&alliance_id, &user_id, AlliancePermission::GroupsWrite),
        db.list_alliance_landscape_entries(alliance_id, &filters)
    )?;
    let navigation_links =
        NavigationLinks::from_filters(&filters, output.total, DASHBOARD_URL, PARTIAL_URL)?;

    Ok((
        filters.clone(),
        landscape::ListPage {
            can_manage_landscape,
            filters,
            entries: output.entries,
            total: output.total,
            navigation_links,
        },
    ))
}
