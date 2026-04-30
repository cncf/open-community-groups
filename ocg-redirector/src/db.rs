//! Database operations for redirect loading.

use std::collections::HashMap;

use anyhow::Result;
use deadpool_postgres::Pool;
use tracing::{instrument, trace};

use crate::router::{CommunityRedirects, Redirects};

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

    /// Loads all redirects keyed by community name and normalized legacy path.
    #[instrument(skip(self), err)]
    pub(crate) async fn load_redirects(&self) -> Result<Redirects> {
        trace!("db: load redirects");

        let db = self.pool.get().await?;

        // Load redirector communities with their optional legacy fallbacks
        let community_rows = db
            .query(
                "select community_name, base_legacy_url from list_redirect_communities()",
                &[],
            )
            .await?;

        // Load concrete path redirects for migrated groups and events
        let redirect_rows = db
            .query(
                "select community_name, legacy_path, new_path from list_redirects()",
                &[],
            )
            .await?;

        let mut redirects = HashMap::new();

        // Seed all known communities so communities without mappings still resolve
        for row in community_rows {
            redirects.insert(
                row.try_get("community_name")?,
                CommunityRedirects {
                    base_legacy_url: row.try_get("base_legacy_url")?,
                    redirects: HashMap::new(),
                },
            );
        }

        // Attach path mappings to their community redirect settings
        for row in redirect_rows {
            let community_name = row.try_get("community_name")?;
            let legacy_path = row.try_get("legacy_path")?;
            let new_path = row.try_get("new_path")?;

            redirects
                .entry(community_name)
                .or_insert_with(CommunityRedirects::default)
                .redirects
                .insert(legacy_path, new_path);
        }

        Ok(redirects)
    }
}
