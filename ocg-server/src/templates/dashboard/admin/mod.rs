//! Templates for the admin dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::db::dashboard::admin::GroupSummary;

pub(crate) mod home;

/// Groups page for the admin dashboard.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/admin/groups.html")]
pub(crate) struct GroupsPage {
    pub groups: Vec<GroupSummary>,
}
