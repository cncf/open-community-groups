//! This module defines database functionality for the group site.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    types::{
        event::{EventKind, EventSummary},
        group::GroupFull,
    },
};

/// Database trait defining all data access operations for the group site.
#[async_trait]
pub(crate) trait DBGroup {
    /// Retrieves group information.
    async fn get_group_full_by_slug(&self, community_id: Uuid, group_slug: &str) -> Result<GroupFull>;

    /// Retrieves past events for a specific group.
    async fn get_group_past_events(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_kinds: Vec<EventKind>,
        limit: i32,
    ) -> Result<Vec<EventSummary>>;

    /// Retrieves upcoming events for a specific group.
    async fn get_group_upcoming_events(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_kinds: Vec<EventKind>,
        limit: i32,
    ) -> Result<Vec<EventSummary>>;

    /// Checks if a user is a member of a group.
    async fn is_group_member(&self, community_id: Uuid, group_id: Uuid, user_id: Uuid) -> Result<bool>;

    /// Adds a user as a member of a group.
    async fn join_group(&self, community_id: Uuid, group_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Removes a user from a group.
    async fn leave_group(&self, community_id: Uuid, group_id: Uuid, user_id: Uuid) -> Result<()>;
}

#[async_trait]
impl DBGroup for PgDB {
    /// [`DBGroup::get_group_full_by_slug`]
    #[instrument(skip(self), err)]
    async fn get_group_full_by_slug(&self, community_id: Uuid, group_slug: &str) -> Result<GroupFull> {
        trace!("db: get group");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group_full_by_slug($1::uuid, $2::text)::text",
                &[&community_id, &group_slug],
            )
            .await?;
        let group = GroupFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(group)
    }

    /// [`DB::get_group_past_events`]
    #[instrument(skip(self), err)]
    async fn get_group_past_events(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_kinds: Vec<EventKind>,
        limit: i32,
    ) -> Result<Vec<EventSummary>> {
        trace!("db: get group past events");

        let event_kind_ids: Vec<String> = event_kinds.iter().map(ToString::to_string).collect();
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group_past_events($1::uuid, $2::text, $3::text[], $4::int)::text",
                &[&community_id, &group_slug, &event_kind_ids, &limit],
            )
            .await?;
        let events = EventSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(events)
    }

    /// [`DB::get_group_upcoming_events`]
    #[instrument(skip(self), err)]
    async fn get_group_upcoming_events(
        &self,
        community_id: Uuid,
        group_slug: &str,
        event_kinds: Vec<EventKind>,
        limit: i32,
    ) -> Result<Vec<EventSummary>> {
        trace!("db: get group upcoming events");

        let event_kind_ids: Vec<String> = event_kinds.iter().map(ToString::to_string).collect();
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group_upcoming_events($1::uuid, $2::text, $3::text[], $4::int)::text",
                &[&community_id, &group_slug, &event_kind_ids, &limit],
            )
            .await?;
        let events = EventSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(events)
    }

    /// [`DB::is_group_member`]
    #[instrument(skip(self), err)]
    async fn is_group_member(&self, community_id: Uuid, group_id: Uuid, user_id: Uuid) -> Result<bool> {
        trace!("db: check group membership");

        let db = self.pool.get().await?;
        let is_group_member = db
            .query_one(
                "select is_group_member($1::uuid, $2::uuid, $3::uuid)",
                &[&community_id, &group_id, &user_id],
            )
            .await?
            .get::<_, bool>(0);

        Ok(is_group_member)
    }

    /// [`DB::join_group`]
    #[instrument(skip(self), err)]
    async fn join_group(&self, community_id: Uuid, group_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: join group");

        let db = self.pool.get().await?;
        db.execute(
            "select join_group($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &group_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DB::leave_group`]
    #[instrument(skip(self), err)]
    async fn leave_group(&self, community_id: Uuid, group_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: leave group");

        let db = self.pool.get().await?;
        db.execute(
            "select leave_group($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &group_id, &user_id],
        )
        .await?;

        Ok(())
    }
}
