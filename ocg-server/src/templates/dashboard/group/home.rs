//! Templates for the group dashboard home page.

use askama::Template;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        dashboard::group::{events, settings},
    },
    types::{community::Community, group::GroupSummary},
};

/// Home page template for the group dashboard.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/home.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Main content section for the page.
    pub content: Content,
    /// List of groups the user belongs to.
    pub groups: Vec<GroupSummary>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Currently selected group ID.
    pub selected_group_id: Uuid,
}

/// Content section for the group dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Events management page.
    Events(events::ListPage),
    /// Settings management page.
    Settings(Box<settings::UpdatePage>),
}

impl Content {
    /// Check if the content is the events page.
    #[allow(dead_code)]
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }

    /// Check if the content is the settings page.
    #[allow(dead_code)]
    fn is_settings(&self) -> bool {
        matches!(self, Content::Settings(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the group dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// Events management tab (default).
    #[default]
    Events,
    /// Settings management tab.
    Settings,
}
