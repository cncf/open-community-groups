//! Notifications templates.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::{event::EventSummary, group::GroupSummary};

// Emails templates.

/// Template for community team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/community_team_invitation.html")]
pub(crate) struct CommunityTeamInvitation {
    /// Link to manage invitations in the dashboard.
    pub link: String,
}

/// Template for email verification notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/email_verification.html")]
pub(crate) struct EmailVerification {
    /// Verification link for the user to confirm their email address.
    pub link: String,
}

/// Template for event canceled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_canceled.html")]
pub(crate) struct EventCanceled {
    /// Link to the event page.
    pub link: String,
    /// Event summary data.
    pub event: EventSummary,
}

/// Template for event published notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_published.html")]
pub(crate) struct EventPublished {
    /// Link to the event page.
    pub link: String,
    /// Event summary data.
    pub event: EventSummary,
}

/// Template for event rescheduled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_rescheduled.html")]
pub(crate) struct EventRescheduled {
    /// Link to the event page.
    pub link: String,
    /// Event summary data.
    pub event: EventSummary,
}

/// Template for group team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_team_invitation.html")]
pub(crate) struct GroupTeamInvitation {
    /// Link to manage invitations in the dashboard.
    pub link: String,
}

/// Template for group welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_welcome.html")]
pub(crate) struct GroupWelcome {
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to the group page.
    pub link: String,
}
