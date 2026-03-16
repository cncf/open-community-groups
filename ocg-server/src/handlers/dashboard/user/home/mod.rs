//! HTTP handlers for the user dashboard.

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
    handlers::error::HandlerError,
    router::serde_qs_config,
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::user::{
            events,
            home::{Content, Page, Tab},
            invitations, session_proposals, submissions,
        },
    },
    types::pagination::NavigationLinks,
};

#[cfg(test)]
mod tests;

/// Handler that returns the user dashboard home page.
///
/// This handler manages the main user dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let raw_query = raw_query.as_deref().unwrap_or_default();
    let tab: Tab = query
        .get("tab")
        .map_or(Tab::default(), |tab| tab.parse().unwrap_or_default());

    // Get site settings
    let site_settings = db.get_site_settings().await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Account => {
            let timezones = db.list_timezones().await?;
            Content::Account(Box::new(auth::UpdateUserPage {
                has_password: user.has_password.unwrap_or(false),
                timezones,
                user: UserDetails::from(user),
            }))
        }
        Tab::Events => {
            let filters: events::UserEventsFilters = serde_qs_config().deserialize_str(raw_query)?;
            let events_output = db.list_user_events(user.user_id, &filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                events_output.total,
                "/dashboard/user?tab=events",
                "/dashboard/user/events",
            )?;
            Content::Events(events::ListPage {
                events: events_output.events,
                navigation_links,
                total: events_output.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
        Tab::Invitations => {
            let (community_invitations, group_invitations) = tokio::try_join!(
                db.list_user_community_team_invitations(user.user_id),
                db.list_user_group_team_invitations(user.user_id)
            )?;
            Content::Invitations(invitations::ListPage {
                community_invitations,
                group_invitations,
            })
        }
        Tab::SessionProposals => {
            let filters: session_proposals::SessionProposalsFilters =
                serde_qs_config().deserialize_str(raw_query)?;
            let (pending_co_speaker_invitations, session_proposal_levels, session_proposals_output) = tokio::try_join!(
                db.list_user_pending_session_proposal_co_speaker_invitations(user.user_id),
                db.list_session_proposal_levels(),
                db.list_user_session_proposals(user.user_id, &filters)
            )?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                session_proposals_output.total,
                "/dashboard/user?tab=session-proposals",
                "/dashboard/user/session-proposals",
            )?;
            Content::SessionProposals(session_proposals::ListPage {
                current_user_id: user.user_id,
                pending_co_speaker_invitations,
                session_proposal_levels,
                session_proposals: session_proposals_output.session_proposals,
                navigation_links,
                total: session_proposals_output.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
        Tab::Submissions => {
            let filters: submissions::CfsSubmissionsFilters = serde_qs_config().deserialize_str(raw_query)?;
            let submissions = db.list_user_cfs_submissions(user.user_id, &filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                submissions.total,
                "/dashboard/user?tab=submissions",
                "/dashboard/user/submissions",
            )?;
            Content::Submissions(submissions::ListPage {
                submissions: submissions.submissions,
                navigation_links,
                total: submissions.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
    };

    // Render the page
    let page = Page {
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::UserDashboard,
        path: "/dashboard/user".to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}
