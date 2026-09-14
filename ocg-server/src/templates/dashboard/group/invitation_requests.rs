//! Templates for listing event invitation requests in the group dashboard.

use askama::Template;

use crate::types::dashboard::group::invitation_requests::{
    InvitationRequest, InvitationRequestsSort, InvitationRequestsStatusFilter,
};
use crate::{
    templates::helpers::user_initials,
    types::{
        dashboard::group::PresenceFilter, event::EventSummary, pagination,
        questionnaire::QuestionnaireQuestion,
    },
};

// Pages templates.

/// List invitation requests page template for a group's event.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/invitation_requests_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event for which invitation requests are listed.
    pub event: EventSummary,
    /// Invitation requests for the selected event.
    pub invitation_requests: Vec<InvitationRequest>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the invitation request list with the current filters.
    pub refresh_url: String,
    /// Invitation request status filter.
    pub status: InvitationRequestsStatusFilter,
    /// Total number of invitation requests for the selected event.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Registration questions configured for the event.
    pub registration_questions: Vec<QuestionnaireQuestion>,
    /// Sort option used to order invitation requests.
    pub sort: Option<InvitationRequestsSort>,
    /// User title presence filter.
    pub title: Option<PresenceFilter>,
    /// Text search query used to filter invitation requests.
    pub ts_query: Option<String>,
}
