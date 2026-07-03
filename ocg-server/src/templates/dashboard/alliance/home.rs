//! Templates for the alliance dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::User,
        dashboard::{
            alliance::{
                analytics, create, email_templates, event_categories, group_categories, groups,
                landscape, members, regions, settings, team,
            },
            audit,
        },
        filters,
        helpers::user_initials,
    },
    types::{alliance::AllianceSummary, site::SiteSettings},
};

/// Home page template for the alliance dashboard.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/alliance/home.html")]
pub(crate) struct Page {
    /// List of alliances the user is a team member of.
    pub alliances: Vec<AllianceSummary>,
    /// Main content section for the page.
    pub content: Content,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Currently selected alliance ID.
    pub selected_alliance_id: Uuid,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Content section for the alliance dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Analytics page.
    Analytics(Box<analytics::Page>),
    /// Alliance create page.
    CreateAlliance(create::Page),
    /// Email templates page.
    EmailTemplates(Box<email_templates::Page>),
    /// Event categories management page.
    EventCategories(event_categories::ListPage),
    /// Group categories management page.
    GroupCategories(group_categories::ListPage),
    /// Groups management page.
    Groups(groups::ListPage),
    /// Landscape management page.
    Landscape(landscape::ListPage),
    /// Members page across all alliance groups.
    Members(Box<members::ListPage>),
    /// Audit logs page.
    Logs(audit::ListPage),
    /// Regions management page.
    Regions(regions::ListPage),
    /// Settings page.
    Settings(Box<settings::UpdatePage>),
    /// Team management page.
    Team(team::ListPage),
}

impl Content {
    /// Check if the content is the analytics page.
    fn is_analytics(&self) -> bool {
        matches!(self, Content::Analytics(_))
    }

    /// Check if the content is the alliance create page.
    fn is_create_alliance(&self) -> bool {
        matches!(self, Content::CreateAlliance(_))
    }

    /// Check if the content is the email templates page.
    fn is_email_templates(&self) -> bool {
        matches!(self, Content::EmailTemplates(_))
    }

    /// Check if the content is the event categories page.
    fn is_event_categories(&self) -> bool {
        matches!(self, Content::EventCategories(_))
    }

    /// Check if the content is the group categories page.
    fn is_group_categories(&self) -> bool {
        matches!(self, Content::GroupCategories(_))
    }

    /// Check if the content is the groups page.
    fn is_groups(&self) -> bool {
        matches!(self, Content::Groups(_))
    }

    /// Check if the content is the landscape page.
    fn is_landscape(&self) -> bool {
        matches!(self, Content::Landscape(_))
    }

    /// Check if the content is the members page.
    fn is_members(&self) -> bool {
        matches!(self, Content::Members(_))
    }

    /// Check if the content is the logs page.
    fn is_logs(&self) -> bool {
        matches!(self, Content::Logs(_))
    }

    /// Check if the content is the regions page.
    fn is_regions(&self) -> bool {
        matches!(self, Content::Regions(_))
    }

    /// Check if the content is the settings page.
    fn is_settings(&self) -> bool {
        matches!(self, Content::Settings(_))
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
            Content::CreateAlliance(template) => write!(f, "{}", template.render()?),
            Content::EmailTemplates(template) => write!(f, "{}", template.render()?),
            Content::EventCategories(template) => write!(f, "{}", template.render()?),
            Content::GroupCategories(template) => write!(f, "{}", template.render()?),
            Content::Groups(template) => write!(f, "{}", template.render()?),
            Content::Landscape(template) => write!(f, "{}", template.render()?),
            Content::Members(template) => write!(f, "{}", template.render()?),
            Content::Logs(template) => write!(f, "{}", template.render()?),
            Content::Regions(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
            Content::Team(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the alliance dashboard home page.
#[derive(
    Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// Analytics tab (default).
    #[default]
    Analytics,
    /// Alliance create tab.
    CreateAlliance,
    /// Email templates tab.
    EmailTemplates,
    /// Event categories management tab.
    EventCategories,
    /// Group categories management tab.
    GroupCategories,
    /// Groups management tab.
    Groups,
    /// Landscape management tab.
    Landscape,
    /// Members tab across all alliance groups.
    Members,
    /// Audit logs tab.
    Logs,
    /// Regions management tab.
    Regions,
    /// Settings tab.
    Settings,
    /// Team management tab.
    Team,
}
