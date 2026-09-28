use std::sync::{Arc, Mutex};

use anyhow::anyhow;
use chrono::{Duration, Utc};
use serde_json::from_value;

use crate::{
    config::HttpServerConfig,
    db::mock::MockDB,
    templates::notifications::{
        EventCohostInvitation, EventCohostRemoved, EventPaidConfigured, EventPublished,
        EventRescheduled, EventSeriesCanceled, EventSeriesPublished, SpeakerSeriesWelcome,
        SpeakerWelcome,
    },
    types::{
        event::{EventFull, EventSummary, Speaker},
        notifications::{NewNotification, NotificationKind},
        tests::{
            sample_event_cohost_group, sample_event_full, sample_event_summary,
            sample_group_summary, sample_site_settings, sample_template_user_with_id,
        },
    },
};

use super::*;

#[tokio::test]
async fn test_enqueue_event_cohost_invitation_notifications_combines_events_per_group() {
    // Setup identifiers and invitations for two co-host groups
    let admin_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_with_admins_id = Uuid::new_v4();
    let group_without_admins_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let refs = vec![
        sample_cohost_ref(group_with_admins_id, event_id),
        sample_cohost_ref(group_with_admins_id, related_event_id),
        sample_cohost_ref(group_without_admins_id, event_id),
    ];
    let data = refs
        .iter()
        .map(|reference| {
            sample_cohost_notification_data(reference.cohost_group_id, reference.event_id)
        })
        .collect::<Vec<_>>();
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_cohost_notification_data()
        .times(1)
        .withf(|items| items.len() == 3)
        .returning(move |_| Ok(data.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_list_group_admin_ids().times(2).returning(move |gid| {
        if gid == group_with_admins_id {
            Ok(vec![admin_id])
        } else {
            Ok(vec![])
        }
    });
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(1)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_cohost_invitation_notifications(&db, &sample_server_cfg(), &refs)
        .await
        .unwrap();

    // Check one combined invitation reaches only the admins
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    let notification = find_notification(&notifications, &NotificationKind::EventCohostInvitation);
    assert_eq!(notification.recipients, vec![admin_id]);
    let template: EventCohostInvitation =
        from_value(notification.template_data.clone().expect("template data to exist"))
            .expect("invitation notification to deserialize");
    assert_eq!(template.events.len(), 2);
    assert_eq!(
        template.link,
        "https://example.test/dashboard/group?tab=cohosts"
    );
}

#[tokio::test]
async fn test_enqueue_event_cohost_invitation_notifications_returns_for_empty_refs() {
    // Setup database mock without expectations
    let db = MockDB::new();

    // Run the workflow
    let result =
        enqueue_event_cohost_invitation_notifications(&db, &sample_server_cfg(), &[]).await;

    // Check nothing was loaded or enqueued
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_enqueue_event_cohost_removed_notifications_links_dashboard_for_removals() {
    // Setup identifiers and one removed co-host
    let admin_id = Uuid::new_v4();
    let cohost_group_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let refs = vec![sample_cohost_ref(cohost_group_id, event_id)];
    let data = vec![sample_cohost_notification_data(cohost_group_id, event_id)];

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_cohost_notification_data()
        .times(1)
        .returning(move |_| Ok(data.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_list_group_admin_ids()
        .times(1)
        .withf(move |gid| *gid == cohost_group_id)
        .returning(move |_| Ok(vec![admin_id]));
    db.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventCohostRemoved)
                && notification.recipients == vec![admin_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventCohostRemoved>(value.clone()).is_ok_and(|template| {
                        template.reason == EventCohostRemovalReason::Removed
                            && template.link.as_deref()
                                == Some("https://example.test/dashboard/group?tab=cohosts")
                    })
                })
        })
        .returning(|_| Ok(()));

    // Run the workflow
    enqueue_event_cohost_removed_notifications(
        &db,
        &sample_server_cfg(),
        EventCohostRemovalReason::Removed,
        &refs,
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_cohost_responded_notification_skips_owner_without_admins() {
    // Setup identifiers and the response
    let owner_group_id = Uuid::new_v4();
    let response = EventCohostResponse {
        cohost_group_id: Uuid::new_v4(),
        event_id: Uuid::new_v4(),
        invitation_id: Uuid::new_v4(),
        owner_community_id: Uuid::new_v4(),
        owner_group_id,
    };

    // Setup database mock without owner admins
    let mut db = MockDB::new();
    db.expect_list_group_admin_ids()
        .times(1)
        .withf(move |gid| *gid == owner_group_id)
        .returning(|_| Ok(vec![]));
    db.expect_get_event_cohost_notification_data().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    let result = enqueue_event_cohost_responded_notification(
        &db,
        &sample_server_cfg(),
        &response,
        EventCohostStatus::Approved,
    )
    .await;

    // Check the workflow skipped the email
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_enqueue_event_paid_configured_notifications_propagates_enqueue_failure() {
    // Setup persisted event and recipient context
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let mut db = MockDB::new();
    db.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow::anyhow!("notification error")));

    // Run the required notification workflow
    let err = enqueue_event_paid_configured_notifications(&db, community_id, group_id, &[event_id])
        .await
        .expect_err("enqueue failure to propagate");

    // Check the required side-effect failure remains visible
    assert_eq!(err.to_string(), "notification error");
}

#[tokio::test]
async fn test_enqueue_event_paid_configured_notifications_returns_for_empty_event_ids() {
    // Forbid every database operation after the empty-input guard
    let mut db = MockDB::new();
    db.expect_list_community_admin_ids().never();
    db.expect_get_event_summary().never();
    db.expect_get_site_settings().never();
    db.expect_enqueue_notification().never();

    // Run the workflow with no event identifiers
    enqueue_event_paid_configured_notifications(&db, Uuid::new_v4(), Uuid::new_v4(), &[])
        .await
        .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_paid_configured_notifications_returns_for_empty_recipients() {
    // Setup identifiers and recipient query
    let community_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(|_| Ok(vec![]));
    db.expect_get_event_summary().never();
    db.expect_get_site_settings().never();
    db.expect_enqueue_notification().never();

    // Run the workflow without loading event data
    enqueue_event_paid_configured_notifications(
        &db,
        community_id,
        Uuid::new_v4(),
        &[Uuid::new_v4()],
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_paid_configured_notifications_returns_for_test_events() {
    // Setup identifiers and a test event
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = EventSummary {
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };

    // Setup recipient and event queries while forbidding downstream work
    let mut db = MockDB::new();
    db.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_site_settings().never();
    db.expect_enqueue_notification().never();

    // Run the workflow through the empty-items guard
    enqueue_event_paid_configured_notifications(&db, community_id, group_id, &[event_id])
        .await
        .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_paid_configured_notifications_sends_ordered_aggregate() {
    // Setup ordered events and recipients
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let related_event = sample_event_summary(related_event_id, group_id);
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database reads in event-id order
    let mut db = MockDB::new();
    db.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(1)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_paid_configured_notifications(
        &db,
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Check the aggregate contract and ordering
    let notifications = notifications.lock().expect("notifications lock not to be poisoned");
    assert_eq!(notifications.len(), 1);
    let notification = &notifications[0];
    assert!(matches!(
        notification.kind,
        NotificationKind::EventPaidConfigured
    ));
    assert_eq!(notification.recipients, vec![admin_id]);
    let template: EventPaidConfigured =
        from_value(notification.template_data.clone().expect("template data to exist"))
            .expect("paid event notification to deserialize");
    assert_eq!(
        template.events.iter().map(|event| event.event_id).collect::<Vec<_>>(),
        vec![event_id, related_event_id]
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_enqueue_event_series_canceled_notifications_groups_by_recipient_event_set() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let test_event_id = Uuid::new_v4();
    let shared_recipient_id = Uuid::new_v4();
    let event_recipient_id = Uuid::new_v4();
    let related_event_recipient_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let test_event_recipient_id = Uuid::new_v4();
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id]);
    let related_event =
        sample_event_full_with_speakers(community_id, related_event_id, group_id, &[]);
    let test_event = EventFull {
        test_event: true,
        ..sample_event_full_with_speakers(community_id, test_event_id, group_id, &[])
    };
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![shared_recipient_id, event_recipient_id]));
    db.expect_list_event_waitlist_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == related_event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![shared_recipient_id]));
    db.expect_list_event_waitlist_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == related_event_id)
        .returning(move |_, _| Ok(vec![related_event_recipient_id]));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == test_event_id
        })
        .returning(move |_, _, _| Ok(test_event.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == test_event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![test_event_recipient_id]));
    db.expect_list_event_waitlist_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == test_event_id)
        .returning(|_, _| Ok(vec![]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(3)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_series_canceled_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        &[event_id, related_event_id, test_event_id],
    )
    .await
    .unwrap();

    // Check notifications match recipient event sets
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    assert_eq!(notifications.len(), 3);
    let groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesCanceled))
        .map(|notification| {
            let template: EventSeriesCanceled =
                from_value(notification.template_data.clone().expect("template data to exist"))
                    .expect("series canceled notification to deserialize");
            let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
            (notification.recipients.clone(), event_ids)
        })
        .collect();
    assert_recipient_event_group_exists(
        &groups,
        &[shared_recipient_id],
        &[event_id, related_event_id],
    );
    assert_recipient_event_group_exists(&groups, &[event_recipient_id, speaker_id], &[event_id]);
    assert_recipient_event_group_exists(
        &groups,
        &[related_event_recipient_id],
        &[related_event_id],
    );
    assert!(
        !groups
            .iter()
            .any(|(recipients, _)| recipients.contains(&test_event_recipient_id))
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_enqueue_event_series_published_notifications_dedupes_cohost_audiences() {
    // Setup identifiers and two occurrences with overlapping co-host audiences
    let alpha_group_id = Uuid::new_v4();
    let alpha_member_id = Uuid::new_v4();
    let beta_group_id = Uuid::new_v4();
    let beta_member_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let owner_member_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let event = EventFull {
        cohosts: vec![sample_event_cohost_group(alpha_group_id, "Alpha")],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let related_event = EventFull {
        cohosts: vec![
            sample_event_cohost_group(beta_group_id, "Beta"),
            sample_event_cohost_group(alpha_group_id, "Alpha"),
        ],
        ..sample_event_full(community_id, related_event_id, group_id)
    };
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock with each audience loaded once
    let mut db = MockDB::new();
    db.expect_list_group_members_ids().times(3).returning(move |gid| {
        if gid == group_id {
            Ok(vec![owner_member_id])
        } else if gid == alpha_group_id {
            Ok(vec![owner_member_id, alpha_member_id])
        } else {
            Ok(vec![alpha_member_id, beta_member_id])
        }
    });
    db.expect_list_group_team_members_ids()
        .times(3)
        .returning(|_| Ok(vec![]));
    db.expect_get_event_full()
        .times(1)
        .withf(move |_, _, eid| *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |_, _, eid| *eid == related_event_id)
        .returning(move |_, _, _| Ok(related_event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(3)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Collect the recipients, events, and co-host name of every copy
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    let copies: Vec<(Option<String>, Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .map(|notification| {
            let template: EventSeriesPublished =
                from_value(notification.template_data.clone().expect("template data to exist"))
                    .expect("series published notification to deserialize");
            let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
            (
                template.cohost_group_name,
                notification.recipients.clone(),
                event_ids,
            )
        })
        .collect();

    // Check each recipient is notified once per occurrence by the first audience
    assert!(copies.contains(&(
        None,
        vec![owner_member_id],
        vec![event_id, related_event_id]
    )));
    assert!(copies.contains(&(
        Some("Alpha".to_string()),
        vec![alpha_member_id],
        vec![event_id, related_event_id]
    )));
    assert!(copies.contains(&(
        Some("Beta".to_string()),
        vec![beta_member_id],
        vec![related_event_id]
    )));
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_enqueue_event_series_published_notifications_groups_members_and_speakers() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let related_event_speaker_id = Uuid::new_v4();
    let team_member_id = Uuid::new_v4();
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id]);
    let related_event = sample_event_full_with_speakers(
        community_id,
        related_event_id,
        group_id,
        &[speaker_id, related_event_speaker_id],
    );
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id, speaker_id]));
    db.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![team_member_id, member_id]));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(3)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Check notifications match member and speaker event sets
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    assert_eq!(notifications.len(), 3);
    let member_groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesPublished))
        .map(|notification| {
            let template: EventSeriesPublished =
                from_value(notification.template_data.clone().expect("template data to exist"))
                    .expect("series published notification to deserialize");
            let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
            (notification.recipients.clone(), event_ids)
        })
        .collect();
    assert_recipient_event_group_exists(
        &member_groups,
        &[member_id, team_member_id],
        &[event_id, related_event_id],
    );
    let speaker_groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::SpeakerSeriesWelcome))
        .map(|notification| {
            let template: SpeakerSeriesWelcome =
                from_value(notification.template_data.clone().expect("template data to exist"))
                    .expect("speaker series notification to deserialize");
            let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
            (notification.recipients.clone(), event_ids)
        })
        .collect();
    assert_recipient_event_group_exists(
        &speaker_groups,
        &[speaker_id],
        &[event_id, related_event_id],
    );
    assert_recipient_event_group_exists(
        &speaker_groups,
        &[related_event_speaker_id],
        &[related_event_id],
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_enqueue_event_series_published_notifications_skips_covered_cohost_recipients() {
    // Setup identifiers and occurrences whose speaker and audiences overlap co-hosts
    let alpha_group_id = Uuid::new_v4();
    let alpha_member_id = Uuid::new_v4();
    let beta_group_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let owner_member_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let event = EventFull {
        cohosts: vec![sample_event_cohost_group(alpha_group_id, "Alpha")],
        ..sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id])
    };
    let related_event = EventFull {
        cohosts: vec![
            sample_event_cohost_group(beta_group_id, "Beta"),
            sample_event_cohost_group(alpha_group_id, "Alpha"),
        ],
        ..sample_event_full(community_id, related_event_id, group_id)
    };
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup audience expectations with each audience loaded once
    let mut db = MockDB::new();
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![owner_member_id]));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == alpha_group_id)
        .returning(move |_| Ok(vec![alpha_member_id, speaker_id]));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == beta_group_id)
        .returning(move |_| Ok(vec![owner_member_id, alpha_member_id]));
    db.expect_list_group_team_members_ids()
        .times(3)
        .returning(|_| Ok(vec![]));

    // Setup event expectations
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event.clone()));

    // Setup notification expectations
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(4)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Collect the co-host name, recipients, and events of every published copy
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    let copies: Vec<(Option<String>, Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesPublished))
        .map(|notification| {
            let template: EventSeriesPublished =
                from_value(notification.template_data.clone().expect("template data to exist"))
                    .expect("series published notification to deserialize");
            let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
            (
                template.cohost_group_name,
                notification.recipients.clone(),
                event_ids,
            )
        })
        .collect();

    // Check the speaker is covered only for the occurrence they speak at
    assert_eq!(copies.len(), 3);
    assert!(copies.contains(&(
        None,
        vec![owner_member_id],
        vec![event_id, related_event_id]
    )));
    assert!(copies.contains(&(
        Some("Alpha".to_string()),
        vec![alpha_member_id],
        vec![event_id, related_event_id]
    )));
    assert!(copies.contains(&(
        Some("Alpha".to_string()),
        vec![speaker_id],
        vec![related_event_id]
    )));

    // Check a fully covered co-host audience gets no copy
    assert!(
        !copies
            .iter()
            .any(|(cohost_group_name, _, _)| cohost_group_name.as_deref() == Some("Beta"))
    );

    // Check the speaker welcome only lists the occurrence they speak at
    let speaker_notification =
        find_notification(&notifications, &NotificationKind::SpeakerSeriesWelcome);
    assert_eq!(speaker_notification.recipients, vec![speaker_id]);
    let template: SpeakerSeriesWelcome = from_value(
        speaker_notification
            .template_data
            .clone()
            .expect("template data to exist"),
    )
    .expect("speaker series notification to deserialize");
    assert_eq!(
        template
            .events
            .iter()
            .map(|event| event.event.event_id)
            .collect::<Vec<_>>(),
        vec![event_id]
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_enqueue_event_published_notifications_dedupes_cohost_audiences() {
    // Setup identifiers and an event whose speaker and audiences overlap
    let alpha_group_id = Uuid::new_v4();
    let alpha_member_id = Uuid::new_v4();
    let beta_group_id = Uuid::new_v4();
    let beta_member_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let gamma_group_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let owner_member_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let event = EventFull {
        cohosts: vec![
            sample_event_cohost_group(gamma_group_id, "Gamma"),
            sample_event_cohost_group(beta_group_id, "Beta"),
            sample_event_cohost_group(alpha_group_id, "Alpha"),
        ],
        ..sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id])
    };
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup event expectations
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));

    // Setup audience expectations, each co-host overlapping an earlier audience
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![owner_member_id]));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == alpha_group_id)
        .returning(move |_| Ok(vec![owner_member_id, alpha_member_id]));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == beta_group_id)
        .returning(move |_| Ok(vec![alpha_member_id, beta_member_id, speaker_id]));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == gamma_group_id)
        .returning(move |_| Ok(vec![owner_member_id, speaker_id]));
    db.expect_list_group_team_members_ids()
        .times(4)
        .returning(|_| Ok(vec![]));

    // Setup notification expectations
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(4)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Collect the co-host name and recipients of every published copy
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    let copies: Vec<(Option<String>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventPublished))
        .map(|notification| {
            let template: EventPublished =
                from_value(notification.template_data.clone().expect("template data to exist"))
                    .expect("published notification to deserialize");
            (template.cohost_group_name, notification.recipients.clone())
        })
        .collect();

    // Check each member gets one copy and a fully covered co-host gets none
    assert_eq!(
        copies,
        vec![
            (None, vec![owner_member_id]),
            (Some("Alpha".to_string()), vec![alpha_member_id]),
            (Some("Beta".to_string()), vec![beta_member_id]),
        ]
    );

    // Check the speaker only gets the speaker welcome
    let speaker_notification = find_notification(&notifications, &NotificationKind::SpeakerWelcome);
    assert_eq!(speaker_notification.recipients, vec![speaker_id]);
}

