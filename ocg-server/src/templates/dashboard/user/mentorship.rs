//! Templates for the user dashboard mentorship requests tab.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// List page showing mentorship requests received by the current user.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/mentorship_list.html")]
pub(crate) struct ListPage {
    /// Total number of received mentorship requests.
    pub total: i64,
    /// Received mentorship request detail rows.
    pub requests: Vec<MentorshipRequest>,
}

/// Mentorship request detail row.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MentorshipRequest {
    /// Request identifier.
    pub mentorship_request_id: Uuid,
    /// Requester user identifier.
    pub requester_user_id: Uuid,
    /// Requester email address.
    pub requester_email: String,
    /// Requester username.
    pub requester_username: String,
    /// Requester display name.
    pub requester_name: Option<String>,
    /// Requester company.
    pub requester_company: Option<String>,
    /// Requester title.
    pub requester_title: Option<String>,
    /// Requester profile photo.
    pub requester_photo_url: Option<String>,
    /// Whether this request is for individual or business mentorship.
    pub audience_type: String,
    /// Request message/details.
    pub message: String,
    /// Request creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

impl MentorshipRequest {
    /// Requester display label.
    pub(crate) fn requester_label(&self) -> &str {
        self.requester_name.as_deref().unwrap_or(&self.requester_username)
    }

    /// Audience display label.
    pub(crate) fn audience_label(&self) -> &'static str {
        match self.audience_type.as_str() {
            "business" => "Business",
            _ => "Individual",
        }
    }
}
