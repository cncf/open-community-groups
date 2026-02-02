//! Templates and types for event CFS submissions in the group dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::templates::filters;
use crate::{
    templates::{
        common::UserSummary,
        dashboard,
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::{MAX_LEN_DESCRIPTION, MAX_PAGINATION_LIMIT, trimmed_non_empty},
};

use super::events::CfsSubmissionStatus;

// Pages templates.

/// List submissions page template for an event.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/event_submissions_list.html")]
pub(crate) struct ListPage {
    /// Event identifier.
    pub event_id: Uuid,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the submissions list.
    pub refresh_url: String,
    /// Submission status options.
    pub statuses: Vec<CfsSubmissionStatus>,
    /// List of submissions.
    pub submissions: Vec<CfsSubmission>,
    /// Total number of submissions.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
}

// Types.

/// Session proposal summary for a submission.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CfsSessionProposal {
    /// Session proposal identifier.
    pub session_proposal_id: Uuid,
    /// Proposal title.
    pub title: String,

    /// Co-speaker information.
    pub co_speaker: Option<UserSummary>,
    /// Proposal description.
    pub description: Option<String>,
    /// Duration in minutes.
    pub duration_minutes: Option<i32>,
    /// Session proposal level identifier.
    pub session_proposal_level_id: Option<String>,
    /// Session proposal level display name.
    pub session_proposal_level_name: Option<String>,
}

/// Event submission summary information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CfsSubmission {
    /// Submission identifier.
    pub cfs_submission_id: Uuid,
    /// Submission creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Session proposal summary information.
    pub session_proposal: CfsSessionProposal,
    /// Speaker information.
    pub speaker: UserSummary,
    /// Submission status identifier.
    pub status_id: String,
    /// Submission status name.
    pub status_name: String,

    /// Action required message for the speaker.
    pub action_required_message: Option<String>,
    /// Linked session identifier.
    pub linked_session_id: Option<Uuid>,
    /// Reviewer information.
    pub reviewed_by: Option<UserSummary>,
    /// Submission last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Notification data for a submission update.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CfsSubmissionNotificationData {
    /// Submission status identifier.
    pub status_id: String,
    /// Submission status name.
    pub status_name: String,
    /// User identifier.
    pub user_id: Uuid,

    /// Action required message for the speaker.
    pub action_required_message: Option<String>,
}

/// Filter parameters for submissions pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CfsSubmissionsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
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

/// Submission update payload.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct CfsSubmissionUpdate {
    /// Submission status identifier.
    #[garde(custom(trimmed_non_empty))]
    pub status_id: String,

    /// Action required message for the speaker.
    #[garde(length(max = MAX_LEN_DESCRIPTION))]
    pub action_required_message: Option<String>,
}
