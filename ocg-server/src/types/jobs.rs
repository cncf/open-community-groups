//! Jobs domain types.

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
        MAX_LEN_TAG, MAX_PAGINATION_LIMIT, trimmed_non_empty, trimmed_non_empty_opt,
    },
};

/// Public jobs search filters.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct JobsFilters {
    /// Free-text search query.
    #[garde(length(max = MAX_LEN_M))]
    pub query: Option<String>,
    /// Location filter.
    #[garde(length(max = MAX_LEN_M))]
    pub location: Option<String>,
    /// Remote-only filter.
    #[garde(skip)]
    pub remote: Option<bool>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(JobsFilters, limit, offset);

impl Default for JobsFilters {
    fn default() -> Self {
        Self {
            query: None,
            location: None,
            remote: None,
            limit: Some(20),
            offset: Some(0),
        }
    }
}

/// User jobs dashboard filters.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct DashboardJobsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(DashboardJobsFilters, limit, offset);

impl Default for DashboardJobsFilters {
    fn default() -> Self {
        Self {
            limit: dashboard::default_limit(),
            offset: dashboard::default_offset(),
        }
    }
}

/// Job form input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct JobInput {
    /// Job title.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub title: String,
    /// Employer/company name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub company_name: String,
    /// Short summary.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub summary: String,
    /// Full job description.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Apply URL.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub apply_url: String,
    /// Location label.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub location: Option<String>,
    /// Remote-friendly role.
    #[garde(skip)]
    pub remote: Option<bool>,
    /// Job tags, comma-separated.
    #[garde(length(max = MAX_LEN_M))]
    pub tags: Option<String>,
}

/// Application form input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct JobApplicationInput {
    /// Optional note to the job poster.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub note: Option<String>,
}

/// Job search output.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct JobsOutput {
    /// Matching jobs.
    pub jobs: Vec<JobSummary>,
    /// Total number of matching jobs.
    pub total: usize,
}

/// User dashboard jobs output.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct DashboardJobsOutput {
    /// Jobs owned by the current user.
    pub jobs: Vec<JobSummary>,
    /// Total number of matching jobs.
    pub total: usize,
}

/// Public job summary.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct JobSummary {
    /// Job identifier.
    pub job_id: Uuid,
    /// Job title.
    pub title: String,
    /// URL slug.
    pub slug: String,
    /// Employer/company name.
    pub company_name: String,
    /// Short summary.
    pub summary: String,
    /// Full job description.
    pub description: String,
    /// Location label.
    pub location: Option<String>,
    /// Remote-friendly role.
    pub remote: bool,
    /// Apply URL.
    pub apply_url: String,
    /// Tags.
    #[serde(default)]
    pub tags: Vec<String>,
    /// Whether the job is published.
    pub published: bool,
    /// Number of applications.
    #[serde(default)]
    pub application_count: i32,
    /// Poster user identifier.
    pub posted_by_user_id: Uuid,
    /// Poster username.
    pub poster_username: String,
    /// Poster display name.
    pub poster_name: Option<String>,
    /// Poster profile photo URL.
    pub poster_photo_url: Option<String>,
    /// Poster title.
    pub poster_title: Option<String>,
    /// Poster company.
    pub poster_company: Option<String>,
    /// Public expiration time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub expires_at: DateTime<Utc>,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Full public job details.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct JobFull {
    /// Summary fields.
    #[serde(flatten)]
    pub summary: JobSummary,
    /// Whether the viewer already applied.
    #[serde(default)]
    pub viewer_has_applied: bool,
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
