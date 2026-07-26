//! Templates for user badge listing, ordering, sharing, and revocation.

use askama::Template;

use crate::types::badges::UserBadge;

// Pages templates.

/// Active user badges dashboard pane.
#[derive(Debug, Clone, Template, serde::Serialize, serde::Deserialize)]
#[template(path = "dashboard/user/badges.html")]
pub(crate) struct ListPage {
    /// Active badge awards in user-selected order.
    pub badges: Vec<UserBadge>,
}
