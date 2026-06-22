//! This module provides a trait-based abstraction layer over database operations.

use std::{future::Future, pin::Pin, sync::Arc};

use anyhow::{Context, Result};
use async_trait::async_trait;
use deadpool_postgres::{Client, Pool};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use tokio_postgres::types::{FromSql, Json, ToSql};

use crate::db::{
    activity_tracker::DBActivityTracker, auth::DBAuth, common::DBCommon, alliance::DBAlliance,
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

/// Module containing database functionality for the alliance site.
pub(crate) mod alliance;

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

/// Module containing database pool configuration.
pub(crate) mod pool;

/// Module containing database functionality for global site.
pub(crate) mod site;

/// Database operations supported by root and transaction-scoped handles.
pub(crate) trait DBOperations:
    DBAuth
    + DBActivityTracker
    + DBCommon
    + DBAlliance
    + DBDashboard
    + DBEvent
    + DBGroup
    + DBImages
    + DBMeetings
    + DBNotifications
    + DBPayments
    + DBSite
    + Send
    + Sync
{
}

impl<T> DBOperations for T where
    T: DBAuth
        + DBActivityTracker
        + DBCommon
        + DBAlliance
        + DBDashboard
        + DBEvent
        + DBGroup
        + DBImages
        + DBMeetings
        + DBNotifications
        + DBPayments
        + DBSite
        + Send
        + Sync
{
}

/// Root database handle capable of opening an atomic unit of work.
#[async_trait]
pub(crate) trait DB: DBOperations {
    /// Starts a database unit of work.
    async fn begin(&self) -> Result<DynDBUnitOfWork>;
}

/// Transaction-scoped database unit of work.
#[async_trait]
pub(crate) trait DBUnitOfWork: DBOperations {
    /// Commits all database operations executed through this unit of work.
    async fn commit(self: Box<Self>) -> Result<()>;

    /// Rolls back all database operations executed through this unit of work.
    async fn rollback(self: Box<Self>) -> Result<()>;
}

/// Type alias for a thread-safe, shared database trait object.
pub(crate) type DynDB = Arc<dyn DB + Send + Sync>;

/// Type alias for an owned transaction-scoped database trait object.
pub(crate) type DynDBUnitOfWork = Box<dyn DBUnitOfWork + Send + Sync>;

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
}

#[async_trait]
impl DB for PgDB {
    /// [`DB::begin`].
    async fn begin(&self) -> Result<DynDBUnitOfWork> {
        let client = self.pool.get().await?;
        client.batch_execute("begin").await?;

        Ok(Box::new(PgUnitOfWork {
            client: Some(client),
        }))
    }
}

/// Transaction-scoped DB implementation backed by a pinned `PostgreSQL` client.
pub(crate) struct PgUnitOfWork {
    /// Pinned `PostgreSQL` client used for the unit of work.
    client: Option<Client>,
}

#[async_trait]
impl DBUnitOfWork for PgUnitOfWork {
    /// [`DBUnitOfWork::commit`].
    async fn commit(mut self: Box<Self>) -> Result<()> {
        let client = self.client.take().context("unit of work has already completed")?;

        match client.batch_execute("commit").await {
            Ok(()) => Ok(()),
            Err(err) => {
                let _ = client.batch_execute("rollback").await;
                Err(err.into())
            }
        }
    }

    /// [`DBUnitOfWork::rollback`].
    async fn rollback(mut self: Box<Self>) -> Result<()> {
        let client = self.client.take().context("unit of work has already completed")?;
        client.batch_execute("rollback").await?;
        Ok(())
    }
}

impl Drop for PgUnitOfWork {
    fn drop(&mut self) {
        let Some(client) = self.client.take() else {
            return;
        };

        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                let _ = client.batch_execute("rollback").await;
            });
        }
    }
}

/// Database client source used by PostgreSQL-backed database implementations.
#[async_trait]
pub(crate) trait PgExecutor {
    /// Returns a client for a single database operation.
    async fn client(&self) -> Result<PgClient<'_>>;

    /// Executes a SQL statement, discarding the row count.
    async fn execute(&self, sql: &str, params: &[&(dyn ToSql + Sync)]) -> Result<()> {
        let db = self.client().await?;
        db.execute(sql, params).await?;
        Ok(())
    }

    /// Fetches a single row and deserializes a non-null JSON column.
    async fn fetch_json_one<T: DeserializeOwned + Send>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<T> {
        let db = self.client().await?;
        let row = db.query_one(sql, params).await?;
        let value = row.try_get::<_, Json<T>>(0)?.0;
        Ok(value)
    }

    /// Fetches a single row and deserializes a nullable JSON column.
    async fn fetch_json_opt<T: DeserializeOwned + Send>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<Option<T>> {
        let db = self.client().await?;
        let value = db
            .query_one(sql, params)
            .await?
            .try_get::<_, Option<Json<T>>>(0)?
            .map(|v| v.0);
        Ok(value)
    }

    /// Fetches exactly one row and extracts a scalar column value.
    async fn fetch_scalar_one<T: for<'a> FromSql<'a> + Send>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<T> {
        let db = self.client().await?;
        let value = db.query_one(sql, params).await?.get(0);
        Ok(value)
    }

