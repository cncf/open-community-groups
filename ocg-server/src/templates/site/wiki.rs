//! Templates and types for the public wiki page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
};

/// Public wiki page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/wiki/page.html")]
pub(crate) struct Page {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Wiki sections.
    pub sections: Vec<WikiSection>,
}

/// A topical wiki digest section.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct WikiSection {
    /// Stable section identifier.
    pub id: String,
    /// Display title.
    pub title: String,
    /// Short generated summary.
    pub summary: String,
    /// Source labels used for this section.
    pub sources: Vec<WikiSource>,
    /// Current links.
    pub links: Vec<WikiLink>,
}

/// Source metadata for a wiki section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct WikiSource {
    /// Source label.
    pub label: String,
    /// Source URL.
    pub url: String,
}

/// A source link in a wiki section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct WikiLink {
    /// Link title.
    pub title: String,
    /// Link URL.
    pub url: String,
    /// Source label.
    pub source: String,
}
