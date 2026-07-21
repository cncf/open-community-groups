//! Database interface for alliance dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use cached::cached;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{PgClient, PgExecutor},
    templates::dashboard::{
        alliance::{
            analytics::AllianceDashboardStats,
            create::AllianceCreate,
            event_categories::EventCategoryInput,
            group_categories::GroupCategoryInput,
            groups::Group,
            partner_integrations::PartnerIntegrationInput,
            regions::RegionInput,
            settings::AllianceUpdate,
            team::{AllianceTeamFilters, AllianceTeamOutput},
        },
        audit::{AuditLogFilters, AuditLogsOutput},
    },
    types::{
        alliance::{AllianceRole, AllianceRoleSummary, AllianceSummary},
        group::{GroupCategory, GroupRegion},
        partner_integration::PartnerIntegration,
    },
};

/// Database trait for alliance dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardAlliance {
    /// Activates a group (sets active=true).
    async fn activate_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
    ) -> Result<()>;

    /// Adds a user to the alliance team.
    async fn add_alliance_team_member(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        user_id: Uuid,
        role: &AllianceRole,
    ) -> Result<()>;

    /// Adds a new alliance to the database.
    async fn add_alliance(&self, actor_user_id: Uuid, alliance: &AllianceCreate) -> Result<Uuid>;

    /// Adds a new group to the database.
    async fn add_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group: &Group,
    ) -> Result<Uuid>;

    /// Adds a new event category to the database.
    async fn add_event_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<Uuid>;

    /// Adds a new group category to the database.
    async fn add_group_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<Uuid>;

    /// Adds a new region to the database.
    async fn add_region(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        region: &RegionInput,
    ) -> Result<Uuid>;

    /// Adds a partner integration to an alliance.
    async fn add_partner_integration(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        partner_integration: &PartnerIntegrationInput,
    ) -> Result<Uuid>;

    /// Deactivates a group (sets active=false without deleting).
    async fn deactivate_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
    ) -> Result<()>;

    /// Deletes a user from the alliance team.
    async fn delete_alliance_team_member(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        user_id: Uuid,
    ) -> Result<()>;

    /// Deletes a group (soft delete by setting active=false).
    async fn delete_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
    ) -> Result<()>;

    /// Deletes an event category from the database.
    async fn delete_event_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_category_id: Uuid,
    ) -> Result<()>;

    /// Deletes a group category from the database.
    async fn delete_group_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_category_id: Uuid,
    ) -> Result<()>;

    /// Deletes a region from the database.
    async fn delete_region(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        region_id: Uuid,
    ) -> Result<()>;

    /// Deletes a partner integration from an alliance.
    async fn delete_partner_integration(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        partner_integration_id: Uuid,
    ) -> Result<()>;

    /// Retrieves analytics statistics for a alliance.
    async fn get_alliance_stats(&self, alliance_id: Uuid) -> Result<AllianceDashboardStats>;

    /// Lists alliance dashboard audit log rows.
    async fn list_alliance_audit_logs(
        &self,
        alliance_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput>;

    /// Lists all available alliance roles.
    async fn list_alliance_roles(&self) -> Result<Vec<AllianceRoleSummary>>;

    /// Lists all alliance team members.
    async fn list_alliance_team_members(
        &self,
        alliance_id: Uuid,
        filters: &AllianceTeamFilters,
    ) -> Result<AllianceTeamOutput>;

    /// Lists all group categories for a alliance.
    async fn list_group_categories(&self, alliance_id: Uuid) -> Result<Vec<GroupCategory>>;

    /// Lists all regions for a alliance.
    async fn list_regions(&self, alliance_id: Uuid) -> Result<Vec<GroupRegion>>;

    /// Lists all partner integrations for an alliance.
    async fn list_partner_integrations(&self, alliance_id: Uuid)
    -> Result<Vec<PartnerIntegration>>;

    /// Lists all alliances where the user is a team member.
    async fn list_user_alliances(&self, user_id: &Uuid) -> Result<Vec<AllianceSummary>>;

    /// Updates a alliance's settings.
    async fn update_alliance(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        alliance: &AllianceUpdate,
    ) -> Result<()>;

    /// Updates whether a alliance report is public.
    async fn update_alliance_report_public_enabled(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        enabled: bool,
    ) -> Result<()>;

    /// Updates a alliance team member role.
    async fn update_alliance_team_member_role(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        user_id: Uuid,
        role: &AllianceRole,
    ) -> Result<()>;

    /// Updates an event category in the database.
    async fn update_event_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_category_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<()>;

    /// Updates a group category in the database.
    async fn update_group_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_category_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<()>;

    /// Updates a region in the database.
    async fn update_region(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        region_id: Uuid,
        region: &RegionInput,
    ) -> Result<()>;

    /// Updates a partner integration in an alliance.
    async fn update_partner_integration(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        partner_integration_id: Uuid,
        partner_integration: &PartnerIntegrationInput,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBDashboardAlliance for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBDashboardAlliance::activate_group`]
    #[instrument(skip(self), err)]
    async fn activate_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select activate_group($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_partner_integration`]
    #[instrument(skip(self, partner_integration), err)]
    async fn add_partner_integration(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        partner_integration: &PartnerIntegrationInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_partner_integration($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &alliance_id, &Json(partner_integration)],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_alliance_team_member`]
    #[instrument(skip(self), err)]
    async fn add_alliance_team_member(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        user_id: Uuid,
        role: &AllianceRole,
    ) -> Result<()> {
        self.execute(
            "select add_alliance_team_member($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[&actor_user_id, &alliance_id, &user_id, &role.to_string()],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_alliance`]
    #[instrument(skip(self, alliance), err)]
    async fn add_alliance(&self, actor_user_id: Uuid, alliance: &AllianceCreate) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_alliance($1::uuid, $2::jsonb)::uuid",
            &[&actor_user_id, &Json(alliance)],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_event_category`]
    #[instrument(skip(self, event_category), err)]
    async fn add_event_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_event_category($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &alliance_id, &Json(event_category)],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_group`]
    #[instrument(skip(self, group), err)]
    async fn add_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group: &Group,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_group($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &alliance_id, &Json(group)],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_group_category`]
    #[instrument(skip(self, group_category), err)]
    async fn add_group_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_group_category($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &alliance_id, &Json(group_category)],
        )
        .await
    }

    /// [`DBDashboardAlliance::add_region`]
    #[instrument(skip(self, region), err)]
    async fn add_region(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        region: &RegionInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_region($1::uuid, $2::uuid, $3::jsonb)::uuid",
            &[&actor_user_id, &alliance_id, &Json(region)],
        )
        .await
    }

    /// [`DBDashboardAlliance::deactivate_group`]
    #[instrument(skip(self), err)]
    async fn deactivate_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select deactivate_group($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::delete_alliance_team_member`]
    #[instrument(skip(self), err)]
    async fn delete_alliance_team_member(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        user_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_alliance_team_member($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &user_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::delete_event_category`]
    #[instrument(skip(self), err)]
    async fn delete_event_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_category_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_event_category($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &event_category_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::delete_group`]
    #[instrument(skip(self), err)]
    async fn delete_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_group($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::delete_group_category`]
    #[instrument(skip(self), err)]
    async fn delete_group_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_category_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_group_category($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &group_category_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::delete_region`]
    #[instrument(skip(self), err)]
    async fn delete_region(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        region_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_region($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &region_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::delete_partner_integration`]
    #[instrument(skip(self), err)]
    async fn delete_partner_integration(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        partner_integration_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_partner_integration($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &partner_integration_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::get_alliance_stats`]
    #[instrument(skip(self), err)]
    async fn get_alliance_stats(&self, alliance_id: Uuid) -> Result<AllianceDashboardStats> {
        #[cached(
            ttl = 3600,
            key = "Uuid",
            convert = "{ alliance_id }",
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>, alliance_id: Uuid) -> Result<AllianceDashboardStats> {
            let row = db
                .query_one("select get_alliance_stats($1::uuid)", &[&alliance_id])
                .await?;
            let stats = row.try_get::<_, Json<AllianceDashboardStats>>(0)?.0;

            Ok(stats)
        }

        let db = self.client().await?;
        inner(db, alliance_id).await
    }

    /// [`DBDashboardAlliance::list_alliance_audit_logs`]
    #[instrument(skip(self, filters), err)]
    async fn list_alliance_audit_logs(
        &self,
        alliance_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput> {
        self.fetch_json_one(
            "select list_alliance_audit_logs($1::uuid, $2::jsonb)",
            &[&alliance_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardAlliance::list_alliance_roles`]
    #[instrument(skip(self), err)]
    async fn list_alliance_roles(&self) -> Result<Vec<AllianceRoleSummary>> {
        #[cached(
            ttl = 86400,
            key = "String",
            convert = r#"{ String::from("alliance_roles") }"#,
            sync_writes = "by_key"
        )]
        async fn inner(db: PgClient<'_>) -> Result<Vec<AllianceRoleSummary>> {
            let row = db.query_one("select list_alliance_roles()", &[]).await?;
            let roles = row.try_get::<_, Json<Vec<AllianceRoleSummary>>>(0)?.0;

            Ok(roles)
        }

        let db = self.client().await?;
        inner(db).await
    }

    /// [`DBDashboardAlliance::list_alliance_team_members`]
    #[instrument(skip(self), err)]
    async fn list_alliance_team_members(
        &self,
        alliance_id: Uuid,
        filters: &AllianceTeamFilters,
    ) -> Result<AllianceTeamOutput> {
        self.fetch_json_one(
            "select list_alliance_team_members($1::uuid, $2::jsonb)",
            &[&alliance_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardAlliance::list_group_categories`]
    #[instrument(skip(self), err)]
    async fn list_group_categories(&self, alliance_id: Uuid) -> Result<Vec<GroupCategory>> {
        self.fetch_json_one("select list_group_categories($1::uuid)", &[&alliance_id])
            .await
    }

    /// [`DBDashboardAlliance::list_regions`]
    #[instrument(skip(self), err)]
    async fn list_regions(&self, alliance_id: Uuid) -> Result<Vec<GroupRegion>> {
        self.fetch_json_one("select list_regions($1::uuid)", &[&alliance_id])
            .await
    }

    /// [`DBDashboardAlliance::list_partner_integrations`]
    #[instrument(skip(self), err)]
    async fn list_partner_integrations(
        &self,
        alliance_id: Uuid,
    ) -> Result<Vec<PartnerIntegration>> {
        self.fetch_json_one(
            "select list_partner_integrations($1::uuid)",
            &[&alliance_id],
        )
        .await
    }

    /// [`DBDashboardAlliance::list_user_alliances`]
    #[instrument(skip(self), err)]
    async fn list_user_alliances(&self, user_id: &Uuid) -> Result<Vec<AllianceSummary>> {
        self.fetch_json_one("select list_user_alliances($1::uuid)", &[&user_id])
            .await
    }

    /// [`DBDashboardAlliance::update_alliance`]
    #[instrument(skip(self, alliance), err)]
    async fn update_alliance(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        alliance: &AllianceUpdate,
    ) -> Result<()> {
        self.execute(
            "select update_alliance($1::uuid, $2::uuid, $3::jsonb)",
            &[&actor_user_id, &alliance_id, &Json(alliance)],
        )
        .await
    }

    /// [`DBDashboardAlliance::update_alliance_report_public_enabled`]
    #[instrument(skip(self), err)]
    async fn update_alliance_report_public_enabled(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        enabled: bool,
    ) -> Result<()> {
        self.execute(
            "select update_alliance_report_public_enabled($1::uuid, $2::uuid, $3::bool)",
            &[&actor_user_id, &alliance_id, &enabled],
        )
        .await
    }

    /// [`DBDashboardAlliance::update_alliance_team_member_role`]
    #[instrument(skip(self), err)]
    async fn update_alliance_team_member_role(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        user_id: Uuid,
        role: &AllianceRole,
    ) -> Result<()> {
        self.execute(
            "select update_alliance_team_member_role($1::uuid, $2::uuid, $3::uuid, $4::text)",
            &[&actor_user_id, &alliance_id, &user_id, &role.to_string()],
        )
        .await
    }

    /// [`DBDashboardAlliance::update_event_category`]
    #[instrument(skip(self, event_category), err)]
    async fn update_event_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_category_id: Uuid,
        event_category: &EventCategoryInput,
    ) -> Result<()> {
        self.execute(
            "select update_event_category($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &alliance_id,
                &event_category_id,
                &Json(event_category),
            ],
        )
        .await
    }

    /// [`DBDashboardAlliance::update_group_category`]
    #[instrument(skip(self, group_category), err)]
    async fn update_group_category(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_category_id: Uuid,
        group_category: &GroupCategoryInput,
    ) -> Result<()> {
        self.execute(
            "select update_group_category($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &alliance_id,
                &group_category_id,
                &Json(group_category),
            ],
        )
        .await
    }

    /// [`DBDashboardAlliance::update_region`]
    #[instrument(skip(self, region), err)]
    async fn update_region(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        region_id: Uuid,
        region: &RegionInput,
    ) -> Result<()> {
        self.execute(
            "select update_region($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[&actor_user_id, &alliance_id, &region_id, &Json(region)],
        )
        .await
    }

    /// [`DBDashboardAlliance::update_partner_integration`]
    #[instrument(skip(self, partner_integration), err)]
    async fn update_partner_integration(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        partner_integration_id: Uuid,
        partner_integration: &PartnerIntegrationInput,
    ) -> Result<()> {
        self.execute(
            "select update_partner_integration($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &alliance_id,
                &partner_integration_id,
                &Json(partner_integration),
            ],
        )
        .await
    }
}
