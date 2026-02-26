//! Templates and types for managing event categories in the community dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    types::event::EventCategory,
    validation::{MAX_LEN_ENTITY_NAME, trimmed_non_empty},
};

// Pages templates.

/// Event categories list page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/event_categories_list.html")]
pub(crate) struct ListPage {
    /// Event categories available in the selected community.
    pub categories: Vec<EventCategory>,
}

/// Event category add form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/event_categories_add.html")]
pub(crate) struct AddPage;

/// Event category update form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/event_categories_update.html")]
pub(crate) struct UpdatePage {
    /// Event category currently being edited.
    pub category: EventCategory,
}

// Types.

/// Event category form payload used by create and update operations.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct EventCategoryInput {
    /// Event category name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
}
