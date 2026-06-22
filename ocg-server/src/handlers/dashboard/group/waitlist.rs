//! HTTP handlers for the waitlist section in the group dashboard.

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
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId},
    },
    router::serde_qs_config,
    templates::dashboard::group::waitlist::{self, WaitlistFilters, WaitlistPaginationFilters},
    types::{pagination::NavigationLinks, permissions::GroupPermission},
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the waiting list for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary and waitlist
    let page_filters: WaitlistPaginationFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let search_filters = WaitlistFilters {
        event_id,
        limit: page_filters.limit,
        offset: page_filters.offset,
    };
    let (can_manage_events, event, search_waitlist_results) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(alliance_id, group_id, event_id),
        db.search_event_waitlist(group_id, &search_filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &page_filters,
        search_waitlist_results.total,
        &format!("/dashboard/group/events/{event_id}/waitlist"),
        &format!("/dashboard/group/events/{event_id}/waitlist"),
    )?;
    let template = waitlist::ListPage {
        can_manage_events,
        event,
        limit: page_filters.limit,
        navigation_links,
        offset: page_filters.offset,
        total: search_waitlist_results.total,
        waitlist: search_waitlist_results.waitlist,
    };

    Ok(Html(template.render()?))
}