    /// Fetches at most one row and extracts a scalar column value.
    async fn fetch_scalar_opt<T: for<'a> FromSql<'a> + Send>(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<Option<T>> {
        let db = self.client().await?;
        let value = db.query_opt(sql, params).await?.and_then(|row| row.get(0));
        Ok(value)
    }
}

#[async_trait]
impl PgExecutor for PgDB {
    /// [`PgExecutor::client`].
    async fn client(&self) -> Result<PgClient<'_>> {
        Ok(PgClient::Pooled(Box::new(self.pool.get().await?)))
    }
}

#[async_trait]
impl PgExecutor for PgUnitOfWork {
    /// [`PgExecutor::client`].
    async fn client(&self) -> Result<PgClient<'_>> {
        let client = self.client.as_ref().context("unit of work has already completed")?;

        Ok(PgClient::Pinned(client))
    }
}

/// `PostgreSQL` client used for one database operation.
pub(crate) enum PgClient<'a> {
    /// Client checked out from the pool for this operation.
    Pooled(Box<Client>),
    /// Client pinned to an open unit of work.
    Pinned(&'a Client),
}

impl PgClient<'_> {
    /// Executes a SQL statement.
    pub(crate) async fn execute(&self, sql: &str, params: &[&(dyn ToSql + Sync)]) -> Result<u64> {
        match self {
            Self::Pooled(client) => Ok(client.execute(sql, params).await?),
            Self::Pinned(client) => Ok(client.execute(sql, params).await?),
        }
    }

    /// Executes a SQL query.
    pub(crate) async fn query(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<Vec<tokio_postgres::Row>> {
        match self {
            Self::Pooled(client) => Ok(client.query(sql, params).await?),
            Self::Pinned(client) => Ok(client.query(sql, params).await?),
        }
    }

    /// Fetches exactly one SQL row.
    pub(crate) async fn query_one(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<tokio_postgres::Row> {
        match self {
            Self::Pooled(client) => Ok(client.query_one(sql, params).await?),
            Self::Pinned(client) => Ok(client.query_one(sql, params).await?),
        }
    }

    /// Fetches at most one SQL row.
    pub(crate) async fn query_opt(
        &self,
        sql: &str,
        params: &[&(dyn ToSql + Sync)],
    ) -> Result<Option<tokio_postgres::Row>> {
        match self {
            Self::Pooled(client) => Ok(client.query_opt(sql, params).await?),
            Self::Pinned(client) => Ok(client.query_opt(sql, params).await?),
        }
    }
}

/// Ergonomic transaction helper layered over [`DB::begin`].
#[async_trait]
pub(crate) trait DBExt {
    /// Runs database work atomically and returns the callback output.
    async fn transaction<T, F>(&self, f: F) -> Result<T>
    where
        T: Send,
        F: for<'tx> FnOnce(&'tx dyn DBOperations) -> TransactionFuture<'tx, T> + Send;
}

#[async_trait]
impl<D> DBExt for D
where
    D: DB + Send + Sync + ?Sized,
{
    async fn transaction<T, F>(&self, f: F) -> Result<T>
    where
        T: Send,
        F: for<'tx> FnOnce(&'tx dyn DBOperations) -> TransactionFuture<'tx, T> + Send,
    {
        let uow = self.begin().await?;
        let result = f(uow.as_ref()).await;

        match result {
            Ok(value) => {
                uow.commit().await?;
                Ok(value)
            }
            Err(err) => {
                let _ = uow.rollback().await;
                Err(err)
            }
        }
    }
}

/// Boxed transaction callback future.
pub(crate) type TransactionFuture<'a, T> = Pin<Box<dyn Future<Output = Result<T>> + Send + 'a>>;

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

#[cfg(test)]
mod tests {
    use anyhow::anyhow;

    use crate::db::{DBExt, mock::MockDB};

    #[tokio::test]
    async fn transaction_commits_successful_work() {
        // Setup transaction-scoped database mock
        let mut uow = MockDB::new();
        uow.expect_list_timezones()
            .times(1)
            .returning(|| Ok(vec!["UTC".to_string()]));
        uow.expect_commit().times(1).returning(|| Ok(()));
        uow.expect_rollback().never();

        // Setup root database mock
        let mut db = MockDB::new();
        db.expect_begin().times(1).return_once(|| Ok(Box::new(uow)));

        // Run the transaction helper
        let timezones = db
            .transaction(|tx| Box::pin(async move { tx.list_timezones().await }))
            .await
            .expect("transaction to succeed");

        // Check callback output is returned
        assert_eq!(timezones, vec!["UTC"]);
    }

    #[tokio::test]
    async fn transaction_rolls_back_failed_work() {
        // Setup transaction-scoped database mock
        let mut uow = MockDB::new();
        uow.expect_list_timezones()
            .times(1)
            .returning(|| Err(anyhow!("database failure")));
        uow.expect_commit().never();
        uow.expect_rollback().times(1).returning(|| Ok(()));

        // Setup root database mock
        let mut db = MockDB::new();
        db.expect_begin().times(1).return_once(|| Ok(Box::new(uow)));

        // Run the transaction helper
        let err = db
            .transaction(|tx| Box::pin(async move { tx.list_timezones().await }))
            .await
            .expect_err("transaction to fail");

        // Check original callback error is preserved
        assert_eq!(err.to_string(), "database failure");
    }
}
