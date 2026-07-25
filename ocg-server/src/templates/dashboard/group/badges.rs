//! Templates for group badge definitions, awards, and artwork.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::{NoneAsEmptyString, serde_as, skip_serializing_none};
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::{
        badges::{BadgeArtwork, GroupAwardedBadges, GroupBadges},
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::{MAX_LEN_DATE, MAX_LEN_M, MAX_LEN_S, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Page templates.

/// Group badge artwork page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/badges_artwork.html")]
pub(crate) struct ArtworkPage {
    /// Reusable group artwork.
    pub artwork: Vec<BadgeArtwork>,
}

/// Group badge award history page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
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
    /// Selected event-source filter.
    pub event_id: Option<Uuid>,
    /// Number of results per page.
    pub limit: Option<usize>,
    /// Current award-history offset.
    pub offset: Option<usize>,
}

/// Group badge definitions page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
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

// Types.

/// Filter parameters for badge award history.
#[serde_as]
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AwardsFilters {
    /// Pagination offset for award history.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub awards_offset: Option<usize>,
    /// Award recipient or badge search text.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub awards_query: Option<String>,
    /// Badge definition filter for award history.
    #[serde_as(as = "NoneAsEmptyString")]
    #[serde(default)]
    #[garde(skip)]
    pub badge_id: Option<Uuid>,
    /// Event source filter for award history.
    #[serde_as(as = "NoneAsEmptyString")]
    #[serde(default)]
    #[garde(skip)]
    pub event_id: Option<Uuid>,
    /// Inclusive earliest award date.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_DATE))]
    pub from: Option<String>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Award status filter.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_S))]
    pub status: Option<String>,
    /// Inclusive latest award date.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_DATE))]
    pub to: Option<String>,
}

impl Pagination for AwardsFilters {
    fn limit(&self) -> Option<usize> {
        self.limit
    }

    fn offset(&self) -> Option<usize> {
        self.awards_offset
    }

    fn set_offset(&mut self, offset: Option<usize>) {
        self.awards_offset = offset;
    }
}

crate::impl_to_raw_query!(AwardsFilters);

/// Filter parameters for badge definitions.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct BadgesFilters {
    /// Pagination offset for badge definitions.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub badges_offset: Option<usize>,
    /// Badge definition search text.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub badges_query: Option<String>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
}

impl Pagination for BadgesFilters {
    fn limit(&self) -> Option<usize> {
        self.limit
    }

    fn offset(&self) -> Option<usize> {
        self.badges_offset
    }

    fn set_offset(&mut self, offset: Option<usize>) {
        self.badges_offset = offset;
    }
}

crate::impl_to_raw_query!(BadgesFilters);
