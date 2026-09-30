//! Contract tests for the `DBDashboardUser` notification preference functions.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::Result;
use chrono::{DateTime, Utc};
use strum::VariantArray;
use tokio_postgres::{
    error::{DbError, SqlState},
    types::Json,
};

use crate::{
    db::{DB, USER_FACING_DB_ERROR_CODE, dashboard::user::DBDashboardUser},
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
        .find(|group| group.group_id == notification_unavailable_group_id())
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
async fn db_contracts_mute_user_group_notifications_rejects_disconnected_group() -> Result<()> {
    // Setup a disconnected user and active group
    let client = contract_tests_pool()?.get().await?;

    // Try to mute a group the user cannot select
    let err = client
        .query_one(
            "select mute_user_group_notifications($1::uuid, $2::uuid)",
            &[&notification_update_user_id(), &subgroup_id()],
        )
        .await
        .expect_err("disconnected groups should be rejected");

    // Check the rejection maps to the user-facing SQLSTATE
    assert_eq!(
        err.as_db_error().map(DbError::message),
        Some("group not available to mute")
    );
    assert_eq!(
        err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_mute_user_group_notifications_serializes_concurrent_requests() -> Result<()> {
    // Setup a clean dedicated mute target
    let pool = contract_tests_pool()?;
    let cleanup_client = pool.get().await?;
    cleanup_client
        .execute(
            "delete from user_group_notification_mute
            where user_id = $1::uuid
            and group_id = $2::uuid",
            &[&notification_concurrency_user_id(), &subgroup_id()],
        )
        .await?;
    let test_started_at: DateTime<Utc> = cleanup_client
        .query_one("select clock_timestamp()", &[])
        .await?
        .get(0);

    // Mute the same connected group through two independent transactions
    let db = contract_tests_db()?;
    let first = db.begin().await?;
    let second = db.begin().await?;
    let first_result = async move {
        first
            .mute_user_group_notifications(notification_concurrency_user_id(), subgroup_id())
            .await?;
        first.commit().await
    };
    let second_result = async move {
        second
            .mute_user_group_notifications(notification_concurrency_user_id(), subgroup_id())
            .await?;
        second.commit().await
    };
    let (first_result, second_result) = tokio::join!(first_result, second_result);
    first_result?;
    second_result?;

    // Check one durable mute and one audit row survived the race
    let row = cleanup_client
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
                    and action = 'group_notifications_muted'
                    and resource_id = $1::uuid
                    and resource_type = 'user'
                    and details->>'group_id' = $2::uuid::text
                    and created_at >= $3::timestamptz
                )",
            &[
                &notification_concurrency_user_id(),
                &subgroup_id(),
                &test_started_at,
            ],
        )
        .await?;
    assert_eq!(row.get::<_, i64>(0), 1);
    assert_eq!(row.get::<_, i64>(1), 1);

    // Clean up the mutable row so repeated focused runs start from the same state
    cleanup_client
        .execute(
            "delete from user_group_notification_mute
            where user_id = $1::uuid
            and group_id = $2::uuid",
            &[&notification_concurrency_user_id(), &subgroup_id()],
        )
        .await?;

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
    // Setup one durable mute row for the concurrent unmute target
    let pool = contract_tests_pool()?;
    let cleanup_client = pool.get().await?;
    cleanup_client
        .execute(
            "delete from user_group_notification_mute
            where user_id = $1::uuid
            and group_id = $2::uuid",
            &[&notification_unmute_concurrency_user_id(), &subgroup_id()],
        )
        .await?;
    cleanup_client
        .execute(
            "insert into user_group_notification_mute (group_id, user_id)
            values ($1::uuid, $2::uuid)",
            &[&subgroup_id(), &notification_unmute_concurrency_user_id()],
        )
        .await?;
    let test_started_at: DateTime<Utc> = cleanup_client
        .query_one("select clock_timestamp()", &[])
        .await?
        .get(0);

    // Unmute the same group through two independent transactions
    let db = contract_tests_db()?;
    let first = db.begin().await?;
    let second = db.begin().await?;
    let first_result = async move {
        first
            .unmute_user_group_notifications(
                notification_unmute_concurrency_user_id(),
                subgroup_id(),
            )
            .await?;
        first.commit().await
    };
    let second_result = async move {
        second
            .unmute_user_group_notifications(
                notification_unmute_concurrency_user_id(),
                subgroup_id(),
            )
            .await?;
        second.commit().await
    };
    let (first_result, second_result) = tokio::join!(first_result, second_result);
    first_result?;
    second_result?;

    // Check the race removed the mute once and audited exactly one unmute
    let row = cleanup_client
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
                    and action = 'group_notifications_unmuted'
                    and resource_id = $1::uuid
                    and resource_type = 'user'
                    and details->>'group_id' = $2::uuid::text
                    and created_at >= $3::timestamptz
                )",
            &[
                &notification_unmute_concurrency_user_id(),
                &subgroup_id(),
                &test_started_at,
            ],
        )
        .await?;
    assert_eq!(row.get::<_, i64>(0), 0);
    assert_eq!(row.get::<_, i64>(1), 1);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_user_notification_preferences_rejects_unknown_category() -> Result<()>
{
    // Setup a raw invalid preferences payload
    let client = contract_tests_pool()?.get().await?;
    let payload = Json(serde_json::json!({ "unknown-category": false }));

    // Submit the unknown category directly to the database function
    let err = client
        .query_one(
            "select update_user_notification_preferences($1::uuid, $2::jsonb)",
            &[&notification_update_user_id(), &payload],
        )
        .await
        .expect_err("unknown categories should be rejected");

    // Check the rejection maps to the user-facing SQLSTATE
    assert_eq!(
        err.as_db_error().map(DbError::message),
        Some("unknown notification category")
    );
    assert_eq!(
        err.code(),
        Some(&SqlState::from_code(USER_FACING_DB_ERROR_CODE))
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_update_user_notification_preferences_saves_categories() -> Result<()> {
    // Setup a clean dedicated preference mutation target
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;
    client
        .execute(
            "delete from user_notification_opt_out where user_id = $1::uuid",
            &[&notification_update_user_id()],
        )
        .await?;
    let test_started_at: DateTime<Utc> =
        client.query_one("select clock_timestamp()", &[]).await?.get(0);

    // Save one disabled category and one explicitly enabled category
    let input = NotificationPreferencesInput {
        preferences: BTreeMap::from([
            (NotificationCategory::Badges, false),
            (NotificationCategory::NewEvents, true),
        ]),
    };
    db.update_user_notification_preferences(notification_update_user_id(), &input)
        .await?;

    // Check the persisted preferences and audit snapshot
    let preferences = db
        .get_user_notification_preferences(notification_update_user_id())
        .await?;
    let audit_count: i64 = client
        .query_one(
            "select count(*)
            from audit_log
            where actor_user_id = $1::uuid
            and action = 'user_notification_preferences_updated'
            and details = '{\"opted_out_categories\":[\"badges\"]}'::jsonb
            and created_at >= $2::timestamptz",
            &[&notification_update_user_id(), &test_started_at],
        )
        .await?
        .get(0);
    assert_eq!(
        preferences.opted_out_categories,
        vec![NotificationCategory::Badges]
    );
    assert_eq!(audit_count, 1);

    Ok(())
}
