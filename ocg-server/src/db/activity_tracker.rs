//! Database operations used by the activity tracker.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::db::PgExecutor;

/// Type aliases.
type Day = String;
type Total = u32;

/// Database interface required by the activity tracker.
#[cfg_attr(test, automock)]
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
impl<T> DBActivityTracker for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self), err)]
    async fn update_community_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()> {
        self.execute("select update_community_views($1::jsonb)", &[&Json(&data)])
            .await
    }

    #[instrument(skip(self), err)]
    async fn update_event_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()> {
        self.execute("select update_event_views($1::jsonb)", &[&Json(&data)])
            .await
    }

    #[instrument(skip(self), err)]
    async fn update_group_views(&self, data: Vec<(Uuid, Day, Total)>) -> Result<()> {
        self.execute("select update_group_views($1::jsonb)", &[&Json(&data)])
            .await
    }
}
