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

use super::{
    accelerator, coffee_meet, events, integrations, logs, members, sponsors, spotlights, store,
    team,
};

use crate::{
    auth::AuthSession,
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{SelectedAllianceId, SelectedGroupId},
    },
    templates::{
        PageId,
        auth::User,
        dashboard::group::{
            analytics, book_exchange as book_exchange_template,
            home::{Content, Page, Tab},
            intentional_dating as intentional_dating_template, settings,
        },
    },
    types::permissions::GroupPermission,
};

#[cfg(test)]
mod tests;

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_lines)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
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
    let (groups_by_alliance, site_settings) =
        tokio::try_join!(db.list_user_groups(&user.user_id), db.get_site_settings())?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Accelerator => {
            let template =
                accelerator::prepare_page(&db, alliance_id, group_id, user.user_id).await?;
            Content::Accelerator(template)
        }
        Tab::Analytics => {
            let (group, stats) = tokio::try_join!(
                db.get_group_full(alliance_id, group_id),
                db.get_group_stats(alliance_id, group_id)
            )?;
            Content::Analytics(Box::new(analytics::Page { group, stats }))
        }
        Tab::Events => {
            let (_, template) = events::prepare_list_page(
                &db,
                alliance_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Events(Box::new(template))
        }
        Tab::CoffeeMeet => {
            let template =
                coffee_meet::prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;
            Content::CoffeeMeet(template)
        }
        Tab::BookExchange => {
            let can_manage_book_exchange = db
                .user_has_group_permission(
                    &alliance_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::SettingsWrite,
                )
                .await?;
            let members = db.list_book_exchange_members(alliance_id, Some(group_id)).await?;
            Content::BookExchange(book_exchange_template::ListPage {
                can_manage_book_exchange,
                members,
            })
        }
        Tab::IntentionalDating => {
            let can_manage_introductions = db
                .user_has_group_permission(
                    &alliance_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::SettingsWrite,
                )
                .await?;
            if !can_manage_introductions {
                return Err(HandlerError::Forbidden);
            }
            let opt_ins = db
                .list_intentional_dating_opt_ins(alliance_id, Some(group_id))
                .await?;
            Content::IntentionalDating(intentional_dating_template::ListPage {
                can_manage_introductions,
                opt_ins,
            })
        }
        Tab::Integrations => Content::Integrations(
            integrations::prepare_page(&db, alliance_id, group_id, user.user_id).await?,
        ),
        Tab::Members => {
            let (_, template) = members::prepare_list_page(
                &db,
                alliance_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Members(template)
        }
        Tab::Logs => {
            let (_, template) =
                logs::prepare_list_page(&db, group_id, raw_query.as_deref().unwrap_or_default())
                    .await?;
            Content::Logs(template)
        }
        Tab::Settings => {
            let (can_manage_settings, group, categories, regions) = tokio::try_join!(
                db.user_has_group_permission(
                    &alliance_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::SettingsWrite
                ),
                db.get_group_full(alliance_id, group_id),
                db.list_group_categories(alliance_id),
                db.list_regions(alliance_id)
            )?;
            Content::Settings(Box::new(settings::UpdatePage {
                can_manage_settings,
                categories,
                group,
                payments_enabled: payments_cfg.is_some(),
                regions,
            }))
        }
        Tab::Sponsors => {
            let (_, template) = sponsors::prepare_list_page(
                &db,
                alliance_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Sponsors(template)
        }
        Tab::Spotlights => {
            let template =
                spotlights::prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;
            Content::Spotlights(template)
        }
        Tab::Store => {
            let template =
                store::prepare_list_page(&db, alliance_id, group_id, user.user_id).await?;
            Content::Store(template)
        }
        Tab::Team => {
            let (_, template) = team::prepare_list_page(
                &db,
                alliance_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Team(template)
        }
    };

    // Render the page
    let page = Page {
        content,
        groups_by_alliance,
        messages: messages.into_iter().collect(),
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        selected_alliance_id: alliance_id,
        selected_group_id: group_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}
