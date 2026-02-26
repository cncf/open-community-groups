//! Templates and types for managing regions in the community dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    types::group::GroupRegion,
    validation::{MAX_LEN_ENTITY_NAME, trimmed_non_empty},
};

// Pages templates.

/// Regions list page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/regions_list.html")]
pub(crate) struct ListPage {
    /// Regions available in the selected community.
    pub regions: Vec<GroupRegion>,
}

/// Region add form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/regions_add.html")]
pub(crate) struct AddPage;

/// Region update form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/regions_update.html")]
pub(crate) struct UpdatePage {
    /// Region currently being edited.
    pub region: GroupRegion,
}

// Types.

/// Region form payload used by create and update operations.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct RegionInput {
    /// Region name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
}
