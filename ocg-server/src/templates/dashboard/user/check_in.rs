//! Templates for attendee check-in credentials.

use askama::Template;

use crate::types::dashboard::user::check_in::UserCheckInEvent;
use crate::types::event::EventKind;

// Pages templates.

/// User check-in event list template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/check_in_list.html")]
pub(crate) struct ListPage {
    /// Events carrying an attendee credential.
    pub events: Vec<UserCheckInEvent>,
    /// User's display name.
    pub name: String,
    /// User's username.
    pub username: String,

    /// User's profile photo URL.
    pub photo_url: Option<String>,
}