#[tokio::test]
async fn test_enqueue_event_published_notifications_notifies_cohost_audience_alone() {
    // Setup identifiers and an event whose only audience is a co-host's
    let cohost_group_id = Uuid::new_v4();
    let cohost_member_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = EventFull {
        cohosts: vec![sample_event_cohost_group(cohost_group_id, "Cohost Group")],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_group_members_ids().times(2).returning(move |gid| {
        if gid == cohost_group_id {
            Ok(vec![cohost_member_id])
        } else {
            Ok(vec![])
        }
    });
    db.expect_list_group_team_members_ids()
        .times(2)
        .returning(|_| Ok(vec![]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(1)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Check the co-host copy names the co-host group
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    let notification = find_notification(&notifications, &NotificationKind::EventPublished);
    assert_eq!(notification.recipients, vec![cohost_member_id]);
    let template: EventPublished =
        from_value(notification.template_data.clone().expect("template data to exist"))
            .expect("published notification to deserialize");
    assert_eq!(template.cohost_group_name.as_deref(), Some("Cohost Group"));
}

#[tokio::test]
async fn test_enqueue_event_published_notifications_sends_members_and_speakers_separately() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let speaker_member_id = Uuid::new_v4();
    let team_member_id = Uuid::new_v4();
    let event = sample_event_full_with_speakers(
        community_id,
        event_id,
        group_id,
        &[speaker_id, speaker_member_id],
    );
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id, speaker_member_id]));
    db.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![team_member_id, member_id]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(2)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Check notifications split member and speaker audiences
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    assert_eq!(notifications.len(), 2);
    let member_notification = find_notification(&notifications, &NotificationKind::EventPublished);
    assert_eq!(
        sorted_ids(member_notification.recipients.clone()),
        sorted_ids(vec![member_id, team_member_id])
    );
    let speaker_notification = find_notification(&notifications, &NotificationKind::SpeakerWelcome);
    assert_eq!(
        sorted_ids(speaker_notification.recipients.clone()),
        sorted_ids(vec![speaker_id, speaker_member_id])
    );
    let _: SpeakerWelcome = from_value(
        speaker_notification
            .template_data
            .clone()
            .expect("template data to exist"),
    )
    .expect("speaker notification to deserialize");
}

