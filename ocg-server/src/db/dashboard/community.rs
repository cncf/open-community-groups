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
        analytics::CommunityStats,
        event_categories::EventCategoryInput,
        group_categories::GroupCategoryInput,
        groups::Group,
        regions::RegionInput,
        settings::CommunityUpdate,
        team::{CommunityTeamFilters, CommunityTeamOutput},
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

    /// Adds a new event category to the database.
    async fn add_event_category(
        &self,
        community_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<Uuid>;

    /// Adds a new group category to the database.
    async fn add_group_category(
        &self,
        community_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<Uuid>;

    /// Adds a new region to the database.
    async fn add_region(&self, community_id: Uuid, region: &RegionInput) -> Result<Uuid>;

    /// Deactivates a group (sets active=false without deleting).
    async fn deactivate_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Deletes a user from the community team.
    async fn delete_community_team_member(&self, community_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Deletes a group (soft delete by setting active=false).
    async fn delete_group(&self, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Deletes an event category from the database.
    async fn delete_event_category(&self, community_id: Uuid, event_category_id: Uuid) -> Result<()>;

    /// Deletes a group category from the database.
    async fn delete_group_category(&self, community_id: Uuid, group_category_id: Uuid) -> Result<()>;

    /// Deletes a region from the database.
    async fn delete_region(&self, community_id: Uuid, region_id: Uuid) -> Result<()>;

    /// Retrieves analytics statistics for a community.
    async fn get_community_stats(&self, community_id: Uuid) -> Result<CommunityStats>;

    /// Lists all community team members.
    async fn list_community_team_members(
        &self,
        community_id: Uuid,
        filters: &CommunityTeamFilters,
    ) -> Result<CommunityTeamOutput>;

    /// Lists all group categories for a community.
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<GroupCategory>>;

    /// Lists all regions for a community.
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<GroupRegion>>;

    /// Lists all communities where the user is a team member.
    async fn list_user_communities(&self, user_id: &Uuid) -> Result<Vec<CommunitySummary>>;

    /// Updates a community's settings.
    async fn update_community(&self, community_id: Uuid, community: &CommunityUpdate) -> Result<()>;

    /// Updates an event category in the database.
    async fn update_event_category(
        &self,
        community_id: Uuid,
        event_category_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<()>;

    /// Updates a group category in the database.
    async fn update_group_category(
        &self,
        community_id: Uuid,
        group_category_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<()>;

    /// Updates a region in the database.
    async fn update_region(&self, community_id: Uuid, region_id: Uuid, region: &RegionInput) -> Result<()>;
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

    /// [`DBDashboardCommunity::add_event_category`]
    #[instrument(skip(self, event_category), err)]
    async fn add_event_category(
        &self,
        community_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<Uuid> {
        trace!("db: add event category");

        let db = self.pool.get().await?;
        let event_category_id = db
            .query_one(
                "select add_event_category($1::uuid, $2::jsonb)::uuid",
                &[&community_id, &Json(event_category)],
            )
            .await?
            .get(0);

        Ok(event_category_id)
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

    /// [`DBDashboardCommunity::add_group_category`]
    #[instrument(skip(self, group_category), err)]
    async fn add_group_category(
        &self,
        community_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<Uuid> {
        trace!("db: add group category");

        let db = self.pool.get().await?;
        let group_category_id = db
            .query_one(
                "select add_group_category($1::uuid, $2::jsonb)::uuid",
                &[&community_id, &Json(group_category)],
            )
            .await?
            .get(0);

        Ok(group_category_id)
    }

    /// [`DBDashboardCommunity::add_region`]
    #[instrument(skip(self, region), err)]
    async fn add_region(&self, community_id: Uuid, region: &RegionInput) -> Result<Uuid> {
        trace!("db: add region");

        let db = self.pool.get().await?;
        let region_id = db
            .query_one(
                "select add_region($1::uuid, $2::jsonb)::uuid",
                &[&community_id, &Json(region)],
            )
            .await?
            .get(0);

        Ok(region_id)
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

    /// [`DBDashboardCommunity::delete_event_category`]
    #[instrument(skip(self), err)]
    async fn delete_event_category(&self, community_id: Uuid, event_category_id: Uuid) -> Result<()> {
        trace!("db: delete event category");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_event_category($1::uuid, $2::uuid)",
            &[&community_id, &event_category_id],
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

    /// [`DBDashboardCommunity::delete_group_category`]
    #[instrument(skip(self), err)]
    async fn delete_group_category(&self, community_id: Uuid, group_category_id: Uuid) -> Result<()> {
        trace!("db: delete group category");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_group_category($1::uuid, $2::uuid)",
            &[&community_id, &group_category_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::delete_region`]
    #[instrument(skip(self), err)]
    async fn delete_region(&self, community_id: Uuid, region_id: Uuid) -> Result<()> {
        trace!("db: delete region");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_region($1::uuid, $2::uuid)",
            &[&community_id, &region_id],
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
                .query_one("select get_community_stats($1::uuid)", &[&community_id])
                .await?;
            let stats = row.try_get::<_, Json<CommunityStats>>(0)?.0;

            Ok(stats)
        }

        let db = self.pool.get().await?;
        inner(db, community_id).await
    }

    /// [`DBDashboardCommunity::list_community_team_members`]
    #[instrument(skip(self), err)]
    async fn list_community_team_members(
        &self,
        community_id: Uuid,
        filters: &CommunityTeamFilters,
    ) -> Result<CommunityTeamOutput> {
        trace!("db: list community team");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_community_team_members($1::uuid, $2::jsonb)",
                &[&community_id, &Json(filters)],
            )
            .await?;
        let output = row.try_get::<_, Json<CommunityTeamOutput>>(0)?.0;

        Ok(output)
    }

    /// [`DBDashboardCommunity::list_group_categories`]
    #[instrument(skip(self), err)]
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<GroupCategory>> {
        trace!("db: list group categories");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_categories($1::uuid)", &[&community_id])
            .await?;
        let categories = row.try_get::<_, Json<Vec<GroupCategory>>>(0)?.0;

        Ok(categories)
    }

    /// [`DBDashboardCommunity::list_regions`]
    #[instrument(skip(self), err)]
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<GroupRegion>> {
        trace!("db: list regions");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_regions($1::uuid)", &[&community_id])
            .await?;
        let regions = row.try_get::<_, Json<Vec<GroupRegion>>>(0)?.0;

        Ok(regions)
    }

    /// [`DBDashboardCommunity::list_user_communities`]
    #[instrument(skip(self), err)]
    async fn list_user_communities(&self, user_id: &Uuid) -> Result<Vec<CommunitySummary>> {
        trace!("db: list user communities");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_user_communities($1::uuid)", &[&user_id])
            .await?;
        let communities = row.try_get::<_, Json<Vec<CommunitySummary>>>(0)?.0;

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

    /// [`DBDashboardCommunity::update_event_category`]
    #[instrument(skip(self, event_category), err)]
    async fn update_event_category(
        &self,
        community_id: Uuid,
        event_category_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<()> {
        trace!("db: update event category");

        let db = self.pool.get().await?;
        db.execute(
            "select update_event_category($1::uuid, $2::uuid, $3::jsonb)",
            &[&community_id, &event_category_id, &Json(event_category)],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::update_group_category`]
    #[instrument(skip(self, group_category), err)]
    async fn update_group_category(
        &self,
        community_id: Uuid,
        group_category_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<()> {
        trace!("db: update group category");

        let db = self.pool.get().await?;
        db.execute(
            "select update_group_category($1::uuid, $2::uuid, $3::jsonb)",
            &[&community_id, &group_category_id, &Json(group_category)],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardCommunity::update_region`]
    #[instrument(skip(self, region), err)]
    async fn update_region(&self, community_id: Uuid, region_id: Uuid, region: &RegionInput) -> Result<()> {
        trace!("db: update region");

        let db = self.pool.get().await?;
        db.execute(
            "select update_region($1::uuid, $2::uuid, $3::jsonb)",
            &[&community_id, &region_id, &Json(region)],
        )
        .await?;

        Ok(())
    }
}
