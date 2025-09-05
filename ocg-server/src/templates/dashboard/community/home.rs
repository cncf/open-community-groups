//! Templates for the community dashboard home page.

use askama::Template;
use axum_messages::Message;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::{self, User},
        dashboard::community::{groups, settings, team},
        filters,
    },
    types::community::Community,
};

/// Home page template for the community dashboard.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/home.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Main content section for the page.
    pub content: Content,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Authenticated user information.
    pub user: User,
}

/// Content section for the community dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// User account page.
    Account(Box<auth::UpdateUserPage>),
    /// Groups management page.
    Groups(groups::ListPage),
    /// Settings page.
    Settings(Box<settings::UpdatePage>),
    /// Team management page.
    Team(team::ListPage),
}

impl Content {
    /// Check if the content is the account page.
    #[allow(dead_code)]
    fn is_account(&self) -> bool {
        matches!(self, Content::Account(_))
    }

    /// Check if the content is the groups page.
    #[allow(dead_code)]
    fn is_groups(&self) -> bool {
        matches!(self, Content::Groups(_))
    }

    /// Check if the content is the settings page.
    #[allow(dead_code)]
    fn is_settings(&self) -> bool {
        matches!(self, Content::Settings(_))
    }

    /// Check if the content is the team page.
    #[allow(dead_code)]
    fn is_team(&self) -> bool {
        matches!(self, Content::Team(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Account(template) => write!(f, "{}", template.render()?),
            Content::Groups(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
            Content::Team(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the community dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// User account tab.
    Account,
    /// Groups management tab (default).
    #[default]
    Groups,
    /// Settings tab.
    Settings,
    /// Team management tab.
    Team,
}
