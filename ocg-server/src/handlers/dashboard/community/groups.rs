//! HTTP handlers for managing groups in the community dashboard.

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
        extractors::{CurrentUser, SelectedCommunityId, ValidatedFormQs},
    },
    router::serde_qs_config,
    templates::dashboard::community::groups::{self, CommunityGroupsFilters, Group},
    types::{
        pagination::{self, NavigationLinks},
        permissions::CommunityPermission,
        search::SearchGroupsFilters,
    },
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial
const DASHBOARD_URL: &str = "/dashboard/community?tab=groups";
const PARTIAL_URL: &str = "/dashboard/community/groups";

// Pages handlers.

/// Displays the list of groups for the community dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        community_id,
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_groups, categories, regions) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::GroupsWrite),
        db.list_group_categories(community_id),
        db.list_regions(community_id)
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_groups, group, categories, regions) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user.user_id, CommunityPermission::GroupsWrite),
        db.get_group_full(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_regions(community_id)
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark group as active in database
    db.activate_group(user.user_id, community_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Adds a new group to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    session: Session,
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    ValidatedFormQs(group): ValidatedFormQs<Group>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add group to database
    let group_id = db.add_group(user.user_id, community_id, &group).await?;

    // Auto-select the new group if none was selected
    if session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await?.is_none() {
        session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;
    }

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    )
        .into_response())
}

/// Deactivates a group (sets active=false without deleting).
#[instrument(skip_all, err)]
pub(crate) async fn deactivate(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark group as not active in database
    db.deactivate_group(user.user_id, community_id, group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Deletes a group from the database (soft delete).
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    session: Session,
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete group from database (soft delete)
    db.delete_group(user.user_id, community_id, group_id).await?;

    // Update selection if deleted group was selected
    if session.get::<Uuid>(SELECTED_GROUP_ID_KEY).await? == Some(group_id) {
        // Get remaining groups in this community
        let groups_by_community = db.list_user_groups(&user.user_id).await?;
        let community_groups = groups_by_community
            .iter()
            .find(|c| c.community.community_id == community_id);

        if let Some(first_group_id) = community_groups.and_then(|c| c.groups.first()).map(|g| g.group_id) {
            session.insert(SELECTED_GROUP_ID_KEY, first_group_id).await?;
        } else {
            session.remove::<Uuid>(SELECTED_GROUP_ID_KEY).await?;
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    ))
}

/// Updates an existing group's information in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
    ValidatedFormQs(group): ValidatedFormQs<Group>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update group in database
    db.update_group(user.user_id, community_id, group_id, &group).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-community-dashboard-table")],
    )
        .into_response())
}

// Helpers.

/// Prepares the groups list page and filters for the community dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
    community_name: Option<String>,
) -> Result<(CommunityGroupsFilters, groups::ListPage), HandlerError> {
    // Use the provided community name when available to avoid an extra lookup
    let community_name = if let Some(community_name) = community_name {
        community_name
    } else {
        let Some(community_name) = db.get_community_name_by_id(community_id).await? else {
            return Err(anyhow::anyhow!("community not found").into());
        };
        community_name
    };

    // Fetch groups
    let filters: CommunityGroupsFilters = serde_qs_config().deserialize_str(raw_query)?;
    let search_filters = SearchGroupsFilters {
        community: vec![community_name],
        include_inactive: Some(true),
        limit: filters.limit,
        offset: filters.offset,
        sort_by: Some(String::from("name")),
        ts_query: filters.ts_query.clone(),
        ..SearchGroupsFilters::default()
    };
    let (can_manage_groups, results) = tokio::try_join!(
        db.user_has_community_permission(&community_id, &user_id, CommunityPermission::GroupsWrite),
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
