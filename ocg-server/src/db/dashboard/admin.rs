//! Database interface for admin dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::PgDB;

/// Database trait for admin dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardAdmin {
    /// Lists all groups in a community for management.
    async fn list_community_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>>;
}

#[async_trait]
impl DBDashboardAdmin for PgDB {
    async fn list_community_groups(&self, _community_id: Uuid) -> Result<Vec<GroupSummary>> {
        // Placeholder implementation - will be implemented later
        Ok(vec![])
    }
}

/// Summary of a group for listing in the admin dashboard.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupSummary {
    pub group_id: Uuid,
    pub name: String,
    pub slug: String,

    pub description: Option<String>,
    pub members_count: Option<i64>,
}
