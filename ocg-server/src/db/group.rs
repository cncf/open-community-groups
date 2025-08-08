//! This module defines database functionality for the group site.

use anyhow::Result;
use async_trait::async_trait;
use tracing::instrument;
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
    async fn get_group(&self, community_id: Uuid, group_slug: &str) -> Result<GroupFull>;

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
}

#[async_trait]
impl DBGroup for PgDB {
    /// [`DB::get_group`]
    #[instrument(skip(self), err)]
    async fn get_group(&self, community_id: Uuid, group_slug: &str) -> Result<GroupFull> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_group($1::uuid, $2::text)::text",
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
}
