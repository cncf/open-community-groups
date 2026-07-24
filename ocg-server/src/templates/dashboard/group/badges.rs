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

// Pages templates.

/// Group badge management page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/badges.html")]
pub(crate) struct Page {
    /// Reusable group artwork.
    pub artwork: Vec<BadgeArtwork>,
    /// Paginated award history.
    pub awarded_badges: GroupAwardedBadges,
    /// Award-history pagination links.
    pub awards_navigation_links: pagination::NavigationLinks,
    /// Current award-history query.
    pub awards_query: String,
    /// Paginated badge definitions.
    pub badges: GroupBadges,
    /// Badge-definition pagination links.
    pub badges_navigation_links: pagination::NavigationLinks,
    /// Current badge-definition query.
    pub badges_query: String,
    /// Inclusive earliest award date.
    pub from: String,
    /// Initially selected management pane.
    pub pane: String,
    /// Selected active or revoked status.
    pub status: String,
    /// Inclusive latest award date.
    pub to: String,

    /// Current award-history offset.
    pub awards_offset: Option<usize>,
    /// Selected badge-definition filter.
    pub badge_id: Option<Uuid>,
    /// Current badge-definition offset.
    pub badges_offset: Option<usize>,
    /// Selected event-source filter.
    pub event_id: Option<Uuid>,
    /// Number of results per page.
    pub limit: Option<usize>,
}

// Types.

/// Filter parameters for badge definitions and award history.
#[serde_as]
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct BadgesFilters {
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
    /// Pagination offset for badge definitions.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub badges_offset: Option<usize>,
    /// Badge definition search text.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub badges_query: Option<String>,
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
    /// Initially selected badge management pane.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_S))]
    pub pane: Option<String>,
    /// Award status filter.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_S))]
    pub status: Option<String>,
    /// Inclusive latest award date.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_DATE))]
    pub to: Option<String>,
}

impl BadgesFilters {
    /// Return the selected management pane or its default.
    pub(crate) fn current_pane(&self) -> &'static str {
        match self.pane.as_deref() {
            Some("artwork") => "artwork",
            Some("awards") => "awards",
            _ => "definitions",
        }
    }
}

impl Pagination for BadgesFilters {
    fn limit(&self) -> Option<usize> {
        self.limit
    }

    fn offset(&self) -> Option<usize> {
        match self.current_pane() {
            "awards" => self.awards_offset,
            _ => self.badges_offset,
        }
    }

    fn set_offset(&mut self, offset: Option<usize>) {
        match self.current_pane() {
            "awards" => self.awards_offset = offset,
            _ => self.badges_offset = offset,
        }
    }
}

crate::impl_to_raw_query!(BadgesFilters);
