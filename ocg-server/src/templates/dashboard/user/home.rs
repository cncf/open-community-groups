//! Templates for the user dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::{self, UserMenuState},
        dashboard::{
            audit, inbox,
            user::{
                badges, check_in, events, groups, invitations, notifications, purchases,
                session_proposals, submissions,
            },
        },
        filters,
        helpers::user_initials,
    },
    types::site::SiteSettings,
};

/// Home page template for the user dashboard.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/home.html")]
pub(crate) struct Page {
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
    pub user: UserMenuState,
}

/// Content section for the user dashboard home page.
#[derive(Debug, Clone)]
pub(crate) enum Content {
    /// User account page.
    Account(Box<auth::UpdateUserPage>),
    /// User badges page.
    Badges(badges::ListPage),
    /// User attendee check-in page.
    CheckIn(check_in::ListPage),
    /// User upcoming events page.
    Events(events::ListPage),
    /// User groups page.
    Groups(groups::ListPage),
    /// Inbox conversations page.
    Inbox(inbox::ListPage),
    /// Inbox conversation thread page.
    InboxConversation(Box<inbox::ConversationPage>),
    /// Invitations page.
    Invitations(invitations::ListPage),
    /// Audit logs page.
    Logs(audit::ListPage),
    /// Notification preferences page.
    Notifications(Box<notifications::Page>),
    /// Paid-ticket invoices and credit notes.
    Purchases(purchases::ListPage),
    /// Session proposals page.
    SessionProposals(session_proposals::ListPage),
    /// Submissions page.
    Submissions(submissions::ListPage),
}

impl Content {
    /// Check if the content is the account page.
    fn is_account(&self) -> bool {
        matches!(self, Content::Account(_))
    }

    /// Check if the content is the badges page.
    fn is_badges(&self) -> bool {
        matches!(self, Content::Badges(_))
    }

    /// Check if the content is the check-in page.
    fn is_check_in(&self) -> bool {
        matches!(self, Content::CheckIn(_))
    }

    /// Check if the content is the events page.
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }

    /// Check if the content is the groups page.
    fn is_groups(&self) -> bool {
        matches!(self, Content::Groups(_))
    }

    /// Check if the content is an inbox page.
    fn is_inbox(&self) -> bool {
        matches!(self, Content::Inbox(_) | Content::InboxConversation(_))
    }

    /// Check if the content is the invitations page.
    fn is_invitations(&self) -> bool {
        matches!(self, Content::Invitations(_))
    }

    /// Check if the content is the logs page.
    fn is_logs(&self) -> bool {
        matches!(self, Content::Logs(_))
    }

    /// Check if the content is the notifications page.
    fn is_notifications(&self) -> bool {
        matches!(self, Content::Notifications(_))
    }

    /// Check if the content is the purchase documents page.
    fn is_purchases(&self) -> bool {
        matches!(self, Content::Purchases(_))
    }

    /// Check if the content is the session proposals page.
    fn is_session_proposals(&self) -> bool {
        matches!(self, Content::SessionProposals(_))
    }

    /// Check if the content is the submissions page.
    fn is_submissions(&self) -> bool {
        matches!(self, Content::Submissions(_))
    }

    /// Returns the partial path used to refresh the dashboard content.
    fn refresh_path(&self) -> &'static str {
        match self {
            // The account page has no list route and keeps the submissions fallback
            Content::Account(_) | Content::Submissions(_) => "submissions",
            Content::Badges(_) => "badges",
            Content::CheckIn(_) => "check-in",
            Content::Events(_) => "events",
            Content::Groups(_) => "groups",
            Content::Inbox(_) | Content::InboxConversation(_) => "inbox",
            Content::Invitations(_) => "invitations",
            Content::Logs(_) => "logs",
            Content::Notifications(_) => "notifications",
            Content::Purchases(_) => "purchases",
            Content::SessionProposals(_) => "session-proposals",
        }
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Account(template) => write!(f, "{}", template.render()?),
            Content::Badges(template) => write!(f, "{}", template.render()?),
            Content::CheckIn(template) => write!(f, "{}", template.render()?),
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Groups(template) => write!(f, "{}", template.render()?),
            Content::Inbox(template) => write!(f, "{}", template.render()?),
            Content::InboxConversation(template) => write!(f, "{}", template.render()?),
            Content::Invitations(template) => write!(f, "{}", template.render()?),
            Content::Logs(template) => write!(f, "{}", template.render()?),
            Content::Notifications(template) => write!(f, "{}", template.render()?),
            Content::Purchases(template) => write!(f, "{}", template.render()?),
            Content::SessionProposals(template) => write!(f, "{}", template.render()?),
            Content::Submissions(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the user dashboard home page.
#[derive(
    Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// User account tab (default).
    #[default]
    Account,
    /// Badges tab.
    Badges,
    /// Attendee check-in tab.
    CheckIn,
    /// Events tab.
    Events,
    /// Groups tab.
    Groups,
    /// Inbox tab.
    Inbox,
    /// Invitations tab.
    Invitations,
    /// Audit logs tab.
    Logs,
    /// Notification preferences tab.
    Notifications,
    /// Paid-ticket purchase documents tab.
    Purchases,
    /// Session proposals tab.
    SessionProposals,
    /// Submissions tab.
    Submissions,
}

#[cfg(test)]
mod tests {
    use crate::types::{
        dashboard::user::notifications::NotificationPreferences, pagination::NavigationLinks,
    };

    use super::*;

    #[test]
    fn test_refresh_path_uses_events_route_for_events_content() {
        let content = Content::Events(events::ListPage {
            events: vec![],
            navigation_links: NavigationLinks::default(),
            total: 0,

            offset: None,
        });

        assert_eq!(content.refresh_path(), "events");
    }

    #[test]
    fn test_refresh_path_uses_invitations_route_for_invitations_content() {
        let content = Content::Invitations(invitations::ListPage {
            community_invitations: vec![],
            event_invitations: vec![],
            group_invitations: vec![],
        });

        assert_eq!(content.refresh_path(), "invitations");
    }

    #[test]
    fn test_refresh_path_uses_notifications_route_for_notifications_content() {
        let content = Content::Notifications(Box::new(notifications::Page {
            preferences: NotificationPreferences::default(),
            show_community_team_section: false,
            show_group_team_section: false,
        }));

        assert_eq!(content.refresh_path(), "notifications");
    }
}
