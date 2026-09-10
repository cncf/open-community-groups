use std::sync::Arc;

use anyhow::anyhow;
use serde_json::from_value;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::mock::MockDB,
    services::notifications::{
        DynNotificationsManager, MockNotificationsManager,
        payloads::build_event_waitlist_joined_notification,
    },
    templates::notifications::{
        CfsSubmissionUpdated, CommunityTeamInvitation, GroupTeamInvitation,
    },
    types::{
        dashboard::group::submissions::CfsSubmissionNotificationData,
        notifications::NotificationKind,
        tests::{
            sample_community_summary, sample_event_summary, sample_group_summary,
            sample_site_settings,
        },
    },
};

use super::{
    enqueue_cfs_submission_updated_best_effort, enqueue_community_team_invitation_best_effort,
    enqueue_event_notification_best_effort, enqueue_group_team_invitation_best_effort,
};

#[tokio::test]
async fn test_enqueue_cfs_submission_updated_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let cfs_submission_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let reviewer_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let site_settings = sample_site_settings();
    let expected_theme = site_settings.theme.clone();
    let notification_data = CfsSubmissionNotificationData {
        status_id: "approved".to_string(),
        status_name: "Approved".to_string(),
        user_id: speaker_id,
        action_required_message: Some("Please update your slides.".to_string()),
    };

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_cfs_submission_notification_data()
        .times(1)
        .withf(move |eid, sid| *eid == event_id && *sid == cfs_submission_id)
        .returning(move |_, _| Ok(notification_data.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup the single enqueue expectation with the full content
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::CfsSubmissionUpdated)
                && notification.recipients == vec![speaker_id]
                && notification.attachments.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<CfsSubmissionUpdated>(value.clone()).is_ok_and(|template| {
                        template.action_required_message.as_deref()
                            == Some("Please update your slides.")
                            && template.event.event_id == event_id
                            && template.link
                                == "https://example.test/dashboard/user?tab=submissions"
                            && template.status_name == "Approved"
                            && template.theme.primary_color == expected_theme.primary_color
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue
    enqueue_cfs_submission_updated_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        reviewer_id,
        cfs_submission_id,
        event,
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_cfs_submission_updated_best_effort_swallows_context_load_failure() {
    // Setup identifiers and notification context
    let cfs_submission_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup a failing context load; the sibling read may be skipped by try_join!
    let mut db = MockDB::new();
    db.expect_get_cfs_submission_notification_data()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));
    db.expect_get_site_settings()
        .times(0..=1)
        .returning(|| Ok(sample_site_settings()));

    // Setup the manager, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_cfs_submission_updated_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        Uuid::new_v4(),
        cfs_submission_id,
        event,
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_cfs_submission_updated_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let cfs_submission_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let notification_data = CfsSubmissionNotificationData {
        status_id: "rejected".to_string(),
        status_name: "Rejected".to_string(),
        user_id: Uuid::new_v4(),
        action_required_message: None,
    };

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_cfs_submission_notification_data()
        .times(1)
        .returning(move |_, _| Ok(notification_data.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_cfs_submission_updated_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        Uuid::new_v4(),
        cfs_submission_id,
        event,
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_community_team_invitation_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let community = sample_community_summary(community_id);
    let expected_community_name = community.display_name.clone();
    let site_settings = sample_site_settings();
    let expected_theme = site_settings.theme.clone();

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(community.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup the single enqueue expectation with the full content
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::CommunityTeamInvitation)
                && notification.recipients == vec![user_id]
                && notification.attachments.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<CommunityTeamInvitation>(value.clone()).is_ok_and(|template| {
                        template.community_name == expected_community_name
                            && template.link
                                == "https://example.test/dashboard/user?tab=invitations"
                            && template.theme.primary_color == expected_theme.primary_color
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue
    enqueue_community_team_invitation_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        community_id,
        user_id,
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_community_team_invitation_best_effort_swallows_context_load_failure() {
    // Setup a failing context load; the sibling read may be skipped by try_join!
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .returning(|_| Err(anyhow!("database unavailable")));
    db.expect_get_site_settings()
        .times(0..=1)
        .returning(|| Ok(sample_site_settings()));

    // Setup the manager, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_community_team_invitation_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        Uuid::new_v4(),
        Uuid::new_v4(),
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_community_team_invitation_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .returning(move |_| Ok(sample_community_summary(community_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_community_team_invitation_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        community_id,
        Uuid::new_v4(),
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_group_team_invitation_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let group = sample_group_summary(group_id);
    let site_settings = sample_site_settings();
    let expected_theme = site_settings.theme.clone();

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));

    // Setup the single enqueue expectation with the full content
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::GroupTeamInvitation)
                && notification.recipients == vec![user_id]
                && notification.attachments.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<GroupTeamInvitation>(value.clone()).is_ok_and(|template| {
                        template.group.group_id == group_id
                            && template.link
                                == "https://example.test/dashboard/user?tab=invitations"
                            && template.theme.primary_color == expected_theme.primary_color
                    })
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue
    enqueue_group_team_invitation_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        community_id,
        group_id,
        user_id,
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_group_team_invitation_best_effort_swallows_context_load_failure() {
    // Setup a failing context load; the sibling read may be skipped by try_join!
    let mut db = MockDB::new();
    db.expect_get_group_summary()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));
    db.expect_get_site_settings()
        .times(0..=1)
        .returning(|| Ok(sample_site_settings()));

    // Setup the manager, which must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_group_team_invitation_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_group_team_invitation_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let group_id = Uuid::new_v4();

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_group_summary()
        .times(1)
        .returning(move |_, _| Ok(sample_group_summary(group_id)));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_group_team_invitation_best_effort(
        &db,
        &nm,
        &test_server_cfg(),
        Uuid::new_v4(),
        group_id,
        Uuid::new_v4(),
    )
    .await;
}

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

// Helpers.

/// Server configuration with a base URL that carries a trailing slash to prove
/// link normalization.
fn test_server_cfg() -> HttpServerConfig {
    HttpServerConfig {
        base_url: "https://example.test/".to_string(),
        ..HttpServerConfig::default()
    }
}
