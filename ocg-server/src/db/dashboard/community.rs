//! Database interface for community dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::{
        audit::{AuditLogFilters, AuditLogsOutput},
        community::{
            analytics::CommunityDashboardStats,
            event_categories::EventCategoryInput,
            group_categories::GroupCategoryInput,
            groups::Group,
            regions::RegionInput,
            settings::CommunityUpdate,
            team::{CommunityTeamFilters, CommunityTeamOutput},
        },
    },
    types::{
        community::{CommunityRole, CommunityRoleSummary, CommunitySummary},
        group::{GroupCategory, GroupRegion},
    },
};

/// Database trait for community dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardCommunity {
    /// Activates a group (sets active=true).
    async fn activate_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Adds a user to the community team.
    async fn add_community_team_member(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        user_id: Uuid,
        role: &CommunityRole,
    ) -> Result<()>;

    /// Adds a new group to the database.
    async fn add_group(&self, actor_user_id: Uuid, community_id: Uuid, group: &Group) -> Result<Uuid>;

    /// Adds a new event category to the database.
    async fn add_event_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<Uuid>;

    /// Adds a new group category to the database.
    async fn add_group_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<Uuid>;

    /// Adds a new region to the database.
    async fn add_region(&self, actor_user_id: Uuid, community_id: Uuid, region: &RegionInput)
    -> Result<Uuid>;

    /// Deactivates a group (sets active=false without deleting).
    async fn deactivate_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Deletes a user from the community team.
    async fn delete_community_team_member(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        user_id: Uuid,
    ) -> Result<()>;

    /// Deletes a group (soft delete by setting active=false).
    async fn delete_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Deletes an event category from the database.
    async fn delete_event_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_category_id: Uuid,
    ) -> Result<()>;

    /// Deletes a group category from the database.
    async fn delete_group_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_category_id: Uuid,
    ) -> Result<()>;

    /// Deletes a region from the database.
    async fn delete_region(&self, actor_user_id: Uuid, community_id: Uuid, region_id: Uuid) -> Result<()>;

    /// Retrieves analytics statistics for a community.
    async fn get_community_stats(&self, community_id: Uuid) -> Result<CommunityDashboardStats>;

    /// Lists community dashboard audit log rows.
    async fn list_community_audit_logs(
        &self,
        community_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput>;

    /// Lists all available community roles.
    async fn list_community_roles(&self) -> Result<Vec<CommunityRoleSummary>>;

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
    async fn update_community(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        community: &CommunityUpdate,
    ) -> Result<()>;

    /// Updates a community team member role.
    async fn update_community_team_member_role(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        user_id: Uuid,
        role: &CommunityRole,
    ) -> Result<()>;

    /// Updates an event category in the database.
    async fn update_event_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_category_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<()>;

    /// Updates a group category in the database.
    async fn update_group_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_category_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<()>;

    /// Updates a region in the database.
    async fn update_region(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        region_id: Uuid,
        region: &RegionInput,
    ) -> Result<()>;
}

#[async_trait]
impl DBDashboardCommunity for PgDB {
    /// [`DBDashboardCommunity::activate_group`]
    #[instrument(skip(self), err)]
    async fn activate_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()> {
        self.execute(
            "select activate_group($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::add_community_team_member`]
    #[instrument(skip(self), err)]
    async fn add_community_team_member(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        user_id: Uuid,
        role: &CommunityRole,
    ) -> Result<()> {
        self.execute(
            "select add_community_team_member($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[&actor_user_id, &community_id, &user_id, &role.to_string()],
        )
        .await
    }

    /// [`DBDashboardCommunity::add_event_category`]
    #[instrument(skip(self, event_category), err)]
    async fn add_event_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_event_category($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &community_id, &Json(event_category)],
        )
        .await
    }

