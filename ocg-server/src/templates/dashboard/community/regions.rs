//! Templates for managing regions in the community dashboard.

use askama::Template;

use crate::types::group::GroupRegion;

// Pages templates.

/// Regions list page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/regions_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage taxonomy.
    pub can_manage_taxonomy: bool,
    /// Regions available in the selected community.
    pub regions: Vec<GroupRegion>,
}

/// Region add form template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/regions_add.html")]
pub(crate) struct AddPage;

/// Region update form template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/regions_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage taxonomy.
    pub can_manage_taxonomy: bool,
    /// Region currently being edited.
    pub region: GroupRegion,
}
