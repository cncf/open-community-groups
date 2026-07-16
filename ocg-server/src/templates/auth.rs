//! Templates and types for authentication-related pages and user info.

use anyhow::Result;
use askama::Template;
use axum_messages::Message;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::{
    auth::AuthSession,
    config::LoginOptions,
    handlers::auth::AUTH_PROVIDER_KEY,
    templates::{PageId, filters, helpers::user_initials},
    types::site::SiteSettings,
    validation::{
        MAX_LEN_BIO, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_DISPLAY_NAME, MAX_LEN_L, MAX_LEN_M,
        MAX_LEN_PHONE_COUNTRY_CODE, MAX_LEN_PHONE_NUMBER, MAX_LEN_S, MAX_LEN_TIMEZONE,
        MIN_PASSWORD_LEN, image_url_opt, trimmed_non_empty, trimmed_non_empty_opt,
        trimmed_non_empty_tag_vec,
    },
};

// Pages and sections templates.

/// Template for the log in page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/log_in.html")]
pub(crate) struct LogInPage {
    /// Login options.
    pub login: LoginOptions,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,

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
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,

    /// Next URL to redirect to after sign up, if any.
    pub next_url: Option<String>,
}

/// Template for the update user page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/update_user.html")]
pub(crate) struct UpdateUserPage {
    /// Whether the user has a password set.
    pub has_password: bool,
    /// List of available timezones.
    pub timezones: Vec<String>,
    /// User details to be updated.
    pub user: UserDetails,
}

/// Template for the user menu section.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "auth/user_menu_section.html")]
pub(crate) struct UserMenuSection {
    /// Authenticated user information.
    pub user: User,
    /// Count of pending actions for the notification bell.
    pub notification_count: i64,
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
    /// Whether the user belongs to their alliance team.
    pub belongs_to_alliance_team: Option<bool>,
    /// Display name of the user, if any.
    pub name: Option<String>,
    /// Whether the user can manage platform-level resources.
    pub platform_admin: bool,
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
            belongs_to_alliance_team: auth_session_user.and_then(|u| u.belongs_to_alliance_team),
            name: auth_session_user.map(|u| u.name.clone()),
            platform_admin: auth_session_user.is_some_and(|u| u.platform_admin),
            username: auth_session_user.map(|u| u.username.clone()),
        };
        Ok(user)
    }
}

/// User details that can be updated.
#[skip_serializing_none]
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct UserDetails {
    /// User's display name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DISPLAY_NAME))]
    pub name: String,
    /// Whether the user receives optional notifications.
    #[garde(skip)]
    pub optional_notifications_enabled: bool,

    /// User's biography.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_BIO))]
    pub bio: Option<String>,
    /// User's Bluesky URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub bluesky_url: Option<String>,
    /// Whether the user privately opts into book exchange.
    #[serde(default)]
    #[garde(skip)]
    pub book_exchange_enabled: bool,
    /// Private book list visible only to eligible community admins.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub book_exchange_books: Option<String>,
    /// User's city.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub city: Option<String>,
    /// Whether the user accepts direct `CoffeeMeet` requests.
    #[serde(default = "default_true")]
    #[garde(skip)]
    pub coffee_meet_enabled: bool,
    /// User's company.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub company: Option<String>,
    /// User's country.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub country: Option<String>,
    /// User's Facebook URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// User's GitHub URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// User's interests.
    #[garde(custom(trimmed_non_empty_tag_vec))]
    pub interests: Option<Vec<String>>,
    /// Whether the user privately opts into intentional dating introductions.
    #[serde(default)]
    #[garde(skip)]
    pub intentional_dating_enabled: bool,
    /// Private dating goals visible only to eligible community admins.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub intentional_dating_goals: Option<String>,
    /// Private dating preferences visible only to eligible community admins.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub intentional_dating_preferences: Option<String>,
    /// User's `LinkedIn` URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// Whether the user offers mentorship services for businesses.
    #[serde(default)]
    #[garde(skip)]
    pub mentorship_businesses: bool,
    /// Whether the user offers mentorship services for individuals.
    #[serde(default)]
    #[garde(skip)]
    pub mentorship_individuals: bool,
    /// Optional description of the user's mentorship offering.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub mentorship_note: Option<String>,
    /// Optional price or pricing guidance for mentorship.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub mentorship_price: Option<String>,
    /// Whether the user authenticated with `LinkedIn`.
    #[serde(default)]
    #[garde(skip)]
    pub linkedin_connected: bool,
    /// User's photo URL.
    #[garde(custom(image_url_opt))]
    pub photo_url: Option<String>,
    /// International calling code for the user's phone number.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_PHONE_COUNTRY_CODE))]
    pub phone_country_code: Option<String>,
    /// User's phone number.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_PHONE_NUMBER))]
    pub phone_number: Option<String>,
    /// User's `Substack` URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub substack_url: Option<String>,
    /// User's timezone.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_TIMEZONE))]
    pub timezone: Option<String>,
    /// User's title.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub title: Option<String>,
    /// User's Twitter URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// User's website URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
    /// User's `YouTube` URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub youtube_url: Option<String>,
}

fn default_true() -> bool {
    true
}

impl From<crate::auth::User> for UserDetails {
    fn from(user: crate::auth::User) -> Self {
        Self {
            name: user.name,
            optional_notifications_enabled: user.optional_notifications_enabled,
            bio: user.bio,
            bluesky_url: user.bluesky_url,
            book_exchange_enabled: user.book_exchange_enabled,
            book_exchange_books: user.book_exchange_books,
            city: user.city,
            coffee_meet_enabled: user.coffee_meet_enabled,
            company: user.company,
            country: user.country,
            facebook_url: user.facebook_url,
            github_url: user.github_url,
            interests: user.interests,
            intentional_dating_enabled: user.intentional_dating_enabled,
            intentional_dating_goals: user.intentional_dating_goals,
            intentional_dating_preferences: user.intentional_dating_preferences,
            linkedin_connected: user
                .provider
                .as_ref()
                .and_then(|provider| provider.linkedin.as_ref())
                .is_some(),
            linkedin_url: user.linkedin_url,
            mentorship_businesses: user.mentorship_businesses,
            mentorship_individuals: user.mentorship_individuals,
            mentorship_note: user.mentorship_note,
            mentorship_price: user.mentorship_price,
            photo_url: user.photo_url,
            phone_country_code: user.phone_country_code,
            phone_number: user.phone_number,
            substack_url: user.substack_url,
            timezone: user.timezone,
            title: user.title,
            twitter_url: user.twitter_url,
            website_url: user.website_url,
            youtube_url: user.youtube_url,
        }
    }
}

/// Input for updating a user's password.
#[derive(Clone, Serialize, Deserialize, Validate)]
pub(crate) struct UserPassword {
    /// The new password to set.
    #[garde(length(min = MIN_PASSWORD_LEN, max = MAX_LEN_S))]
    pub new_password: String,
    /// The user's current password.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub old_password: String,
}