#[tokio::test]
async fn test_enqueue_event_rescheduled_notification_skips_small_shift() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let before = sample_future_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|starts_at| starts_at + Duration::minutes(10)),
        ..before.clone()
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(after.clone()));

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        event_id,
        &before,
        Utc::now(),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_rescheduled_notification_sends_to_attendees_and_speakers() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let before = sample_future_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|starts_at| starts_at + Duration::minutes(30)),
        ..before.clone()
    };
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id]);
    let notifications = Arc::new(Mutex::new(Vec::new()));

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(after.clone()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id, speaker_id]));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(1)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg(),
        community_id,
        group_id,
        event_id,
        &before,
        Utc::now(),
    )
    .await
    .unwrap();

    // Check notification matches recipient selection
    let notifications = notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone();
    assert_eq!(notifications.len(), 1);
    let notification = find_notification(&notifications, &NotificationKind::EventRescheduled);
    assert_eq!(
        sorted_ids(notification.recipients.clone()),
        sorted_ids(vec![attendee_id, speaker_id])
    );
    let template: EventRescheduled =
        from_value(notification.template_data.clone().expect("template data to exist"))
            .expect("event rescheduled notification to deserialize");
    assert_eq!(template.event.event_id, event_id);
}

#[tokio::test]
async fn test_enqueue_tracked_event_custom_notification_builds_content_and_tracking() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let attendee_id1 = Uuid::new_v4();
    let attendee_id2 = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);
    let expected_link = format!(
        "https://example.test/{}/group/{}/event/{}",
        event.community_name, event.group_slug, event.slug
    );
    let expected_event_name = event.name.clone();
    let input = EventCustomNotificationInput {
        actor_user_id,
        body: "Hello, event attendees!".to_string(),
        community_id,
        event_id,
        group_id,
        recipients: vec![attendee_id1, attendee_id2],
        subject: "Event Update".to_string(),
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            matches!(notification.kind, NotificationKind::EventCustom)
                && notification.attachments.is_empty()
                && notification.recipients == vec![attendee_id1, attendee_id2]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventCustom>(value.clone()).is_ok_and(|template| {
                        template.subject == "Event Update"
                            && template.body == "Hello, event attendees!"
                            && template.event.name == expected_event_name
                            && template.link == expected_link
                            && template.theme.primary_color
                                == sample_site_settings().theme.primary_color
                    })
                })
                && tracking.body == "Hello, event attendees!"
                && tracking.created_by == actor_user_id
                && tracking.event_id == Some(event_id)
                && tracking.group_id == Some(group_id)
                && tracking.recipient_count == 2
                && tracking.subject == "Event Update"
        })
        .returning(|_, _| Ok(()));

    // Run the workflow
    enqueue_tracked_event_custom_notification(&db, &sample_server_cfg(), &input)
        .await
        .unwrap();
}

