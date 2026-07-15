//! Templates and types for the public jobs pages.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        jobs::{JobFull, JobSummary, JobsFilters},
        mock_interviews::{
            INTERVIEW_TYPE_OPTIONS, LOCATION_OPTIONS, MockInterviewDashboard, MockInterviewOption,
            PRACTICE_ROLE_OPTIONS, SENIORITY_OPTIONS, TARGET_COMPANY_OPTIONS,
        },
        pagination::NavigationLinks,
        site::SiteSettings,
    },
};

/// Public jobs listing page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/jobs/page.html")]
pub(crate) struct Page {
    /// Identifier for the current page.
    #[allow(dead_code)]
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
    #[allow(dead_code)]
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

/// Public mock interviews page.
#[derive(Debug, Clone, Template, Serialize)]
#[template(path = "site/jobs/mock_interviews.html")]
pub(crate) struct MockInterviewsPage {
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Dashboard stats and recent totals.
    pub dashboard: MockInterviewDashboard,
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
        path: String,
        site_settings: SiteSettings,
        user: User,
        dashboard: MockInterviewDashboard,
    ) -> Self {
        Self {
            page_id: PageId::SiteJobs,
            path,
            site_settings,
            user,
            dashboard,
            practice_role_options: PRACTICE_ROLE_OPTIONS
                .iter()
                .copied()
                .filter(|option| matches!(option.value, "interviewee" | "interviewer"))
                .collect(),
            interview_type_options: INTERVIEW_TYPE_OPTIONS.to_vec(),
            target_company_options: TARGET_COMPANY_OPTIONS.to_vec(),
            seniority_options: SENIORITY_OPTIONS.to_vec(),
            location_options: LOCATION_OPTIONS.to_vec(),
        }
    }

    /// Returns the total number of interview type poll votes represented.
    pub(crate) fn interview_type_vote_total(&self) -> i32 {
        self.interview_type_options.iter().map(|option| option.votes).sum()
    }

    /// Returns the most requested interview type label.
    pub(crate) fn top_interview_type_label(&self) -> &str {
        self.interview_type_options
            .first()
            .map_or("Mock interviews", |option| option.label)
    }
}
