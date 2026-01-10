//! This module defines the templates for the event page.

use askama::Template;

use crate::{
    templates::{PageId, auth::User, filters, helpers::user_initials},
    types::{
        event::{EventFull, EventKind, EventSummary},
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Event page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {
    /// Detailed information about the event.
    pub event: EventFull,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

/// Event check-in page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "event/check_in_page.html")]
pub(crate) struct CheckInPage {
    /// Whether the check-in window is open.
    pub check_in_window_open: bool,
    /// Event summary being checked into.
    pub event: EventSummary,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Whether the user is an attendee of the event.
    pub user_is_attendee: bool,
    /// Whether the user is already checked in to the event.
    pub user_is_checked_in: bool,
}
