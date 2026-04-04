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

use super::{groups, logs, team};

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedCommunityId},
    templates::{
        PageId,
        auth::User,
        dashboard::community::{
            analytics, event_categories, group_categories,
            home::{Content, Page, Tab},
            regions, settings,
        },
    },
    types::permissions::CommunityPermission,
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
            let (_, template) = groups::prepare_list_page(
                &db,
                community_id,
                user_id,
                raw_query.as_deref().unwrap_or_default(),
                Some(community.name.clone()),
            )
            .await?;
            Content::Groups(template)
        }
        Tab::Logs => {
            let (_, template) =
                logs::prepare_list_page(&db, community_id, raw_query.as_deref().unwrap_or_default()).await?;
            Content::Logs(template)
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
            let (_, template) = team::prepare_list_page(
                &db,
                community_id,
                user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Team(template)
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
