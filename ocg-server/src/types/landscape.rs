//! Landscape domain types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::pagination::{Pagination, ToRawQuery},
    validation::{
        MAX_LEN_DESCRIPTION, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME, MAX_LEN_M,
        MAX_LEN_TAG, MAX_PAGINATION_LIMIT, image_url_opt, optional_trimmed_string,
        trimmed_non_empty, trimmed_non_empty_opt,
    },
};

/// Public landscape search filters.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct LandscapeFilters {
    /// Free-text search query.
    #[garde(length(max = MAX_LEN_M))]
    pub query: Option<String>,
    /// Filter by alliance slug/name.
    #[garde(length(max = MAX_LEN_M))]
    pub alliance: Option<String>,
    /// Filter by entry kind.
    #[garde(length(max = MAX_LEN_M))]
    pub kind: Option<String>,
    /// Filter by category.
    #[garde(length(max = MAX_LEN_M))]
    pub category: Option<String>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(LandscapeFilters, limit, offset);

impl Default for LandscapeFilters {
    fn default() -> Self {
        Self {
            query: None,
            alliance: None,
            kind: None,
            category: None,
            limit: Some(20),
            offset: Some(0),
        }
    }
}

/// Alliance dashboard landscape filters.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct DashboardLandscapeFilters {
    /// Free-text search query.
    #[garde(length(max = MAX_LEN_M))]
    pub query: Option<String>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(DashboardLandscapeFilters, limit, offset);

impl Default for DashboardLandscapeFilters {
    fn default() -> Self {
        Self {
            query: None,
            limit: dashboard::default_limit(),
            offset: dashboard::default_offset(),
        }
    }
}

/// Landscape form input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct LandscapeEntryInput {
    /// Entry name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub name: String,
    /// Entry kind, either startup or `github_project`.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub kind: String,
    /// Short summary.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub summary: String,
    /// Full description.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub description: Option<String>,
    /// Website URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_M), custom(trimmed_non_empty_opt))]
    pub website_url: Option<String>,
    /// GitHub URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_M), custom(trimmed_non_empty_opt))]
    pub github_url: Option<String>,
    /// Logo URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(image_url_opt))]
    pub logo_url: Option<String>,
    /// Category label.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub category: Option<String>,
    /// Tags, comma-separated.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(length(max = MAX_LEN_M))]
    pub tags: Option<String>,
}

/// Landscape search output.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct LandscapeOutput {
    /// Matching landscape entries.
    pub entries: Vec<LandscapeEntry>,
    /// Total matching entries.
    pub total: usize,
}

/// Public or dashboard landscape entry.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct LandscapeEntry {
    /// Entry identifier.
    pub landscape_entry_id: Uuid,
    /// Owning alliance identifier.
    pub alliance_id: Uuid,
    /// User that added the entry.
    pub added_by_user_id: Uuid,
    /// Entry name.
    pub name: String,
    /// URL slug.
    pub slug: String,
    /// Entry kind.
    pub kind: String,
    /// Short summary.
    pub summary: String,
    /// Full description.
    pub description: Option<String>,
    /// Website URL.
    pub website_url: Option<String>,
    /// GitHub URL.
    pub github_url: Option<String>,
    /// Logo URL.
    pub logo_url: Option<String>,
    /// Category label.
    pub category: Option<String>,
    /// Tags.
    #[serde(default)]
    pub tags: Vec<String>,
    /// Whether the entry is public.
    pub published: bool,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Tags parsed from comma-separated form input.
pub(crate) fn parse_tags(input: Option<&str>) -> Vec<String> {
    input
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|tag| !tag.is_empty())
        .take(12)
        .map(|tag| tag.chars().take(MAX_LEN_TAG).collect())
        .collect()
}