#[tokio::test]
async fn test_enqueue_tracked_event_custom_notification_propagates_context_failure() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let input = EventCustomNotificationInput {
        actor_user_id: Uuid::new_v4(),
        body: "Hello".to_string(),
        community_id,
        event_id,
        group_id: Uuid::new_v4(),
        recipients: vec![Uuid::new_v4()],
        subject: "Subject".to_string(),
    };

    // Setup database mock with a failing context load
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));
    db.expect_get_site_settings()
        .times(0..=1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_enqueue_tracked_custom_notification().never();

    // Run the workflow
    let result = enqueue_tracked_event_custom_notification(&db, &sample_server_cfg(), &input).await;

    // Check the failure propagates
    assert!(result.is_err());
}

#[tokio::test]
async fn test_enqueue_tracked_group_custom_notification_builds_content_and_tracking() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id1 = Uuid::new_v4();
    let member_id2 = Uuid::new_v4();
    let mut group = sample_group_summary(group_id);
    group.slug_pretty = Some("pretty-group".to_string());
    let expected_link = format!(
        "https://example.test/{}/group/{}",
        group.community_name,
        group.public_slug()
    );
    let expected_group_name = group.name.clone();
    let input = GroupCustomNotificationInput {
        actor_user_id,
        body: "Hello, group members!".to_string(),
        community_id,
        group_id,
        recipients: vec![member_id1, member_id2],
        subject: "Important Update".to_string(),
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            matches!(notification.kind, NotificationKind::GroupCustom)
                && notification.attachments.is_empty()
                && notification.recipients == vec![member_id1, member_id2]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<GroupCustom>(value.clone()).is_ok_and(|template| {
                        template.subject == "Important Update"
                            && template.body == "Hello, group members!"
                            && template.group.name == expected_group_name
                            && template.link == expected_link
                            && template.theme.primary_color
                                == sample_site_settings().theme.primary_color
                    })
                })
                && tracking.body == "Hello, group members!"
                && tracking.created_by == actor_user_id
                && tracking.event_id.is_none()
                && tracking.group_id == Some(group_id)
                && tracking.recipient_count == 2
                && tracking.subject == "Important Update"
        })
        .returning(|_, _| Ok(()));

    // Run the workflow
    enqueue_tracked_group_custom_notification(&db, &sample_server_cfg(), &input)
        .await
        .unwrap();
}

