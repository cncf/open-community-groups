//! Templates and types for user session proposals.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        common::UserSummary,
        dashboard,
        pagination::{self, Pagination, ToRawQuery},
    },
    validation::{MAX_LEN_DESCRIPTION, MAX_LEN_ENTITY_NAME, MAX_PAGINATION_LIMIT, trimmed_non_empty},
};

// Pages templates.

/// List session proposals page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/session_proposals_list.html")]
pub(crate) struct ListPage {
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Available session proposal levels.
    pub session_proposal_levels: Vec<SessionProposalLevel>,
    /// List of session proposals.
    pub session_proposals: Vec<SessionProposal>,
    /// Total number of session proposals.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
}

// Types.
/// Session proposal summary information.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SessionProposal {
    /// Proposal creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Proposal description.
    pub description: String,
    /// Duration in minutes.
    pub duration_minutes: i32,
    /// Whether the proposal has submissions.
    pub has_submissions: bool,
    /// Session proposal identifier.
    pub session_proposal_id: Uuid,
    /// Session proposal level identifier.
    pub session_proposal_level_id: String,
    /// Session proposal level display name.
    pub session_proposal_level_name: String,
    /// Proposal title.
    pub title: String,

    /// Co-speaker information.
    pub co_speaker: Option<UserSummary>,
    /// Linked session identifier.
    pub linked_session_id: Option<Uuid>,
    /// Proposal last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

/// Session proposal form input.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct SessionProposalInput {
    /// Proposal description.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Duration in minutes.
    #[garde(range(min = 1))]
    pub duration_minutes: i32,
    /// Session proposal level identifier.
    #[garde(custom(trimmed_non_empty))]
    pub session_proposal_level_id: String,
    /// Proposal title.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_ENTITY_NAME))]
    pub title: String,

    /// Co-speaker user identifier.
    #[garde(skip)]
    pub co_speaker_user_id: Option<Uuid>,
}

/// Session proposal level option.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SessionProposalLevel {
    /// Display name.
    pub display_name: String,
    /// Session proposal level identifier.
    pub session_proposal_level_id: String,
}

/// Filter parameters for session proposals pagination.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct SessionProposalsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(SessionProposalsFilters, limit, offset);

/// Paginated session proposals response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SessionProposalsOutput {
    /// List of session proposals.
    pub session_proposals: Vec<SessionProposal>,
    /// Total number of session proposals.
    pub total: usize,
}
