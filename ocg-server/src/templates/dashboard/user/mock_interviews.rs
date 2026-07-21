//! Templates for user mock interview matches.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::mock_interviews::{MockInterviewRequest, UserMockInterviewMatch, option_label};

/// List page for mock interviews where the current user is a participant.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/mock_interviews_list.html")]
pub(crate) struct ListPage {
    /// Requests submitted by the current user.
    pub requests: Vec<MockInterviewRequest>,
    /// Matches assigned to the current user.
    pub matches: Vec<UserMockInterviewMatch>,
}

impl ListPage {
    /// Returns a human-readable label for a stored mock interview option.
    pub(crate) fn option_label<'a>(&self, value: &'a str) -> &'a str {
        option_label(value)
    }

    /// Returns the number of requests still waiting on an organizer match.
    pub(crate) fn waiting_request_count(&self) -> usize {
        self.requests
            .iter()
            .filter(|request| request.status == "requested")
            .count()
    }

    /// Returns the number of matches needing a schedule or meeting link.
    pub(crate) fn scheduling_needed_count(&self) -> usize {
        self.matches
            .iter()
            .filter(|session| {
                matches!(session.match_.status.as_str(), "matched" | "scheduled")
                    && (session.match_.scheduled_at.is_none()
                        || session.match_.meeting_url.is_none())
            })
            .count()
    }

    /// Returns the number of active assigned sessions.
    pub(crate) fn active_match_count(&self) -> usize {
        self.matches
            .iter()
            .filter(|session| matches!(session.match_.status.as_str(), "matched" | "scheduled"))
            .count()
    }

    /// Returns the number of completed assigned sessions.
    pub(crate) fn completed_match_count(&self) -> usize {
        self.matches
            .iter()
            .filter(|session| session.match_.status == "completed")
            .count()
    }
}
