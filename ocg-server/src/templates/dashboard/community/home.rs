//! Templates for the community dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::User,
        dashboard::community::{analytics, groups, settings, team},
        filters,
        helpers::user_initials,
    },
    types::{community::Community, site::SiteSettings},
};

/// Home page template for the community dashboard.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/home.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Option<Community>,
    /// Main content section for the page.
    pub content: Content,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Content section for the community dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Analytics page.
    Analytics(Box<analytics::Page>),
    /// Groups management page.
    Groups(groups::ListPage),
    /// Settings page.
    Settings(Box<settings::UpdatePage>),
    /// Team management page.
    Team(team::ListPage),
}

impl Content {
    /// Check if the content is the analytics page.
    #[allow(dead_code)]
    fn is_analytics(&self) -> bool {
        matches!(self, Content::Analytics(_))
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
            Content::Analytics(template) => write!(f, "{}", template.render()?),
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
    /// Analytics tab (default).
    #[default]
    Analytics,
    /// Groups management tab.
    Groups,
    /// Settings tab.
    Settings,
    /// Team management tab.
    Team,
}
