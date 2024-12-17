//! This module defines the templates for the group site.

use rinja::Template;

/// Group index page template.
#[derive(Debug, Clone, Template)]
#[template(path = "group/index.html")]
pub(crate) struct Index {}
