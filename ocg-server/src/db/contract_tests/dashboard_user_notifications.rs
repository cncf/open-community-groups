//! Contract tests for the `DBDashboardUser` notification preference functions.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::Result;
use chrono::{DateTime, Utc};
use strum::VariantArray;
use tokio_postgres::types::Json;
use uuid::Uuid;

use crate::{
    db::{DBUnitOfWork, PgExecutor, dashboard::user::DBDashboardUser},
    types::dashboard::user::notifications::{NotificationCategory, NotificationPreferencesInput},
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_get_user_notification_preferences_deserializes() -> Result<()> {
    // Setup the contract database and raw JSON probe
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;

    // Load preferences through the production wrapper and raw SQL contract
    let preferences = db
        .get_user_notification_preferences(notification_preferences_user_id())
        .await?;
    let raw_row = client
        .query_one(
            "select get_user_notification_preferences($1::uuid)",
            &[&notification_preferences_user_id()],
        )
        .await?;
    let Json(raw): Json<serde_json::Value> = raw_row.get(0);

    // Check opted-out category enum decoding
    assert_eq!(
        preferences.opted_out_categories,
        vec![NotificationCategory::Badges]
    );
    assert!(!preferences.receives(NotificationCategory::Badges));
    assert!(preferences.receives(NotificationCategory::NewEvents));

    // Check muted group required fields and timestamp decoding
    assert_eq!(preferences.muted_groups.len(), 2);
    let connected_group = preferences
        .muted_groups
        .iter()
        .find(|group| group.group_id == subgroup_id())
        .expect("connected muted group should be present");
    assert!(connected_group.available);
    assert_eq!(connected_group.community_display_name, "Contract Community");
    assert_eq!(
        connected_group.muted_at,
        DateTime::from_timestamp(1_704_067_200, 0).unwrap()
    );
    assert_eq!(connected_group.name, "Contract Subgroup");

    // Check unavailable muted groups remain visible and nullable logo URLs deserialize
    let unavailable_group = preferences
        .muted_groups
        .iter()
        .find(|group| group.group_id == cohost_reinvited_group_id())
        .expect("unavailable muted group should be present");
    assert!(!unavailable_group.available);
    assert_eq!(
        unavailable_group.logo_url.as_deref(),
        Some("https://example.com/cohost-reinvited-logo.png")
    );
    assert_eq!(
        unavailable_group.muted_at,
        DateTime::from_timestamp(1_704_153_600, 0).unwrap()
    );
    assert_eq!(unavailable_group.name, "Contract Reinvited Co-host");

    // Check null logo URLs are omitted from the raw JSON object
    let raw_muted_groups = raw["muted_groups"]
        .as_array()
        .expect("muted_groups should be an array");
    let connected_group_id = subgroup_id().to_string();
    let raw_connected_group = raw_muted_groups
        .iter()
        .find(|group| group["group_id"].as_str() == Some(connected_group_id.as_str()))
        .expect("raw connected muted group should be present");
    assert_eq!(raw_connected_group["available"], true);
    assert_eq!(raw_connected_group["muted_at"], 1_704_067_200);
    assert!(!raw_connected_group.as_object().unwrap().contains_key("logo_url"));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_list_user_notification_group_options_deserializes() -> Result<()> {
    // Setup the contract database and connected attendee fixture
    let db = contract_tests_db()?;

    // Load connected group mute options through the production wrapper
    let options = db.list_user_notification_group_options(attendee_id()).await?;

    // Check required and optional group fields decode in stable display order
    assert_eq!(options.len(), 2);
    assert_eq!(options[0].community_display_name, "Contract Community");
    assert_eq!(options[0].group_id, group_id());
    assert_eq!(options[0].name, "Contract Group");
    assert_eq!(
        options[0].logo_url.as_deref(),
        Some("https://example.com/group-logo.png")
    );
    assert_eq!(options[1].community_display_name, "Contract Community");
    assert_eq!(options[1].group_id, subgroup_id());
    assert_eq!(options[1].name, "Contract Subgroup");
    assert_eq!(options[1].logo_url, None);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_mute_user_group_notifications_serializes_concurrent_requests() -> Result<()> {
    // Setup a clean dedicated mute target and two racing units of work
    let user_id = notification_concurrency_user_id();
    let probe_client = contract_tests_pool()?.get().await?;
    delete_mute(&probe_client, user_id).await?;
    let test_started_at = clock_timestamp(&probe_client).await?;
    let first = contract_unit_of_work().await?;
    let second = contract_unit_of_work().await?;
    let first_backend_pid = uow_backend_pid(&first).await?;
    let second_backend_pid = uow_backend_pid(&second).await?;

    // Mute the group while retaining the uncommitted mute row
    first.mute_user_group_notifications(user_id, subgroup_id()).await?;

    // Mute the same group concurrently from the second transaction
    let second_mute = tokio::spawn(async move {
        second.mute_user_group_notifications(user_id, subgroup_id()).await?;
        Box::new(second).commit().await
    });
    wait_for_backend_blocker(&probe_client, first_backend_pid, second_backend_pid).await?;

    // Commit the first mute so the waiting request observes it
    Box::new(first).commit().await?;
    second_mute.await??;

    // Check one durable mute and one audit row survived the race
    let counts = mute_and_audit_counts(
        &probe_client,
        user_id,
        "group_notifications_muted",
        test_started_at,
    )
    .await?;
    delete_mute(&probe_client, user_id).await?;
    assert_eq!(counts, (1, 1));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_notification_categories_match_enum() -> Result<()> {
    // Load every notification category identifier from the reference table
    let client = contract_tests_pool()?.get().await?;
    let ids: Vec<String> = client
        .query(
            "select notification_category_id from notification_category",
            &[],
        )
        .await?
        .iter()
        .map(|row| row.get(0))
        .collect();

    // Decode each identifier through the same serde encoding used by the DTOs
    let decoded = ids
        .iter()
        .map(|id| serde_json::from_value(serde_json::json!(id)))
        .collect::<Result<BTreeSet<NotificationCategory>, _>>()?;

    // Check the database and the enum define exactly the same categories
    let variants: BTreeSet<_> = NotificationCategory::VARIANTS.iter().copied().collect();
    assert_eq!(decoded, variants);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_unmute_user_group_notifications_serializes_concurrent_requests() -> Result<()>
{
    // Setup one durable mute row and two racing units of work
    let user_id = notification_unmute_concurrency_user_id();
    let probe_client = contract_tests_pool()?.get().await?;
    delete_mute(&probe_client, user_id).await?;
    probe_client
        .execute(
            "insert into user_group_notification_mute (group_id, user_id)
            values ($1::uuid, $2::uuid)",
            &[&subgroup_id(), &user_id],
        )
        .await?;
    let test_started_at = clock_timestamp(&probe_client).await?;
    let first = contract_unit_of_work().await?;
    let second = contract_unit_of_work().await?;
    let first_backend_pid = uow_backend_pid(&first).await?;
    let second_backend_pid = uow_backend_pid(&second).await?;

    // Unmute the group while retaining the lock on the deleted mute row
    first.unmute_user_group_notifications(user_id, subgroup_id()).await?;

    // Unmute the same group concurrently from the second transaction
    let second_unmute = tokio::spawn(async move {
        second.unmute_user_group_notifications(user_id, subgroup_id()).await?;
        Box::new(second).commit().await
    });
    wait_for_backend_blocker(&probe_client, first_backend_pid, second_backend_pid).await?;

    // Commit the first unmute so the waiting request observes it
    Box::new(first).commit().await?;
    second_unmute.await??;

    // Check the race removed the mute once and audited exactly one unmute
    let counts = mute_and_audit_counts(
        &probe_client,
        user_id,
        "group_notifications_unmuted",
        test_started_at,
    )
    .await?;
    assert_eq!(counts, (0, 1));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_user_notification_preferences_saves_categories() -> Result<()> {
    // Setup a rolled-back unit of work and a clean preference mutation target
    let uow = contract_unit_of_work().await?;
    uow.execute(
        "delete from user_notification_opt_out where user_id = $1::uuid",
        &[&notification_update_user_id()],
    )
    .await?;

    // Save one disabled category and one explicitly enabled category
    let input = NotificationPreferencesInput {
        preferences: BTreeMap::from([
            (NotificationCategory::Badges, false),
            (NotificationCategory::NewEvents, true),
        ]),
    };
    uow.update_user_notification_preferences(notification_update_user_id(), &input)
        .await?;

    // Check the persisted preferences and audit snapshot
    let preferences = uow
        .get_user_notification_preferences(notification_update_user_id())
        .await?;
    let audit_count: i64 = uow
        .fetch_scalar_one(
            "select count(*)
            from audit_log
            where actor_user_id = $1::uuid
            and action = 'user_notification_preferences_updated'
            and details = '{\"opted_out_categories\":[\"badges\"]}'::jsonb
            and created_at >= current_timestamp",
            &[&notification_update_user_id()],
        )
        .await?;
    assert_eq!(
        preferences.opted_out_categories,
        vec![NotificationCategory::Badges]
    );
    assert_eq!(audit_count, 1);

    Ok(())
}

// Helpers.

/// Returns the current database clock time.
async fn clock_timestamp(client: &tokio_postgres::Client) -> Result<DateTime<Utc>> {
    Ok(client.query_one("select clock_timestamp()", &[]).await?.get(0))
}

/// Deletes the mute of the subgroup for the given user.
async fn delete_mute(client: &tokio_postgres::Client, user_id: Uuid) -> Result<()> {
    client
        .execute(
            "delete from user_group_notification_mute
            where user_id = $1::uuid
            and group_id = $2::uuid",
            &[&user_id, &subgroup_id()],
        )
        .await?;

    Ok(())
}

/// Returns the subgroup mute rows of the user and the audit rows of the given
/// action recorded since `since`.
async fn mute_and_audit_counts(
    client: &tokio_postgres::Client,
    user_id: Uuid,
    action: &str,
    since: DateTime<Utc>,
) -> Result<(i64, i64)> {
    let row = client
        .query_one(
            "select
                (
                    select count(*)
                    from user_group_notification_mute
                    where user_id = $1::uuid
                    and group_id = $2::uuid
                ),
                (
                    select count(*)
                    from audit_log
                    where actor_user_id = $1::uuid
                    and action = $3::text
                    and resource_id = $1::uuid
                    and resource_type = 'user'
                    and details->>'group_id' = $2::uuid::text
                    and created_at >= $4::timestamptz
                )",
            &[&user_id, &subgroup_id(), &action, &since],
        )
        .await?;

    Ok((row.get(0), row.get(1)))
}
