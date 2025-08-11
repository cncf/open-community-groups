//! Templates for the group dashboard home page.

use askama::Template;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{templates::dashboard::group, types::community::Community};

/// Home page template for the group dashboard.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/home.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Current request path.
    pub path: String,
    /// Group identifier.
    pub group_id: Uuid,
    /// Group name.
    pub group_name: String,
    /// Main content section for the page.
    pub content: Content,
}

/// Content section for the group dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Events management page.
    Events(group::EventsPage),
}

impl Content {
    /// Check if the content is the events page.
    #[allow(dead_code)]
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Events(template) => write!(f, "{}", template.render()?),
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
}
