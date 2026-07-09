//! Templates and types for the jobs dashboard.

use askama::Template;
use axum_messages::{Level, Message};
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        jobs::{DashboardJobsFilters, JobSummary},
        mock_interviews::{
            INTERVIEW_TYPE_OPTIONS, LOCATION_OPTIONS, MockInterviewDashboard,
            MockInterviewFilters, MockInterviewOption, PRACTICE_ROLE_OPTIONS, SENIORITY_OPTIONS,
            TARGET_COMPANY_OPTIONS, option_label,
        },
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

/// Mock interviews dashboard page.
#[derive(Debug, Clone, Template, Serialize)]
#[template(path = "dashboard/jobs/mock_interviews.html")]
pub(crate) struct MockInterviewsPage {
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
    pub filters: MockInterviewFilters,
    /// Queue, matches, and stats.
    pub dashboard: MockInterviewDashboard,
    /// Pagination links.
    pub navigation_links: NavigationLinks,
    /// Practice role options.
    pub practice_role_options: Vec<MockInterviewOption>,
    /// Interview type options.
    pub interview_type_options: Vec<MockInterviewOption>,
    /// Target company options.
    pub target_company_options: Vec<MockInterviewOption>,
    /// Seniority options.
    pub seniority_options: Vec<MockInterviewOption>,
    /// Location options.
    pub location_options: Vec<MockInterviewOption>,
}

impl MockInterviewsPage {
    /// Create with the static poll option lists.
    pub(crate) fn new(
        messages: Vec<Message>,
        path: String,
        site_settings: SiteSettings,
        user: User,
        filters: MockInterviewFilters,
        dashboard: MockInterviewDashboard,
        navigation_links: NavigationLinks,
    ) -> Self {
        Self {
            messages,
            page_id: PageId::JobsDashboard,
            path,
            site_settings,
            user,
            filters,
            dashboard,
            navigation_links,
            practice_role_options: PRACTICE_ROLE_OPTIONS.to_vec(),
            interview_type_options: INTERVIEW_TYPE_OPTIONS.to_vec(),
            target_company_options: TARGET_COMPANY_OPTIONS.to_vec(),
            seniority_options: SENIORITY_OPTIONS.to_vec(),
            location_options: LOCATION_OPTIONS.to_vec(),
        }
    }
}
