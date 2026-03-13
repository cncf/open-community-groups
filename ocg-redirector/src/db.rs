//! Database operations for redirect loading.

use std::collections::HashMap;

use anyhow::Result;
use deadpool_postgres::Pool;
use tracing::{instrument, trace};

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

    /// Loads all redirects keyed by their normalized legacy path.
    #[instrument(skip(self), err)]
    pub(crate) async fn load_redirects(&self) -> Result<HashMap<String, String>> {
        trace!("db: load redirects");

        let db = self.pool.get().await?;
        let rows = db
            .query("select legacy_path, new_path from list_redirects()", &[])
            .await?;

        let redirects = rows
            .into_iter()
            .map(|row| Ok((row.try_get("legacy_path")?, row.try_get("new_path")?)))
            .collect::<std::result::Result<HashMap<String, String>, tokio_postgres::Error>>()?;

        Ok(redirects)
    }
}
