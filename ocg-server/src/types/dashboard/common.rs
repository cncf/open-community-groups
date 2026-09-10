//! Type definitions shared across dashboards.

use std::collections::BTreeMap;

use chrono::{DateTime, NaiveDate, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        pagination::{Pagination, ToRawQuery},
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

/// Shared audit log filter parameters.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AuditLogFilters {
    /// Raw action key used to filter results.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub action: Option<String>,
    /// Actor username filter used in community and group dashboards.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub actor: Option<String>,
    /// Inclusive start date filter.
    #[garde(skip)]
    pub date_from: Option<NaiveDate>,
    /// Inclusive end date filter.
    #[garde(skip)]
    pub date_to: Option<NaiveDate>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Sort option used to order audit rows.
    #[serde(default = "default_sort")]
    #[garde(skip)]
    pub sort: Option<AuditLogSort>,
}

crate::impl_pagination_and_raw_query!(AuditLogFilters, limit, offset);

/// Raw audit log row returned by the database.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditLogRecord {
    /// Raw audit action key.
    pub action: String,
    /// Unique audit row identifier.
    pub audit_log_id: Uuid,
    /// Timestamp when the action was recorded.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Raw details object from the audit row.
    pub details: BTreeMap<String, Value>,
    /// Target resource identifier.
    pub resource_id: Uuid,
    /// Raw target resource type.
    pub resource_type: String,

    /// Snapshot username of the actor when available.
    pub actor_username: Option<String>,
    /// Display name for the resource.
    pub resource_name: Option<String>,
}

/// Supported audit log sort options.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum AuditLogSort {
    /// Sort by creation time ascending.
    CreatedAsc,
    /// Sort by creation time descending.
    CreatedDesc,
}

/// Paginated audit log response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AuditLogsOutput {
    /// Audit rows matching the filters.
    pub logs: Vec<AuditLogRecord>,
    /// Total number of matching rows before pagination.
    pub total: usize,
}

/// Default sort option for audit lists.
#[allow(clippy::unnecessary_wraps)]
fn default_sort() -> Option<AuditLogSort> {
    Some(AuditLogSort::CreatedDesc)
}
