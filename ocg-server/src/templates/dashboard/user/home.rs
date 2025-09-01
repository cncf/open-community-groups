//! Templates for the user dashboard home page.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::{self, User},
    },
    types::community::Community,
};

/// Home page template for the user dashboard.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/home.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Main content section for the page.
    pub content: Content,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Authenticated user information.
    pub user: User,
}

/// Content section for the user dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// User account page.
    Account(auth::UpdateUserPage),
}

impl Content {
    /// Check if the content is the account page.
    #[allow(dead_code)]
    fn is_account(&self) -> bool {
        matches!(self, Content::Account(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Account(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the user dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// User account tab (default).
    #[default]
    Account,
}
