//! Templates for the global site docs page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
};

/// Template for rendering the global site docs page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/docs/page.html")]
pub struct Page {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}
