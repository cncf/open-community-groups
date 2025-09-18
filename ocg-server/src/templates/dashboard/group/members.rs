//! Templates and types for listing group members in the dashboard.

use anyhow::Result;
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::instrument;

use crate::templates::{filters, helpers::user_initials};

// Pages templates.

/// List members page template for a group.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/members_list.html")]
pub(crate) struct ListPage {
    /// List of members in the group.
    pub members: Vec<GroupMember>,
}

// Types.

/// Group member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMember {
    /// Membership creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
}

impl GroupMember {
    /// Try to create a vector of `GroupMember` from a JSON array string.
    #[instrument(skip_all, err)]
    pub fn try_from_json_array(data: &str) -> Result<Vec<Self>> {
        let members: Vec<Self> = serde_json::from_str(data)?;
        Ok(members)
    }
}
