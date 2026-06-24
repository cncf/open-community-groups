//! Templates for shareable public profile cards.

use askama::Template;

use crate::{
    templates::{
        PageId,
        auth::User,
        filters,
        helpers::{self, user_initials},
    },
    types::{site::SiteSettings, user::PublicUserProfile},
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
    pub page_id: PageId,
    /// Public user profile.
    pub profile: PublicUserProfile,
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
