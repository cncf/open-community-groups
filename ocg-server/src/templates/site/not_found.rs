//! Templates for the global site not found page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::site::SiteSettings,
};

// Pages templates.

/// Template for rendering the not found page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/not_found/page.html")]
pub(crate) struct Page {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Stable path used by the shared base and header templates.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}
