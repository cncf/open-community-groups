use std::{
    cell::RefCell,
    fmt::Write as _,
    sync::{Arc, Mutex, Once},
};

use anyhow::anyhow;
use serde_json::from_value;
use tracing::{
    Event, Metadata, Subscriber,
    field::{Field, Visit},
    span::{Attributes, Id, Record},
};
use uuid::Uuid;

use crate::{
    config::tests::sample_server_cfg,
    db::mock::{MockDB, expect_site_settings},
    services::notifications::{
        DynNotificationsManager, MockNotificationsManager,
        payloads::build_event_waitlist_joined_notification,
    },
    templates::notifications::{
        CfsSubmissionUpdated, CommunityTeamInvitation, GroupTeamInvitation,
        SessionProposalCoSpeakerInvitation,
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
    CfsSubmissionUpdatedNotice, CoSpeakerInvitationNotice,
    enqueue_cfs_submission_updated_best_effort, enqueue_community_team_invitation_best_effort,
    enqueue_event_notification_best_effort, enqueue_group_team_invitation_best_effort,
    enqueue_session_proposal_co_speaker_invitation_best_effort,
};

#[tokio::test]
async fn test_enqueue_cfs_submission_updated_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let cfs_submission_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let reviewer_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let expected_theme = sample_site_settings().theme;
    let notification_data = CfsSubmissionNotificationData {
        status_id: "approved".to_string(),
        status_name: "Approved".to_string(),
        user_id: speaker_id,
        action_required_message: Some("Please update your slides.".to_string()),
    };

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_cfs_submission_notification_data()
        .times(1)
        .withf(move |gid, eid, sid| {
            *gid == group_id && *eid == event_id && *sid == cfs_submission_id
        })
        .returning(move |_, _, _| Ok(notification_data.clone()));
    expect_site_settings(&mut db);

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
        &sample_server_cfg("https://example.test/"),
        CfsSubmissionUpdatedNotice {
            cfs_submission_id,
            community_id,
            event_id,
            group_id,
            reviewer_id,
        },
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_cfs_submission_updated_best_effort_swallows_context_load_failure() {
    // Setup identifiers
    let cfs_submission_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup a failing event load; the sibling reads may be skipped by try_join!
    let mut db = MockDB::new();
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(|_, _, _| Err(anyhow!("database unavailable")));
    db.expect_get_cfs_submission_notification_data()
        .times(0..=1)
        .returning(|_, _, _| {
            Ok(CfsSubmissionNotificationData {
                status_id: "approved".to_string(),
                status_name: "Approved".to_string(),
                user_id: Uuid::new_v4(),
                action_required_message: None,
            })
        });
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
        &sample_server_cfg("https://example.test/"),
        CfsSubmissionUpdatedNotice {
            cfs_submission_id,
            community_id,
            event_id,
            group_id,
            reviewer_id: Uuid::new_v4(),
        },
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_cfs_submission_updated_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let cfs_submission_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let reviewer_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);
    let notification_data = CfsSubmissionNotificationData {
        status_id: "rejected".to_string(),
        status_name: "Rejected".to_string(),
        user_id: Uuid::new_v4(),
        action_required_message: None,
    };

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_event_summary()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_cfs_submission_notification_data()
        .times(1)
        .returning(move |_, _, _| Ok(notification_data.clone()));
    expect_site_settings(&mut db);

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    let (logs, _guard) = capture_logs();
    enqueue_cfs_submission_updated_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        CfsSubmissionUpdatedNotice {
            cfs_submission_id,
            community_id,
            event_id,
            group_id,
            reviewer_id,
        },
    )
    .await;

    // Check the failure was logged with the identifiers
    let line = logged_line(
        &logs,
        "failed to enqueue CFS submission update notification",
    );
    assert!(line.contains("error=queue unavailable"), "{line}");
    assert!(
        line.contains(&format!("cfs_submission_id={cfs_submission_id}")),
        "{line}"
    );
    assert!(
        line.contains(&format!("community_id={community_id}")),
        "{line}"
    );
    assert!(line.contains(&format!("event_id={event_id}")), "{line}");
    assert!(line.contains(&format!("group_id={group_id}")), "{line}");
    assert!(
        line.contains(&format!("reviewer_id={reviewer_id}")),
        "{line}"
    );
}

