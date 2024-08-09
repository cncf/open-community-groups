//! This module defines an abstraction layer over the database.

use deadpool_postgres::Pool;
use std::sync::Arc;

/// Trait that defines some operations a DB implementation must support.
pub(crate) trait DB {}

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

impl DB for PgDB {}