#[tokio::test]
async fn test_enqueue_tracked_group_custom_notification_propagates_context_failure() {
    // Setup identifiers and data structures
    let input = GroupCustomNotificationInput {
        actor_user_id: Uuid::new_v4(),
        body: "Hello".to_string(),
        community_id: Uuid::new_v4(),
        group_id: Uuid::new_v4(),
        recipients: vec![Uuid::new_v4()],
        subject: "Subject".to_string(),
    };

    // Setup database mock with a failing context load
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_summary()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));
    db.expect_enqueue_tracked_custom_notification().never();

    // Run the workflow
    let result = enqueue_tracked_group_custom_notification(&db, &sample_server_cfg(), &input).await;

    // Check the failure propagates
    assert!(result.is_err());
}

// Helpers.

/// Asserts that a recipient group exists for the exact event ids.
fn assert_recipient_event_group_exists(
    groups: &[(Vec<Uuid>, Vec<Uuid>)],
    recipients: &[Uuid],
    event_ids: &[Uuid],
) {
    let recipients = sorted_ids(recipients.to_vec());
    assert!(
        groups.iter().any(|(actual_recipients, actual_event_ids)| {
            sorted_ids(actual_recipients.clone()) == recipients && actual_event_ids == event_ids
        }),
        "expected notification group for recipients {recipients:?} and events {event_ids:?}"
    );
}

