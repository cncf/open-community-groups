//! Templates for managing event categories in the community dashboard.

use askama::Template;

use crate::types::event::EventCategory;

// Pages templates.

/// Event categories list page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/event_categories_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage taxonomy.
    pub can_manage_taxonomy: bool,
    /// Event categories available in the selected community.
    pub categories: Vec<EventCategory>,
}

/// Event category add form template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/event_categories_add.html")]
pub(crate) struct AddPage;

/// Event category update form template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/event_categories_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage taxonomy.
    pub can_manage_taxonomy: bool,
    /// Event category currently being edited.
    pub category: EventCategory,
}
