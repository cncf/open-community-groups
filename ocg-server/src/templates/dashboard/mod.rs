//! Templates for dashboard pages.

/// Default pagination limit for dashboard lists.
pub(crate) const DASHBOARD_PAGINATION_LIMIT: usize = 50;

/// Community dashboard templates.
pub(crate) mod community;
/// Group dashboard templates.
pub(crate) mod group;
/// User dashboard templates.
pub(crate) mod user;
