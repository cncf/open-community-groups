//! Notifications templates.

use askama::Template;
use serde::{Deserialize, Serialize};

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

/// Template for group team invitation notification.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "notifications/group_team_invitation.html")]
pub(crate) struct GroupTeamInvitation {
    /// Link to manage invitations in the dashboard.
    pub link: String,
}
