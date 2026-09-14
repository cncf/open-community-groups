//! Real-database lifecycle contracts for `PgUnitOfWork`: behaviors that mocks
//! cannot prove.

use std::time::Duration;

use anyhow::Result;
use deadpool_postgres::{PoolConfig, Runtime};
use tokio::{sync::oneshot, time::timeout};
use tokio_postgres::{NoTls, error::DbError};
use uuid::Uuid;

use crate::db::{DB, DBExt, DBUnitOfWork, PgDB, PgExecutor, PgUnitOfWork, group::DBGroup};

use super::helpers::{
    community_id, contract_tests_config, contract_tests_db, contract_tests_pool, event_category_id,
    group_id, lifecycle_cancelee_id, lifecycle_rollback_cancelee_id,
};

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unit_of_work_commit_failure_persists_nothing() -> Result<()> {
    // Setup a unit of work whose deferred constraint fires at commit
    let db = contract_tests_db()?;
    let pool = contract_tests_pool()?;
    let client = pool.get().await?;
    client.batch_execute("begin").await?;
    let uow = PgUnitOfWork {
        client: Some(client),
    };
    let event_id = Uuid::new_v4();

    // Insert an event without the ticket type its deferred constraint requires
    uow.execute(
        "
        insert into event (
            capacity, description, ends_at, event_category_id, event_id, event_kind_id,
            group_id, name, published, slug, starts_at, test_event, timezone
        ) values (
            10, 'Lifecycle contract event', '2099-09-01 11:00:00+00', $1::uuid, $2::uuid,
            'virtual', $3::uuid, 'Lifecycle Contract Event', false, $4::text,
            '2099-09-01 10:00:00+00', true, 'UTC'
        )
        ",
        &[
            &event_category_id(),
            &event_id,
            &group_id(),
            &format!("lifecycle-{event_id}"),
        ],
    )
    .await?;

    // Commit and check the deferred violation surfaces as an error
    let err = Box::new(uow)
        .commit()
        .await
        .expect_err("deferred constraint violation should fail the commit");
    let message = err
        .downcast_ref::<tokio_postgres::Error>()
        .and_then(|err| err.as_db_error())
        .map(DbError::message);
    assert_eq!(message, Some("events require at least one ticket type"));

    // Check the failed commit persisted nothing
    let event_exists: bool = db
        .fetch_scalar_one(
            "select exists (select 1 from event where event_id = $1::uuid)",
            &[&event_id],
        )
        .await?;
    assert!(!event_exists);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unit_of_work_dropped_future_rolls_back_and_releases_clean_connection()
-> Result<()> {
    // Setup a single-connection pool so the next borrower reuses the same connection
    let mut cfg = contract_tests_config()?;
    cfg.pool = Some(PoolConfig::new(1));
    let pool = cfg.create_pool(Some(Runtime::Tokio1), NoTls)?;
    let db = PgDB::new(pool.clone());
    let user_id = lifecycle_cancelee_id();

    // Run the transaction until its write completes, then drop it before commit
    let (written_tx, written_rx) = oneshot::channel();
    let mut transaction = db.transaction(|tx| {
        Box::pin(async move {
            tx.join_group(community_id(), group_id(), user_id).await?;
            let _ = written_tx.send(());
            std::future::pending::<()>().await;
            Ok(())
        })
    });
    let written = timeout(Duration::from_secs(10), async {
        tokio::select! {
            result = &mut transaction => panic!("the transaction future should not complete: {result:?}"),
            written = written_rx => written,
        }
    })
    .await;
    written
        .expect("the write should complete before the timeout")
        .expect("the write should succeed before the future is dropped");
    drop(transaction);

    // Check the next borrower gets a usable connection outside any transaction
    let client = pool.get().await?;
    let in_transaction: bool = client
        .query_one("select pg_current_xact_id_if_assigned() is not null", &[])
        .await?
        .get(0);
    assert!(!in_transaction);
    let probe: i32 = client.query_one("select 1", &[]).await?.get(0);
    assert_eq!(probe, 1);
    drop(client);

    // Check the write was rolled back
    let is_member = db.is_group_member(community_id(), group_id(), user_id).await?;
    assert!(!is_member);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unit_of_work_rollback_leaves_nothing_visible() -> Result<()> {
    // Setup the contract database and a membership write
    let db = contract_tests_db()?;
    let user_id = lifecycle_rollback_cancelee_id();
    let uow = db.begin().await?;
    uow.join_group(community_id(), group_id(), user_id).await?;

    // Check the write is visible inside the unit of work only
    assert!(uow.is_group_member(community_id(), group_id(), user_id).await?);
    assert!(!db.is_group_member(community_id(), group_id(), user_id).await?);

    // Roll back and check nothing persisted
    uow.rollback().await?;
    assert!(!db.is_group_member(community_id(), group_id(), user_id).await?);

    Ok(())
}
