//! Database interface for group dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tracing::instrument;
use uuid::Uuid;

use crate::{db::PgDB, types::event::EventSummary};

/// Database trait for group dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardGroup {
    /// Lists all events for a group for management.
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl DBDashboardGroup for PgDB {
    /// [`DBDashboardGroup::list_group_events`]
    #[instrument(skip(self), err)]
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_events($1::uuid)::text", &[&group_id])
            .await?;
        let events = EventSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(events)
    }
}
