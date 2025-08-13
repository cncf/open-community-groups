//! This module defines some database functionality for the community site.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::{BBox, PgDB, Total},
    templates::community::{explore, home},
    types::{
        event::{EventDetailed, EventKind, EventSummary},
        group::{GroupDetailed, GroupSummary},
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

    /// Searches for events within a community based on filter criteria.
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &explore::EventsFilters,
    ) -> Result<SearchCommunityEventsOutput>;

    /// Searches for groups within a community based on filter criteria.
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &explore::GroupsFilters,
    ) -> Result<SearchCommunityGroupsOutput>;
}

#[async_trait]
impl DBCommunity for PgDB {
    /// [`DB::get_community_filters_options`]
    #[instrument(skip(self), err)]
    async fn get_community_filters_options(&self, community_id: Uuid) -> Result<explore::FiltersOptions> {
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

    /// [`DB::search_community_events`]
    #[instrument(skip(self), err)]
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &explore::EventsFilters,
    ) -> Result<SearchCommunityEventsOutput> {
        // Query database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select events::text, bbox::text, total
                from search_community_events($1::uuid, $2::jsonb)
                ",
                &[&community_id, &Json(filters)],
            )
            .await?;

        // Prepare search output
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let output = SearchCommunityEventsOutput {
            events: EventDetailed::try_from_json_array(&row.get::<_, String>("events"))?,
            bbox: if let Some(bbox) = row.get::<_, Option<String>>("bbox") {
                serde_json::from_str(&bbox)?
            } else {
                None
            },
            total: row.get::<_, i64>("total") as usize,
        };

        Ok(output)
    }

    /// [`DB::search_community_groups`]
    #[instrument(skip(self), err)]
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &explore::GroupsFilters,
    ) -> Result<SearchCommunityGroupsOutput> {
        // Query database
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "
                select groups::text, bbox::text, total
                from search_community_groups($1::uuid, $2::jsonb)
                ",
                &[&community_id, &Json(filters)],
            )
            .await?;

        // Prepare search output
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let output = SearchCommunityGroupsOutput {
            groups: GroupDetailed::try_from_json_array(&row.get::<_, String>("groups"))?,
            bbox: if let Some(bbox) = row.get::<_, Option<String>>("bbox") {
                serde_json::from_str(&bbox)?
            } else {
                None
            },
            total: row.get::<_, i64>("total") as usize,
        };

        Ok(output)
    }
}

/// Output structure for community events search operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SearchCommunityEventsOutput {
    pub events: Vec<EventDetailed>,
    pub bbox: Option<BBox>,
    pub total: Total,
}

/// Output structure for community groups search operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SearchCommunityGroupsOutput {
    pub groups: Vec<GroupDetailed>,
    pub bbox: Option<BBox>,
    pub total: Total,
}
