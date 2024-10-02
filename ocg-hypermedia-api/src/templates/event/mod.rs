//! This module defines the templates for the event page.

use askama::Template;

/// Home page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/home.html")]
pub(crate) struct Home {}
