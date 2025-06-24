//! This module defines the templates for the event page.

use askama::Template;

/// Event index page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {}
