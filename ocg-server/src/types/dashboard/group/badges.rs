//! Group dashboard badge types.

use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::{NoneAsEmptyString, serde_as, skip_serializing_none};
use uuid::Uuid;

use crate::{
    types::{
        badges::BadgeAwardSourceFilter,
        dashboard,
        pagination::{Pagination, ToRawQuery},
    },
    validation::{MAX_LEN_DATE, MAX_LEN_M, MAX_LEN_S, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

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
    /// Inclusive earliest award date.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(length(max = MAX_LEN_DATE))]
    pub from: Option<String>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Award source filter for award history.
    #[serde_as(as = "NoneAsEmptyString")]
    #[serde(default)]
    #[garde(skip)]
    pub source: Option<BadgeAwardSourceFilter>,
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
