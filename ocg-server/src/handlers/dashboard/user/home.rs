//! HTTP handlers for the user dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::error::HandlerError,
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::user::home::{Content, Page, Tab},
    },
};

/// Handler that returns the user dashboard home page.
///
/// This handler manages the main user dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session
    let Some(user) = auth_session.user.clone() else {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

    // Get selected tab from query
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Account => {
            let timezones = db.list_timezones().await?;
            Content::Account(auth::UpdateUserPage {
                has_password: user.has_password.unwrap_or(false),
                timezones,
                user: UserDetails::from(user),
            })
        }
    };

    // Render the page
    let page = Page {
        content,
        page_id: PageId::UserDashboard,
        path: "/dashboard/user".to_string(),
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html.into_response())
}
