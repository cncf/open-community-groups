//! Database interface for group dashboard operations.

use std::{collections::HashMap, time::Duration};

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    services::meetings::MeetingProvider,
    templates::dashboard::group::{
        analytics::GroupStats,
        attendees::{Attendee, AttendeesFilters},
        events::{Event, GroupEvents},
        members::GroupMember,
        sponsors::Sponsor,
        team::GroupTeamMember,
    },
    types::{
        event::{EventCategory, EventKindSummary as EventKind, SessionKindSummary as SessionKind},
        group::{GroupRole, GroupRoleSummary, GroupSponsor, UserGroupsByCommunity},
    },
};

/// Database trait for group dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardGroup {
    /// Adds a user to the group team (pending by default).
    async fn add_group_team_member(&self, group_id: Uuid, user_id: Uuid, role: &GroupRole) -> Result<()>;

    /// Adds a new sponsor to the database.
    async fn add_group_sponsor(&self, group_id: Uuid, sponsor: &Sponsor) -> Result<Uuid>;

    /// Adds a new event to the database.
    async fn add_event(
        &self,
        group_id: Uuid,
        event: &Event,
        cfg_max_participants: &HashMap<MeetingProvider, i32>,
    ) -> Result<Uuid>;

    /// Cancels an event (sets canceled=true).
    async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Deletes an event (soft delete by setting deleted=true and `deleted_at`).
    async fn delete_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Deletes a sponsor from the database.
    async fn delete_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<()>;

    /// Deletes a user from the group team.
    async fn delete_group_team_member(&self, group_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Gets a single sponsor from the database.
    async fn get_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<GroupSponsor>;

    /// Retrieves analytics statistics for a group.
    async fn get_group_stats(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupStats>;

    /// Lists all event categories for a community.
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>>;

    /// Lists all available event kinds.
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>>;

    /// Lists all verified attendees user ids for an event.
    async fn list_event_attendees_ids(&self, group_id: Uuid, event_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all events for a group for management.
    async fn list_group_events(&self, group_id: Uuid) -> Result<GroupEvents>;

    /// Lists all group members.
    async fn list_group_members(&self, group_id: Uuid) -> Result<Vec<GroupMember>>;

    /// Lists all group member user ids.
    async fn list_group_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all available group roles.
    async fn list_group_roles(&self) -> Result<Vec<GroupRoleSummary>>;

    /// Lists all sponsors for a group.
    async fn list_group_sponsors(&self, group_id: Uuid) -> Result<Vec<GroupSponsor>>;

    /// Lists all group team members.
    async fn list_group_team_members(&self, group_id: Uuid) -> Result<Vec<GroupTeamMember>>;

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
    ) -> Result<Vec<Attendee>>;

    /// Unpublishes an event (sets published=false and clears publication metadata).
    async fn unpublish_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

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
    /// [`DBDashboardGroup::add_group_team_member`]
    #[instrument(skip(self), err)]
    async fn add_group_team_member(&self, group_id: Uuid, user_id: Uuid, role: &GroupRole) -> Result<()> {
        trace!("db: add group team member");

        let db = self.pool.get().await?;
        db.execute(
            "select add_group_team_member($1::uuid, $2::uuid, $3::text)",
            &[&group_id, &user_id, &role.to_string()],
        )
        .await?;

        Ok(())
    }
    /// [`DBDashboardGroup::add_group_sponsor`]
    #[instrument(skip(self, sponsor), err)]
    async fn add_group_sponsor(&self, group_id: Uuid, sponsor: &Sponsor) -> Result<Uuid> {
        trace!("db: add group sponsor");

        let db = self.pool.get().await?;
        let id = db
            .query_one(
                "select add_group_sponsor($1::uuid, $2::jsonb)::uuid",
                &[&group_id, &Json(sponsor)],
            )
            .await?
            .get(0);

        Ok(id)
    }
    /// [`DBDashboardGroup::add_event`]
    #[instrument(skip(self, event, cfg_max_participants), err)]
    async fn add_event(
        &self,
        group_id: Uuid,
        event: &Event,
        cfg_max_participants: &HashMap<MeetingProvider, i32>,
    ) -> Result<Uuid> {
        trace!("db: add event");

        let db = self.pool.get().await?;
        let event_id = db
            .query_one(
                "select add_event($1::uuid, $2::jsonb, $3::jsonb)::uuid",
                &[&group_id, &Json(event), &Json(cfg_max_participants)],
            )
            .await?
            .get(0);

        Ok(event_id)
    }

    /// [`DBDashboardGroup::cancel_event`]
    #[instrument(skip(self), err)]
    async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        trace!("db: cancel event");

        let db = self.pool.get().await?;
        db.execute("select cancel_event($1::uuid, $2::uuid)", &[&group_id, &event_id])
            .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::delete_event`]
    #[instrument(skip(self), err)]
    async fn delete_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        trace!("db: delete event");

        let db = self.pool.get().await?;
        db.execute("select delete_event($1::uuid, $2::uuid)", &[&group_id, &event_id])
            .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::delete_group_sponsor`]
    #[instrument(skip(self), err)]
    async fn delete_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<()> {
        trace!("db: delete group sponsor");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_group_sponsor($1::uuid, $2::uuid)",
            &[&group_id, &group_sponsor_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::delete_group_team_member`]
    #[instrument(skip(self), err)]
    async fn delete_group_team_member(&self, group_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: delete group team member");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_group_team_member($1::uuid, $2::uuid)",
            &[&group_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::get_group_sponsor`]
    #[instrument(skip(self), err)]
    async fn get_group_sponsor(&self, group_id: Uuid, group_sponsor_id: Uuid) -> Result<GroupSponsor> {
        trace!("db: get group sponsor");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group_sponsor($1::uuid, $2::uuid)::text",
                &[&group_sponsor_id, &group_id],
            )
            .await?;
        let sponsor: GroupSponsor = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(sponsor)
    }

    /// [`DBDashboardGroup::get_group_stats`]
    #[instrument(skip(self), err)]
    async fn get_group_stats(&self, community_id: Uuid, group_id: Uuid) -> Result<GroupStats> {
        #[cached(
            time = 21600,
            key = "(Uuid, Uuid)",
            convert = "{ (community_id, group_id) }",
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client, community_id: Uuid, group_id: Uuid) -> Result<GroupStats> {
            trace!(community_id = ?community_id, group_id = ?group_id, "db: get group stats");

            let row = db
                .query_one(
                    "select get_group_stats($1::uuid, $2::uuid)::text",
                    &[&community_id, &group_id],
                )
                .await?;
            let stats: GroupStats = serde_json::from_str(&row.get::<_, String>(0))?;

            Ok(stats)
        }

        let db = self.pool.get().await?;
        inner(db, community_id, group_id).await
    }

    /// [`DBDashboardGroup::list_event_categories`]
    #[instrument(skip(self), err)]
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>> {
        trace!("db: list event categories");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_event_categories($1::uuid)::text", &[&community_id])
            .await?;
        let categories: Vec<EventCategory> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(categories)
    }

    /// [`DBDashboardGroup::list_event_kinds`]
    #[instrument(skip(self), err)]
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>> {
        trace!("db: list event kinds");

        let db = self.pool.get().await?;
        let row = db.query_one("select list_event_kinds()::text", &[]).await?;
        let kinds: Vec<EventKind> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(kinds)
    }

    /// [`DBDashboardGroup::list_event_attendees_ids`]
    #[instrument(skip(self), err)]
    async fn list_event_attendees_ids(&self, group_id: Uuid, event_id: Uuid) -> Result<Vec<Uuid>> {
        trace!("db: list event attendees ids");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_event_attendees_ids($1::uuid, $2::uuid)::text",
                &[&group_id, &event_id],
            )
            .await?;
        let ids: Vec<Uuid> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(ids)
    }

    /// [`DBDashboardGroup::list_group_events`]
    #[instrument(skip(self), err)]
    async fn list_group_events(&self, group_id: Uuid) -> Result<GroupEvents> {
        trace!("db: list group events");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_events($1::uuid)::text", &[&group_id])
            .await?;
        let events = GroupEvents::try_from_json(&row.get::<_, String>(0))?;

        Ok(events)
    }

    /// [`DBDashboardGroup::list_group_members`]
    #[instrument(skip(self), err)]
    async fn list_group_members(&self, group_id: Uuid) -> Result<Vec<GroupMember>> {
        trace!("db: list group members");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_members($1::uuid)::text", &[&group_id])
            .await?;
        let members = GroupMember::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(members)
    }

    /// [`DBDashboardGroup::list_group_members_ids`]
    #[instrument(skip(self), err)]
    async fn list_group_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>> {
        trace!("db: list group members ids");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_members_ids($1::uuid)::text", &[&group_id])
            .await?;
        let ids: Vec<Uuid> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(ids)
    }

    /// [`DBDashboardGroup::list_group_roles`]
    #[instrument(skip(self), err)]
    async fn list_group_roles(&self) -> Result<Vec<GroupRoleSummary>> {
        trace!("db: list group roles");

        let db = self.pool.get().await?;
        let row = db.query_one("select list_group_roles()::text", &[]).await?;
        let roles: Vec<GroupRoleSummary> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(roles)
    }

    /// [`DBDashboardGroup::list_group_sponsors`]
    #[instrument(skip(self), err)]
    async fn list_group_sponsors(&self, group_id: Uuid) -> Result<Vec<GroupSponsor>> {
        trace!("db: list group sponsors");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_sponsors($1::uuid)::text", &[&group_id])
            .await?;
        let sponsors: Vec<GroupSponsor> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(sponsors)
    }

    /// [`DBDashboardGroup::list_group_team_members`]
    #[instrument(skip(self), err)]
    async fn list_group_team_members(&self, group_id: Uuid) -> Result<Vec<GroupTeamMember>> {
        trace!("db: list group team members");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_team_members($1::uuid)::text", &[&group_id])
            .await?;
        let members = GroupTeamMember::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(members)
    }

    /// [`DBDashboardGroup::list_session_kinds`]
    #[instrument(skip(self), err)]
    async fn list_session_kinds(&self) -> Result<Vec<SessionKind>> {
        trace!("db: list session kinds");

        let db = self.pool.get().await?;
        let row = db.query_one("select list_session_kinds()::text", &[]).await?;
        let kinds: Vec<SessionKind> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(kinds)
    }

    /// [`DBDashboardGroup::list_user_groups`]
    #[instrument(skip(self), err)]
    async fn list_user_groups(&self, user_id: &Uuid) -> Result<Vec<UserGroupsByCommunity>> {
        trace!("db: list user groups");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_user_groups($1::uuid)::text", &[&user_id])
            .await?;
        let groups = UserGroupsByCommunity::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(groups)
    }

    /// [`DBDashboardGroup::publish_event`]
    #[instrument(skip(self), err)]
    async fn publish_event(&self, group_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: publish event");

        let db = self.pool.get().await?;
        db.execute(
            "select publish_event($1::uuid, $2::uuid, $3::uuid)",
            &[&group_id, &event_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::search_event_attendees`]
    #[instrument(skip(self, filters), err)]
    async fn search_event_attendees(
        &self,
        group_id: Uuid,
        filters: &AttendeesFilters,
    ) -> Result<Vec<Attendee>> {
        trace!("db: search event attendees");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select search_event_attendees($1::uuid, $2::jsonb)::text",
                &[&group_id, &Json(filters)],
            )
            .await?;
        let attendees = Attendee::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(attendees)
    }

    /// [`DBDashboardGroup::unpublish_event`]
    #[instrument(skip(self), err)]
    async fn unpublish_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        trace!("db: unpublish event");

        let db = self.pool.get().await?;
        db.execute(
            "select unpublish_event($1::uuid, $2::uuid)",
            &[&group_id, &event_id],
        )
        .await?;

        Ok(())
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
        trace!("db: update event");

        let db = self.pool.get().await?;
        db.execute(
            "select update_event($1::uuid, $2::uuid, $3::jsonb, $4::jsonb)",
            &[&group_id, &event_id, &Json(event), &Json(cfg_max_participants)],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::update_group_sponsor`]
    #[instrument(skip(self, sponsor), err)]
    async fn update_group_sponsor(
        &self,
        group_id: Uuid,
        group_sponsor_id: Uuid,
        sponsor: &Sponsor,
    ) -> Result<()> {
        trace!("db: update group sponsor");

        let db = self.pool.get().await?;
        db.execute(
            "select update_group_sponsor($1::uuid, $2::uuid, $3::jsonb)",
            &[&group_id, &group_sponsor_id, &Json(sponsor)],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::update_group_team_member_role`]
    #[instrument(skip(self), err)]
    async fn update_group_team_member_role(
        &self,
        group_id: Uuid,
        user_id: Uuid,
        role: &GroupRole,
    ) -> Result<()> {
        trace!("db: update group team member role");

        let db = self.pool.get().await?;
        db.execute(
            "select update_group_team_member_role($1::uuid, $2::uuid, $3::text)",
            &[&group_id, &user_id, &role.to_string()],
        )
        .await?;

        Ok(())
    }
}
