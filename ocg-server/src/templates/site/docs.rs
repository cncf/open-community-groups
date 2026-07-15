//! Templates for the public docs page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
};

/// Public docs page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/docs/page.html")]
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
    /// Rendered Markdown document content.
    pub content_html: String,
}
