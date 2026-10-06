//! Templates and types for the group dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::UserMenuState,
        dashboard::{
            audit,
            group::{
                analytics, badges, check_in, cohosts, events, members, refunds, settings, sponsors,
                team,
            },
            inbox,
        },
        filters,
        helpers::user_initials,
    },
    types::{
        community::CommunitySummary, dashboard::group::home::UserGroupsByCommunity,
        group::GroupMinimal, site::SiteSettings,
    },
};

/// Home page template for the group dashboard.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/home.html")]
#[allow(clippy::struct_excessive_bools)]
pub(crate) struct Page {
    /// Whether the current user can open the protected badge surface.
    pub can_manage_badges: bool,
    /// Whether the current user can process attendee check-ins.
    pub can_manage_check_ins: bool,
    /// Whether the current user can read and answer the group inbox.
    pub can_manage_inbox: bool,
    /// Main content section for the page.
    pub content: Content,
    /// Groups organized by community.
    pub groups_by_community: Vec<UserGroupsByCommunity>,
    /// Number of open inbox conversations shown in the menu badge.
    pub inbox_open_count: usize,
    /// Whether Check-In content fell back because the selected group is not manageable.
    pub is_check_in_fallback: bool,
    /// Whether Inbox content fell back because the selected group's inbox is not accessible.
    pub is_inbox_fallback: bool,
    /// Flash or status messages to display.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Whether the selected group can use the configured payments provider.
    pub payments_ready: bool,
    /// Currently selected community ID.
    pub selected_community_id: Uuid,
    /// Currently selected group ID.
    pub selected_group_id: Uuid,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: UserMenuState,
}

impl Page {
    /// Returns all communities the user has access to.
    fn communities(&self) -> Vec<&CommunitySummary> {
        self.groups_by_community.iter().map(|c| &c.community).collect()
    }

    /// Returns the selected community and group details.
    fn current_selection_details(&self) -> (&CommunitySummary, &GroupMinimal) {
        let selected_community = self
            .groups_by_community
            .iter()
            .find(|c| c.community.community_id == self.selected_community_id)
            .expect("selected community exists");
        let selected_group = selected_community
            .groups
            .iter()
            .find(|g| g.group_id == self.selected_group_id)
            .expect("selected group exists");

        (&selected_community.community, selected_group)
    }

    /// Returns groups for the currently selected community.
    fn selected_community_groups(&self) -> &[GroupMinimal] {
        self.groups_by_community
            .iter()
            .find(|c| c.community.community_id == self.selected_community_id)
            .map_or(&[], |c| c.groups.as_slice())
    }
}

/// Content section for the group dashboard home page.
#[derive(Debug, Clone)]
pub(crate) enum Content {
    /// Analytics page.
    Analytics(Box<analytics::Page>),
    /// Badge artwork page.
    Artwork(Box<badges::ArtworkPage>),
    /// Badge award history page.
    Awards(Box<badges::AwardsPage>),
    /// Badge definitions page.
    Badges(Box<badges::BadgesPage>),
    /// Attendee check-in page.
    CheckIn(check_in::ListPage),
    /// Co-hosted events page.
    Cohosts(cohosts::ListPage),
    /// Events management page.
    Events(Box<events::ListPage>),
    /// Inbox conversations page.
    Inbox(inbox::ListPage),
    /// Inbox conversation thread page.
    InboxConversation(Box<inbox::ConversationPage>),
    /// Audit logs page.
    Logs(audit::ListPage),
    /// Members list page.
    Members(members::ListPage),
    /// Refund operations page.
    Refunds(refunds::ListPage),
    /// Settings management page.
    Settings(Box<settings::UpdatePage>),
    /// Sponsors management page.
    Sponsors(sponsors::ListPage),
    /// Team management page.
    Team(team::ListPage),
}

impl Content {
    /// Check if the content is the analytics page.
    fn is_analytics(&self) -> bool {
        matches!(self, Content::Analytics(_))
    }

    /// Check if the content is the badge artwork page.
    fn is_artwork(&self) -> bool {
        matches!(self, Content::Artwork(_))
    }

    /// Check if the content is the badge award history page.
    fn is_awards(&self) -> bool {
        matches!(self, Content::Awards(_))
    }

