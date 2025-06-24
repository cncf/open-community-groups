//! This module defines the templates for the group site.

use askama::Template;

/// Group page template.
#[derive(Debug, Clone, Template)]
#[template(path = "group/page.html")]
pub(crate) struct Page {}
