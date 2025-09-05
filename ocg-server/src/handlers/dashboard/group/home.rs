//! HTTP handlers for the group dashboard home page.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, RawQuery, State},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CommunityId, SelectedGroupId},
    },
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::group::{
            attendees, events,
            home::{Content, Page, Tab},
            members, settings, team,
        },
    },
};

/// Handler that returns the group dashboard home page.
///
/// This handler manages the main group dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    CommunityId(community_id): CommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(serde_qs_de): State<serde_qs::Config>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get community and user groups information
    let (community, groups) =
        tokio::try_join!(db.get_community(community_id), db.list_user_groups(&user.user_id))?;

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
        Tab::Attendees => {
            let filters: attendees::AttendeesFilters = serde_qs_de
                .deserialize_str(&raw_query.unwrap_or_default())
                .map_err(anyhow::Error::new)?;
            let (filters_options, attendees) = tokio::try_join!(
                db.get_attendees_filters_options(group_id),
                db.search_event_attendees(group_id, &filters)
            )?;
            Content::Attendees(attendees::ListPage {
                attendees,
                filters,
                filters_options,
            })
        }
        Tab::Events => {
            let events = db.list_group_events(group_id).await?;
            Content::Events(events::ListPage { events })
        }
        Tab::Members => {
            let members = db.list_group_members(group_id).await?;
            Content::Members(members::ListPage { members })
        }
        Tab::Settings => {
            let (group, categories, regions) = tokio::try_join!(
                db.get_group_full(group_id),
                db.list_group_categories(community_id),
                db.list_regions(community_id)
            )?;
            Content::Settings(Box::new(settings::UpdatePage {
                categories,
                group,
                regions,
            }))
        }
        Tab::Team => {
            let members = db.list_group_team_members(group_id).await?;
            Content::Team(team::ListPage { members })
        }
    };

    // Render the page
    let page = Page {
        community,
        content,
        groups,
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".to_string(),
        selected_group_id: group_id,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html.into_response())
}
