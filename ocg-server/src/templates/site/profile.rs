//! Templates for shareable public profile cards.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::User,
        filters,
        helpers::{self, user_initials},
    },
    types::{site::SiteSettings, user::PublicUserProfile},
    validation::{MAX_LEN_DESCRIPTION_SHORT, trimmed_non_empty},
};

/// Shareable user profile card page.
#[derive(Debug, Clone, Template)]
#[template(path = "site/profile.html")]
pub(crate) struct Page {
    /// Configured public base URL.
    pub base_url: String,
    /// Current path.
    pub path: String,
    /// Page identifier.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Public user profile.
    pub profile: PublicUserProfile,
    /// Whether a mentorship request was just submitted.
    pub mentorship_request_sent: bool,
    /// Whether a coffee request was just submitted.
    pub coffee_request_sent: bool,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

impl Page {
    /// Canonical URL for the profile card.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(
            &self.base_url,
            &format!("/profiles/{}", self.profile.username),
        )
    }

    /// Preview title for social shares.
    pub(crate) fn preview_title(&self) -> String {
        format!(
            "{} on GOUP",
            self.profile.name.as_deref().unwrap_or(&self.profile.username)
        )
    }

    /// Preview description without exposing private email.
    pub(crate) fn preview_description(&self) -> String {
        let mut parts = Vec::new();
        if let Some(title) = self.profile.title.as_deref() {
            parts.push(title);
        }
        if let Some(company) = self.profile.company.as_deref() {
            parts.push(company);
        }
        if parts.is_empty() {
            return self
                .profile
                .bio
                .clone()
                .unwrap_or_else(|| "A GOUP community member profile.".to_string());
        }
        parts.join(" at ")
    }

    /// `OpenGraph` image URL for the profile.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.profile
            .photo_url
            .as_deref()
            .or(self.site_settings.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }
}

/// `CoffeeMeet` request form input.
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub(crate) struct CoffeeMeetRequestInput {
    /// Request details.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub message: String,
}

/// Stored `CoffeeMeet` request metadata returned from the database.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct CoffeeMeetRequestRecord {
    /// Request identifier.
    pub coffee_meet_request_id: Uuid,
    /// Recipient user identifier.
    pub recipient_user_id: Uuid,
    /// Recipient email address.
    pub recipient_email: String,
    /// Recipient username.
    pub recipient_username: String,
    /// Recipient display name.
    pub recipient_name: Option<String>,
    /// Requester user identifier.
    pub requester_user_id: Uuid,
    /// Requester email address.
    pub requester_email: String,
    /// Requester username.
    pub requester_username: String,
    /// Requester display name.
    pub requester_name: Option<String>,
    /// Request details.
    pub message: String,
    /// Total requests received by this member.
    pub request_count: i32,
}

impl CoffeeMeetRequestRecord {
    /// Recipient display label.
    pub(crate) fn recipient_label(&self) -> &str {
        self.recipient_name.as_deref().unwrap_or(&self.recipient_username)
    }

    /// Requester display label.
    pub(crate) fn requester_label(&self) -> &str {
        self.requester_name.as_deref().unwrap_or(&self.requester_username)
    }
}

/// Mentorship request form input.
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub(crate) struct MentorshipRequestInput {
    /// Whether this is for an individual or business.
    #[garde(custom(valid_audience_type))]
    pub audience_type: String,
    /// Request details.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub message: String,
}

/// Stored mentorship request metadata returned from the database.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct MentorshipRequestRecord {
    /// Request identifier.
    pub mentorship_request_id: Uuid,
    /// Mentor user identifier.
    pub mentor_user_id: Uuid,
    /// Mentor email address.
    pub mentor_email: String,
    /// Mentor username.
    pub mentor_username: String,
    /// Mentor display name.
    pub mentor_name: Option<String>,
    /// Mentor's listed mentorship price, if configured.
    pub mentor_price: Option<String>,
    /// Requester user identifier.
    pub requester_user_id: Uuid,
    /// Requester email address.
    pub requester_email: String,
    /// Requester username.
    pub requester_username: String,
    /// Requester display name.
    pub requester_name: Option<String>,
    /// Whether this is for an individual or business.
    pub audience_type: String,
    /// Request details.
    pub message: String,
    /// Total requests received by this mentor.
    pub request_count: i32,
}

impl MentorshipRequestRecord {
    /// Mentor display label.
    pub(crate) fn mentor_label(&self) -> &str {
        self.mentor_name.as_deref().unwrap_or(&self.mentor_username)
    }

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

#[allow(clippy::trivially_copy_pass_by_ref)]
fn valid_audience_type(value: &str, _ctx: &()) -> garde::Result {
    if matches!(value, "individual" | "business") {
        Ok(())
    } else {
        Err(garde::Error::new("invalid mentorship request type"))
    }
}
