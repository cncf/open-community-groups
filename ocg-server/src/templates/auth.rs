//! Templates and types for authentication-related pages and user info.

use anyhow::Result;
use askama::Template;
use axum_messages::Message;
use serde::{Deserialize, Serialize};

use crate::{
    auth::AuthSession, config::LoginOptions, handlers::auth::AUTH_PROVIDER_KEY, templates::PageId,
    types::community::Community,
};

// Pages and sections templates.

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
    /// User details to be updated.
    pub user: UserDetails,
}

/// Template for the user menu section.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/user_menu_section.html")]
pub(crate) struct UserMenuSection {
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
    /// Whether the user belongs to any group team.
    pub belongs_to_any_group_team: Option<bool>,
    /// Whether the user belongs to their community team.
    pub belongs_to_community_team: Option<bool>,
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
            belongs_to_any_group_team: auth_session_user.and_then(|u| u.belongs_to_any_group_team),
            belongs_to_community_team: auth_session_user.and_then(|u| u.belongs_to_community_team),
            name: auth_session_user.map(|u| u.name.clone()),
            username: auth_session_user.map(|u| u.username.clone()),
        };
        Ok(user)
    }
}

/// User details that can be updated.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserDetails {
    /// User's display name.
    pub name: String,

    /// User's biography.
    pub bio: Option<String>,
    /// User's city.
    pub city: Option<String>,
    /// User's company.
    pub company: Option<String>,
    /// User's country.
    pub country: Option<String>,
    /// User's Facebook URL.
    pub facebook_url: Option<String>,
    /// User's interests.
    pub interests: Option<Vec<String>>,
    /// User's `LinkedIn` URL.
    pub linkedin_url: Option<String>,
    /// User's photo URL.
    pub photo_url: Option<String>,
    /// User's timezone.
    pub timezone: Option<String>,
    /// User's title.
    pub title: Option<String>,
    /// User's Twitter URL.
    pub twitter_url: Option<String>,
    /// User's website URL.
    pub website_url: Option<String>,
}

impl From<crate::auth::User> for UserDetails {
    fn from(user: crate::auth::User) -> Self {
        Self {
            name: user.name,
            bio: user.bio,
            city: user.city,
            company: user.company,
            country: user.country,
            facebook_url: user.facebook_url,
            interests: user.interests,
            linkedin_url: user.linkedin_url,
            photo_url: user.photo_url,
            timezone: user.timezone,
            title: user.title,
            twitter_url: user.twitter_url,
            website_url: user.website_url,
        }
    }
}

/// Input for updating a user's password.
#[derive(Clone, Serialize, Deserialize)]
pub(crate) struct UserPassword {
    /// The new password to set.
    pub new_password: String,
    /// The user's current password.
    pub old_password: String,
}
