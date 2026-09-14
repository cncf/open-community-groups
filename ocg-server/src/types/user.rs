//! Shared user types used across the application.

use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::validation::{
    MAX_LEN_BIO, MAX_LEN_DISPLAY_NAME, MAX_LEN_L, MAX_LEN_M, MAX_LEN_S, MAX_LEN_TIMEZONE,
    MIN_PASSWORD_LEN, image_url_opt, trimmed_non_empty, trimmed_non_empty_opt,
    trimmed_non_empty_tag_vec, web_url_opt,
};

/// Full user information.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct User {
    /// Unique identifier for the user.
    pub user_id: Uuid,
    /// User's username.
    pub username: String,

    /// Short biography.
    pub bio: Option<String>,
    /// Bluesky profile URL.
    pub bluesky_url: Option<String>,
    /// Company the user works for.
    pub company: Option<String>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// GitHub profile URL.
    pub github_url: Option<String>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// User's name.
    pub name: Option<String>,
    /// URL to the user's profile photo.
    pub photo_url: Option<String>,
    /// External provider metadata.
    pub provider: Option<UserProvider>,
    /// User's job title.
    pub title: Option<String>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Personal website URL.
    pub website_url: Option<String>,
}

/// Summary user information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct UserSummary {
    /// User identifier.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// External provider metadata.
    pub provider: Option<UserProvider>,
    /// Title held by the user.
    pub title: Option<String>,
}

/// External provider metadata associated with a user.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct UserProvider {
    /// GitHub metadata.
    pub github: Option<GitHubUserProvider>,
    /// Linux Foundation SSO metadata.
    pub linuxfoundation: Option<LinuxFoundationUserProvider>,
}

impl UserProvider {
    /// Build provider metadata for a GitHub account.
    pub(crate) fn from_github_username(username: String) -> Self {
        Self {
            github: Some(GitHubUserProvider { username }),
            linuxfoundation: None,
        }
    }

    /// Build provider metadata for a Linux Foundation OIDC identity.
    pub(crate) fn from_linuxfoundation_identity(
        issuer: String,
        subject: String,
        username: String,
    ) -> Self {
        Self {
            github: None,
            linuxfoundation: Some(LinuxFoundationUserProvider {
                username,

                issuer: Some(issuer),
                subject: Some(subject),
            }),
        }
    }

    /// Merge another provider payload into this one.
    pub(crate) fn merge(&mut self, other: Self) {
        if let Some(github) = other.github {
            self.github = Some(github);
        }
        if let Some(linuxfoundation) = other.linuxfoundation {
            self.linuxfoundation = Some(linuxfoundation);
        }
    }
}

/// GitHub-specific user metadata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct GitHubUserProvider {
    /// Username on GitHub.
    pub username: String,
}

/// Linux Foundation-specific user metadata.
#[skip_serializing_none]
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct LinuxFoundationUserProvider {
    /// Username on Linux Foundation SSO.
    pub username: String,

    /// OIDC issuer for the Linux Foundation SSO account.
    pub issuer: Option<String>,
    /// OIDC subject for the Linux Foundation SSO account.
    pub subject: Option<String>,
}

/// User details that can be updated.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct UserDetailsInput {
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
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub bluesky_url: Option<String>,
    /// User's city.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub city: Option<String>,
    /// User's company.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub company: Option<String>,
    /// User's country.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub country: Option<String>,
    /// User's Facebook URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// User's GitHub URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// User's interests.
    #[garde(custom(trimmed_non_empty_tag_vec))]
    pub interests: Option<Vec<String>>,
    /// User's `LinkedIn` URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// User's photo URL.
    #[garde(custom(image_url_opt))]
    pub photo_url: Option<String>,
    /// User's timezone.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_TIMEZONE))]
    pub timezone: Option<String>,
    /// User's title.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub title: Option<String>,
    /// User's Twitter URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// User's website URL.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
}

impl From<crate::auth::User> for UserDetailsInput {
    fn from(user: crate::auth::User) -> Self {
        Self {
            name: user.name,
            optional_notifications_enabled: user.optional_notifications_enabled,
            bio: user.bio,
            bluesky_url: user.bluesky_url,
            city: user.city,
            company: user.company,
            country: user.country,
            facebook_url: user.facebook_url,
            github_url: user.github_url,
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
#[derive(Clone, Serialize, Deserialize, Validate)]
pub(crate) struct UserPasswordInput {
    /// The new password to set.
    #[garde(length(min = MIN_PASSWORD_LEN, max = MAX_LEN_S))]
    pub new_password: String,
    /// The user's current password.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub old_password: String,
}
