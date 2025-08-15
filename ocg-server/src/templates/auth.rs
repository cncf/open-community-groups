//! Templates and types for authentication-related pages and user info.

use askama::Template;
use axum_messages::Message;
use serde::{Deserialize, Serialize};

use crate::{auth::AuthSession, config::LoginOptions, templates::PageId};

// Pages templates.

/// Template for the log in page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/log_in.html")]
pub(crate) struct LogInPage {
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Authenticated user information.
    pub user: User,

    /// Name of the authentication provider, if any.
    pub auth_provider: Option<String>,
    /// Next URL to redirect to after login, if any.
    pub next_url: Option<String>,
}

/// Template for the sign up page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/sign_up.html")]
pub(crate) struct SignUpPage {
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Authenticated user information.
    pub user: User,

    /// Name of the authentication provider, if any.
    pub auth_provider: Option<String>,
    /// Next URL to redirect to after sign up, if any.
    pub next_url: Option<String>,
}

// Types.

/// User information for authentication templates and session state.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct User {
    /// Whether the user is logged in.
    pub logged_in: bool,

    /// Display name of the user, if any.
    pub name: Option<String>,
    /// Username, if any.
    pub username: Option<String>,
}

/// Conversion from `AuthSession` to User for template rendering.
impl From<AuthSession> for User {
    fn from(session: AuthSession) -> Self {
        let user = session.user.as_ref();

        Self {
            logged_in: user.is_some(),
            name: user.map(|u| u.name.clone()),
            username: user.map(|u| u.username.clone()),
        }
    }
}
