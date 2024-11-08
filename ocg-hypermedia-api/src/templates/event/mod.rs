//! This module defines the templates for the event page.

use askama_axum::Template;

/// Event index page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/index.html")]
pub(crate) struct Index {}