    /// Check if the content is the badges page.
    fn is_badges(&self) -> bool {
        matches!(self, Content::Badges(_))
    }

    /// Check if the content is the check-in page.
    fn is_check_in(&self) -> bool {
        matches!(self, Content::CheckIn(_))
    }

    /// Check if the content is the co-hosted events page.
    fn is_cohosts(&self) -> bool {
        matches!(self, Content::Cohosts(_))
    }

    /// Check if the content is the events page.
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }

    /// Check if the content is an inbox page.
    fn is_inbox(&self) -> bool {
        matches!(self, Content::Inbox(_) | Content::InboxConversation(_))
    }

    /// Check if the content is the logs page.
    fn is_logs(&self) -> bool {
        matches!(self, Content::Logs(_))
    }

    /// Check if the content is the members page.
    fn is_members(&self) -> bool {
        matches!(self, Content::Members(_))
    }

    /// Checks whether the content is the refunds page.
    fn is_refunds(&self) -> bool {
        matches!(self, Content::Refunds(_))
    }

    /// Check if the content is the settings page.
    fn is_settings(&self) -> bool {
        matches!(self, Content::Settings(_))
    }

    /// Check if the content is the sponsors page.
    fn is_sponsors(&self) -> bool {
        matches!(self, Content::Sponsors(_))
    }

    /// Check if the content is the team page.
    fn is_team(&self) -> bool {
        matches!(self, Content::Team(_))
    }

    /// Returns the partial path used to refresh the dashboard content.
    fn refresh_path(&self) -> &'static str {
        match self {
            Content::Analytics(_) => "analytics",
            Content::Artwork(_) => "artwork",
            Content::Awards(_) => "awards",
            Content::Badges(_) => "badges",
            Content::CheckIn(_) => "check-in",
            Content::Cohosts(_) => "cohosts",
            Content::Events(_) => "events",
            Content::Inbox(_) | Content::InboxConversation(_) => "inbox",
            Content::Logs(_) => "logs",
            Content::Members(_) => "members",
            Content::Refunds(_) => "refunds",
            Content::Settings(_) => "settings",
            Content::Sponsors(_) => "sponsors",
            Content::Team(_) => "team",
        }
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Analytics(template) => write!(f, "{}", template.render()?),
            Content::Artwork(template) => write!(f, "{}", template.render()?),
            Content::Awards(template) => write!(f, "{}", template.render()?),
            Content::Badges(template) => write!(f, "{}", template.render()?),
            Content::CheckIn(template) => write!(f, "{}", template.render()?),
            Content::Cohosts(template) => write!(f, "{}", template.render()?),
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Inbox(template) => write!(f, "{}", template.render()?),
            Content::InboxConversation(template) => write!(f, "{}", template.render()?),
            Content::Logs(template) => write!(f, "{}", template.render()?),
            Content::Members(template) => write!(f, "{}", template.render()?),
            Content::Refunds(template) => write!(f, "{}", template.render()?),
            Content::Settings(template) => write!(f, "{}", template.render()?),
            Content::Sponsors(template) => write!(f, "{}", template.render()?),
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
    /// Analytics tab.
    Analytics,
    /// Badge artwork tab.
    Artwork,
    /// Badge award history tab.
    Awards,
    /// Badge definitions tab.
    Badges,
    /// Attendee check-in tab.
    CheckIn,
    /// Co-hosted events tab.
    Cohosts,
    /// Events management tab.
    Events,
    /// Inbox tab.
    Inbox,
    /// Audit logs tab.
    Logs,
    /// Members list tab.
    Members,
    /// Refund operations tab.
    Refunds,
    /// Settings management tab (default).
    #[default]
    Settings,
    /// Sponsors management tab.
    Sponsors,
    /// Team management tab.
    Team,
}

#[cfg(test)]
mod tests {
    use crate::types::pagination::NavigationLinks;

    use super::*;

    #[test]
    fn test_refresh_path_uses_members_route_for_members_content() {
        let content = Content::Members(members::ListPage {
            can_manage_members: false,
            default_notification_subject: String::new(),
            members: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
        });

        assert_eq!(content.refresh_path(), "members");
    }
}
