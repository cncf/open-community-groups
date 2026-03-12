//! This module provides a trait-based abstraction layer over redirect lookups.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use deadpool_postgres::Pool;
use serde::Deserialize;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};

/// Database trait defining all data access operations.
#[async_trait]
pub(crate) trait DB {
    /// Retrieves a redirect target for the provided legacy path and entity.
    async fn get_redirect_target(
        &self,
        entity: RedirectEntity,
        legacy_path: &str,
    ) -> Result<Option<RedirectTarget>>;
}

/// Type alias for a thread-safe, shared database trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// DB implementation backed by `PostgreSQL`.
pub(crate) struct PgDB {
    /// Connection pool for `PostgreSQL` clients.
    pool: Pool,
}

impl PgDB {
    /// Creates a new `PgDB` instance with the provided connection pool.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DB for PgDB {
    /// [`DB::get_redirect_target`]
    #[instrument(skip(self), err)]
    async fn get_redirect_target(
        &self,
        entity: RedirectEntity,
        legacy_path: &str,
    ) -> Result<Option<RedirectTarget>> {
        trace!(entity = entity.as_ref(), %legacy_path, "db: get redirect target");

        let db = self.pool.get().await?;
        let rows = db
            .query_one(
                "select get_redirect_target($1::text, $2::text)",
                &[&entity.as_ref(), &legacy_path],
            )
            .await?;
        let redirect_target = rows
            .try_get::<_, Option<Json<RedirectTarget>>>(0)?
            .map(|target| target.0);

        Ok(redirect_target)
    }
}

/// Redirect entity types supported by the redirector.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq, strum::AsRefStr)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub(crate) enum RedirectEntity {
    /// Event redirect target.
    Event,
    /// Group redirect target.
    Group,
}

/// Redirect target data needed to build the canonical URL.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub(crate) struct RedirectTarget {
    /// Community name used in the canonical redirect path.
    pub community_name: String,
    /// Entity kind used to build the canonical redirect path.
    pub entity: RedirectEntity,
    /// Group slug used in the canonical redirect path.
    pub group_slug: String,

    /// Event slug used only for event redirect targets.
    pub event_slug: Option<String>,
}

#[cfg(test)]
mockall::mock! {
    /// Mock `DB` struct for testing purposes.
    pub(crate) DB {}

    #[async_trait]
    impl crate::db::DB for DB {
        async fn get_redirect_target(
            &self,
            entity: crate::db::RedirectEntity,
            legacy_path: &str,
        ) -> Result<Option<crate::db::RedirectTarget>>;
    }
}
