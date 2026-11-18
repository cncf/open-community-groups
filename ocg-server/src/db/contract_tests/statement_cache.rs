//! Real-database contracts for the statement cache behind `PgClient`:
//! behaviors that mocks cannot prove.

use anyhow::Result;
use deadpool_postgres::{Client, ManagerConfig, Pool, PoolConfig, RecyclingMethod, Runtime};
use tokio_postgres::{NoTls, error::SqlState};

use crate::db::{DBUnitOfWork, PgDB, PgExecutor, PgUnitOfWork, pool::create_pool};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_statement_cache_evicts_stale_statement_in_unit_of_work() -> Result<()> {
    // Setup a single-connection pool and a session table read through the
    // cache (fast recycling keeps the temp table the default recycle discards)
    let pool = single_connection_pool(RecyclingMethod::Fast)?;
    let db = PgDB::new(pool.clone());
    let sql = "select value from pg_temp.statement_cache_probe";
    create_probe_table(&pool).await?;
    let value: i32 = db.fetch_scalar_one(sql, &[]).await?;
    assert_eq!(value, 1);

    // Change the result type the cached statement reads
    alter_probe_column_type(&pool, "int8").await?;

    // Check the stale statement fails the unit of work on the same connection
    let client = pool.get().await?;
    client.batch_execute("begin").await?;
    let uow = PgUnitOfWork {
        client: Some(client),
    };
    let err = uow
        .fetch_scalar_one::<i64>(sql, &[])
        .await
        .expect_err("a stale statement should fail inside a unit of work");
    let code = err
        .downcast_ref::<tokio_postgres::Error>()
        .and_then(tokio_postgres::Error::code);
    assert_eq!(code, Some(&SqlState::FEATURE_NOT_SUPPORTED));
    Box::new(uow).rollback().await?;

    // Check the stale statement was evicted from the connection
    let client = pool.get().await?;
    assert_eq!(
        prepared_statement_executions(&client, sql).await?,
        Vec::<i64>::new()
    );
    drop(client);

    // Check the next call on the connection prepares the statement again
    let value: i64 = db.fetch_scalar_one(sql, &[]).await?;
    assert_eq!(value, 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_statement_cache_retries_stale_statement_outside_unit_of_work() -> Result<()> {
    // Setup a single-connection pool and a session table read through the
    // cache (fast recycling keeps the temp table the default recycle discards)
    let pool = single_connection_pool(RecyclingMethod::Fast)?;
    let db = PgDB::new(pool.clone());
    let sql = "select value from pg_temp.statement_cache_probe";
    create_probe_table(&pool).await?;
    let value: i32 = db.fetch_scalar_one(sql, &[]).await?;
    assert_eq!(value, 1);

    // Check a pooled call recovers with a freshly prepared statement
    alter_probe_column_type(&pool, "int8").await?;
    let value: i64 = db.fetch_scalar_one(sql, &[]).await?;
    assert_eq!(value, 1);
    let client = pool.get().await?;
    assert_eq!(prepared_statement_executions(&client, sql).await?, vec![1]);
    drop(client);

    // Check a call on a client borrowed from a pooled operation recovers too
    alter_probe_column_type(&pool, "int4").await?;
    let pooled_client = db.client().await?;
    let value: i32 = pooled_client.fetch_scalar_one(sql, &[]).await?;
    assert_eq!(value, 1);
    drop(pooled_client);
    let client = pool.get().await?;
    assert_eq!(prepared_statement_executions(&client, sql).await?, vec![1]);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_statement_cache_reuses_statement_across_checkouts() -> Result<()> {
    // Setup a single-connection pool with the server's default recycling
    let mut cfg = contract_tests_config()?;
    cfg.pool = Some(PoolConfig::new(1));
    let pool = create_pool(&cfg, NoTls)?;
    let db = PgDB::new(pool.clone());
    let sql = "select $1::int4 + 1";

    // Run the same statement on three checkouts of the connection
    for value in 1..=3 {
        let result: i32 = db.fetch_scalar_one(sql, &[&value]).await?;
        assert_eq!(result, value + 1);
    }

    // Check one server-side statement served every call
    let client = pool.get().await?;
    assert_eq!(prepared_statement_executions(&client, sql).await?, vec![3]);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_statement_cache_survives_custom_discard_all_recycle() -> Result<()> {
    // Setup a single-connection pool recycled with DISCARD ALL
    let recycling_method = RecyclingMethod::Custom("DISCARD ALL".to_string());
    let pool = single_connection_pool(recycling_method.clone())?;
    let db = PgDB::new(pool.clone());
    let sql = "select $1::int4 + 2";

    // Run the same statement on three checkouts of the connection
    for value in 1..=3 {
        let result: i32 = db.fetch_scalar_one(sql, &[&value]).await?;
        assert_eq!(result, value + 2);
    }

    // Check the recycle left no cached statement behind
    let client = pool.get().await?;
    assert_eq!(client.statement_cache.size(), 0);
    assert_eq!(
        prepared_statement_executions(&client, sql).await?,
        Vec::<i64>::new()
    );
    drop(client);

    // Check the same recycle breaks cached statements a pool keeps
    let mut cfg = contract_tests_config()?;
    cfg.manager = Some(ManagerConfig { recycling_method });
    cfg.pool = Some(PoolConfig::new(1));
    let unguarded_db = PgDB::new(cfg.create_pool(Some(Runtime::Tokio1), NoTls)?);
    let result: i32 = unguarded_db.fetch_scalar_one(sql, &[&1]).await?;
    assert_eq!(result, 3);
    let err = unguarded_db
        .fetch_scalar_one::<i32>(sql, &[&1])
        .await
        .expect_err("a deallocated cached statement should fail");
    let code = err
        .downcast_ref::<tokio_postgres::Error>()
        .and_then(tokio_postgres::Error::code);
    assert_eq!(code, Some(&SqlState::INVALID_SQL_STATEMENT_NAME));

    Ok(())
}

// Helpers.

/// Changes the column type of the session probe table.
async fn alter_probe_column_type(pool: &Pool, column_type: &str) -> Result<()> {
    let client = pool.get().await?;
    client
        .batch_execute(&format!(
            "alter table pg_temp.statement_cache_probe alter column value type {column_type}"
        ))
        .await?;

    Ok(())
}

/// Creates the session probe table holding one `int4` value.
async fn create_probe_table(pool: &Pool) -> Result<()> {
    let client = pool.get().await?;
    client
        .batch_execute(
            "
            create temp table statement_cache_probe (value int4);
            insert into statement_cache_probe values (1);
            ",
        )
        .await?;

    Ok(())
}

/// Returns the execution count of each statement the connection prepared
/// from the given SQL.
async fn prepared_statement_executions(client: &Client, sql: &str) -> Result<Vec<i64>> {
    let rows = client
        .query(
            "
            select generic_plans + custom_plans
            from pg_prepared_statements
            where statement = $1::text
            order by prepare_time
            ",
            &[&sql],
        )
        .await?;

    Ok(rows.iter().map(|row| row.get(0)).collect())
}

/// Creates a single-connection server pool with the given recycling method,
/// so every checkout reuses the same connection.
fn single_connection_pool(recycling_method: RecyclingMethod) -> Result<Pool> {
    let mut cfg = contract_tests_config()?;
    cfg.manager = Some(ManagerConfig { recycling_method });
    cfg.pool = Some(PoolConfig::new(1));

    create_pool(&cfg, NoTls)
}