#[tokio::test]
async fn test_enqueue_community_team_invitation_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let community = sample_community_summary(community_id);
    let expected_community_name = community.display_name.clone();
    let expected_theme = sample_site_settings().theme;

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(community.clone()));
    expect_site_settings(&mut db);

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
        &sample_server_cfg("https://example.test/"),
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
        &sample_server_cfg("https://example.test/"),
        Uuid::new_v4(),
        Uuid::new_v4(),
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_community_team_invitation_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .returning(move |_| Ok(sample_community_summary(community_id)));
    expect_site_settings(&mut db);

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    let (logs, _guard) = capture_logs();
    enqueue_community_team_invitation_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        community_id,
        user_id,
    )
    .await;

    // Check the failure was logged with the identifiers
    let line = logged_line(
        &logs,
        "failed to enqueue community team invitation notification",
    );
    assert!(line.contains("error=queue unavailable"), "{line}");
    assert!(
        line.contains(&format!("community_id={community_id}")),
        "{line}"
    );
    assert!(line.contains(&format!("user_id={user_id}")), "{line}");
}

#[tokio::test]
async fn test_enqueue_event_notification_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database context reads
    let mut db = MockDB::new();
    expect_site_settings(&mut db);
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
        &sample_server_cfg("https://example.test/"),
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
    let event = sample_event_summary(event_id);

    // Setup database context reads
    let mut db = MockDB::new();
    expect_site_settings(&mut db);
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
        &sample_server_cfg("https://example.test/"),
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
    expect_site_settings(&mut db);
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
        &sample_server_cfg("https://example.test/"),
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
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id);

    // Setup database context reads
    let mut db = MockDB::new();
    expect_site_settings(&mut db);
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
    let (logs, _guard) = capture_logs();
    enqueue_event_notification_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        community_id,
        event_id,
        |event, server_cfg, site_settings| {
            build_event_waitlist_joined_notification(event, user_id, server_cfg, site_settings)
        },
    )
    .await;

    // Check the failure was logged with the identifiers
    let line = logged_line(&logs, "failed to enqueue event notification");
    assert!(line.contains("error=queue unavailable"), "{line}");
    assert!(
        line.contains(&format!("community_id={community_id}")),
        "{line}"
    );
    assert!(line.contains(&format!("event_id={event_id}")), "{line}");
    assert!(line.contains("kind=EventWaitlistJoined"), "{line}");
}

#[tokio::test]
async fn test_enqueue_group_team_invitation_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let group = sample_group_summary(group_id);
    let expected_theme = sample_site_settings().theme;

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));
    expect_site_settings(&mut db);

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
        &sample_server_cfg("https://example.test/"),
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
        &sample_server_cfg("https://example.test/"),
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_group_team_invitation_best_effort_swallows_enqueue_failure() {
    // Setup identifiers and notification context
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database context reads
    let mut db = MockDB::new();
    db.expect_get_group_summary()
        .times(1)
        .returning(move |_, _| Ok(sample_group_summary(group_id)));
    expect_site_settings(&mut db);

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    let (logs, _guard) = capture_logs();
    enqueue_group_team_invitation_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        user_id,
    )
    .await;

    // Check the failure was logged with the identifiers
    let line = logged_line(
        &logs,
        "failed to enqueue group team invitation notification",
    );
    assert!(line.contains("error=queue unavailable"), "{line}");
    assert!(
        line.contains(&format!("community_id={community_id}")),
        "{line}"
    );
    assert!(line.contains(&format!("group_id={group_id}")), "{line}");
    assert!(line.contains(&format!("user_id={user_id}")), "{line}");
}

#[tokio::test]
async fn test_enqueue_session_proposal_co_speaker_invitation_best_effort_enqueues_once() {
    // Setup identifiers and notification context
    let co_speaker_user_id = Uuid::new_v4();
    let expected_theme = sample_site_settings().theme;

    // Setup database context reads
    let mut db = MockDB::new();
    expect_site_settings(&mut db);

    // Setup the single enqueue expectation with the full content
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(
                notification.kind,
                NotificationKind::SessionProposalCoSpeakerInvitation
            ) && notification.recipients == vec![co_speaker_user_id]
                && notification.attachments.is_empty()
                && notification.group_ids.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SessionProposalCoSpeakerInvitation>(value.clone()).is_ok_and(
                        |template| {
                            template.link
                                == "https://example.test/dashboard/user?tab=session-proposals"
                                && template.session_proposal_title == "Proposal title"
                                && template.speaker_name == "Speaker Name"
                                && template.theme.primary_color == expected_theme.primary_color
                        },
                    )
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue
    enqueue_session_proposal_co_speaker_invitation_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        CoSpeakerInvitationNotice {
            actor_user_id: Uuid::new_v4(),
            co_speaker_user_id,
            session_proposal_title: "Proposal title",
            speaker_name: "Speaker Name",
            session_proposal_id: None,
        },
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_session_proposal_co_speaker_invitation_best_effort_swallows_context_load_failure()
 {
    // Setup a failing context read
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Err(anyhow!("db unavailable")));

    // Setup notifications manager that must not be called
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue().never();
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    enqueue_session_proposal_co_speaker_invitation_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        CoSpeakerInvitationNotice {
            actor_user_id: Uuid::new_v4(),
            co_speaker_user_id: Uuid::new_v4(),
            session_proposal_title: "Proposal title",
            speaker_name: "Speaker Name",
            session_proposal_id: Some(Uuid::new_v4()),
        },
    )
    .await;
}

