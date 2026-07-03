//! Templates and types for listing group members in the dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{dashboard, helpers::user_initials},
    types::pagination::{self, Pagination, ToRawQuery},
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Pages templates.

/// List members page template for a group.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/members_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage members.
    pub can_manage_members: bool,
    /// Default notification subject.
    pub default_notification_subject: String,
    /// List of members in the group.
    pub members: Vec<GroupMember>,
    /// Pending join requests awaiting admin review.
    pub join_requests: Vec<GroupJoinRequest>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Total number of members in the group.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Text search query used to filter members.
    pub query: Option<String>,
}

// Types.

/// Group member summary information.
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMember {
    /// Membership creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Email address.
    pub email: String,
    /// User identifier.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// User biography.
    pub bio: Option<String>,
    /// Bluesky profile URL.
    pub bluesky_url: Option<String>,
    /// City where the user is based.
    pub city: Option<String>,
    /// Whether this member accepts direct `CoffeeMeet` requests.
    #[serde(default = "default_true")]
    pub coffee_meet_enabled: bool,
    /// Country where the user is based.
    pub country: Option<String>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// GitHub profile URL.
    pub github_url: Option<String>,
    /// User interests.
    pub interests: Option<Vec<String>>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// Whether the user has a connected `LinkedIn` provider.
    pub linkedin_connected: bool,
    /// Whether this member offers mentorship services for businesses.
    #[serde(default)]
    pub mentorship_businesses: bool,
    /// Whether this member offers mentorship services for individuals.
    #[serde(default)]
    pub mentorship_individuals: bool,
    /// Optional mentorship description.
    pub mentorship_note: Option<String>,
    /// Optional price or pricing guidance for mentorship.
    pub mentorship_price: Option<String>,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// Whether this member has a phone number configured.
    #[serde(default)]
    pub has_phone_number: bool,
    /// International calling code visible to the current viewer.
    pub phone_country_code: Option<String>,
    /// Phone number visible to the current viewer.
    pub phone_number: Option<String>,
    /// Current viewer's request status for this member's phone number.
    pub phone_request_status: Option<String>,
    /// Pending phone visibility requests awaiting this member's approval.
    #[serde(default)]
    pub phone_requesters: Vec<GroupMemberPhoneRequester>,
    /// `Substack` publication URL.
    pub substack_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
    /// X/Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Website URL.
    pub website_url: Option<String>,
    /// `YouTube` channel URL.
    pub youtube_url: Option<String>,
}

impl GroupMember {
    /// Returns true when the current viewer can see this member's phone number.
    pub(crate) fn phone_visible(&self) -> bool {
        self.phone_country_code.is_some() && self.phone_number.is_some()
    }

    /// Returns true when the current viewer already requested this phone number.
    pub(crate) fn phone_request_pending(&self) -> bool {
        self.phone_request_status.as_deref() == Some("pending")
    }
}

fn default_true() -> bool {
    true
}

/// A member who requested access to another member's phone number.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMemberPhoneRequester {
    /// Requester user identifier.
    pub user_id: Uuid,
    /// Requester username.
    pub username: String,
    /// Requester display name.
    pub name: Option<String>,
}

/// Pending group join request summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupJoinRequest {
    /// Request creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Email address.
    pub email: String,
    /// User identifier.
    pub user_id: Uuid,
    /// Username.
    pub username: String,

    /// Company the user represents.
    pub company: Option<String>,
    /// User biography.
    pub bio: Option<String>,
    /// Bluesky profile URL.
    pub bluesky_url: Option<String>,
    /// City where the user is based.
    pub city: Option<String>,
    /// Country where the user is based.
    pub country: Option<String>,
    /// Facebook profile URL.
    pub facebook_url: Option<String>,
    /// GitHub profile URL.
    pub github_url: Option<String>,
    /// User interests.
    pub interests: Option<Vec<String>>,
    /// `LinkedIn` profile URL.
    pub linkedin_url: Option<String>,
    /// Whether the user has a connected `LinkedIn` provider.
    pub linkedin_connected: bool,
    /// Full name.
    pub name: Option<String>,
    /// URL to user's avatar.
    pub photo_url: Option<String>,
    /// `Substack` publication URL.
    pub substack_url: Option<String>,
    /// Title held by the user.
    pub title: Option<String>,
    /// X/Twitter profile URL.
    pub twitter_url: Option<String>,
    /// Website URL.
    pub website_url: Option<String>,
    /// `YouTube` channel URL.
    pub youtube_url: Option<String>,
}

/// Filter parameters for group members pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct GroupMembersFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Text search query.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub query: Option<String>,
}

crate::impl_pagination_and_raw_query!(GroupMembersFilters, limit, offset);

/// Paginated group members response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupMembersOutput {
    /// List of members in the group.
    pub members: Vec<GroupMember>,
    /// Total number of members in the group.
    pub total: usize,
}
