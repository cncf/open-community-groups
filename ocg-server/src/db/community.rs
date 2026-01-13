//! This module defines some database functionality for the community site.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::community,
    types::{
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

/// Database trait defining all data access operations for the community site.
#[async_trait]
pub(crate) trait DBCommunity {
    /// Retrieves statistical data for the community page.
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<community::Stats>;

    /// Resolves a community ID from the provided community name.
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>>;

    /// Retrieves the most recently added groups in the community.
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>>;

    /// Retrieves upcoming events for the community.
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>>;
}

#[async_trait]
impl DBCommunity for PgDB {
    /// [`DB::get_community_site_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_site_stats(&self, community_id: Uuid) -> Result<community::Stats> {
        trace!("db: get community site stats");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_site_stats($1::uuid)::text",
                &[&community_id],
            )
            .await?;
        let stats = community::Stats::try_from_json(&row.get::<_, String>(0))?;

        Ok(stats)
    }

    /// [`DB::get_community_id_by_name`]
    #[instrument(skip(self), err)]
    async fn get_community_id_by_name(&self, name: &str) -> Result<Option<Uuid>> {
        trace!("db: get community id by name");

        let db = self.pool.get().await?;
        let community_id = db
            .query_opt("select get_community_id_by_name($1::text)", &[&name])
            .await?
            .map(|row| row.get(0));

        Ok(community_id)
    }

    /// [`DB::get_community_recently_added_groups`]
    #[instrument(skip(self), err)]
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<GroupSummary>> {
        trace!("db: get community recently added groups");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_recently_added_groups($1::uuid)::text",
                &[&community_id],
            )
            .await?;
        let groups = GroupSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(groups)
    }

    /// [`DB::get_community_upcoming_events`]
    #[instrument(skip(self), err)]
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<EventSummary>> {
        trace!("db: get community upcoming events");

        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_upcoming_events($1::uuid, $2::text[])::text",
                &[&community_id, &event_kinds],
            )
            .await?;
        let events = EventSummary::try_from_json_array(&row.get::<_, String>(0))?;

        Ok(events)
    }
}
