use askama::Template;

/// Home page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/home.html")]
pub(crate) struct Home {}
