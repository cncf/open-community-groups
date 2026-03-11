//! Database operations used by the activity tracker.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::db::PgDB;

/// Type aliases.
type Day = String;
type Total = u32;

/// Database interface required by the activity tracker.
#[async_trait]
pub(crate) trait DBActivityTracker {
    /// Updates community page views counters.
    async fn update_community_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()>;

    /// Updates event page views counters.
    async fn update_event_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()>;

    /// Updates group page views counters.
    async fn update_group_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()>;
}

/// Shared database handle for activity tracking operations.
pub(crate) type DynDBActivityTracker = Arc<dyn DBActivityTracker + Send + Sync>;

#[async_trait]
impl DBActivityTracker for PgDB {
    #[instrument(skip(self), err)]
    async fn update_community_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()> {
        trace!("db: update community views");

        let db = self.pool.get().await?;
        db.execute("select update_community_views($1::jsonb)", &[&Json(&data)])
            .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn update_event_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()> {
        trace!("db: update event views");

        let db = self.pool.get().await?;
        db.execute("select update_event_views($1::jsonb)", &[&Json(&data)])
            .await?;

        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn update_group_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()> {
        trace!("db: update group views");

        let db = self.pool.get().await?;
        db.execute("select update_group_views($1::jsonb)", &[&Json(&data)])
            .await?;

        Ok(())
    }
}
