//! HTTP handlers for the invitation requests section in the group dashboard.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId},
    },
    router::serde_qs_config,
    templates::dashboard::group::invitation_requests::{
        self, InvitationRequestsFilters, InvitationRequestsPaginationFilters,
    },
    types::{pagination::NavigationLinks, permissions::GroupPermission},
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
    let page_filters: InvitationRequestsPaginationFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let search_filters = InvitationRequestsFilters {
        event_id,
        limit: page_filters.limit,
        offset: page_filters.offset,
    };
    let (can_manage_events, event, search_results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_invitation_requests(group_id, &search_filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &page_filters,
        search_results.total,
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
        &format!("/dashboard/group/events/{event_id}/invitation-requests"),
    )?;
    let template = invitation_requests::ListPage {
        can_manage_events,
        event,
        invitation_requests: search_results.invitation_requests,
        limit: page_filters.limit,
        navigation_links,
        offset: page_filters.offset,
        total: search_results.total,
    };

    Ok(Html(template.render()?))
}
