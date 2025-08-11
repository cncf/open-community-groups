//! Database interface for admin dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::admin::groups::Group,
    types::group::{Category, GroupSummary, Region},
};

/// Database trait for admin dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardAdmin {
    /// Adds a new group to the database.
    async fn add_group(&self, community_id: Uuid, group: &Group) -> Result<Uuid>;

    /// Deletes a group (soft delete by setting active=false).
    async fn delete_group(&self, group_id: Uuid) -> Result<()>;

    /// Lists all groups in a community for management.
    async fn list_community_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>>;

    /// Lists all group categories for a community.
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<Category>>;

    /// Lists all regions for a community.
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<Region>>;

    /// Updates an existing group.
    async fn update_group(&self, group_id: Uuid, group: &Group) -> Result<()>;
}

#[async_trait]
impl DBDashboardAdmin for PgDB {
    /// [`DBDashboardAdmin::add_group`]
    #[instrument(skip(self, group), err)]
    async fn add_group(&self, community_id: Uuid, group: &Group) -> Result<Uuid> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select add_group($1::uuid, $2::jsonb)::uuid",
                &[&community_id, &Json(group)],
            )
            .await?;
        Ok(row.get(0))
    }

    /// [`DBDashboardAdmin::delete_group`]
    #[instrument(skip(self), err)]
    async fn delete_group(&self, group_id: Uuid) -> Result<()> {
        let db = self.pool.get().await?;
        db.execute("select delete_group($1::uuid)", &[&group_id]).await?;
        Ok(())
    }

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

    /// [`DBDashboardAdmin::list_group_categories`]
    #[instrument(skip(self), err)]
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<Category>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_categories($1::uuid)::text", &[&community_id])
            .await?;
        let categories: Vec<Category> = serde_json::from_str(&row.get::<_, String>(0))?;
        Ok(categories)
    }

    /// [`DBDashboardAdmin::list_regions`]
    #[instrument(skip(self), err)]
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<Region>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_regions($1::uuid)::text", &[&community_id])
            .await?;
        let regions: Vec<Region> = serde_json::from_str(&row.get::<_, String>(0))?;
        Ok(regions)
    }

    /// [`DBDashboardAdmin::update_group`]
    #[instrument(skip(self, group), err)]
    async fn update_group(&self, group_id: Uuid, group: &Group) -> Result<()> {
        let db = self.pool.get().await?;
        db.execute(
            "select update_group($1::uuid, $2::jsonb)",
            &[&group_id, &Json(group)],
        )
        .await?;
        Ok(())
    }
}
