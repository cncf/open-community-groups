//! Database interface for community dashboard operations.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::community::{
        analytics::CommunityStats, groups::Group, settings::CommunityUpdate, team::CommunityTeamMember,
    },
    types::{
        community::CommunitySummary,
        group::{GroupCategory, GroupRegion},
    },
};

/// Database trait for community dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardCommunity {
    /// Activates a group (sets active=true).
    async fn activate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Adds a user to the community team.
    async fn add_community_team_member(&self, community_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Adds a new group to the database.
    async fn add_group(&self, community_id: Uuid, group: &Group) -> Result<Uuid>;

    /// Deactivates a group (sets active=false without deleting).
    async fn deactivate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Deletes a user from the community team.
    async fn delete_community_team_member(&self, community_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Deletes a group (soft delete by setting active=false).
    async fn delete_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Retrieves analytics statistics for a community.
    async fn get_community_stats(&self, community_id: Uuid) -> Result<CommunityStats>;

    /// Lists all community team members.
    async fn list_community_team_members(&self, community_id: Uuid) -> Result<Vec<CommunityTeamMember>>;

    /// Lists all group categories for a community.
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<GroupCategory>>;

    /// Lists all regions for a community.
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<GroupRegion>>;

    /// Lists all communities where the user is a team member.
    async fn list_user_communities(&self, user_id: &Uuid) -> Result<Vec<CommunitySummary>>;

    /// Updates a community's settings.
    async fn update_community(&self, community_id: Uuid, community: &CommunityUpdate) -> Result<()>;
}

#[async_trait]
impl DBDashboardCommunity for PgDB {
    /// [`DBDashboardCommunity::activate_group`]
    #[instrument(skip(self), err)]
    async fn activate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()> {
        trace!("db: activate group");

        let db = self.pool.get().await?;
        db.execute(
            "select activate_group($1::uuid, $2::uuid)",
            &[&community_id, &group_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::add_community_team_member`]
    #[instrument(skip(self), err)]
    async fn add_community_team_member(&self, community_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: add community team member");

        let db = self.pool.get().await?;
        db.execute(
            "select add_community_team_member($1::uuid, $2::uuid)",
            &[&community_id, &user_id],
        )
        .await?;

        Ok(())
    }

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

    /// [`DBDashboardCommunity::deactivate_group`]
    #[instrument(skip(self), err)]
    async fn deactivate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()> {
        trace!("db: deactivate group");

        let db = self.pool.get().await?;
        db.execute(
            "select deactivate_group($1::uuid, $2::uuid)",
            &[&community_id, &group_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::delete_community_team_member`]
    #[instrument(skip(self), err)]
    async fn delete_community_team_member(&self, community_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: delete community team member");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_community_team_member($1::uuid, $2::uuid)",
            &[&community_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::delete_group`]
    #[instrument(skip(self), err)]
    async fn delete_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()> {
        trace!("db: delete group");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_group($1::uuid, $2::uuid)",
            &[&community_id, &group_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::get_community_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_stats(&self, community_id: Uuid) -> Result<CommunityStats> {
        #[cached(
            time = 21600,
            key = "Uuid",
            convert = "{ community_id }",
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, community_id: Uuid) -> Result<CommunityStats> {
            trace!(community_id = ?community_id, "db: get community stats");

            let row = db
                .query_one("select get_community_stats($1::uuid)::text", &[&community_id])
                .await?;
            let stats: CommunityStats = serde_json::from_str(&row.get::<_, String>(0))?;

            Ok(stats)
        }

        let db = self.pool.get().await?;
        inner(db, community_id).await
    }

    /// [`DBDashboardCommunity::list_community_team_members`]
    #[instrument(skip(self), err)]
    async fn list_community_team_members(&self, community_id: Uuid) -> Result<Vec<CommunityTeamMember>> {
        trace!("db: list community team");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_community_team_members($1::uuid)::text",
                &[&community_id],
            )
            .await?;
        let members = CommunityTeamMember::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(members)
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

    /// [`DBDashboardCommunity::list_user_communities`]
    #[instrument(skip(self), err)]
    async fn list_user_communities(&self, user_id: &Uuid) -> Result<Vec<CommunitySummary>> {
        trace!("db: list user communities");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_user_communities($1::uuid)::text", &[&user_id])
            .await?;
        let communities: Vec<CommunitySummary> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(communities)
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
