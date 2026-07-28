//! HTTP handlers for user groups.

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
    handlers::{error::HandlerError, extractors::CurrentUser},
    router::serde_qs_config,
    templates::dashboard::user::groups,
    types::pagination::{self, NavigationLinks},
};

#[cfg(test)]
mod tests;

/// URL used by the full dashboard page.
const DASHBOARD_URL: &str = "/dashboard/user?tab=groups";

/// URL used by the groups tab partial.
const PARTIAL_URL: &str = "/dashboard/user/groups";

// Pages handlers.

/// Returns the groups list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) =
        prepare_list_page(&db, user.user_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Prepare response headers
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Removes the current user's membership from a group.
#[instrument(skip_all, err)]
pub(crate) async fn leave_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((community_name, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the community from the dashboard route
    let community_id = db
        .get_community_id_by_name(&community_name)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Remove the user's membership
    db.leave_group(community_id, group_id, user.user_id).await?;

    // Refresh the dashboard list after the mutation
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

// Helpers.

/// Prepares the groups list page and filters for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(groups::UserGroupsFilters, groups::ListPage), HandlerError> {
    // Fetch the user's groups
    let filters: groups::UserGroupsFilters = serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;
    let results = db.list_user_dashboard_groups(user_id, &filters).await?;

    // Prepare the paginated template
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let template = groups::ListPage {
        groups: results.groups,
        navigation_links,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    Ok((filters, template))
}
