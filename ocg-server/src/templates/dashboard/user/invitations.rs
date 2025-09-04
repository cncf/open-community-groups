//! Templates for the user dashboard invitations tab.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::templates::helpers::DATE_FORMAT_2;

// Pages templates.

/// List page showing pending invitations for the user.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/invitations_list.html")]
pub(crate) struct ListPage {
    /// Pending community invitations for the current user.
    pub community_invitations: Vec<CommunityTeamInvitation>,
    /// Pending group invitations for the current user.
    pub group_invitations: Vec<GroupTeamInvitation>,
}

// Types.

/// Community team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CommunityTeamInvitation {
    /// Community name (slug).
    pub community_name: String,
    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Group team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupTeamInvitation {
    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Group identifier.
    pub group_id: Uuid,
    /// Group name.
    pub group_name: String,
    /// Role within the group.
    pub role: String,
}
