//! Templates for the group dashboard home page.

use askama::Template;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::{self, User},
        dashboard::group::{attendees, events, members, settings, team},
        filters,
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
    /// Authenticated user information.
    pub user: User,
}

/// Content section for the group dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// User account page.
    Account(Box<auth::UpdateUserPage>),
    /// Attendees list page.
    Attendees(attendees::ListPage),
    /// Events management page.
    Events(events::ListPage),
    /// Members list page.
    Members(members::ListPage),
    /// Settings management page.
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

    /// Check if the content is the attendees page.
    #[allow(dead_code)]
    fn is_attendees(&self) -> bool {
        matches!(self, Content::Attendees(_))
    }

    /// Check if the content is the events page.
    #[allow(dead_code)]
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }

    /// Check if the content is the members page.
    #[allow(dead_code)]
    fn is_members(&self) -> bool {
        matches!(self, Content::Members(_))
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
            Content::Attendees(template) => write!(f, "{}", template.render()?),
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Members(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
            Content::Team(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the group dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// User account tab.
    Account,
    /// Attendees list tab.
    Attendees,
    /// Events management tab (default).
    #[default]
    Events,
    /// Members list tab.
    Members,
    /// Settings management tab.
    Settings,
    /// Team management tab.
    Team,
}
