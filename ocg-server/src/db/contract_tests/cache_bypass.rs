//! Real-database contracts for transactional cache bypass on `PgExecutor`.

use anyhow::Result;
use uuid::Uuid;

use crate::db::{DBUnitOfWork, PgExecutor, common::DBCommon, community::DBCommunity};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unit_of_work_bypasses_keyed_aggregate_cache() -> Result<()> {
    // Setup a fresh community identifier absent from both database and cache
    let db = contract_tests_db()?;
    let fresh_community_id = Uuid::new_v4();

    // Insert uncommitted rows inside a transaction and read through the cached method
    let uow = contract_unit_of_work().await?;
    insert_community_with_member(&uow, fresh_community_id, "tx-bypass-agg-rollback").await?;
    let tx_stats = uow.get_community_site_stats(fresh_community_id).await?;
    assert_eq!(tx_stats.groups, 1);
    assert_eq!(tx_stats.groups_members, 1);

    // Roll back the transaction and check the root handle does not see rolled-back state
    Box::new(uow).rollback().await?;
    let root_stats = db.get_community_site_stats(fresh_community_id).await?;
    assert_eq!(root_stats.groups, 0);
    assert_eq!(root_stats.groups_members, 0);

    // Insert uncommitted rows in a second transaction after the cache is warmed
    let uow = contract_unit_of_work().await?;
    insert_community_with_member(&uow, fresh_community_id, "tx-bypass-agg-warm").await?;

    // Check both the unit of work and its pinned client bypass the warmed cache
    let tx_stats = uow.get_community_site_stats(fresh_community_id).await?;
    assert_eq!(tx_stats.groups, 1);
    assert_eq!(tx_stats.groups_members, 1);
    let pinned = uow.client().await?;
    let pinned_stats = pinned.get_community_site_stats(fresh_community_id).await?;
    assert_eq!(pinned_stats.groups, 1);
    assert_eq!(pinned_stats.groups_members, 1);

    // Check the root handle still serves the warmed entry without being overwritten
    let root_stats = db.get_community_site_stats(fresh_community_id).await?;
    assert_eq!(root_stats.groups, 0);
    assert_eq!(root_stats.groups_members, 0);

    // Roll back the fixture changes
    Box::new(uow).rollback().await?;
    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unit_of_work_bypasses_positive_only_community_id_cache() -> Result<()> {
    // Setup a fresh community identifier and slug absent from both database and cache
    let db = contract_tests_db()?;
    let fresh_community_id = Uuid::new_v4();
    let slug = format!(
        "tx-bypass-{}",
        &fresh_community_id.simple().to_string()[..12]
    );

    // Insert an uncommitted active community and resolve it inside the transaction
    let uow = contract_unit_of_work().await?;
    insert_community(&uow, fresh_community_id, &slug, true).await?;
    assert_eq!(
        uow.get_community_id_by_name(&slug).await?,
        Some(fresh_community_id)
    );

    // Roll back and check the positive-only cache was never populated with the rolled-back row
    Box::new(uow).rollback().await?;
    assert_eq!(db.get_community_id_by_name(&slug).await?, None);

    // Warm the positive-only cache on the seeded contract community
    assert_eq!(
        db.get_community_id_by_name("contract-community").await?,
        Some(community_id())
    );

    // Deactivate the seeded community inside a transaction and check the warm cache is bypassed
    let uow = contract_unit_of_work().await?;
    uow.execute(
        "update community set active = false where community_id = $1::uuid",
        &[&community_id()],
    )
    .await?;
    assert_eq!(
        uow.get_community_id_by_name("contract-community").await?,
        None
    );

    // Check the root handle still serves the warmed entry
    assert_eq!(
        db.get_community_id_by_name("contract-community").await?,
        Some(community_id())
    );

    // Roll back the fixture changes
    Box::new(uow).rollback().await?;
    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unit_of_work_bypasses_singleton_cache() -> Result<()> {
    // Setup the contract database
    let db = contract_tests_db()?;

    // Insert an uncommitted UTM medium and read through the singleton cached method
    let uow = contract_unit_of_work().await?;
    uow.execute(
        "insert into utm_medium (utm_medium_id) values ($1::text)",
        &[&"tx-bypass-medium-rollback"],
    )
    .await?;
    let tx_mediums = uow.list_utm_mediums().await?;
    assert!(tx_mediums.iter().any(|m| m == "tx-bypass-medium-rollback"));

    // Roll back and check the root handle does not see the rolled-back value (warming the cache)
    Box::new(uow).rollback().await?;
    let root_mediums = db.list_utm_mediums().await?;
    assert!(!root_mediums.iter().any(|m| m == "tx-bypass-medium-rollback"));

    // Insert another uncommitted UTM medium after the singleton cache is warmed
    let uow = contract_unit_of_work().await?;
    uow.execute(
        "insert into utm_medium (utm_medium_id) values ($1::text)",
        &[&"tx-bypass-medium-warm"],
    )
    .await?;
    let tx_mediums = uow.list_utm_mediums().await?;
    assert!(tx_mediums.iter().any(|m| m == "tx-bypass-medium-warm"));

    // Roll back and check the warmed singleton cache remains clean
    Box::new(uow).rollback().await?;
    let root_mediums = db.list_utm_mediums().await?;
    assert!(!root_mediums.iter().any(|m| m == "tx-bypass-medium-warm"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_use_cache_enabled_only_for_root_pg_db() -> Result<()> {
    // Setup root handle, pooled/borrowed clients, and unit of work with pinned client
    let db = contract_tests_db()?;
    let pooled = db.client().await?;
    let borrowed = pooled.client().await?;
    let uow = contract_unit_of_work().await?;
    let pinned = uow.client().await?;

    // Check only the root PgDB handle enables process-wide caches
    assert!(db.use_cache());
    assert!(!pooled.use_cache());
    assert!(!borrowed.use_cache());
    assert!(!uow.use_cache());
    assert!(!pinned.use_cache());

    // Roll back the unit of work
    Box::new(uow).rollback().await?;
    Ok(())
}

// Helpers.

/// Inserts a community row on the given executor.
async fn insert_community(
    executor: &(impl PgExecutor + Sync),
    community_id: Uuid,
    name: &str,
    active: bool,
) -> Result<()> {
    executor
        .execute(
            "
            insert into community (
                active,
                banner_mobile_url,
                banner_url,
                community_id,
                description,
                display_name,
                logo_url,
                name
            ) values (
                $1::bool,
                'https://example.com/tx-bypass-banner-mobile.png',
                'https://example.com/tx-bypass-banner.png',
                $2::uuid,
                'Temporary community for cache bypass contract test',
                'Tx Bypass Community',
                'https://example.com/tx-bypass-logo.png',
                $3::text
            )
            ",
            &[&active, &community_id, &name],
        )
        .await
}

/// Inserts an inactive community with one active group and one group member.
async fn insert_community_with_member(
    executor: &(impl PgExecutor + Sync),
    community_id: Uuid,
    slug: &str,
) -> Result<()> {
    let group_category_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Insert the community
    insert_community(executor, community_id, slug, false).await?;

    // Insert the group category
    executor
        .execute(
            "
            insert into group_category (
                community_id,
                group_category_id,
                name
            ) values (
                $1::uuid,
                $2::uuid,
                'Tx bypass'
            )
            ",
            &[&community_id, &group_category_id],
        )
        .await?;

    // Insert the active group
    executor
        .execute(
            "
            insert into \"group\" (
                community_id,
                group_category_id,
                group_id,
                name,
                slug
            ) values (
                $1::uuid,
                $2::uuid,
                $3::uuid,
                'Tx Bypass Group',
                $4::text
            )
            ",
            &[&community_id, &group_category_id, &group_id, &slug],
        )
        .await?;

    // Insert one member into the group
    executor
        .execute(
            "
            insert into group_member (
                group_id,
                user_id
            ) values (
                $1::uuid,
                $2::uuid
            )
            ",
            &[&group_id, &attendee_id()],
        )
        .await
}
