//! Templates for dashboard pages.

/// Alliance dashboard templates.
pub(crate) mod alliance;
/// Shared dashboard audit log templates.
pub(crate) mod audit;
/// Group dashboard templates.
pub(crate) mod group;
/// Jobs dashboard templates.
pub(crate) mod jobs;
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
