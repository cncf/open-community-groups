//! Templates for group badge definitions, awards, and artwork.

use askama::Template;
use uuid::Uuid;

use crate::types::{
    badges::{
        BadgeArtwork, BadgeAwardSource, BadgeAwardSourceFilter, GroupAwardedBadges, GroupBadges,
    },
    pagination,
};

// Page templates.

/// Group badge artwork page.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/badges_artwork.html")]
pub(crate) struct ArtworkPage {
    /// Reusable group artwork.
    pub artwork: Vec<BadgeArtwork>,
}

/// Group badge award history page.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/badges_awards.html")]
pub(crate) struct AwardsPage {
    /// Paginated award history.
    pub awarded_badges: GroupAwardedBadges,
    /// Inclusive earliest award date.
    pub from: String,
    /// Award-history pagination links.
    pub navigation_links: pagination::NavigationLinks,
    /// Current award-history query.
    pub query: String,
    /// Selected active or revoked status.
    pub status: String,
    /// Inclusive latest award date.
    pub to: String,

    /// Selected badge-definition filter.
    pub badge_id: Option<Uuid>,
    /// Number of results per page.
    pub limit: Option<usize>,
    /// Current award-history offset.
    pub offset: Option<usize>,
    /// Selected award-source filter.
    pub source: Option<BadgeAwardSourceFilter>,
}

impl AwardsPage {
    /// Returns whether an award-source filter option is selected.
    fn is_source_selected(&self, source: &BadgeAwardSource) -> bool {
        self.source == Some(source.filter())
    }
}

/// Group badge definitions page.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/badges.html")]
pub(crate) struct BadgesPage {
    /// Reusable group artwork.
    pub artwork: Vec<BadgeArtwork>,
    /// Paginated badge definitions.
    pub badges: GroupBadges,
    /// Badge-definition pagination links.
    pub navigation_links: pagination::NavigationLinks,
    /// Current badge-definition query.
    pub query: String,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Current badge-definition offset.
    pub offset: Option<usize>,
}