#[tokio::test]
async fn test_enqueue_session_proposal_co_speaker_invitation_best_effort_swallows_enqueue_failure()
{
    // Setup identifiers
    let actor_user_id = Uuid::new_v4();
    let co_speaker_user_id = Uuid::new_v4();
    let session_proposal_id = Uuid::new_v4();

    // Setup database context reads
    let mut db = MockDB::new();
    expect_site_settings(&mut db);

    // Setup a failing enqueue
    let mut nm = MockNotificationsManager::new();
    nm.expect_enqueue()
        .times(1)
        .returning(|_| Box::pin(async { Err(anyhow!("queue unavailable")) }));
    let nm: DynNotificationsManager = Arc::new(nm);

    // Run the best-effort enqueue, which must return without error
    let (logs, _guard) = capture_logs();
    enqueue_session_proposal_co_speaker_invitation_best_effort(
        &db,
        &nm,
        &sample_server_cfg("https://example.test/"),
        CoSpeakerInvitationNotice {
            actor_user_id,
            co_speaker_user_id,
            session_proposal_title: "Proposal title",
            speaker_name: "Speaker Name",
            session_proposal_id: Some(session_proposal_id),
        },
    )
    .await;

    // Check the failure was logged with the identifiers
    let line = logged_line(
        &logs,
        "failed to enqueue session proposal co-speaker invitation notification",
    );
    assert!(line.contains("error=queue unavailable"), "{line}");
    assert!(line.contains(&format!("user_id={actor_user_id}")), "{line}");
    assert!(
        line.contains(&format!("co_speaker_user_id={co_speaker_user_id}")),
        "{line}"
    );
    assert!(
        line.contains(&format!("session_proposal_id={session_proposal_id}")),
        "{line}"
    );
}

// Types.

/// Process-wide subscriber that records each event as `name=value` pairs in
/// the log buffer of the capture active on the emitting thread.
struct LogCapture;

impl Subscriber for LogCapture {
    fn enabled(&self, _metadata: &Metadata<'_>) -> bool {
        true
    }

    fn enter(&self, _span: &Id) {}

    fn event(&self, event: &Event<'_>) {
        CAPTURED_LOGS.with_borrow(|logs| {
            if let Some(logs) = logs {
                let mut line = String::new();
                event.record(&mut LogLineVisitor(&mut line));
                logs.lock().expect("logs lock not to be poisoned").push(line);
            }
        });
    }

    fn exit(&self, _span: &Id) {}

    fn new_span(&self, _span: &Attributes<'_>) -> Id {
        Id::from_u64(1)
    }

    fn record(&self, _span: &Id, _values: &Record<'_>) {}

    fn record_follows_from(&self, _span: &Id, _follows: &Id) {}
}

/// Field visitor appending `name=value` pairs to a log line.
struct LogLineVisitor<'a>(&'a mut String);

impl Visit for LogLineVisitor<'_> {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        let _ = write!(self.0, "{}={value:?} ", field.name());
    }
}

/// Guard that stops the log capture on this thread when dropped.
struct LogCaptureGuard;

impl Drop for LogCaptureGuard {
    fn drop(&mut self) {
        CAPTURED_LOGS.set(None);
    }
}

// Helpers.

thread_local! {
    /// Log buffer of the capture active on this thread, if any.
    static CAPTURED_LOGS: RefCell<Option<Arc<Mutex<Vec<String>>>>> =
        const { RefCell::new(None) };
}

/// Records the formatted fields of every event logged on this thread while the
/// returned guard is alive.
///
/// A process-wide subscriber is used because tracing caches callsite interest
/// globally: with a scoped subscriber, a concurrent test without one can
/// register a shared callsite as disabled and the event is never captured.
fn capture_logs() -> (Arc<Mutex<Vec<String>>>, LogCaptureGuard) {
    static INSTALL_SUBSCRIBER: Once = Once::new();
    INSTALL_SUBSCRIBER.call_once(|| {
        tracing::subscriber::set_global_default(LogCapture)
            .expect("global log capture subscriber to be installed");
    });

    let logs = Arc::new(Mutex::new(Vec::new()));
    CAPTURED_LOGS.set(Some(logs.clone()));
    (logs, LogCaptureGuard)
}

/// Returns the captured log line containing the given message.
fn logged_line(logs: &Mutex<Vec<String>>, message: &str) -> String {
    logs.lock()
        .expect("logs lock not to be poisoned")
        .iter()
        .find(|line| line.contains(message))
        .cloned()
        .unwrap_or_else(|| panic!("expected a log line containing {message:?}"))
}
