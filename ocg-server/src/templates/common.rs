//! Common types used across multiple template modules.

use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

// Types.

/// This struct represents basic user profile information that can be displayed
/// throughout the application.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct User {
    /// Unique identifier for the user.
    pub user_id: Uuid,
    /// User's username.
    pub username: String,

    /// Short biography.
    pub bio: Option<String>,
    /// Company the user works for.
    pub company: Option<String>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// User's name.
    pub name: Option<String>,
    /// URL to the user's profile photo.
    pub photo_url: Option<String>,
    /// User's job title.
    pub title: Option<String>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Personal website URL.
    pub website_url: Option<String>,
}
