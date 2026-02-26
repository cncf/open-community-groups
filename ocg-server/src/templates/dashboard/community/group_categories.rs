//! Templates and types for managing group categories in the community dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    types::group::GroupCategory,
    validation::{MAX_LEN_ENTITY_NAME, trimmed_non_empty},
};

// Pages templates.

/// Group categories list page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/group_categories_list.html")]
pub(crate) struct ListPage {
    /// Group categories available in the selected community.
    pub categories: Vec<GroupCategory>,
}

/// Group category add form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/group_categories_add.html")]
pub(crate) struct AddPage;

/// Group category update form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/group_categories_update.html")]
pub(crate) struct UpdatePage {
    /// Group category currently being edited.
    pub category: GroupCategory,
}

// Types.

/// Group category form payload used by create and update operations.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct GroupCategoryInput {
    /// Group category name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
}
