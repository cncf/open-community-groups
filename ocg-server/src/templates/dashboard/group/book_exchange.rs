//! Templates and types for group book exchange.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::db::dashboard::common::BookExchangeMember;

/// Group-level book exchange page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/book_exchange.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage book exchange settings and contact details.
    pub can_manage_book_exchange: bool,
    /// Book exchange member lists visible to authorized group members.
    pub members: Vec<BookExchangeMember>,
}
