//! This module defines the templates for the group site.

use askama::Template;

/// Home page template.
#[derive(Debug, Clone, Template)]
#[template(path = "group/home.html")]
pub(crate) struct Home {}
