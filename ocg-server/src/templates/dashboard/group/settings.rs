//! Templates for the group dashboard settings page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::group::{GroupCategory, GroupFull, GroupParentOption, GroupRegion};

// Pages templates.

/// Update page template for group settings.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage settings.
    pub can_manage_settings: bool,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// Group information.
    pub group: GroupFull,
    /// Whether this group has non-deleted child links.
    pub has_child_links: bool,
    /// List of groups that can be selected as parents.
    pub parent_options: Vec<GroupParentOption>,
    /// Whether payments are globally enabled.
    pub payments_enabled: bool,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
}

// Types.

/// Group update form data (alias for the Group type from community dashboard).
pub(crate) use crate::templates::dashboard::community::groups::Group as GroupUpdate;
