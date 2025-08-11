//! Common database operations shared across different modules.

use anyhow::Result;
use async_trait::async_trait;
use tracing::instrument;
use uuid::Uuid;

use crate::{db::PgDB, types::group::GroupFull};

/// Common database operations trait.
#[async_trait]
pub(crate) trait DBCommon {
    /// Gets a group by ID with full details.
    async fn get_group_full(&self, group_id: Uuid) -> Result<GroupFull>;
}

#[async_trait]
impl DBCommon for PgDB {
    /// [`DBCommon::get_group_full`]
    #[instrument(skip(self), err)]
    async fn get_group_full(&self, group_id: Uuid) -> Result<GroupFull> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_group_full($1::uuid)::text", &[&group_id])
            .await?;
        let group = GroupFull::try_from_json(&row.get::<_, String>(0))?;
        Ok(group)
    }
}