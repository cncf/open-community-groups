//! Templates and types for managing the group team in the dashboard.

use anyhow::Result;
use askama::Template;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::templates::{
    filters,
    helpers::{InitialsCount, user_initials},
};
use crate::types::group::{GroupRole, GroupRoleSummary};

// Pages templates.

/// List team members page template for a group.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/team_list.html")]
pub(crate) struct ListPage {
    /// Number of members with approved status.
    pub approved_members_count: usize,
    /// List of team members in the group.
    pub members: Vec<GroupTeamMember>,
    /// List of available team roles.
    pub roles: Vec<GroupRoleSummary>,
}

// Types.

/// Group team member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupTeamMember {
    /// Whether the membership has been accepted.
    pub accepted: bool,
    /// Unique identifier for the user.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Team role.
    pub role: Option<GroupRole>,
}

impl GroupTeamMember {
    /// Try to create a vector of `GroupTeamMember` from a JSON array string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let members: Vec<Self> = serde_json::from_str(data)?;
        Ok(members)
    }
}
