//! Templates and types for authentication-related pages and user info.

use anyhow::Result;
use askama::Template;
use axum_messages::Message;
use serde::{Deserialize, Serialize};

use crate::{
    auth::AuthSession, config::LoginOptions, handlers::auth::AUTH_PROVIDER_KEY, templates::PageId,
    types::community::Community,
};

// Pages templates.

/// Template for the log in page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/log_in.html")]
pub(crate) struct LogInPage {
    /// Community information.
    pub community: Community,
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Authenticated user information.
    pub user: User,

    /// Next URL to redirect to after login, if any.
    pub next_url: Option<String>,
}

/// Template for the sign up page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/sign_up.html")]
pub(crate) struct SignUpPage {
    /// Community information.
    pub community: Community,
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Authenticated user information.
    pub user: User,

    /// Next URL to redirect to after sign up, if any.
    pub next_url: Option<String>,
}

/// Template for the update user page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/update_user.html")]
pub(crate) struct UpdateUserPage {
    /// Authenticated user information.
    pub user: User,
}

// Types.

/// User information for authentication templates and session state.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct User {
    /// Whether the user is logged in.
    pub logged_in: bool,

    /// Name of the authentication provider, if any.
    pub auth_provider: Option<String>,
    /// Display name of the user, if any.
    pub name: Option<String>,
    /// Username, if any.
    pub username: Option<String>,
}

impl User {
    /// Conversion from `AuthSession` to User for template rendering.
    pub(crate) async fn from_session(auth_session: AuthSession) -> Result<Self> {
        let auth_session_user = auth_session.user.as_ref();
        let user = Self {
            logged_in: auth_session_user.is_some(),
            auth_provider: auth_session.session.get(AUTH_PROVIDER_KEY).await?,
            name: auth_session_user.map(|u| u.name.clone()),
            username: auth_session_user.map(|u| u.username.clone()),
        };
        Ok(user)
    }
}
