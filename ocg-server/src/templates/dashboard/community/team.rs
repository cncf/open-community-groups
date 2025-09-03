//! Templates and types for managing the community team in the dashboard.

use anyhow::Result;
use askama::Template;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

// Pages templates.

/// List team members page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/team_list.html")]
pub(crate) struct ListPage {
    /// List of team members in the community.
    pub members: Vec<CommunityTeamMember>,
}

// Types.

/// Community team member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommunityTeamMember {
    /// Unique identifier for the user.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
}

impl CommunityTeamMember {
    /// Try to create a vector of `CommunityTeamMember` from a JSON array string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let members: Vec<Self> = serde_json::from_str(data)?;
        Ok(members)
    }
}
