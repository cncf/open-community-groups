//! Templates and types for managing sponsors in the group dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::types::group::GroupSponsor;

// Pages templates.

/// Add sponsor page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/sponsors_add.html")]
pub(crate) struct AddPage {
    /// Group identifier.
    pub group_id: Uuid,
}

/// List sponsors page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/sponsors_list.html")]
pub(crate) struct ListPage {
    /// List of sponsors in the group.
    pub sponsors: Vec<GroupSponsor>,
}

/// Update sponsor page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/sponsors_update.html")]
pub(crate) struct UpdatePage {
    /// Group identifier.
    pub group_id: Uuid,
    /// Sponsor information to update.
    pub sponsor: GroupSponsor,
}

// Types.

/// Sponsor input for create/update operations.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Sponsor {
    /// Sponsorship level.
    pub level: String,
    /// URL to sponsor logo.
    pub logo_url: String,
    /// Sponsor name.
    pub name: String,

    /// Sponsor website URL.
    pub website_url: Option<String>,
}
