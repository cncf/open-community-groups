//! This module defines the templates for the event page.

use askama::Template;

use crate::types::event::EventFull;

// Pages templates.

/// Event page template.
#[allow(dead_code)]
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {
    /// Detailed information about the event.
    pub event: EventFull,
}
