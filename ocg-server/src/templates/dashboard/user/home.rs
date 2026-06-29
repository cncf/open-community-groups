//! Templates for the user dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::{self, User},
        dashboard::{
            audit,
            user::{coffee_meet, events, invitations, mentorship, session_proposals, submissions},
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
    /// Pending invitations the user can review and accept or reject.
    pub pending_invitation_count: i64,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Content section for the user dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// User account page.
    Account(Box<auth::UpdateUserPage>),
    /// User upcoming events page.
    Events(events::ListPage),
    /// `CoffeeMeet` subscriptions page.
    CoffeeMeet(coffee_meet::ListPage),
    /// Invitations page.
    Invitations(invitations::ListPage),
    /// Audit logs page.
    Logs(audit::ListPage),
    /// Mentorship requests page.
    Mentorship(mentorship::ListPage),
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

    /// Check if the content is the events page.
    fn is_events(&self) -> bool {
        matches!(self, Content::Events(_))
    }

    /// Check if the content is the `CoffeeMeet` page.
    fn is_coffee_meet(&self) -> bool {
        matches!(self, Content::CoffeeMeet(_))
    }

    /// Check if the content is the invitations page.
    fn is_invitations(&self) -> bool {
        matches!(self, Content::Invitations(_))
    }

    /// Check if the content is the logs page.
    fn is_logs(&self) -> bool {
        matches!(self, Content::Logs(_))
    }

    /// Check if the content is the mentorship requests page.
    fn is_mentorship(&self) -> bool {
        matches!(self, Content::Mentorship(_))
    }

    /// Check if the content is the session proposals page.
    fn is_session_proposals(&self) -> bool {
        matches!(self, Content::SessionProposals(_))
    }

    /// Check if the content is the submissions page.
    fn is_submissions(&self) -> bool {
        matches!(self, Content::Submissions(_))
    }
}

impl std::fmt::Display for Content {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Content::Account(template) => write!(f, "{}", template.render()?),
            Content::CoffeeMeet(template) => write!(f, "{}", template.render()?),
            Content::Events(template) => write!(f, "{}", template.render()?),
            Content::Invitations(template) => write!(f, "{}", template.render()?),
            Content::Logs(template) => write!(f, "{}", template.render()?),
            Content::Mentorship(template) => write!(f, "{}", template.render()?),
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
    /// Events tab.
    Events,
    /// `CoffeeMeet` tab.
    CoffeeMeet,
    /// Invitations tab.
    Invitations,
    /// Audit logs tab.
    Logs,
    /// Mentorship requests tab.
    Mentorship,
    /// Session proposals tab.
    SessionProposals,
    /// Submissions tab.
    Submissions,
}
