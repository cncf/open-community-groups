//! Database interface for group dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::PgDB;

/// Database trait for group dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardGroup {
    /// Lists all events for a group for management.
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl DBDashboardGroup for PgDB {
    async fn list_group_events(&self, _group_id: Uuid) -> Result<Vec<EventSummary>> {
        // Placeholder implementation - will be implemented later
        Ok(vec![])
    }
}

/// Summary of an event for listing in the group dashboard.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventSummary {
    pub event_id: Uuid,
    pub name: String,
    pub slug: String,

    pub attendees_count: Option<i64>,
    pub date: Option<String>,
    pub status: Option<String>,
}
