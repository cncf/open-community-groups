//! Templates for the user dashboard home page.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};

use crate::{
    templates::{
        PageId,
        auth::{self, User},
        dashboard::user::{invitations, session_proposals, submissions},
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
    pub user: User,
}

/// Content section for the user dashboard home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Content {
    /// User account page.
    Account(Box<auth::UpdateUserPage>),
    /// Invitations page.
    Invitations(invitations::ListPage),
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

    /// Check if the content is the invitations page.
    fn is_invitations(&self) -> bool {
        matches!(self, Content::Invitations(_))
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
            Content::Invitations(template) => write!(f, "{}", template.render()?),
            Content::SessionProposals(template) => write!(f, "{}", template.render()?),
            Content::Submissions(template) => write!(f, "{}", template.render()?),
        }
    }
}

/// Tab selection for the user dashboard home page.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Tab {
    /// User account tab (default).
    #[default]
    Account,
    /// Invitations tab.
    Invitations,
    /// Session proposals tab.
    SessionProposals,
    /// Submissions tab.
    Submissions,
}
