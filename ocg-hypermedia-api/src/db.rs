//! This module defines an abstraction layer over the database.

use crate::handlers::community;
use anyhow::{Context, Result};
use async_trait::async_trait;
use deadpool_postgres::Pool;
use std::sync::Arc;
use uuid::Uuid;

/// Abstraction layer over the database. Trait that defines some operations a
/// DB implementation must support.
#[async_trait]
pub(crate) trait DB {
    /// Get the community id from the host provided.
    async fn get_community_id(&self, host: &str) -> Result<Option<Uuid>>;

    /// Get data for the community home template.
    async fn get_community_home_data(&self, community_id: Uuid) -> Result<community::Home>;

    /// Get data for the community explore template.
    async fn get_community_explore_data(&self, community_id: Uuid) -> Result<community::Explore>;

    /// Search community events that match the criteria provided.
    async fn search_community_events(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<community::ExploreEvent>>;

    /// Search community groups that match the criteria provided.
    async fn search_community_groups(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<community::ExploreGroup>>;
}

/// Type alias to represent a DB trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// DB implementation backed by PostgreSQL.
pub(crate) struct PgDB {
    pool: Pool,
}

impl PgDB {
    /// Create a new PgDB instance.
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

    /// [DB::get_community_home_data]
    async fn get_community_home_data(&self, community_id: Uuid) -> Result<community::Home> {
        let db = self.pool.get().await?;
        let json_data: serde_json::Value = db
            .query_one("select get_community_home_data($1::uuid)", &[&community_id])
            .await?
            .get(0);
        let home = community::Home::try_from(json_data)?;

        Ok(home)
    }

    /// [DB::get_community_explore_data]
    async fn get_community_explore_data(&self, community_id: Uuid) -> Result<community::Explore> {
        let db = self.pool.get().await?;
        let json_data: serde_json::Value = db
            .query_one(
                "select get_community_explore_data($1::uuid)",
                &[&community_id],
            )
            .await?
            .get(0);
        let explore = community::Explore::try_from(json_data)?;

        Ok(explore)
    }

    /// [DB::search_community_events]
    async fn search_community_events(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<community::ExploreEvent>> {
        let db = self.pool.get().await?;
        let json_data: serde_json::Value = db
            .query_one("select search_community_events($1::uuid)", &[&community_id])
            .await?
            .get(0);
        let events = serde_json::from_value(json_data)
            .context("error deserializing community events json data")?;

        Ok(events)
    }

    /// [DB::search_community_groups]
    async fn search_community_groups(
        &self,
        community_id: Uuid,
    ) -> Result<Vec<community::ExploreGroup>> {
        let db = self.pool.get().await?;
        let json_data: serde_json::Value = db
            .query_one("select search_community_groups($1::uuid)", &[&community_id])
            .await?
            .get(0);
        let groups = serde_json::from_value(json_data)
            .context("error deserializing community groups json data")?;

        Ok(groups)
    }
}
