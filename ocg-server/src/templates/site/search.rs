//! Templates for the public site search page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
};

/// Public site search page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/search/page.html")]
pub(crate) struct Page {
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// User-provided search query.
    pub query: String,
    /// URL-encoded search query for linking into searchable pages.
    pub encoded_query: String,
    /// Categorized search results.
    pub sections: Vec<SearchSection>,
    /// Total matches across all result sections.
    pub total: usize,
}

/// Categorized search results.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct SearchSection {
    /// Section label.
    pub title: String,
    /// Link to continue searching in the source page.
    pub href: String,
    /// Total matches reported by the source.
    pub total: usize,
    /// Result cards.
    pub results: Vec<SearchResult>,
}

/// One search result card.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SearchResult {
    /// Result title.
    pub title: String,
    /// Result URL.
    pub href: String,
    /// Short result context.
    pub summary: String,
    /// Small source/type label.
    pub eyebrow: String,
    /// Whether the link should be boosted by HTMX.
    pub hx_boost: bool,
}