    /// [`DBDashboardCommunity::add_group`]
    #[instrument(skip(self, group), err)]
    async fn add_group(&self, actor_user_id: Uuid, community_id: Uuid, group: &Group) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_group($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &community_id, &Json(group)],
        )
        .await
    }

    /// [`DBDashboardCommunity::add_group_category`]
    #[instrument(skip(self, group_category), err)]
    async fn add_group_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_group_category($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &community_id, &Json(group_category)],
        )
        .await
    }

    /// [`DBDashboardCommunity::add_region`]
    #[instrument(skip(self, region), err)]
    async fn add_region(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        region: &RegionInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_region($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &community_id, &Json(region)],
        )
        .await
    }

    /// [`DBDashboardCommunity::deactivate_group`]
    #[instrument(skip(self), err)]
    async fn deactivate_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()> {
        self.execute(
            "select deactivate_group($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::delete_community_team_member`]
    #[instrument(skip(self), err)]
    async fn delete_community_team_member(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        user_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_community_team_member($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &user_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::delete_event_category`]
    #[instrument(skip(self), err)]
    async fn delete_event_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_category_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_event_category($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &event_category_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::delete_group`]
    #[instrument(skip(self), err)]
    async fn delete_group(&self, actor_user_id: Uuid, community_id: Uuid, group_id: Uuid) -> Result<()> {
        self.execute(
            "select delete_group($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::delete_group_category`]
    #[instrument(skip(self), err)]
    async fn delete_group_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_category_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_group_category($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &group_category_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::delete_region`]
    #[instrument(skip(self), err)]
    async fn delete_region(&self, actor_user_id: Uuid, community_id: Uuid, region_id: Uuid) -> Result<()> {
        self.execute(
            "select delete_region($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &community_id, &region_id],
        )
        .await
    }

    /// [`DBDashboardCommunity::get_community_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_stats(&self, community_id: Uuid) -> Result<CommunityDashboardStats> {
        #[cached(
            time = 21600,
            key = "Uuid",
            convert = "{ community_id }",
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, community_id: Uuid) -> Result<CommunityDashboardStats> {
            let row = db
                .query_one("select get_community_stats($1::uuid)", &[&community_id])
                .await?;
            let stats = row.try_get::<_, Json<CommunityDashboardStats>>(0)?.0;

            Ok(stats)
        }

        let db = self.pool.get().await?;
        inner(db, community_id).await
    }

    /// [`DBDashboardCommunity::list_community_audit_logs`]
    #[instrument(skip(self, filters), err)]
    async fn list_community_audit_logs(
        &self,
        community_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput> {
        self.fetch_json_one(
            "select list_community_audit_logs($1::uuid, $2::jsonb)",
            &[&community_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardCommunity::list_community_roles`]
    #[instrument(skip(self), err)]
    async fn list_community_roles(&self) -> Result<Vec<CommunityRoleSummary>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from("community_roles") }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client) -> Result<Vec<CommunityRoleSummary>> {
            let row = db.query_one("select list_community_roles()", &[]).await?;
            let roles = row.try_get::<_, Json<Vec<CommunityRoleSummary>>>(0)?.0;

            Ok(roles)
        }

        let db = self.pool.get().await?;
        inner(db).await
    }

    /// [`DBDashboardCommunity::list_community_team_members`]
    #[instrument(skip(self), err)]
    async fn list_community_team_members(
        &self,
        community_id: Uuid,
        filters: &CommunityTeamFilters,
    ) -> Result<CommunityTeamOutput> {
        self.fetch_json_one(
            "select list_community_team_members($1::uuid, $2::jsonb)",
            &[&community_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardCommunity::list_group_categories`]
    #[instrument(skip(self), err)]
    async fn list_group_categories(&self, community_id: Uuid) -> Result<Vec<GroupCategory>> {
        self.fetch_json_one("select list_group_categories($1::uuid)", &[&community_id])
            .await
    }

    /// [`DBDashboardCommunity::list_regions`]
    #[instrument(skip(self), err)]
    async fn list_regions(&self, community_id: Uuid) -> Result<Vec<GroupRegion>> {
        self.fetch_json_one("select list_regions($1::uuid)", &[&community_id])
            .await
    }

    /// [`DBDashboardCommunity::list_user_communities`]
    #[instrument(skip(self), err)]
    async fn list_user_communities(&self, user_id: &Uuid) -> Result<Vec<CommunitySummary>> {
        self.fetch_json_one("select list_user_communities($1::uuid)", &[&user_id])
            .await
    }

    /// [`DBDashboardCommunity::update_community`]
    #[instrument(skip(self, community), err)]
    async fn update_community(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        community: &CommunityUpdate,
    ) -> Result<()> {
        self.execute(
            "select update_community($1::uuid, $2::uuid, $3::jsonb)",
            &[&actor_user_id, &community_id, &Json(community)],
        )
        .await
    }

    /// [`DBDashboardCommunity::update_community_team_member_role`]
    #[instrument(skip(self), err)]
    async fn update_community_team_member_role(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        user_id: Uuid,
        role: &CommunityRole,
    ) -> Result<()> {
        self.execute(
            "select update_community_team_member_role($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[&actor_user_id, &community_id, &user_id, &role.to_string()],
        )
        .await
    }

    /// [`DBDashboardCommunity::update_event_category`]
    #[instrument(skip(self, event_category), err)]
    async fn update_event_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_category_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<()> {
        self.execute(
            "select update_event_category($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &community_id,
                &event_category_id,
                &Json(event_category),
            ],
        )
        .await
    }

    /// [`DBDashboardCommunity::update_group_category`]
    #[instrument(skip(self, group_category), err)]
    async fn update_group_category(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_category_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<()> {
        self.execute(
            "select update_group_category($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &community_id,
                &group_category_id,
                &Json(group_category),
            ],
        )
        .await
    }

    /// [`DBDashboardCommunity::update_region`]
    #[instrument(skip(self, region), err)]
    async fn update_region(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        region_id: Uuid,
        region: &RegionInput,
    ) -> Result<()> {
        self.execute(
            "select update_region($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[&actor_user_id, &community_id, &region_id, &Json(region)],
        )
        .await
    }
}
