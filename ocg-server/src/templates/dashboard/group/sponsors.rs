//! Templates and types for managing sponsors in the group dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::group::GroupSponsor,
    validation::{MAX_LEN_L, MAX_LEN_M, image_url, trimmed_non_empty},
};

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
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct Sponsor {
    /// URL to sponsor logo.
    #[garde(custom(image_url))]
    pub logo_url: String,
    /// Sponsor name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub name: String,

    /// Sponsor website URL.
    #[garde(url, length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
}
