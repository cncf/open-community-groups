//! Common types used across multiple template modules.

use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

/// This struct represents basic user profile information that can be displayed
/// throughout the application.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct User {
    /// Unique identifier for the user.
    #[serde(rename = "user_id")]
    pub id: Uuid,

    /// User's first name.
    pub first_name: Option<String>,
    /// User's last name.
    pub last_name: Option<String>,
    /// Company the user works for.
    pub company: Option<String>,
    /// User's job title.
    pub title: Option<String>,
    /// URL to the user's profile photo.
    pub photo_url: Option<String>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Personal website URL.
    pub website_url: Option<String>,
}
