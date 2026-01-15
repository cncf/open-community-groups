//! Notifications templates.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::{event::EventSummary, group::GroupSummary, site::Theme};

// Emails templates.

/// Template for community team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/community_team_invitation.html")]
pub(crate) struct CommunityTeamInvitation {
    /// Community display name.
    pub community_name: String,
    /// Link to manage invitations in the dashboard.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for email verification notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/email_verification.html")]
pub(crate) struct EmailVerification {
    /// Verification link for the user to confirm their email address.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event canceled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_canceled.html")]
pub(crate) struct EventCanceled {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event custom notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_custom.html")]
pub(crate) struct EventCustom {
    /// Body text provided for the event notification.
    pub body: String,
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the notification.
    pub theme: Theme,
    /// Display title provided for the event notification.
    pub title: String,
}

/// Template for event published notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_published.html")]
pub(crate) struct EventPublished {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event rescheduled notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_rescheduled.html")]
pub(crate) struct EventRescheduled {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for event welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/event_welcome.html")]
pub(crate) struct EventWelcome {
    /// Link to the event page.
    pub link: String,
    /// Event summary data.
    pub event: EventSummary,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for group custom notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_custom.html")]
pub(crate) struct GroupCustom {
    /// Body text provided for the group notification.
    pub body: String,
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to the group page.
    pub link: String,
    /// Theme configuration for the notification.
    pub theme: Theme,
    /// Display title provided for the group notification.
    pub title: String,
}

/// Template for group team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_team_invitation.html")]
pub(crate) struct GroupTeamInvitation {
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to manage invitations in the dashboard.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for group welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_welcome.html")]
pub(crate) struct GroupWelcome {
    /// Group summary data.
    pub group: GroupSummary,
    /// Link to the group page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}

/// Template for speaker welcome notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/speaker_welcome.html")]
pub(crate) struct SpeakerWelcome {
    /// Event summary data.
    pub event: EventSummary,
    /// Link to the event page.
    pub link: String,
    /// Theme configuration for the community.
    pub theme: Theme,
}
