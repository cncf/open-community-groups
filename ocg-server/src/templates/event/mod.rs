//! This module defines the templates for the event page.

use askama::Template;

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        community::Community,
        event::{EventFull, EventKind},
    },
};

// Pages and sections templates.

/// Event page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {
    /// Community information.
    pub community: Community,
    /// Detailed information about the event.
    pub event: EventFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Authenticated user information.
    pub user: User,
}
