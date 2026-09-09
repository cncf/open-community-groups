use std::sync::Arc;

use anyhow::anyhow;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::mock::MockDB,
    services::notifications::{
        DynNotificationsManager, MockNotificationsManager,
        payloads::build_event_waitlist_joined_notification,
    },
    types::{
        notifications::NotificationKind,
        tests::{sample_event_summary, sample_site_settings},
    },
};

use super::enqueue_event_notification_best_effort;

#[tokio::test]
async fn test_enqueue_event_notification_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));

    // Setup the single enqueue expectation
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistJoined)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue
    enqueue_event_notification_best_effort(
        &db,
        &nm,
        &HttpServerConfig::default(),
        community_id,
        event_id,
        |event, server_cfg, site_settings| {
            build_event_waitlist_joined_notification(event, user_id, server_cfg, site_settings)
        },
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_event_notification_best_effort_swallows_build_failure() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));

    // Setup the manager, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue with a failing builder
    enqueue_event_notification_best_effort(
        &db,
        &nm,
        &HttpServerConfig::default(),
        community_id,
        event_id,
        |_, _, _| Err(anyhow!("payload build failed")),
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_event_notification_best_effort_swallows_context_load_failure() {
    // Setup identifiers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup a failing context load
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));

    // Setup the manager, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue
    enqueue_event_notification_best_effort(
        &db,
        &nm,
        &HttpServerConfig::default(),
        community_id,
        event_id,
        |event, server_cfg, site_settings| {
            build_event_waitlist_joined_notification(event, user_id, server_cfg, site_settings)
        },
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_event_notification_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_event_notification_best_effort(
        &db,
        &nm,
        &HttpServerConfig::default(),
        community_id,
        event_id,
        |event, server_cfg, site_settings| {
            build_event_waitlist_joined_notification(event, user_id, server_cfg, site_settings)
        },
    )
    .await;
}
