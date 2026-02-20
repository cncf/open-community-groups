//! This module defines the templates for the event page.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{PageId, auth::User, common::UserSummary, filters, helpers::user_initials},
    types::{
        event::{EventCfsLabel, EventFull, EventKind, EventSummary},
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Event page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {
    /// Detailed information about the event.
    pub event: EventFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Event check-in page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/check_in_page.html")]
pub(crate) struct CheckInPage {
    /// Whether the check-in window is open.
    pub check_in_window_open: bool,
    /// Event summary being checked into.
    pub event: EventSummary,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Whether the user is an attendee of the event.
    pub user_is_attendee: bool,
    /// Whether the user is already checked in to the event.
    pub user_is_checked_in: bool,
}

/// Call for speakers modal template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/cfs_modal.html")]
pub(crate) struct CfsModal {
    /// Event summary information.
    pub event: EventSummary,
    /// Labels available for the event.
    pub labels: Vec<EventCfsLabel>,
    /// List of session proposals for the current user.
    pub session_proposals: Vec<SessionProposal>,
    /// Authenticated user information.
    pub user: User,

    /// Notice message displayed after submissions.
    pub notice: Option<String>,
}

/// Session proposal details for CFS modal.
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
    /// Whether the proposal has already been submitted.
    pub is_submitted: bool,
    /// Session proposal identifier.
    pub session_proposal_id: Uuid,
    /// Session proposal level identifier.
    pub session_proposal_level_id: String,
    /// Session proposal level display name.
    pub session_proposal_level_name: String,
    /// Proposal status identifier.
    pub session_proposal_status_id: String,
    /// Proposal status name.
    pub status_name: String,
    /// Proposal title.
    pub title: String,

    /// Co-speaker information.
    pub co_speaker: Option<UserSummary>,
    /// Submission status identifier.
    pub submission_status_id: Option<String>,
    /// Submission status name.
    pub submission_status_name: Option<String>,
    /// Proposal last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}
