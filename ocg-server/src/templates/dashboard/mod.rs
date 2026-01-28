//! Templates for dashboard pages.

/// Community dashboard templates.
pub(crate) mod community;
/// Group dashboard templates.
pub(crate) mod group;
/// User dashboard templates.
pub(crate) mod user;

/// Default pagination limit for dashboard lists.
pub(crate) const DASHBOARD_PAGINATION_LIMIT: usize = 50;

/// Default dashboard pagination limit for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_limit() -> Option<usize> {
    Some(DASHBOARD_PAGINATION_LIMIT)
}

/// Default dashboard pagination offset for serde.
#[allow(clippy::unnecessary_wraps)]
pub(crate) fn default_offset() -> Option<usize> {
    Some(0)
}
