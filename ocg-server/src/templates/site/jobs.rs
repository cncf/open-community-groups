//! Templates and types for the public jobs pages.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        jobs::{JobFull, JobSummary, JobsFilters},
        pagination::NavigationLinks,
        site::SiteSettings,
    },
};

/// Public jobs listing page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/jobs/page.html")]
pub(crate) struct Page {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Search filters.
    pub filters: JobsFilters,
    /// Matching jobs.
    pub jobs: Vec<JobSummary>,
    /// Total matching jobs.
    pub total: usize,
    /// Pagination links.
    pub navigation_links: NavigationLinks,
}

/// Public job details page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/jobs/details.html")]
pub(crate) struct DetailsPage {
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Job details.
    pub job: JobFull,
}
