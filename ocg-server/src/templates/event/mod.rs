//! This module defines the templates for the event page.

use askama::Template;

use crate::types::{community::Community, event::EventFull};

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
    /// Current URL path.
    pub path: String,
}
