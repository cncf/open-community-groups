//! Templates for the community dashboard settings page.

use askama::Template;

use crate::types::community::CommunityFull;

// Pages templates.

/// Update page template for community settings.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage settings.
    pub can_manage_settings: bool,
    /// Community information.
    pub community: CommunityFull,
}
