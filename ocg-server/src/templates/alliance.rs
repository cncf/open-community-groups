//! Templates and data structures for the alliance site.
//!
//! The home page displays an overview of the alliance including alliance statistics,
//! upcoming events (both in-person and virtual), and recently added groups.

use askama::Template;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::User,
        dashboard::{self, alliance::analytics::AllianceDashboardStats},
        filters,
        helpers::{self, user_initials},
    },
    types::{
        alliance::AllianceFull,
        event::{EventKind, EventSummary},
        group::GroupSummary,
        pagination::{NavigationLinks, Pagination, ToRawQuery},
        site::SiteSettings,
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

/// Link preview description for alliance pages.
pub(crate) const PREVIEW_DESCRIPTION: &str =
    "Open Alliance Groups, where Open Source alliances thrive.";
/// Link preview description for alliance brand pages.
pub(crate) const BRAND_PREVIEW_DESCRIPTION: &str =
    "Brand assets and identity links for this alliance.";

// Pages and sections templates.

/// Template for the alliance page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "alliance/page.html")]
pub(crate) struct Page {
    /// Configured public base URL.
    pub base_url: String,
    /// Alliance information.
    pub alliance: AllianceFull,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// List of groups recently added to the alliance.
    pub recently_added_groups: Vec<GroupCard>,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Aggregated statistics about groups, members, events, and attendees.
    pub stats: Stats,
    /// List of upcoming in-person events across all alliance groups.
    pub upcoming_in_person_events: Vec<EventCard>,
    /// List of upcoming virtual events across all alliance groups.
    pub upcoming_virtual_events: Vec<EventCard>,
    /// Authenticated user information.
    pub user: User,
}

impl Page {
    /// Returns the canonical public URL for the alliance page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(&self.base_url, &format!("/{}", self.alliance.name))
    }

    /// Returns the Open Graph image URL for the alliance page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.alliance
            .og_image_url
            .as_deref()
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview title for the alliance page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} alliance", self.alliance.display_name)
    }
}

/// Template for the alliance brand page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "alliance/brand.html")]
pub(crate) struct BrandPage {
    /// Configured public base URL.
    pub base_url: String,
    /// Alliance information.
    pub alliance: AllianceFull,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Template for the alliance members page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "alliance/members.html")]
pub(crate) struct MembersPage {
    /// Configured public base URL.
    pub base_url: String,
    /// Alliance information.
    pub alliance: AllianceFull,
    /// Members across alliance groups.
    pub members: Vec<AllianceMember>,
    /// Pagination links.
    pub navigation_links: NavigationLinks,
    /// Number of results per page.
    pub offset: Option<usize>,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Search query.
    pub query: Option<String>,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Total matching members.
    pub total: usize,
    /// Authenticated user information.
    pub user: User,
}

/// Template for the public alliance report page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "alliance/report.html")]
pub(crate) struct ReportPage {
    /// Configured public base URL.
    pub base_url: String,
    /// Alliance information.
    pub alliance: AllianceFull,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current request path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Alliance dashboard statistics.
    pub stats: AllianceDashboardStats,
    /// Authenticated user information.
    pub user: User,
}

impl MembersPage {
    /// Returns the canonical public URL for the alliance members page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(&self.base_url, &format!("/{}/members", self.alliance.name))
    }

    /// Returns the Open Graph image URL for the alliance members page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.alliance
            .og_image_url
            .as_deref()
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview title for the alliance members page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} members", self.alliance.display_name)
    }

    /// Returns the preview description for the alliance members page.
    pub(crate) fn preview_description(&self) -> String {
        format!(
            "Browse member cards across {} groups.",
            self.alliance.display_name
        )
    }
}

impl ReportPage {
    /// Returns the canonical public URL for the alliance report page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(&self.base_url, &format!("/{}/reports", self.alliance.name))
    }

    /// Returns the Open Graph image URL for the alliance report page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.alliance
            .og_image_url
            .as_deref()
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview title for the alliance report page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} report", self.alliance.display_name)
    }

    /// Returns the preview description for the alliance report page.
    pub(crate) fn preview_description(&self) -> String {
        format!(
            "Public growth and activity report for {}.",
            self.alliance.display_name
        )
    }
}

/// Alliance member summary information.
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AllianceMember {
    /// User identifier.
    pub user_id: Uuid,
    /// Username.
    pub username: String,
    /// Group names this member belongs to in the alliance.
    pub group_names: Vec<String>,

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

fn default_true() -> bool {
    true
}

/// Filter parameters for alliance member directory pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, garde::Validate)]
pub(crate) struct AllianceMembersFilters {
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

crate::impl_pagination_and_raw_query!(AllianceMembersFilters, limit, offset);

/// Paginated alliance members response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AllianceMembersOutput {
    /// Members across alliance groups.
    pub members: Vec<AllianceMember>,
    /// Total matching members.
    pub total: usize,
}

impl BrandPage {
    /// Returns the canonical public URL for the alliance brand page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(&self.base_url, &format!("/{}/brand", self.alliance.name))
    }

    /// Returns the Open Graph image URL for the alliance brand page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.alliance
            .og_image_url
            .as_deref()
            .or(Some(self.alliance.logo_url.as_str()))
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview title for the alliance brand page.
    pub(crate) fn preview_title(&self) -> String {
        format!("{} brand", self.alliance.display_name)
    }
}

/// Event card template for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "common/event_card_small.html")]
pub(crate) struct EventCard {
    /// Event data
    pub event: EventSummary,
}

/// Group card template for home page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "alliance/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    pub group: GroupSummary,
}

/// Alliance statistics for the home page.
#[derive(Debug, Clone, Default, Template, Serialize, Deserialize)]
#[template(path = "alliance/stats.html")]
pub(crate) struct Stats {
    /// Total number of groups in the alliance.
    pub groups: i64,
    /// Total number of members across all groups.
    pub groups_members: i64,
    /// Total number of events hosted by all groups.
    pub events: i64,
    /// Total number of attendees across all events.
    pub events_attendees: i64,
}
