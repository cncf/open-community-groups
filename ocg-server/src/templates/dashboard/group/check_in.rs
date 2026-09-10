//! Templates for group attendee check-in.

use askama::Template;

use crate::types::dashboard::group::check_in::GroupCheckInEvent;
use crate::types::event::EventKind;

// Pages templates.

/// Group check-in event list template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/check_in_list.html")]
pub(crate) struct ListPage {
    /// Events available to the scanner.
    pub events: Vec<GroupCheckInEvent>,
}
