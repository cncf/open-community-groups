//! This module provides a trait-based abstraction layer over database operations.

use std::sync::Arc;

use async_trait::async_trait;
use deadpool_postgres::Pool;
use serde::{Deserialize, Serialize};

use crate::db::community::DBCommunity;

/// Module containing database functionality for the community site.
pub(crate) mod community;

/// Database trait defining all data access operations. This is the parent trait
/// that includes all the functionality defined in other traits (e.g. `DBCommunity`).
#[async_trait]
pub(crate) trait DB: DBCommunity {}

/// Type alias for a thread-safe, shared database trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// `PostgreSQL` implementation of the database trait.
///
/// Uses deadpool for connection pooling and, in some cases, relies on `PostgreSQL`
/// functions that return JSON (e.g. for complex queries).
pub(crate) struct PgDB {
    pool: Pool,
}

impl PgDB {
    /// Creates a new `PostgreSQL` database instance with the given connection pool.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }
}

impl DB for PgDB {}

/// Geographic bounding box coordinates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct BBox {
    pub ne_lat: f64,
    pub ne_lon: f64,
    pub sw_lat: f64,
    pub sw_lon: f64,
}

/// Type alias for result counts, used in pagination.
pub(crate) type Total = usize;
