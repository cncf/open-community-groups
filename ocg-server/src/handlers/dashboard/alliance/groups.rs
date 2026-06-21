//! HTTP handlers for managing groups in the alliance dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        auth::SELECTED_GROUP_ID_KEY,
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, ValidatedFormQs},
    },
    router::serde_qs_config,
    templates::dashboard::alliance::groups::{self, AllianceGroupsFilters, Group},
    types::{
        pagination::{self, NavigationLinks},
        permissions::AlliancePermission,
        search::SearchGroupsFilters,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/alliance?tab=groups";
const PARTIAL_URL: &str = "/dashboard/alliance/groups";

// Pages handlers.

/// Displays the list of groups for the alliance dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        alliance_id,
        user.user_id,
        raw_query.as_deref().unwrap_or_default(),
        None,
    )
    .await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Displays the page to add a new group.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_groups, categories, regions) = tokio::try_join!(
        db.user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::GroupsWrite
        ),
        db.list_group_categories(alliance_id),
        db.list_regions(alliance_id)
    )?;
    let template = groups::AddPage {
        can_manage_groups,
        categories,
        regions,
    };

    Ok(Html(template.render()?))
}

/// Displays the page to update an existing group.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_groups, group, categories, regions) = tokio::try_join!(
        db.user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::GroupsWrite
        ),
        db.get_group_full(alliance_id, group_id),
        db.list_group_categories(alliance_id),
        db.list_regions(alliance_id)
    )?;
    let template = groups::UpdatePage {
        can_manage_groups,
        categories,
        group,
        regions,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Activates a group (sets active=true).
#[instrument(skip_all, err)]
pub(crate) async fn activate(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark group as active in database
    db.activate_group(user.user_id, alliance_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Adds a new group to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    session: Session,
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    ValidatedFormQs(group): ValidatedFormQs<Group>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add group to database
    let group_id = db.add_group(user.user_id, alliance_id, &group).await?;

    // Auto-select the new group if none was selected
    if session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await?.is_none() {
        session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;
    }

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    )
        .into_response())
}

/// Deactivates a group (sets active=false without deleting).
#[instrument(skip_all, err)]
pub(crate) async fn deactivate(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark group as not active in database
    db.deactivate_group(user.user_id, alliance_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Deletes a group from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    session: Session,
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete group from database (soft delete)
    db.delete_group(user.user_id, alliance_id, group_id).await?;

    // Update selection if deleted group was selected
    if session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await? == Some(group_id) {
        // Get remaining groups in this alliance
        let groups_by_alliance = db.list_user_groups(&user.user_id).await?;
        let alliance_groups = groups_by_alliance
            .iter()
            .find(|c| c.alliance.alliance_id == alliance_id);

        if let Some(first_group_id) =
            alliance_groups.and_then(|c| c.groups.first()).map(|g| g.group_id)
        {
            session.insert(SELECTED_GROUP_ID_KEY, first_group_id).await?;
        } else {
            session.remove::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    ))
}

/// Updates an existing group's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
    ValidatedFormQs(group): ValidatedFormQs<Group>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update group in database
    db.update_group(user.user_id, alliance_id, group_id, &group).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-alliance-dashboard-table")],
    )
        .into_response())
}

// Helpers.

/// Prepares the groups list page and filters for the alliance dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    alliance_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
    alliance_name: Option<String>,
) -> Result<(AllianceGroupsFilters, groups::ListPage), HandlerError> {
    // Use the provided alliance name when available to avoid an extra lookup
    let alliance_name = if let Some(alliance_name) = alliance_name {
        alliance_name
    } else {
        let Some(alliance_name) = db.get_alliance_name_by_id(alliance_id).await? else {
            return Err(anyhow::anyhow!("alliance not found").into());
        };
        alliance_name
    };

    // Fetch groups
    let filters: AllianceGroupsFilters = serde_qs_config().deserialize_str(raw_query)?;
    let search_filters = SearchGroupsFilters {
        alliance: vec![alliance_name],
        include_inactive: Some(true),
        limit: filters.limit,
        offset: filters.offset,
        sort_by: Some(String::from("name")),
        ts_query: filters.ts_query.clone(),
        ..SearchGroupsFilters::default()
    };
    let (can_manage_groups, results) = tokio::try_join!(
        db.user_has_alliance_permission(&alliance_id, &user_id, AlliancePermission::GroupsWrite),
        db.search_groups(&search_filters)
    )?;

    // Prepare template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = groups::ListPage {
        can_manage_groups,
        groups: results.groups,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
        ts_query: filters.ts_query.clone(),
    };

    Ok((filters, template))
}
