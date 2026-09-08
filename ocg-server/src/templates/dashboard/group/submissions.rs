//! Templates for event CFS submissions in the group dashboard.

use askama::Template;
use uuid::Uuid;

use crate::templates::{filters, helpers::user_initials};
use crate::types::{event::EventCfsLabel, pagination};

use crate::types::dashboard::group::submissions::CfsSubmission;

// Pages templates.

/// List submissions page template for an event.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/event_submissions_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event CFS labels available for filtering and submission updates.
    pub event_cfs_labels: Vec<EventCfsLabel>,
    /// Event identifier.
    pub event_id: Uuid,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the submissions list.
    pub refresh_url: String,
    /// Selected CFS label identifiers used to filter submissions.
    pub selected_event_cfs_label_ids: Option<Vec<Uuid>>,
    /// Sort option used to order submissions.
    pub sort: String,
    /// List of submissions.
    pub submissions: Vec<CfsSubmission>,
    /// Total number of submissions.
    pub total: usize,
}
