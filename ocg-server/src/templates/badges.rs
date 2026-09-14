//! Templates for public badge credentials and verification.

use askama::Template;

use crate::{
    templates::filters,
    types::{
        badges::{UserBadge, VerifiedBadge},
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Public credential page.
#[derive(Debug, Clone, Template)]
#[template(path = "badges/credential.html")]
pub struct CredentialPage {
    /// Durable award and immutable credential snapshot.
    pub award: UserBadge,
    /// Public badge image URL.
    pub image_url: String,
    /// Current request path.
    pub path: String,
    /// Whether this credential is permanently revoked.
    pub revoked: bool,
    /// Global site settings.
    pub site_settings: SiteSettings,
}

impl CredentialPage {
    /// Return the badge image as Open Graph metadata when available.
    pub fn open_graph_image_url(&self) -> Option<String> {
        (!self.image_url.is_empty()).then(|| self.image_url.clone())
    }
}

/// Public badge verification page.
#[derive(Debug, Clone, Template)]
#[template(path = "badges/verify.html")]
pub struct VerifyPage {
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,

    /// Generic invalid-result message.
    pub error: Option<String>,
    /// Successful verification result.
    pub verified: Option<VerifiedBadge>,
}
