//! Templates for user mock interview matches.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::mock_interviews::UserMockInterviewMatch;

/// List page for mock interviews where the current user is a participant.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/mock_interviews_list.html")]
pub(crate) struct ListPage {
    /// Matches assigned to the current user.
    pub matches: Vec<UserMockInterviewMatch>,
}
