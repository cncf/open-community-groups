//! Templates for the public sponsor inquiry page.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
    validation::{
        MAX_LEN_DESCRIPTION, MAX_LEN_M, MAX_LEN_S, optional_trimmed_string, trimmed_non_empty,
        trimmed_non_empty_opt,
    },
};

/// Recipient for sponsorship inquiries.
pub(crate) const SPONSOR_INQUIRY_RECIPIENT: &str = "team@goup.vc";

/// Public sponsor inquiry page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/sponsor/page.html")]
pub(crate) struct Page {
    /// Whether the sponsorship inquiry was submitted.
    pub submitted: bool,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Sponsor inquiry form.
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub(crate) struct SponsorInquiry {
    /// Sponsor contact name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub name: String,
    /// Sponsor contact email.
    #[garde(email, length(max = MAX_LEN_M))]
    pub email: String,
    /// Company or organization name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_S))]
    pub company: String,
    /// Optional company website.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub website: Option<String>,
    /// Optional sponsorship budget or range.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    pub budget: Option<String>,
    /// Sponsor inquiry details.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub message: String,
}

impl SponsorInquiry {
    /// Build the outbound email subject.
    pub(crate) fn email_subject(&self) -> String {
        format!("GOUP sponsor inquiry from {}", self.company.trim())
    }

    /// Build the outbound plain text email body.
    pub(crate) fn email_body(&self) -> String {
        format!(
            "\
New GOUP sponsor inquiry

Name: {name}
Email: {email}
Company: {company}
Website: {website}
Budget: {budget}

Message:
{message}
",
            name = self.name.trim(),
            email = self.email.trim(),
            company = self.company.trim(),
            website = self.website.as_deref().unwrap_or("-"),
            budget = self.budget.as_deref().unwrap_or("-"),
            message = self.message.trim(),
        )
    }
}
