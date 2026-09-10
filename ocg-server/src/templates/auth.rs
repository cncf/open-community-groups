//! Templates and types for authentication-related pages and user info.

use anyhow::Result;
use askama::Template;
use axum_messages::Message;

use crate::types::user::UserDetailsInput;
use crate::{
    auth::{AUTH_PROVIDER_KEY, AuthSession},
    config::LoginOptions,
    templates::{PageId, filters, helpers::user_initials},
    types::site::SiteSettings,
};

// Pages and sections templates.

/// Template for the log in page.
#[derive(Debug, Clone, Template)]
#[template(path = "auth/log_in.html")]
pub(crate) struct LogInPage {
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: UserMenuState,

    /// Next URL to redirect to after login, if any.
    pub next_url: Option<String>,
}

/// Template for the sign up page.
#[derive(Debug, Clone, Template)]
#[template(path = "auth/sign_up.html")]
pub(crate) struct SignUpPage {
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: UserMenuState,

    /// Next URL to redirect to after sign up, if any.
    pub next_url: Option<String>,
}

/// Template for the update user page.
#[derive(Debug, Clone, Template)]
#[template(path = "auth/update_user.html")]
pub(crate) struct UpdateUserPage {
    /// Whether the user has a password set.
    pub has_password: bool,
    /// List of available timezones.
    pub timezones: Vec<String>,
    /// User details to be updated.
    pub user: UserDetailsInput,
}

/// Template for the user menu section.
#[derive(Debug, Clone, Template)]
#[template(path = "auth/user_menu_section.html")]
pub(crate) struct UserMenuSection {
    /// Authenticated user information.
    pub user: UserMenuState,
}

// Types.

/// User menu view state derived from the session (login, profile completion,
/// and team membership flags).
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct UserMenuState {
    /// Whether the user is logged in.
    pub logged_in: bool,
    /// Whether the logged-in user has completed their profile.
    pub profile_complete: bool,

    /// Name of the authentication provider, if any.
    pub auth_provider: Option<String>,
    /// Whether the user belongs to any group team.
    pub belongs_to_any_group_team: Option<bool>,
    /// Whether the user belongs to their community team.
    pub belongs_to_community_team: Option<bool>,
    /// Display name of the user, if any.
    pub name: Option<String>,
    /// Username, if any.
    pub username: Option<String>,
}

impl UserMenuState {
    /// Build the user menu state from the current `AuthSession`.
    pub(crate) async fn from_session(auth_session: AuthSession) -> Result<Self> {
        let auth_session_user = auth_session.user.as_ref();
        let user = Self {
            logged_in: auth_session_user.is_some(),
            profile_complete: auth_session_user.is_some_and(crate::auth::User::is_profile_complete),
            auth_provider: auth_session.session.get(AUTH_PROVIDER_KEY).await?,
            belongs_to_any_group_team: auth_session_user.and_then(|u| u.belongs_to_any_group_team),
            belongs_to_community_team: auth_session_user.and_then(|u| u.belongs_to_community_team),
            name: auth_session_user.map(|u| u.name.clone()),
            username: auth_session_user.map(|u| u.username.clone()),
        };
        Ok(user)
    }
}
