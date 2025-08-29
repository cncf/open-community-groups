//! Common database operations shared across different dashboards.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{db::PgDB, templates::dashboard::community::groups::Group};

/// Common database operations for dashboards.
#[async_trait]
pub(crate) trait DBDashboardCommon {
    /// Searches for users by query within a community.
    async fn search_user(&self, community_id: Uuid, query: &str) -> Result<Vec<User>>;

    /// Updates an existing group.
    async fn update_group(&self, community_id: Uuid, group_id: Uuid, group: &Group) -> Result<()>;
}

#[async_trait]
impl DBDashboardCommon for PgDB {
    /// [`DBDashboardCommon::search_user`]
    #[instrument(skip(self), err)]
    async fn search_user(&self, community_id: Uuid, query: &str) -> Result<Vec<User>> {
        trace!("db: search user");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select search_user($1::uuid, $2::text)", &[&community_id, &query])
            .await?;
        let users = serde_json::from_value(row.get::<_, serde_json::Value>(0))?;

        Ok(users)
    }

    /// [`DBDashboardCommon::update_group`]
    #[instrument(skip(self, group), err)]
    async fn update_group(&self, community_id: Uuid, group_id: Uuid, group: &Group) -> Result<()> {
        trace!("db: update group");

        let db = self.pool.get().await?;
        db.execute(
            "select update_group($1::uuid, $2::uuid, $3::jsonb)",
            &[&community_id, &group_id, &Json(group)],
        )
        .await?;

        Ok(())
    }
}

// Types.

/// User search result.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct User {
    pub username: String,

    pub name: Option<String>,
    pub photo_url: Option<String>,
}
