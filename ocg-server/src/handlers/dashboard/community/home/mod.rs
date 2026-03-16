//! HTTP handlers for the community dashboard.

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
    handlers::{error::HandlerError, extractors::SelectedCommunityId},
    router::serde_qs_config,
    templates::{
        PageId,
        auth::User,
        dashboard::community::{
            analytics, event_categories, group_categories,
            groups::{self, CommunityGroupsFilters},
            home::{Content, Page, Tab},
            regions, settings,
            team::{self, CommunityTeamFilters},
        },
    },
    types::{pagination::NavigationLinks, permissions::CommunityPermission, search::SearchGroupsFilters},
};

#[cfg(test)]
mod tests;

/// Handler that returns the community dashboard home page.
///
/// This handler manages the main community dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    SelectedCommunityId(community_id): SelectedCommunityId,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get selected tab from query
    let tab: Tab = query
        .get("tab")
        .map_or(Tab::default(), |tab| tab.parse().unwrap_or_default());

    // Get user_id from session
    let user_id = auth_session.user.as_ref().expect("user to be logged in").user_id;

    // Get selected community, user communities and site settings
    let (community, communities, site_settings) = tokio::try_join!(
        db.get_community_full(community_id),
        db.list_user_communities(&user_id),
        db.get_site_settings()
    )?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Analytics => {
            let stats = db.get_community_stats(community_id).await?;
            Content::Analytics(Box::new(analytics::Page { stats }))
        }
        Tab::EventCategories => {
            let (can_manage_taxonomy, categories) = tokio::try_join!(
                db.user_has_community_permission(&community_id, &user_id, CommunityPermission::TaxonomyWrite),
                db.list_event_categories(community_id)
            )?;
            Content::EventCategories(event_categories::ListPage {
                can_manage_taxonomy,
                categories,
            })
        }
        Tab::GroupCategories => {
            let (can_manage_taxonomy, categories) = tokio::try_join!(
                db.user_has_community_permission(&community_id, &user_id, CommunityPermission::TaxonomyWrite),
                db.list_group_categories(community_id)
            )?;
            Content::GroupCategories(group_categories::ListPage {
                can_manage_taxonomy,
                categories,
            })
        }
        Tab::Groups => {
            // Fetch groups
            let page_filters: CommunityGroupsFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            let search_filters = SearchGroupsFilters {
                community: vec![community.name.clone()],
                include_inactive: Some(true),
                limit: page_filters.limit,
                offset: page_filters.offset,
                sort_by: Some("name".to_string()),
                ts_query: page_filters.ts_query.clone(),
                ..SearchGroupsFilters::default()
            };
            let (can_manage_groups, results) = tokio::try_join!(
                db.user_has_community_permission(&community_id, &user_id, CommunityPermission::GroupsWrite),
                db.search_groups(&search_filters)
            )?;

            // Prepare template content
            let navigation_links = NavigationLinks::from_filters(
                &page_filters,
                results.total,
                "/dashboard/community?tab=groups",
                "/dashboard/community/groups",
            )?;
            Content::Groups(groups::ListPage {
                can_manage_groups,
                groups: results.groups,
                navigation_links,
                total: results.total,
                limit: page_filters.limit,
                offset: page_filters.offset,
                ts_query: page_filters.ts_query,
            })
        }
        Tab::Regions => {
            let (can_manage_taxonomy, regions) = tokio::try_join!(
                db.user_has_community_permission(&community_id, &user_id, CommunityPermission::TaxonomyWrite),
                db.list_regions(community_id)
            )?;
            Content::Regions(regions::ListPage {
                can_manage_taxonomy,
                regions,
            })
        }
        Tab::Settings => {
            let can_manage_settings = db
                .user_has_community_permission(&community_id, &user_id, CommunityPermission::SettingsWrite)
                .await?;
            Content::Settings(Box::new(settings::UpdatePage {
                can_manage_settings,
                community: community.clone(),
            }))
        }
        Tab::Team => {
            // Fetch team members
            let page_filters: CommunityTeamFilters =
                serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
            let (results, roles, can_manage_team) = tokio::try_join!(
                db.list_community_team_members(community_id, &page_filters),
                db.list_community_roles(),
                db.user_has_community_permission(&community_id, &user_id, CommunityPermission::TeamWrite)
            )?;

            // Prepare template content
            let navigation_links = NavigationLinks::from_filters(
                &page_filters,
                results.total,
                "/dashboard/community?tab=team",
                "/dashboard/community/team",
            )?;
            Content::Team(team::ListPage {
                can_manage_team,
                members: results.members,
                navigation_links,
                roles,
                total: results.total,
                total_accepted: results.total_accepted,
                total_admins_accepted: results.total_admins_accepted,
                limit: page_filters.limit,
                offset: page_filters.offset,
            })
        }
    };

    // Render the page
    let page = Page {
        communities,
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::CommunityDashboard,
        path: "/dashboard/community".to_string(),
        selected_community_id: community_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    Ok(Html(page.render()?))
}
