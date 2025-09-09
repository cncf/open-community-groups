//! Database interface for group dashboard operations.

use anyhow::{Result, bail};
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::group::{
        attendees::{Attendee, AttendeesFilterOptions, AttendeesFilters},
        events::Event,
        members::GroupMember,
        team::GroupTeamMember,
    },
    types::{
        event::{
            EventCategory, EventKindSummary as EventKind, EventSummary, SessionKindSummary as SessionKind,
        },
        group::{GroupRole, GroupRoleSummary, GroupSummary},
    },
};

/// Database trait for group dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardGroup {
    /// Adds a user to the group team (pending by default).
    async fn add_group_team_member(&self, group_id: Uuid, user_id: Uuid, role: &GroupRole) -> Result<()>;

    /// Adds a new event to the database.
    async fn add_event(&self, group_id: Uuid, event: &Event) -> Result<Uuid>;

    /// Archives an event (sets published=false and clears publication metadata).
    async fn archive_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Cancels an event (sets canceled=true).
    async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Deletes an event (soft delete by setting deleted=true and `deleted_at`).
    async fn delete_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()>;

    /// Deletes a user from the group team.
    async fn delete_group_team_member(&self, group_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Returns attendees filters options for a group.
    async fn get_attendees_filters_options(&self, group_id: Uuid) -> Result<AttendeesFilterOptions>;

    /// Lists all event categories for a community.
    async fn list_event_categories(&self, community_id: Uuid) -> Result<Vec<EventCategory>>;

    /// Lists all available event kinds.
    async fn list_event_kinds(&self) -> Result<Vec<EventKind>>;

    /// Lists all verified attendees user ids for an event.
    async fn list_event_attendees_ids(&self, event_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all events for a group for management.
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>>;

    /// Lists all group members.
    async fn list_group_members(&self, group_id: Uuid) -> Result<Vec<GroupMember>>;

    /// Lists all group member user ids.
    async fn list_group_members_ids(&self, group_id: Uuid) -> Result<Vec<Uuid>>;

    /// Lists all available group roles.
    async fn list_group_roles(&self) -> Result<Vec<GroupRoleSummary>>;

    /// Lists all group team members.
    async fn list_group_team_members(&self, group_id: Uuid) -> Result<Vec<GroupTeamMember>>;

    /// Lists all available session kinds.
    async fn list_session_kinds(&self) -> Result<Vec<SessionKind>>;

    /// Lists all groups where the user is a team member.
    async fn list_user_groups(&self, user_id: &Uuid) -> Result<Vec<GroupSummary>>;

    /// Publishes an event (sets published=true and records publication metadata).
    async fn publish_event(&self, group_id: Uuid, event_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Searches attendees for a group's event using filters.
    async fn search_event_attendees(
        &self,
        group_id: Uuid,
        filters: &AttendeesFilters,
    ) -> Result<Vec<Attendee>>;

    /// Updates an existing event.
    async fn update_event(&self, group_id: Uuid, event_id: Uuid, event: &Event) -> Result<()>;

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
    /// [`DBDashboardGroup::add_event`]
    #[instrument(skip(self, event), err)]
    async fn add_event(&self, group_id: Uuid, event: &Event) -> Result<Uuid> {
        trace!("db: add event");

        let db = self.pool.get().await?;
        let event_id = db
            .query_one(
                "select add_event($1::uuid, $2::jsonb)::uuid",
                &[&group_id, &Json(event)],
            )
            .await?
            .get(0);

        Ok(event_id)
    }

    /// [`DBDashboardGroup::archive_event`]
    #[instrument(skip(self), err)]
    async fn archive_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        trace!("db: archive event");

        let db = self.pool.get().await?;
        db.execute(
            "select archive_event($1::uuid, $2::uuid)",
            &[&group_id, &event_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardGroup::cancel_event`]
    #[instrument(skip(self), err)]
    async fn cancel_event(&self, group_id: Uuid, event_id: Uuid) -> Result<()> {
        trace!("db: cancel event");

        let db = self.pool.get().await?;
        let rows_affected = db
            .execute(
                "
                update event set canceled = true
                where event_id = $1
                and group_id = $2
                and deleted = false;
                ",
                &[&event_id, &group_id],
            )
            .await?;
        if rows_affected == 0 {
            bail!("event not found or already deleted");
        }

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

    /// [`DBDashboardGroup::get_attendees_filters_options`]
    #[instrument(skip(self), err)]
    async fn get_attendees_filters_options(&self, group_id: Uuid) -> Result<AttendeesFilterOptions> {
        trace!("db: get attendees filters options");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_attendees_filters_options($1::uuid)::text",
                &[&group_id],
            )
            .await?;
        let filters_options: AttendeesFilterOptions = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(filters_options)
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
    async fn list_event_attendees_ids(&self, event_id: Uuid) -> Result<Vec<Uuid>> {
        trace!("db: list event attendees ids");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_event_attendees_ids($1::uuid)::text", &[&event_id])
            .await?;
        let ids: Vec<Uuid> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(ids)
    }

    /// [`DBDashboardGroup::list_group_events`]
    #[instrument(skip(self), err)]
    async fn list_group_events(&self, group_id: Uuid) -> Result<Vec<EventSummary>> {
        trace!("db: list group events");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_group_events($1::uuid)::text", &[&group_id])
            .await?;
        let events = EventSummary::try_from_json_array(&row.get::<_, String>(0))?;

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
    async fn list_user_groups(&self, user_id: &Uuid) -> Result<Vec<GroupSummary>> {
        trace!("db: list user groups");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_user_groups($1::uuid)::text", &[&user_id])
            .await?;
        let groups = GroupSummary::try_from_json_array(&row.get::<_, String>(0))?;

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

    /// [`DBDashboardGroup::update_event`]
    #[instrument(skip(self, event), err)]
    async fn update_event(&self, group_id: Uuid, event_id: Uuid, event: &Event) -> Result<()> {
        trace!("db: update event");

        let db = self.pool.get().await?;
        db.execute(
            "select update_event($1::uuid, $2::uuid, $3::jsonb)",
            &[&group_id, &event_id, &Json(event)],
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
