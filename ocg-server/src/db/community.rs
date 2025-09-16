//! This module defines some database functionality for the community site.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::community::{explore, home},
    types::{
        event::{EventKind, EventSummary},
        group::GroupSummary,
    },
};

/// Database trait defining all data access operations for the community site.
#[async_trait]
pub(crate) trait DBCommunity {
    /// Retrieves available filter options for the community explore page.
    async fn get_community_filters_options(&self, community_id: Uuid) -> Result<explore::FiltersOptions>;

    /// Retrieves statistical data for the community home page.
    async fn get_community_home_stats(&self, community_id: Uuid) -> Result<home::Stats>;

    /// Resolves a community ID from the provided hostname.
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;

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
    /// [`DB::get_community_filters_options`]
    #[instrument(skip(self), err)]
    async fn get_community_filters_options(&self, community_id: Uuid) -> Result<explore::FiltersOptions> {
        trace!("db: get community filters options");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_filters_options($1::uuid)::text",
                &[&community_id],
            )
            .await?;
        let filters_options = explore::FiltersOptions::try_from_json(&row.get::<_, String>(0))?;

        Ok(filters_options)
    }

    /// [`DB::get_community_home_stats`]
    #[instrument(skip(self), err)]
    async fn get_community_home_stats(&self, community_id: Uuid) -> Result<home::Stats> {
        trace!("db: get community home stats");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_home_stats($1::uuid)::text",
                &[&community_id],
            )
            .await?;
        let stats = home::Stats::try_from_json(&row.get::<_, String>(0))?;

        Ok(stats)
    }

    /// [`DB::get_community_id`]
    #[instrument(skip(self), err)]
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>> {
        trace!("db: get community id");

        let db = self.pool.get().await?;
        let community_id = db
            .query_opt(
                "select community_id from community where host = $1::text",
                &[&host],
            )
            .await?
            .map(|row| row.get("community_id"));

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
