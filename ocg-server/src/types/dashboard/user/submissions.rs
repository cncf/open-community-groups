//! User dashboard CFS submission types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        event::{CfsSessionProposal, EventCfsLabel, EventSummary},
        pagination::{Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

/// CFS submission summary information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CfsSubmission {
    /// Submission identifier.
    pub cfs_submission_id: Uuid,
    /// Submission creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Event summary information.
    pub event: EventSummary,
    /// Labels assigned to the submission.
    pub labels: Vec<EventCfsLabel>,
    /// Session proposal summary information.
    pub session_proposal: CfsSessionProposal,
    /// Submission status identifier.
    pub status_id: String,
    /// Submission status name.
    pub status_name: String,

    /// Action required message for the speaker.
    pub action_required_message: Option<String>,
    /// Linked session identifier.
    pub linked_session_id: Option<Uuid>,
    /// Submission last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Filter parameters for submissions pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CfsSubmissionsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(CfsSubmissionsFilters, limit, offset);

/// Paginated submissions response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CfsSubmissionsOutput {
    /// List of submissions.
    pub submissions: Vec<CfsSubmission>,
    /// Total number of submissions.
    pub total: usize,
}
