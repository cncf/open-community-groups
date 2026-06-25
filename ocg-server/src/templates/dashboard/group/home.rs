//! Templates and types for the group dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::User,
        dashboard::{
            audit,
            group::{analytics, events, members, settings, sponsors, spotlights, team},
        },
        filters,
        helpers::user_initials,
    },
    types::{alliance::AllianceSummary, group::GroupMinimal, site::SiteSettings},
};

/// Home page template for the group dashboard.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/home.html")]
pub(crate) struct Page {
    /// Main content section for the page.
    pub content: Content,
    /// Groups organized by alliance.
    pub groups_by_alliance: Vec<UserGroupsByAlliance>,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Currently selected alliance ID.
    pub selected_alliance_id: Uuid,
    /// Currently selected group ID.
    pub selected_group_id: Uuid,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

impl Page {
    /// Returns all alliances the user has access to.
    fn alliances(&self) -> Vec<&AllianceSummary> {
        self.groups_by_alliance.iter().map(|c| &c.alliance).collect()
    }

    /// Returns the selected alliance and group details.
    fn current_selection_details(&self) -> (&AllianceSummary, &GroupMinimal) {
        let selected_alliance = self
            .groups_by_alliance
            .iter()
            .find(|c| c.alliance.alliance_id == self.selected_alliance_id)
            .expect("selected alliance exists");
        let selected_group = selected_alliance
            .groups
            .iter()
            .find(|g| g.group_id == self.selected_group_id)
            .expect("selected group exists");

        (&selected_alliance.alliance, selected_group)
    }

    /// Returns groups for the currently selected alliance.
    fn selected_alliance_groups(&self) -> &[GroupMinimal] {
        self.groups_by_alliance
            .iter()
            .find(|c| c.alliance.alliance_id == self.selected_alliance_id)
            .map_or(&[], |c| c.groups.as_slice())
    }
}

/// Content section for the group dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Analytics page.
    Analytics(Box<analytics::Page>),
    /// Events management page.
    Events(Box<events::ListPage>),
    /// Audit logs page.
    Logs(audit::ListPage),
    /// Members list page.
    Members(members::ListPage),
    /// Settings management page.
    Settings(Box<settings::UpdatePage>),
    /// Sponsors management page.
    Sponsors(sponsors::ListPage),
    /// Member spotlight management page.
    Spotlights(spotlights::ListPage),
    /// Team management page.
    Team(team::ListPage),
}

impl Content {
    /// Check if the content is the analytics page.
    fn is_analytics(&self) -> bool {
        matches!(self, Content::Analytics(_))
    }

    /// Check if the content is the events page.
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }

    /// Check if the content is the logs page.
    fn is_logs(&self) -> bool {
        matches!(self, Content::Logs(_))
    }

    /// Check if the content is the members page.
    fn is_members(&self) -> bool {
        matches!(self, Content::Members(_))
    }

    /// Check if the content is the settings page.
    fn is_settings(&self) -> bool {
        matches!(self, Content::Settings(_))
    }

    /// Check if the content is the sponsors page.
    fn is_sponsors(&self) -> bool {
        matches!(self, Content::Sponsors(_))
    }

    /// Check if the content is the spotlights page.
    fn is_spotlights(&self) -> bool {
        matches!(self, Content::Spotlights(_))
    }

    /// Check if the content is the team page.
    fn is_team(&self) -> bool {
        matches!(self, Content::Team(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Analytics(template) => write!(f, "{}", template.render()?),
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Logs(template) => write!(f, "{}", template.render()?),
            Content::Members(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
            Content::Sponsors(template) => write!(f, "{}", template.render()?),
            Content::Spotlights(template) => write!(f, "{}", template.render()?),
            Content::Team(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the group dashboard home page.
#[derive(
    Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// Analytics tab (default).
    #[default]
    Analytics,
    /// Events management tab.
    Events,
    /// Audit logs tab.
    Logs,
    /// Members list tab.
    Members,
    /// Settings management tab.
    Settings,
    /// Sponsors management tab.
    Sponsors,
    /// Member spotlight management tab.
    Spotlights,
    /// Team management tab.
    Team,
}

// Types.

/// Groups organized by alliance, used for displaying user's groups in dashboard.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserGroupsByAlliance {
    /// Alliance information.
    pub alliance: AllianceSummary,
    /// Groups belonging to this alliance.
    pub groups: Vec<GroupMinimal>,
}
