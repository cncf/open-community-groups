//! Database interface for group dashboard operations.

use std::{collections::HashMap, time::Duration};

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    services::meetings::MeetingProvider,
    templates::dashboard::group::{
        analytics::GroupDashboardStats,
        attendees::{AttendeesFilters, AttendeesOutput},
        events::{ApprovedSubmissionSummary, CfsSubmissionStatus, Event, EventsListFilters, GroupEvents},
        home::UserGroupsByCommunity,
        members::{GroupMembersFilters, GroupMembersOutput},
        sponsors::{GroupSponsorsFilters, GroupSponsorsOutput, Sponsor},
        submissions::{
            CfsSubmissionNotificationData, CfsSubmissionUpdate, CfsSubmissionsFilters, CfsSubmissionsOutput,
        },
        team::{GroupTeamFilters, GroupTeamOutput},
    },
    types::{
        event::{EventCategory, EventKindSummary as EventKind, SessionKindSummary as SessionKind},
        group::{GroupRole, GroupRoleSummary, GroupSponsor},
    },
};

/// Database trait for group dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardGroup {
    /// Adds a new event to the database.
    async fn add_event(
        &self,
        group_id: Uuid,
        event: &Event,
        cfg_max_participants: &HashMap<MeetingProvider, i32>,
    ) -> Result<Uuid>;

    /// Adds a new sponsor to the database.
    async fn add_group_sponsor(&self, group_id: Uuid, sponsor: &Sponsor) -> Result<Uuid>;

    /// Adds a user to the group team (pending by default).
    async fn add_group_team_member(&self, group_id: Uuid, user_id: Uuid, role: &GroupRole) -> Result<()>;

    /// Cancels an event (sets canceled=true).
    async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Deletes an event (soft delete by setting deleted=true and `deleted_at`).
    async fn delete_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Deletes a sponsor from the database.
    async fn delete_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<()>;

    /// Deletes a user from the group team.
    async fn delete_group_team_member(&self, group_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Gets submission notification data.
    async fn get_cfs_submission_notification_data(
        &self,
        event_id: Uuid,
        cfs_submission_id: Uuid,
    ) -> Result<CfsSubmissionNotificationData>;

    /// Gets a single sponsor from the database.
    async fn get_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<GroupSponsor>;

    /// Retrieves analytics statistics for a group.
    async fn get_group_stats(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupDashboardStats>;

    /// Lists reviewer-available CFS submission statuses.
    async fn list_cfs_submission_statuses_for_review(&self) -> Result<Vec<CfsSubmissionStatus>>;

    /// Lists approved CFS submissions for an event.
    async fn list_event_approved_cfs_submissions(
        &self,
        event_id: Uuid,
    ) -> Result<Vec<ApprovedSubmissionSummary>>;

    /// Lists all verified attendees user ids for an event.
    async fn list_event_attendees_ids(&self, group_id: Uuid, event_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all event categories for a community.
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>>;

    /// Lists CFS submissions for an event.
    async fn list_event_cfs_submissions(
        &self,
        event_id: Uuid,
        filters: &CfsSubmissionsFilters,
    ) -> Result<CfsSubmissionsOutput>;

    /// Lists all available event kinds.
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>>;

    /// Lists all events for a group for management.
    async fn list_group_events(&self, group_id: Uuid, filters: &EventsListFilters) -> Result<GroupEvents>;

    /// Lists all group members.
    async fn list_group_members(
        &self,
        group_id: Uuid,
        filters: &GroupMembersFilters,
    ) -> Result<GroupMembersOutput>;

    /// Lists all group member user ids.
    async fn list_group_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all available group roles.
    async fn list_group_roles(&self) -> Result<Vec<GroupRoleSummary>>;

    /// Lists sponsors for a group.
    /// When `full_list` is true, ignores pagination filters.
    async fn list_group_sponsors(
        &self,
        group_id: Uuid,
        filters: &GroupSponsorsFilters,
        full_list: bool,
    ) -> Result<GroupSponsorsOutput>;

    /// Lists all group team members.
    async fn list_group_team_members(
        &self,
        group_id: Uuid,
        filters: &GroupTeamFilters,
    ) -> Result<GroupTeamOutput>;

    /// Lists all accepted, verified group team member user ids.
    async fn list_group_team_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all available session kinds.
    async fn list_session_kinds(&self) -> Result<Vec<SessionKind>>;

    /// Lists all groups where the user is a team member, grouped by community.
    async fn list_user_groups(&self, user_id: &Uuid) -> Result<Vec<UserGroupsByCommunity>>;

    /// Publishes an event (sets published=true and records publication metadata).
    async fn publish_event(&self, group_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Searches attendees for a group's event using filters.
    async fn search_event_attendees(
        &self,
        group_id: Uuid,
        filters: &AttendeesFilters,
    ) -> Result<AttendeesOutput>;

    /// Unpublishes an event (sets published=false and clears publication metadata).
    async fn unpublish_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Updates a CFS submission for an event.
    async fn update_cfs_submission(
        &self,
        reviewer_id: Uuid,
        event_id: Uuid,
        cfs_submission_id: Uuid,
        submission: &CfsSubmissionUpdate,
    ) -> Result<bool>;

    /// Updates an existing event.
    async fn update_event(
        &self,
        group_id: Uuid,
        event_id: Uuid,
        event: &serde_json::Value,
        cfg_max_participants: &HashMap<MeetingProvider, i32>,
    ) -> Result<()>;

    /// Updates an existing sponsor.
    async fn update_group_sponsor(
        &self,
        group_id: Uuid,
        group_sponsor_id: Uuid,
        sponsor: &Sponsor,
    ) -> Result<()>;

    /// Updates a group team member role.
    async fn update_group_team_member_role(
        &self,
        group_id: Uuid,
        user_id: Uuid,
        role: &GroupRole,
    ) -> Result<()>;
}

#[async_trait]
impl DBDashboardGroup for PgDB {
    /// [`DBDashboardGroup::add_event`]
    #[instrument(skip(self, event, cfg_max_participants), err)]
    async fn add_event(
        &self,
        group_id: Uuid,
        event: &Event,
        cfg_max_participants: &HashMap<MeetingProvider, i32>,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_event($1::uuid, $2::jsonb, $3::jsonb)::uuid",
            &[&group_id, &Json(event), &Json(cfg_max_participants)],
        )
        .await
    }

    /// [`DBDashboardGroup::add_group_sponsor`]
    #[instrument(skip(self, sponsor), err)]
    async fn add_group_sponsor(&self, group_id: Uuid, sponsor: &Sponsor) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_group_sponsor($1::uuid, $2::jsonb)::uuid",
            &[&group_id, &Json(sponsor)],
        )
        .await
    }

    /// [`DBDashboardGroup::add_group_team_member`]
    #[instrument(skip(self), err)]
    async fn add_group_team_member(&self, group_id: Uuid, user_id: Uuid, role: &GroupRole) -> Result<()> {
        self.execute(
            "select add_group_team_member($1::uuid, $2::uuid, $3::text)",
            &[&group_id, &user_id, &role.to_string()],
        )
        .await
    }

    /// [`DBDashboardGroup::cancel_event`]
    #[instrument(skip(self), err)]
    async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        self.execute("select cancel_event($1::uuid, $2::uuid)", &[&group_id, &event_id])
            .await
    }

    /// [`DBDashboardGroup::delete_event`]
    #[instrument(skip(self), err)]
    async fn delete_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        self.execute("select delete_event($1::uuid, $2::uuid)", &[&group_id, &event_id])
            .await
    }

    /// [`DBDashboardGroup::delete_group_sponsor`]
    #[instrument(skip(self), err)]
    async fn delete_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<()> {
        self.execute(
            "select delete_group_sponsor($1::uuid, $2::uuid)",
            &[&group_id, &group_sponsor_id],
        )
        .await
    }

    /// [`DBDashboardGroup::delete_group_team_member`]
    #[instrument(skip(self), err)]
    async fn delete_group_team_member(&self, group_id: Uuid, user_id: Uuid) -> Result<()> {
        self.execute(
            "select delete_group_team_member($1::uuid, $2::uuid)",
            &[&group_id, &user_id],
        )
        .await
    }

    /// [`DBDashboardGroup::get_cfs_submission_notification_data`]
    #[instrument(skip(self), err)]
    async fn get_cfs_submission_notification_data(
        &self,
        event_id: Uuid,
        cfs_submission_id: Uuid,
    ) -> Result<CfsSubmissionNotificationData> {
        self.fetch_json_one(
            "select get_cfs_submission_notification_data($1::uuid, $2::uuid)",
            &[&event_id, &cfs_submission_id],
        )
        .await
    }

    /// [`DBDashboardGroup::get_group_sponsor`]
    #[instrument(skip(self), err)]
    async fn get_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<GroupSponsor> {
        self.fetch_json_one(
            "select get_group_sponsor($1::uuid, $2::uuid)",
            &[&group_sponsor_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardGroup::get_group_stats`]
    #[instrument(skip(self), err)]
    async fn get_group_stats(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupDashboardStats> {
        #[cached(
            time = 21600,
            key = "(Uuid, Uuid)",
            convert = "{ (community_id, group_id) }",
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, community_id: Uuid, group_id: Uuid) -> Result<GroupDashboardStats> {
            let row = db
                .query_one(
                    "select get_group_stats($1::uuid, $2::uuid)",
                    &[&community_id, &group_id],
                )
                .await?;
            let stats = row.try_get::<_, Json<GroupDashboardStats>>(0)?.0;

            Ok(stats)
        }

        let db = self.pool.get().await?;
        inner(db, community_id, group_id).await
    }

    /// [`DBDashboardGroup::list_cfs_submission_statuses_for_review`]
    #[instrument(skip(self), err)]
    async fn list_cfs_submission_statuses_for_review(&self) -> Result<Vec<CfsSubmissionStatus>> {
        self.fetch_json_one("select list_cfs_submission_statuses_for_review()", &[])
            .await
    }

    /// [`DBDashboardGroup::list_event_approved_cfs_submissions`]
    #[instrument(skip(self), err)]
    async fn list_event_approved_cfs_submissions(
        &self,
        event_id: Uuid,
    ) -> Result<Vec<ApprovedSubmissionSummary>> {
        self.fetch_json_one(
            "select list_event_approved_cfs_submissions($1::uuid)",
            &[&event_id],
        )
        .await
    }

    /// [`DBDashboardGroup::list_event_attendees_ids`]
    #[instrument(skip(self), err)]
    async fn list_event_attendees_ids(&self, group_id: Uuid, event_id: Uuid) -> Result<Vec<Uuid>> {
        self.fetch_json_one(
            "select list_event_attendees_ids($1::uuid, $2::uuid)",
            &[&group_id, &event_id],
        )
        .await
    }

    /// [`DBDashboardGroup::list_event_categories`]
    #[instrument(skip(self), err)]
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>> {
        self.fetch_json_one("select list_event_categories($1::uuid)", &[&community_id])
            .await
    }

    /// [`DBDashboardGroup::list_event_cfs_submissions`]
    #[instrument(skip(self, filters), err)]
    async fn list_event_cfs_submissions(
        &self,
        event_id: Uuid,
        filters: &CfsSubmissionsFilters,
    ) -> Result<CfsSubmissionsOutput> {
        self.fetch_json_one(
            "select list_event_cfs_submissions($1::uuid, $2::jsonb)",
            &[&event_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardGroup::list_event_kinds`]
    #[instrument(skip(self), err)]
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from("event_kinds") }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client) -> Result<Vec<EventKind>> {
            let row = db.query_one("select list_event_kinds()", &[]).await?;
            let kinds = row.try_get::<_, Json<Vec<EventKind>>>(0)?.0;

            Ok(kinds)
        }

        let db = self.pool.get().await?;
        inner(db).await
    }

    /// [`DBDashboardGroup::list_group_events`]
    #[instrument(skip(self), err)]
    async fn list_group_events(&self, group_id: Uuid, filters: &EventsListFilters) -> Result<GroupEvents> {
        self.fetch_json_one(
            "select list_group_events($1::uuid, $2::jsonb)",
            &[&group_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardGroup::list_group_members`]
    #[instrument(skip(self), err)]
    async fn list_group_members(
        &self,
        group_id: Uuid,
        filters: &GroupMembersFilters,
    ) -> Result<GroupMembersOutput> {
        self.fetch_json_one(
            "select list_group_members($1::uuid, $2::jsonb)",
            &[&group_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardGroup::list_group_members_ids`]
    #[instrument(skip(self), err)]
    async fn list_group_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>> {
        self.fetch_json_one("select list_group_members_ids($1::uuid)", &[&group_id])
            .await
    }

    /// [`DBDashboardGroup::list_group_roles`]
    #[instrument(skip(self), err)]
    async fn list_group_roles(&self) -> Result<Vec<GroupRoleSummary>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from("group_roles") }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client) -> Result<Vec<GroupRoleSummary>> {
            let row = db.query_one("select list_group_roles()", &[]).await?;
            let roles = row.try_get::<_, Json<Vec<GroupRoleSummary>>>(0)?.0;

            Ok(roles)
        }

        let db = self.pool.get().await?;
        inner(db).await
    }

    /// [`DBDashboardGroup::list_group_sponsors`]
    #[instrument(skip(self), err)]
    async fn list_group_sponsors(
        &self,
        group_id: Uuid,
        filters: &GroupSponsorsFilters,
        full_list: bool,
    ) -> Result<GroupSponsorsOutput> {
        self.fetch_json_one(
            "select list_group_sponsors($1::uuid, $2::jsonb, $3::bool)",
            &[&group_id, &Json(filters), &full_list],
        )
        .await
    }

    /// [`DBDashboardGroup::list_group_team_members`]
    #[instrument(skip(self), err)]
    async fn list_group_team_members(
        &self,
        group_id: Uuid,
        filters: &GroupTeamFilters,
    ) -> Result<GroupTeamOutput> {
        self.fetch_json_one(
            "select list_group_team_members($1::uuid, $2::jsonb)",
            &[&group_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardGroup::list_group_team_members_ids`]
    #[instrument(skip(self), err)]
    async fn list_group_team_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>> {
        self.fetch_json_one("select list_group_team_members_ids($1::uuid)", &[&group_id])
            .await
    }

    /// [`DBDashboardGroup::list_session_kinds`]
    #[instrument(skip(self), err)]
    async fn list_session_kinds(&self) -> Result<Vec<SessionKind>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from("session_kinds") }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client) -> Result<Vec<SessionKind>> {
            let row = db.query_one("select list_session_kinds()", &[]).await?;
            let kinds = row.try_get::<_, Json<Vec<SessionKind>>>(0)?.0;

            Ok(kinds)
        }

        let db = self.pool.get().await?;
        inner(db).await
    }

    /// [`DBDashboardGroup::list_user_groups`]
    #[instrument(skip(self), err)]
    async fn list_user_groups(&self, user_id: &Uuid) -> Result<Vec<UserGroupsByCommunity>> {
        self.fetch_json_one("select list_user_groups($1::uuid)", &[&user_id])
            .await
    }

    /// [`DBDashboardGroup::publish_event`]
    #[instrument(skip(self), err)]
    async fn publish_event(&self, group_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()> {
        self.execute(
            "select publish_event($1::uuid, $2::uuid, $3::uuid)",
            &[&group_id, &event_id, &user_id],
        )
        .await
    }

    /// [`DBDashboardGroup::search_event_attendees`]
    #[instrument(skip(self, filters), err)]
    async fn search_event_attendees(
        &self,
        group_id: Uuid,
        filters: &AttendeesFilters,
    ) -> Result<AttendeesOutput> {
        self.fetch_json_one(
            "select search_event_attendees($1::uuid, $2::jsonb)",
            &[&group_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardGroup::unpublish_event`]
    #[instrument(skip(self), err)]
    async fn unpublish_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        self.execute(
            "select unpublish_event($1::uuid, $2::uuid)",
            &[&group_id, &event_id],
        )
        .await
    }

    /// [`DBDashboardGroup::update_cfs_submission`]
    #[instrument(skip(self, submission), err)]
    async fn update_cfs_submission(
        &self,
        reviewer_id: Uuid,
        event_id: Uuid,
        cfs_submission_id: Uuid,
        submission: &CfsSubmissionUpdate,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select update_cfs_submission($1::uuid, $2::uuid, $3::uuid, $4::jsonb)::bool",
            &[&reviewer_id, &event_id, &cfs_submission_id, &Json(submission)],
        )
        .await
    }

    /// [`DBDashboardGroup::update_event`]
    #[instrument(skip(self, event, cfg_max_participants), err)]
    async fn update_event(
        &self,
        group_id: Uuid,
        event_id: Uuid,
        event: &serde_json::Value,
        cfg_max_participants: &HashMap<MeetingProvider, i32>,
    ) -> Result<()> {
        self.execute(
            "select update_event($1::uuid, $2::uuid, $3::jsonb, $4::jsonb)",
            &[&group_id, &event_id, &Json(event), &Json(cfg_max_participants)],
        )
        .await
    }

    /// [`DBDashboardGroup::update_group_sponsor`]
    #[instrument(skip(self, sponsor), err)]
    async fn update_group_sponsor(
        &self,
        group_id: Uuid,
        group_sponsor_id: Uuid,
        sponsor: &Sponsor,
    ) -> Result<()> {
        self.execute(
            "select update_group_sponsor($1::uuid, $2::uuid, $3::jsonb)",
            &[&group_id, &group_sponsor_id, &Json(sponsor)],
        )
        .await
    }

    /// [`DBDashboardGroup::update_group_team_member_role`]
    #[instrument(skip(self), err)]
    async fn update_group_team_member_role(
        &self,
        group_id: Uuid,
        user_id: Uuid,
        role: &GroupRole,
    ) -> Result<()> {
        self.execute(
            "select update_group_team_member_role($1::uuid, $2::uuid, $3::text)",
            &[&group_id, &user_id, &role.to_string()],
        )
        .await
    }
}
