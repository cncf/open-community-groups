//! Database interface for admin dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tracing::instrument;
use uuid::Uuid;

use crate::{db::PgDB, types::group::GroupSummary};

/// Database trait for admin dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardAdmin {
    /// Lists all groups in a community for management.
    async fn list_community_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>>;
}

#[async_trait]
impl DBDashboardAdmin for PgDB {
    /// [`DBDashboardAdmin::list_community_groups`]
    #[instrument(skip(self), err)]
    async fn list_community_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_community_groups($1::uuid)::text", &[&community_id])
            .await?;
        let groups = GroupSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(groups)
    }
}
