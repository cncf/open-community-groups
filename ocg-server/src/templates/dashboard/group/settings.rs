//! Templates for the group dashboard settings page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::group::GroupFull;

// Pages templates.

/// Update page template for group settings.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Group information.
    pub group: GroupFull,
}

// Types.

/// Group update form data (alias for the Group type from community dashboard).
pub(crate) use crate::templates::dashboard::community::groups::Group as GroupUpdate;
