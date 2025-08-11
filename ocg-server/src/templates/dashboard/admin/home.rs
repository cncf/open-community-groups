//! Templates for the admin dashboard home page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{templates::dashboard::admin, types::community::Community};

/// Home page template for the admin dashboard.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/admin/home.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Current request path.
    pub path: String,
    /// Main content section for the page.
    pub content: Content,
}

/// Content section for the admin dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Groups management page.
    Groups(admin::GroupsPage),
}

impl Content {
    /// Check if the content is the groups page.
    fn is_groups(&self) -> bool {
        matches!(self, Content::Groups(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Groups(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the admin dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// Groups management tab (default).
    #[default]
    Groups,
}