/// Builds co-hosting notification content for one event and co-host group.
fn sample_cohost_notification_data(
    cohost_group_id: Uuid,
    event_id: Uuid,
) -> EventCohostNotificationData {
    EventCohostNotificationData {
        canceled: false,
        cohost_community_display_name: "Cohost Community".to_string(),
        cohost_group_id,
        cohost_group_name: "Cohost Group".to_string(),
        event_id,
        event_name: "Co-hosted Event".to_string(),
        invitation_id: Uuid::new_v4(),
        owner_community_display_name: "Owner Community".to_string(),
        owner_community_id: Uuid::new_v4(),
        owner_group_id: Uuid::new_v4(),
        owner_group_name: "Owner Group".to_string(),
        status: EventCohostStatus::Pending,
        timezone: chrono_tz::UTC,

        starts_at: Some(Utc::now()),
    }
}

/// Builds a reference to one co-hosting invitation.
fn sample_cohost_ref(cohost_group_id: Uuid, event_id: Uuid) -> EventCohostRef {
    EventCohostRef {
        cohost_group_id,
        event_id,
        invitation_id: Uuid::new_v4(),
    }
}

/// Finds the first captured notification of the expected kind.
fn find_notification<'a>(
    notifications: &'a [NewNotification],
    expected_kind: &NotificationKind,
) -> &'a NewNotification {
    notifications
        .iter()
        .find(|notification| notification.kind.to_string() == expected_kind.to_string())
        .expect("notification to exist")
}

