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
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId},
    },
    templates::{
        PageId,
        auth::User,
        dashboard::group::{
            analytics,
            home::{Content, Page, Tab},
            settings,
        },
    },
    types::permissions::GroupPermission,
};

use super::{badges, check_in, events, logs, members, payments_ready, refunds, sponsors, team};

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
    CurrentUser(user): CurrentUser,
    auth_session: AuthSession,
    messages: Messages,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get selected tab from query
    let requested_tab: Tab = query
        .get("tab")
        .map_or(Tab::default(), |tab| tab.parse().unwrap_or_default());

    // Load dashboard context and payment readiness
    let payment_recipient = async {
        if matches!(&requested_tab, Tab::Refunds) {
            db.get_group_payment_recipient(community_id, group_id).await
        } else {
            Ok(None)
        }
    };
    let (
        can_manage_badges,
        can_manage_check_ins,
        groups_by_community,
        payment_recipient,
        site_settings,
    ) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::BadgesWrite
        ),
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::CheckInsWrite
        ),
        db.list_user_groups(&user.user_id),
        payment_recipient,
        db.get_site_settings()
    )?;
    let payments_ready = payments_ready(payment_recipient.as_ref(), payments_cfg.as_ref());

    // Protect restricted dashboard tabs before preparing their content
    if !can_manage_badges && matches!(&requested_tab, Tab::Artwork | Tab::Awards | Tab::Badges) {
        return Err(HandlerError::Forbidden);
    }

    // Fall back internally so check-in users can recover their group selection
    let is_check_in_fallback = !can_manage_check_ins && matches!(&requested_tab, Tab::CheckIn);
    let effective_tab = if is_check_in_fallback {
        Tab::default()
    } else {
        requested_tab
    };

    // Prepare content for the effective tab
    let content = match effective_tab {
        Tab::Analytics => {
            let (stats, has_subgroups) = tokio::try_join!(
                db.get_group_stats(community_id, group_id, false),
                db.group_has_active_subgroups(community_id, group_id)
            )?;
            Content::Analytics(Box::new(analytics::Page {
                include_subgroups: false,
                has_subgroups,
                stats,
            }))
        }
        Tab::Artwork => {
            let template = badges::prepare_artwork_page(&db, group_id).await?;
            Content::Artwork(Box::new(template))
        }
        Tab::Awards => {
            let (_, template) = badges::prepare_awards_page(
                &db,
                group_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Awards(Box::new(template))
        }
        Tab::Badges => {
            let (_, template) = badges::prepare_badges_page(
                &db,
                group_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Badges(Box::new(template))
        }
        Tab::CheckIn => Content::CheckIn(check_in::prepare_list_page(&db, group_id).await?),
        Tab::Events => {
            let (_, template) = events::prepare_list_page(
                &db,
                community_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Events(Box::new(template))
        }
        Tab::Logs => {
            let (_, template) =
                logs::prepare_list_page(&db, group_id, raw_query.as_deref().unwrap_or_default())
                    .await?;
            Content::Logs(template)
        }
        Tab::Members => {
            let (_, template) = members::prepare_list_page(
                &db,
                community_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Members(template)
        }
        Tab::Refunds => {
            let (_, template) = refunds::prepare_list_page(
                &db,
                community_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Refunds(template)
        }
        Tab::Settings => {
            let (
                can_manage_settings,
                group,
                has_child_links,
                categories,
                parent_options,
                regions,
                external_payments,
            ) = tokio::try_join!(
                db.user_has_group_permission(
                    &community_id,
                    &group_id,
                    &user.user_id,
                    GroupPermission::SettingsWrite
                ),
                db.get_group_full(community_id, group_id),
                db.group_has_child_links(community_id, group_id),
                db.list_group_categories(community_id),
                db.list_group_parent_options(community_id, user.user_id, Some(group_id)),
                db.list_regions(community_id),
                db.get_group_external_payments_context(community_id, group_id)
            )?;
            Content::Settings(Box::new(settings::UpdatePage {
                can_manage_settings,
                categories,
                external_payments,
                group,
                has_child_links,
                parent_options,
                payments_enabled: payments_cfg.is_some(),
                regions,
            }))
        }
        Tab::Sponsors => {
            let (_, template) = sponsors::prepare_list_page(
                &db,
                community_id,
                group_id,
                user.user_id,
                raw_query.as_deref().unwrap_or_default(),
            )
            .await?;
            Content::Sponsors(template)
        }
        Tab::Team => {
            let (_, template) = team::prepare_list_page(
                &db,
                community_id,
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
        can_manage_badges,
        can_manage_check_ins,
        content,
        groups_by_community,
        is_check_in_fallback,
        messages: messages.into_iter().collect(),
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        payments_ready,
        selected_community_id: community_id,
        selected_group_id: group_id,
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}
