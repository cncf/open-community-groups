//! Templates for managing group categories in the community dashboard.

use askama::Template;

use crate::types::group::GroupCategory;

// Pages templates.

/// Group categories list page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/group_categories_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage taxonomy.
    pub can_manage_taxonomy: bool,
    /// Group categories available in the selected community.
    pub categories: Vec<GroupCategory>,
}

/// Group category add form template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/group_categories_add.html")]
pub(crate) struct AddPage;

/// Group category update form template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/group_categories_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage taxonomy.
    pub can_manage_taxonomy: bool,
    /// Group category currently being edited.
    pub category: GroupCategory,
}