/// Builds a sample full event with the provided event-level speakers.
fn sample_event_full_with_speakers(
    community_id: Uuid,
    event_id: Uuid,
    group_id: Uuid,
    speaker_ids: &[Uuid],
) -> EventFull {
    EventFull {
        speakers: speaker_ids
            .iter()
            .copied()
            .map(|user_id| Speaker {
                featured: false,
                user: sample_template_user_with_id(user_id),
            })
            .collect(),
        ..sample_event_full(community_id, event_id, group_id)
    }
}

/// Builds a published event summary safely in the future.
fn sample_future_event_summary(event_id: Uuid, group_id: Uuid) -> EventSummary {
    let starts_at = Utc::now() + Duration::hours(1);
    EventSummary {
        ends_at: Some(starts_at + Duration::hours(1)),
        starts_at: Some(starts_at),
        ..sample_event_summary(event_id, group_id)
    }
}

/// Builds server config with a stable public base URL.
fn sample_server_cfg() -> HttpServerConfig {
    HttpServerConfig {
        base_url: "https://example.test/".to_string(),
        ..Default::default()
    }
}

/// Sorts identifiers for order-independent assertions.
fn sorted_ids(mut ids: Vec<Uuid>) -> Vec<Uuid> {
    ids.sort();
    ids
}
