//! Templates and types for the group dashboard home page.

use anyhow::Result;
use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::User,
        dashboard::group::{analytics, attendees, events, members, settings, sponsors, team},
        filters,
        helpers::{color, user_initials},
    },
    types::{community::CommunitySummary, group::GroupSummary, site::SiteSettings},
};

/// Home page template for the group dashboard.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/home.html")]
pub(crate) struct Page {
    /// Main content section for the page.
    pub content: Content,
    /// Groups organized by community.
    pub groups_by_community: Vec<UserGroupsByCommunity>,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Currently selected community ID.
    pub selected_community_id: Uuid,
    /// Currently selected group ID.
    pub selected_group_id: Uuid,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

impl Page {
    /// Returns groups for the currently selected community.
    fn selected_community_groups(&self) -> &[GroupSummary] {
        self.groups_by_community
            .iter()
            .find(|c| c.community.community_id == self.selected_community_id)
            .map_or(&[], |c| c.groups.as_slice())
    }
}

/// Content section for the group dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// Analytics page.
    Analytics(Box<analytics::Page>),
    /// Attendees list page.
    Attendees(Box<attendees::ListPage>),
    /// Events management page.
    Events(events::ListPage),
    /// Members list page.
    Members(members::ListPage),
    /// Settings management page.
    Settings(Box<settings::UpdatePage>),
    /// Sponsors management page.
    Sponsors(sponsors::ListPage),
    /// Team management page.
    Team(team::ListPage),
}

impl Content {
    /// Check if the content is the analytics page.
    #[allow(dead_code)]
    fn is_analytics(&self) -> bool {
        matches!(self, Content::Analytics(_))
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

    /// Check if the content is the sponsors page.
    #[allow(dead_code)]
    fn is_sponsors(&self) -> bool {
        matches!(self, Content::Sponsors(_))
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
            Content::Attendees(template) => write!(f, "{}", template.render()?),
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Members(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
            Content::Sponsors(template) => write!(f, "{}", template.render()?),
            Content::Team(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the group dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// Analytics tab (default).
    #[default]
    Analytics,
    /// Attendees list tab.
    Attendees,
    /// Events management tab.
    Events,
    /// Members list tab.
    Members,
    /// Settings management tab.
    Settings,
    /// Sponsors management tab.
    Sponsors,
    /// Team management tab.
    Team,
}

// Types.

/// Groups organized by community, used for displaying user's groups in dashboard.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserGroupsByCommunity {
    /// Community information.
    pub community: CommunitySummary,
    /// Groups belonging to this community.
    pub groups: Vec<GroupSummary>,
}

impl UserGroupsByCommunity {
    /// Try to create a vector of `UserGroupsByCommunity` instances from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let mut communities: Vec<Self> = serde_json::from_str(data)?;

        // Apply color to each group summary
        for community in &mut communities {
            for group in &mut community.groups {
                group.color = color(&group.name).to_string();
            }
        }

        Ok(communities)
    }
}
