//! Templates and types for managing the community team in the dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        dashboard,
        helpers::user_initials,
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// List team members page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/community/team_list.html")]
pub(crate) struct ListPage {
    /// Number of members with approved status.
    pub approved_members_count: usize,
    /// List of team members in the community.
    pub members: Vec<CommunityTeamMember>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of team members.
    pub total: usize,
}

// Types.

/// Filter parameters for community team pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CommunityTeamFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(CommunityTeamFilters, limit, offset);

/// Community team member summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommunityTeamMember {
    /// Whether the membership has been accepted.
    pub accepted: bool,
    /// Unique identifier for the user.
    pub user_id: Uuid,
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

/// Paginated community team response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CommunityTeamOutput {
    /// Total number of approved members.
    pub approved_total: usize,
    /// List of team members in the community.
    pub members: Vec<CommunityTeamMember>,
    /// Total number of team members.
    pub total: usize,
}
