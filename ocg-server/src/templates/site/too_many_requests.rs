//! Templates for the page answering a rate-limited document navigation.

use askama::Template;

#[cfg(test)]
mod tests;

// Pages templates.

/// Template for rendering the too many requests page.
///
/// Standalone: the base layout needs site settings, which take a database read.
#[derive(Debug, Clone, Template)]
#[template(path = "site/too_many_requests/page.html")]
pub(crate) struct Page {
    /// Wait message, the same text htmx and fetch callers receive.
    pub message: String,
}
