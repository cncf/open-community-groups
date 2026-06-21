//! HTTP handlers for the alliance dashboard.

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
    handlers::{error::HandlerError, extractors::SelectedAllianceId},
    templates::{
        PageId,
        auth::User,
        dashboard::alliance::{
            analytics, event_categories, group_categories,
            home::{Content, Page, Tab},
            regions, settings,
        },
    },
    types::permissions::AlliancePermission,
};

#[cfg(test)]
mod tests;

/// Handler that returns the alliance dashboard home page.
///
/// This handler manages the main alliance dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
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

    // Get selected alliance, user alliances and site settings
    let (alliance, alliances, site_settings) = tokio::try_join!(
        db.get_alliance_full(alliance_id),
        db.list_user_alliances(&user_id),
        db.get_site_settings()
    )?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Analytics => {
            let stats = db.get_alliance_stats(alliance_id).await?;
            Content::Analytics(Box::new(analytics::Page { stats }))
        }
        Tab::EventCategories => {
            let (can_manage_taxonomy, categories) = tokio::try_join!(
                db.user_has_alliance_permission(
                    &alliance_id,
                    &user_id,
                    AlliancePermission::TaxonomyWrite
                ),
                db.list_event_categories(alliance_id)
            )?;
            Content::EventCategories(event_categories::ListPage {
                can_manage_taxonomy,
                categories,
            })
        }
        Tab::GroupCategories => {
            let (can_manage_taxonomy, categories) = tokio::try_join!(
                db.user_has_alliance_permission(
                    &alliance_id,
                    &user_id,
                    AlliancePermission::TaxonomyWrite
                ),
                db.list_group_categories(alliance_id)
            )?;
            Content::GroupCategories(group_categories::ListPage {
                can_manage_taxonomy,
                categories,
            })
        }
        Tab::Groups => {
            let (_, template) = groups::prepare_list_page(
                &db,
                alliance_id,
                user_id,
                raw_query.as_deref().unwrap_or_default(),
                Some(alliance.name.clone()),
            )
            .await?;
            Content::Groups(template)
        }
        Tab::Logs => {
            let (_, template) = logs::prepare_list_page(
                &db,
                alliance_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Logs(template)
        }
        Tab::Regions => {
            let (can_manage_taxonomy, regions) = tokio::try_join!(
                db.user_has_alliance_permission(
                    &alliance_id,
                    &user_id,
                    AlliancePermission::TaxonomyWrite
                ),
                db.list_regions(alliance_id)
            )?;
            Content::Regions(regions::ListPage {
                can_manage_taxonomy,
                regions,
            })
        }
        Tab::Settings => {
            let can_manage_settings = db
                .user_has_alliance_permission(
                    &alliance_id,
                    &user_id,
                    AlliancePermission::SettingsWrite,
                )
                .await?;
            Content::Settings(Box::new(settings::UpdatePage {
                can_manage_settings,
                alliance: alliance.clone(),
            }))
        }
        Tab::Team => {
            let (_, template) = team::prepare_list_page(
                &db,
                alliance_id,
                user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Team(template)
        }
    };

    // Render the page
    let page = Page {
        alliances,
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::AllianceDashboard,
        path: "/dashboard/alliance".to_string(),
        selected_alliance_id: alliance_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    Ok(Html(page.render()?))
}
