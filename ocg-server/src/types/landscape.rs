//! Landscape domain types.

#![allow(clippy::ref_option, clippy::trivially_copy_pass_by_ref)]

use chrono::{DateTime, NaiveDate, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::pagination::{Pagination, ToRawQuery},
    validation::{
        MAX_LEN_DATE, MAX_LEN_DESCRIPTION, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_ENTITY_NAME,
        MAX_LEN_M, MAX_LEN_TAG, MAX_PAGINATION_LIMIT, image_url_opt, optional_trimmed_string,
        trimmed_non_empty, trimmed_non_empty_opt,
    },
};

const LANDSCAPE_KINDS: [&str; 6] = [
    "accelerator",
    "startup",
    "github_project",
    "partner_community",
    "podcast_lead",
    "investor",
];
const ACCELERATOR_COHORT_STATUSES: [&str; 4] = ["planned", "open", "running", "completed"];

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
    /// Sort option for the GitHub leaderboard.
    #[garde(length(max = MAX_LEN_M))]
    pub github_sort: Option<String>,
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
            github_sort: None,
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
    /// Entry kind.
    #[garde(custom(valid_landscape_kind), length(max = MAX_LEN_M))]
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
    /// Accelerator application URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_M), custom(trimmed_non_empty_opt))]
    pub accelerator_application_url: Option<String>,
    /// Accelerator curriculum URL.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_M), custom(trimmed_non_empty_opt))]
    pub accelerator_curriculum_url: Option<String>,
    /// Accelerator cohort status.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_accelerator_cohort_status_opt), length(max = MAX_LEN_M))]
    pub accelerator_cohort_status: Option<String>,
    /// Accelerator start date in YYYY-MM-DD format.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub accelerator_starts_on: Option<String>,
    /// Accelerator end date in YYYY-MM-DD format.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_date_opt), length(max = MAX_LEN_DATE))]
    pub accelerator_ends_on: Option<String>,
    /// Accelerator tracks, comma-separated.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(length(max = MAX_LEN_M))]
    pub accelerator_tracks: Option<String>,
    /// Accelerator weekly agenda as JSON.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(valid_json_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub accelerator_weekly_agenda: Option<String>,
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
    /// Accelerator-specific profile.
    pub accelerator: Option<LandscapeAcceleratorProfile>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Accelerator-specific metadata for a landscape entry.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct LandscapeAcceleratorProfile {
    /// Application URL.
    pub application_url: Option<String>,
    /// Curriculum URL.
    pub curriculum_url: Option<String>,
    /// Cohort lifecycle status.
    pub cohort_status: Option<String>,
    /// Cohort start date in YYYY-MM-DD format.
    pub starts_on: Option<String>,
    /// Cohort end date in YYYY-MM-DD format.
    pub ends_on: Option<String>,
    /// Accelerator tracks.
    #[serde(default)]
    pub tracks: Vec<String>,
    /// Structured weekly agenda.
    pub weekly_agenda: Option<serde_json::Value>,
    /// Last accelerator metadata update time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub updated_at: DateTime<Utc>,
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

/// Accelerator tracks parsed from comma-separated form input.
pub(crate) fn parse_accelerator_tracks(input: Option<&str>) -> Vec<String> {
    parse_tags(input)
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn valid_landscape_kind(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    let value = value.as_ref().trim();
    if LANDSCAPE_KINDS.contains(&value) {
        Ok(())
    } else {
        Err(garde::Error::new("invalid landscape kind"))
    }
}

fn valid_accelerator_cohort_status_opt(
    value: &Option<String>,
    _ctx: &(),
) -> garde::Result {
    let Some(value) = value.as_deref().map(str::trim) else {
        return Ok(());
    };
    if ACCELERATOR_COHORT_STATUSES.contains(&value) {
        Ok(())
    } else {
        Err(garde::Error::new("invalid accelerator cohort status"))
    }
}

fn valid_date_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    let Some(value) = value.as_deref().map(str::trim) else {
        return Ok(());
    };
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map(|_| ())
        .map_err(|_| garde::Error::new("invalid date"))
}

fn valid_json_opt(value: &Option<String>, _ctx: &()) -> garde::Result {
    let Some(value) = value.as_deref().map(str::trim) else {
        return Ok(());
    };
    serde_json::from_str::<serde_json::Value>(value)
        .map(|_| ())
        .map_err(|_| garde::Error::new("invalid JSON"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_landscape_kinds() {
        assert!(valid_landscape_kind(&"accelerator", &()).is_ok());
        assert!(valid_landscape_kind(&"startup", &()).is_ok());
        assert!(valid_landscape_kind(&"github_project", &()).is_ok());
        assert!(valid_landscape_kind(&"partner_community", &()).is_ok());
        assert!(valid_landscape_kind(&"podcast_lead", &()).is_ok());
        assert!(valid_landscape_kind(&"investor", &()).is_ok());
        assert!(valid_landscape_kind(&"unknown", &()).is_err());
    }

    #[test]
    fn parses_accelerator_tracks() {
        assert_eq!(
            parse_accelerator_tracks(Some("AI, Open Source, Revenue")),
            vec!["AI", "Open Source", "Revenue"]
        );
        assert!(parse_accelerator_tracks(None).is_empty());
    }

    #[test]
    fn validates_accelerator_cohort_statuses() {
        assert!(valid_accelerator_cohort_status_opt(&None, &()).is_ok());
        assert!(valid_accelerator_cohort_status_opt(&Some("planned".to_string()), &()).is_ok());
        assert!(valid_accelerator_cohort_status_opt(&Some("open".to_string()), &()).is_ok());
        assert!(valid_accelerator_cohort_status_opt(&Some("running".to_string()), &()).is_ok());
        assert!(valid_accelerator_cohort_status_opt(&Some("completed".to_string()), &()).is_ok());
        assert!(valid_accelerator_cohort_status_opt(&Some("paused".to_string()), &()).is_err());
    }

    #[test]
    fn validates_accelerator_dates_and_agenda_json() {
        assert!(valid_date_opt(&Some("2026-07-08".to_string()), &()).is_ok());
        assert!(valid_date_opt(&Some("07/08/2026".to_string()), &()).is_err());
        assert!(
            valid_json_opt(&Some(
                r#"[{"week":1,"focus":"AI Distribution"}]"#.to_string()
            ), &())
            .is_ok()
        );
        assert!(valid_json_opt(&Some("not-json".to_string()), &()).is_err());
    }
}
