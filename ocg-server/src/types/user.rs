//! Shared user types used across the application.

use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

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
    /// LinkedIn metadata.
    pub linkedin: Option<LinkedInUserProvider>,
}

impl UserProvider {
    /// Build provider metadata for a GitHub account.
    pub(crate) fn from_github_username(username: String) -> Self {
        Self {
            github: Some(GitHubUserProvider { username }),
            linkedin: None,
        }
    }

    /// Build provider metadata for a LinkedIn account.
    pub(crate) fn from_linkedin_subject(subject: String) -> Self {
        Self {
            github: None,
            linkedin: Some(LinkedInUserProvider { subject }),
        }
    }

    /// Merge another provider payload into this one.
    pub(crate) fn merge(&mut self, other: Self) {
        if let Some(github) = other.github {
            self.github = Some(github);
        }
        if let Some(linkedin) = other.linkedin {
            self.linkedin = Some(linkedin);
        }
    }
}

/// GitHub-specific user metadata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct GitHubUserProvider {
    /// Username on GitHub.
    pub username: String,
}

/// LinkedIn-specific user metadata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct LinkedInUserProvider {
    /// Stable LinkedIn OIDC subject identifier.
    pub subject: String,
}
