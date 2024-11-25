//! This module defines an abstraction layer over the database.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use deadpool_postgres::Pool;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use uuid::Uuid;

use crate::templates::community::{
    common::{Community, EventKind},
    explore::{self, EventsFilters, GroupsFilters},
    home,
};

/// Abstraction layer over the database. Trait that defines some operations a
/// DB implementation must support.
#[async_trait]
pub(crate) trait DB {
    /// Get community data.
    async fn get_community(&self, community_id: Uuid) -> Result<Community>;

    /// Get filters options used in the community explore page.
    async fn get_community_filters_options(&self, community_id: Uuid) -> Result<explore::FiltersOptions>;

    /// Get some stats for the community home page.
    async fn get_community_home_stats(&self, community_id: Uuid) -> Result<home::Stats>;

    /// Get the community id from the host provided.
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;

    /// Get the groups recently added to the community.
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<home::Group>>;

    /// Get the community upcoming events.
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<home::Event>>;

    /// Search community events that match the criteria provided.
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &EventsFilters,
    ) -> Result<(Vec<explore::Event>, Option<BBox>, Total)>;

    /// Search community groups that match the criteria provided.
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &GroupsFilters,
    ) -> Result<(Vec<explore::Group>, Total)>;
}

/// Type alias to represent a DB trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// DB implementation backed by `PostgreSQL`.
pub(crate) struct PgDB {
    pool: Pool,
}

impl PgDB {
    /// Create a new `PgDB` instance.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DB for PgDB {
    /// [DB::get_community]
    async fn get_community(&self, community_id: Uuid) -> Result<Community> {
        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_community($1::uuid)::text", &[&community_id])
            .await?;
        let community = Community::try_from_json(&row.get::<_, String>(0))?;

        Ok(community)
    }

    /// [DB::get_community_filters_options]
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

    /// [DB::get_community_home_stats]
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

    /// [DB::get_community_id]
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

    /// [DB::get_community_recently_added_groups]
    async fn get_community_recently_added_groups(&self, community_id: Uuid) -> Result<Vec<home::Group>> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_recently_added_groups($1::uuid)::text",
                &[&community_id],
            )
            .await?;
        let groups = home::Group::try_new_vec_from_json(&row.get::<_, String>(0))?;

        Ok(groups)
    }

    /// [DB::get_community_upcoming_events]
    async fn get_community_upcoming_events(
        &self,
        community_id: Uuid,
        event_kinds: Vec<EventKind>,
    ) -> Result<Vec<home::Event>> {
        let event_kinds = event_kinds.into_iter().map(|k| k.to_string()).collect::<Vec<_>>();
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_upcoming_events($1::uuid, $2::text[])::text",
                &[&community_id, &event_kinds],
            )
            .await?;
        let events = home::Event::try_new_vec_from_json(&row.get::<_, String>(0))?;

        Ok(events)
    }

    /// [DB::search_community_events]
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &EventsFilters,
    ) -> Result<(Vec<explore::Event>, Option<BBox>, Total)> {
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

        let events = explore::Event::try_new_vec_from_json(&row.get::<_, String>("events"))?;
        let bbox = if let Some(bbox) = row.get::<_, Option<String>>("bbox") {
            serde_json::from_str(&bbox)?
        } else {
            None
        };
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let total: Total = row.get::<_, i64>("total") as usize;

        Ok((events, bbox, total))
    }

    /// [DB::search_community_groups]
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &GroupsFilters,
    ) -> Result<(Vec<explore::Group>, Total)> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select groups::text, total from search_community_groups($1::uuid, $2::jsonb)",
                &[&community_id, &Json(filters)],
            )
            .await?;
        let groups = explore::Group::try_new_vec_from_json(&row.get::<_, String>("groups"))?;
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let total: Total = row.get::<_, i64>("total") as usize;

        Ok((groups, total))
    }
}

/// Bounding box coordinates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct BBox {
    pub ne_lat: f64,
    pub ne_lon: f64,
    pub sw_lat: f64,
    pub sw_lon: f64,
}

/// Type alias to represent the total count .
pub(crate) type Total = usize;
