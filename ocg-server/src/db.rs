//! This module provides a trait-based abstraction layer over database operations.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use deadpool_postgres::Pool;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use tokio_postgres::types::{FromSql, Json, ToSql};

use crate::db::{
    activity_tracker::DBActivityTracker, auth::DBAuth, common::DBCommon, community::DBCommunity,
    dashboard::DBDashboard, event::DBEvent, group::DBGroup, images::DBImages, meetings::DBMeetings,
    notifications::DBNotifications, payments::DBPayments, site::DBSite,
};

/// Module containing authentication database operations.
pub(crate) mod auth;

/// Module containing common database operations.
pub(crate) mod common;

/// Module containing database contract tests.
#[cfg(test)]
mod contract_tests;

/// Module containing database functionality for the community site.
pub(crate) mod community;

/// Module containing database functionality for dashboards.
pub(crate) mod dashboard;

/// Module containing database functionality for the event page.
pub(crate) mod event;

/// Module containing database functionality for the activity tracker.
pub(crate) mod activity_tracker;

/// Module containing database functionality for the group site.
pub(crate) mod group;

/// Module containing database functionality for storing images.
pub(crate) mod images;

/// Module containing database functionality for managing meetings.
pub(crate) mod meetings;

/// Module containing mock database implementation for testing.
#[cfg(test)]
pub(crate) mod mock;

/// Module containing database functionality for managing notifications.
pub(crate) mod notifications;

/// Module containing database functionality for payments and ticketing.
pub(crate) mod payments;

/// Module containing database functionality for global site.
pub(crate) mod site;

/// Database trait defining all data access operations. This is the parent trait
/// that includes all the functionality defined in other traits.
#[async_trait]
pub(crate) trait DB:
    DBAuth
    + DBActivityTracker
    + DBCommon
    + DBCommunity
    + DBDashboard
    + DBEvent
    + DBGroup
    + DBImages
    + DBMeetings
    + DBNotifications
    + DBPayments
    + DBSite
{
}

/// Type alias for a thread-safe, shared database trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// DB implementation backed by `PostgreSQL`.
#[allow(clippy::type_complexity)]
pub(crate) struct PgDB {
    /// Connection pool for `PostgreSQL` clients.
    pool: Pool,
}

impl PgDB {
    /// Creates a new `PgDB` instance with the provided connection pool.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }

    /// Executes a SQL statement, discarding the row count.
    async fn execute(&self, sql: &str, params: &[&(dyn ToSql + Sync)]) -> Result<()> {
        let db = self.pool.get().await?;
        db.execute(sql, params).await?;
        Ok(())
    }

    /// Fetches a single row and deserializes a non-null JSON column.
    async fn fetch_json_one<T: DeserializeOwned>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<T> {
        let db = self.pool.get().await?;
        let row = db.query_one(sql, params).await?;
        let value = row.try_get::<_, Json<T>>(0)?.0;
        Ok(value)
    }

    /// Fetches a single row and deserializes a nullable JSON column.
    async fn fetch_json_opt<T: DeserializeOwned>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<Option<T>> {
        let db = self.pool.get().await?;
        let value = db
            .query_one(sql, params)
            .await?
            .try_get::<_, Option<Json<T>>>(0)?
            .map(|v| v.0);
        Ok(value)
    }

    /// Fetches exactly one row and extracts a scalar column value.
    async fn fetch_scalar_one<T: for<'a> FromSql<'a>>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<T> {
        let db = self.pool.get().await?;
        let value = db.query_one(sql, params).await?.get(0);
        Ok(value)
    }

    /// Fetches at most one row and extracts a scalar column value.
    async fn fetch_scalar_opt<T: for<'a> FromSql<'a>>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<Option<T>> {
        let db = self.pool.get().await?;
        let value = db.query_opt(sql, params).await?.and_then(|row| row.get(0));
        Ok(value)
    }
}

#[async_trait]
impl DB for PgDB {}

/// Geographic bounding box coordinates.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct BBox {
    pub ne_lat: f64,
    pub ne_lon: f64,
    pub sw_lat: f64,
    pub sw_lon: f64,
}

/// Type alias for result counts, used in pagination.
pub(crate) type Total = usize;
