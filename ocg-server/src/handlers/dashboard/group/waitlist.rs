//! HTTP handlers for the waitlist section in the group dashboard.

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
    templates::dashboard::group::waitlist::{self, WaitlistFilters},
    types::{
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the waiting list for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary and waitlist
    let filters: WaitlistFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    filters.validate()?;
    let (can_manage_events, event, search_waitlist_results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_waitlist(group_id, event_id, &filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        search_waitlist_results.total,
        &format!("/dashboard/group/events/{event_id}/waitlist"),
        &format!("/dashboard/group/events/{event_id}/waitlist"),
    )?;
    let refresh_url = pagination::build_url(
        &format!("/dashboard/group/events/{event_id}/waitlist"),
        &filters,
    )?;
    let template = waitlist::ListPage {
        can_manage_events,
        event,
        navigation_links,
        refresh_url,
        total: search_waitlist_results.total,
        waitlist: search_waitlist_results.waitlist,
        limit: filters.limit,
        offset: filters.offset,
        sort: filters.sort,
        title: filters.title,
        ts_query: filters.ts_query,
    };

    Ok(Html(template.render()?))
}
