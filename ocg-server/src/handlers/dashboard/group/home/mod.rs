//! HTTP handlers for the group dashboard home page.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, RawQuery, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId},
    },
    router::serde_qs_config,
    templates::{
        PageId,
        auth::User,
        dashboard::group::{
            analytics,
            events::{self, EventsListFilters, EventsTab},
            home::{Content, Page, Tab},
            members::{self, GroupMembersFilters},
            settings,
            sponsors::{self, GroupSponsorsFilters},
            team::{self, GroupTeamFilters},
        },
    },
    types::{pagination::NavigationLinks, permissions::GroupPermission},
};

#[cfg(test)]
mod tests;

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let tab: Tab = query
        .get("tab")
        .map_or(Tab::default(), |tab| tab.parse().unwrap_or_default());

    // Get site settings and user groups information
    let (groups_by_community, site_settings) =
        tokio::try_join!(db.list_user_groups(&user.user_id), db.get_site_settings())?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Analytics => {
            let stats = db.get_group_stats(community_id, group_id).await?;
            Content::Analytics(Box::new(analytics::Page { stats }))
        }
        Tab::Events => {
            // Fetch past and upcoming events
            let filters: EventsListFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            let (can_manage_events, events) = tokio::try_join!(
                db.user_has_group_permission(
                    &community_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::EventsWrite
                ),
                db.list_group_events(group_id, &filters)
            )?;
            let mut past_filters = filters.clone();
            past_filters.events_tab = Some(EventsTab::Past);
            let mut upcoming_filters = filters.clone();
            upcoming_filters.events_tab = Some(EventsTab::Upcoming);

            // Prepare template content
            let past_navigation_links = NavigationLinks::from_filters(
                &past_filters,
                events.past.total,
                "/dashboard/group?tab=events",
                "/dashboard/group/events",
            )?;
            let upcoming_navigation_links = NavigationLinks::from_filters(
                &upcoming_filters,
                events.upcoming.total,
                "/dashboard/group?tab=events",
                "/dashboard/group/events",
            )?;
            Content::Events(Box::new(events::ListPage {
                can_manage_events,
                events,
                events_tab: filters.current_tab(),
                past_navigation_links,
                upcoming_navigation_links,
                limit: filters.limit,
                past_offset: filters.past_offset,
                upcoming_offset: filters.upcoming_offset,
            }))
        }
        Tab::Members => {
            // Fetch group members
            let filters: GroupMembersFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            let (can_manage_members, results) = tokio::try_join!(
                db.user_has_group_permission(
                    &community_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::MembersWrite
                ),
                db.list_group_members(group_id, &filters)
            )?;

            // Prepare template content
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                results.total,
                "/dashboard/group?tab=members",
                "/dashboard/group/members",
            )?;
            Content::Members(members::ListPage {
                can_manage_members,
                members: results.members,
                navigation_links,
                total: results.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
        Tab::Settings => {
            let (can_manage_settings, group, categories, regions) = tokio::try_join!(
                db.user_has_group_permission(
                    &community_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::SettingsWrite
                ),
                db.get_group_full(community_id, group_id),
                db.list_group_categories(community_id),
                db.list_regions(community_id)
            )?;
            Content::Settings(Box::new(settings::UpdatePage {
                can_manage_settings,
                categories,
                group,
                regions,
            }))
        }
        Tab::Sponsors => {
            // Fetch group sponsors
            let filters: GroupSponsorsFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            let (can_manage_sponsors, results) = tokio::try_join!(
                db.user_has_group_permission(
                    &community_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::SponsorsWrite
                ),
                db.list_group_sponsors(group_id, &filters, false)
            )?;

            // Prepare template content
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                results.total,
                "/dashboard/group?tab=sponsors",
                "/dashboard/group/sponsors",
            )?;
            Content::Sponsors(sponsors::ListPage {
                can_manage_sponsors,
                navigation_links,
                sponsors: results.sponsors,
                total: results.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
        Tab::Team => {
            // Fetch group team members
            let filters: GroupTeamFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            let user = auth_session.user.as_ref().expect("user to be logged in");
            let (results, roles, can_manage_team) = tokio::try_join!(
                db.list_group_team_members(group_id, &filters),
                db.list_group_roles(),
                db.user_has_group_permission(
                    &community_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::TeamWrite
                )
            )?;

            // Prepare template content
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                results.total,
                "/dashboard/group?tab=team",
                "/dashboard/group/team",
            )?;
            Content::Team(team::ListPage {
                can_manage_team,
                members: results.members,
                navigation_links,
                roles,
                total: results.total,
                total_accepted: results.total_accepted,
                total_admins_accepted: results.total_admins_accepted,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
    };

    // Render the page
    let page = Page {
        content,
        groups_by_community,
        messages: messages.into_iter().collect(),
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        selected_community_id: community_id,
        selected_group_id: group_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}
