//! HTTP handlers for the invitation requests section in the group dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    response::{Html, IntoResponse},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId},
    },
    router::serde_qs_config,
    templates::dashboard::group::invitation_requests::{self, InvitationRequestsFilters},
    types::{
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the invitation requests for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary and invitation requests
    let filters: InvitationRequestsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    filters.validate()?;
    let (can_manage_events, event, search_results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_invitation_requests(group_id, event_id, &filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        search_results.total,
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
    )?;
    let refresh_url = pagination::build_url(
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
        &filters,
    )?;
    let template = invitation_requests::ListPage {
        can_manage_events,
        event,
        invitation_requests: search_results.invitation_requests,
        navigation_links,
        refresh_url,
        total: search_results.total,
        limit: filters.limit,
        offset: filters.offset,
        sort: filters.sort,
        status: filters.status,
        title: filters.title,
        ts_query: filters.ts_query,
    };

    Ok(Html(template.render()?))
}
