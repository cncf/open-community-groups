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

    /// Get data for the community index template.
    async fn get_community_index_data(&self, community_id: Uuid) -> Result<community::Index>;
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
                "select community_id from community where host = $1",
                &[&host],
            )
            .await?
            .map(|row| row.get("community_id"));

        Ok(community_id)
    }

    /// [DB::get_community_index_data]
    async fn get_community_index_data(&self, community_id: Uuid) -> Result<community::Index> {
        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_community_index_data($1::uuid)",
                &[&community_id],
            )
            .await?;
        let index = serde_json::from_value(row.get(0)).context("error deserializing index data")?;

        Ok(index)
    }
}
