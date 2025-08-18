//! Database interface for community dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::community::{groups::Group, settings::CommunityUpdate},
    types::group::{GroupCategory, GroupRegion, GroupSummary},
};

/// Database trait for community dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardCommunity {
    /// Adds a new group to the database.
    async fn add_group(&self, community_id: Uuid, group: &Group) -> Result<Uuid>;

    /// Deletes a group (soft delete by setting active=false).
    async fn delete_group(&self, group_id: Uuid) -> Result<()>;

    /// Lists all groups in a community for management.
    async fn list_community_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>>;

    /// Lists all group categories for a community.
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<GroupCategory>>;

    /// Lists all regions for a community.
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<GroupRegion>>;

    /// Updates a community's settings.
    async fn update_community(&self, community_id: Uuid, community: &CommunityUpdate) -> Result<()>;
}

#[async_trait]
impl DBDashboardCommunity for PgDB {
    /// [`DBDashboardCommunity::add_group`]
    #[instrument(skip(self, group), err)]
    async fn add_group(&self, community_id: Uuid, group: &Group) -> Result<Uuid> {
        trace!("db: add group");

        let db = self.pool.get().await?;
        let group_id = db
            .query_one(
                "select add_group($1::uuid, $2::jsonb)::uuid",
                &[&community_id, &Json(group)],
            )
            .await?
            .get(0);

        Ok(group_id)
    }

    /// [`DBDashboardCommunity::delete_group`]
    #[instrument(skip(self), err)]
    async fn delete_group(&self, group_id: Uuid) -> Result<()> {
        trace!("db: delete group");

        let db = self.pool.get().await?;
        db.execute("select delete_group($1::uuid)", &[&group_id]).await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::list_community_groups`]
    #[instrument(skip(self), err)]
    async fn list_community_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>> {
        trace!("db: list community groups");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_community_groups($1::uuid)::text", &[&community_id])
            .await?;
        let groups = GroupSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(groups)
    }

    /// [`DBDashboardCommunity::list_group_categories`]
    #[instrument(skip(self), err)]
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<GroupCategory>> {
        trace!("db: list group categories");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_categories($1::uuid)::text", &[&community_id])
            .await?;
        let categories: Vec<GroupCategory> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(categories)
    }

    /// [`DBDashboardCommunity::list_regions`]
    #[instrument(skip(self), err)]
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<GroupRegion>> {
        trace!("db: list regions");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_regions($1::uuid)::text", &[&community_id])
            .await?;
        let regions: Vec<GroupRegion> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(regions)
    }

    /// [`DBDashboardCommunity::update_community`]
    #[instrument(skip(self, community), err)]
    async fn update_community(&self, community_id: Uuid, community: &CommunityUpdate) -> Result<()> {
        trace!("db: update community");

        let db = self.pool.get().await?;
        db.execute(
            "select update_community($1::uuid, $2::jsonb)",
            &[&community_id, &Json(community)],
        )
        .await?;

        Ok(())
    }
}
