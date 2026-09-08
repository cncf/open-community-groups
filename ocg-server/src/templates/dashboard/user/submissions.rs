//! Templates for user CFS submissions.

use askama::Template;

use crate::types::dashboard::user::submissions::CfsSubmission;
use crate::types::pagination;

// Pages templates.

/// List submissions page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/submissions_list.html")]
pub(crate) struct ListPage {
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// List of submissions.
    pub submissions: Vec<CfsSubmission>,
    /// Total number of submissions.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
