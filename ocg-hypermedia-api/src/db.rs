//! This module defines an abstraction layer over the database.

use crate::templates::community::explore::{EventsFilters, GroupsFilters};
use anyhow::Result;
use async_trait::async_trait;
use deadpool_postgres::Pool;
use std::sync::Arc;
use tokio_postgres::types::Json;
use uuid::Uuid;

/// Type alias to represent a string of json data.
pub(crate) type JsonString = String;

/// Abstraction layer over the database. Trait that defines some operations a
/// DB implementation must support.
#[async_trait]
pub(crate) trait DB {
    /// Get the community id from the host provided.
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;

    /// Get data for the community home index template.
    async fn get_community_home_index_data(&self, community_id: Uuid) -> Result<JsonString>;

    /// Get data for the community explore index template.
    async fn get_community_explore_index_data(&self, community_id: Uuid) -> Result<JsonString>;

    /// Search community events that match the criteria provided.
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &EventsFilters,
    ) -> Result<JsonString>;

    /// Search community groups that match the criteria provided.
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &GroupsFilters,
    ) -> Result<JsonString>;
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
    /// [DB::get_community_name]
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

    /// [DB::get_community_home_index_data]
    async fn get_community_home_index_data(&self, community_id: Uuid) -> Result<JsonString> {
        let db = self.pool.get().await?;
        let json_data = db
            .query_one(
                "select get_community_home_index_data($1::uuid)::text",
                &[&community_id],
            )
            .await?
            .get(0);

        Ok(json_data)
    }

    /// [DB::get_community_explore_index_data]
    async fn get_community_explore_index_data(&self, community_id: Uuid) -> Result<JsonString> {
        let db = self.pool.get().await?;
        let json_data = db
            .query_one(
                "select get_community_explore_index_data($1::uuid)::text",
                &[&community_id],
            )
            .await?
            .get(0);

        Ok(json_data)
    }

    /// [DB::search_community_events]
    async fn search_community_events(
        &self,
        community_id: Uuid,
        filters: &EventsFilters,
    ) -> Result<JsonString> {
        let db = self.pool.get().await?;
        let json_data = db
            .query_one(
                "select search_community_events($1::uuid, $2::jsonb)::text",
                &[&community_id, &Json(filters)],
            )
            .await?
            .get(0);

        Ok(json_data)
    }

    /// [DB::search_community_groups]
    async fn search_community_groups(
        &self,
        community_id: Uuid,
        filters: &GroupsFilters,
    ) -> Result<JsonString> {
        let db = self.pool.get().await?;
        let json_data = db
            .query_one(
                "select search_community_groups($1::uuid, $2::jsonb)::text",
                &[&community_id, &Json(filters)],
            )
            .await?
            .get(0);

        Ok(json_data)
    }
}
