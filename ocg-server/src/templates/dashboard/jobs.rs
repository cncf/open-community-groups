//! Templates and types for the jobs dashboard.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        jobs::{DashboardJobsFilters, JobSummary},
        pagination::NavigationLinks,
        site::SiteSettings,
    },
};

/// Jobs dashboard page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/jobs.html")]
pub(crate) struct Page {
    /// Flash messages.
    pub messages: Vec<Message>,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Pagination filters.
    pub filters: DashboardJobsFilters,
    /// User-owned jobs.
    pub jobs: Vec<JobSummary>,
    /// Total jobs.
    pub total: usize,
    /// Pagination links.
    pub navigation_links: NavigationLinks,
}
