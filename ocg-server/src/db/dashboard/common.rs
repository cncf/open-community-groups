//! Common database operations shared across different dashboards.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{db::PgDB, templates::dashboard::community::groups::Group};

/// Common database operations for dashboards.
#[async_trait]
pub(crate) trait DBDashboardCommon {
    /// Updates an existing group.
    async fn update_group(&self, group_id: Uuid, group: &Group) -> Result<()>;
}

#[async_trait]
impl DBDashboardCommon for PgDB {
    /// [`DBDashboardCommon::update_group`]
    #[instrument(skip(self, group), err)]
    async fn update_group(&self, group_id: Uuid, group: &Group) -> Result<()> {
        trace!("db: update group");

        let db = self.pool.get().await?;
        db.execute(
            "select update_group($1::uuid, $2::jsonb)",
            &[&group_id, &Json(group)],
        )
        .await?;

        Ok(())
    }
}
