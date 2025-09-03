//! Templates for the user dashboard invitations tab.

use askama::Template;
use serde::{Deserialize, Serialize};

// Pages templates.

/// List page showing pending invitations for the user.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/invitations_list.html")]
pub(crate) struct ListPage {
    /// Pending community invitations for the current user.
    pub community_invitations: Vec<CommunityTeamInvitation>,
}

// Types.

/// Community team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CommunityTeamInvitation {
    /// Community name (slug).
    pub community_name: String,

    /// Invitation creation time (epoch seconds).
    pub created_at: i64,
}
