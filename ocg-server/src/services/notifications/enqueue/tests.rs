use std::sync::{Arc, Mutex};

use anyhow::anyhow;
use chrono::{Duration, Utc};
use serde_json::from_value;

use crate::{
    config::tests::sample_server_cfg,
    db::mock::{MockDB, expect_site_settings, sample_posted_inbox_message},
    services::notifications::tests::template_of,
    templates::notifications::{
        EventCanceled, EventCohostInvitation, EventCohostRemoved, EventCohostResponded,
        EventPaidConfigured, EventPublished, EventRescheduled, EventSeriesCanceled,
        EventSeriesPublished, InboxMessageReceived, InboxReplyReceived, SpeakerSeriesWelcome,
        SpeakerWelcome,
    },
    types::{
        dashboard::community::contact::{CommunityContactFilters, RegionFilterValue},
        event::{EventFull, EventSummary, Speaker},
        group::GroupRole,
        inbox::InboxMessageKind,
        notifications::{NewNotification, NotificationKind},
        tests::{
            sample_community_summary, sample_custom_notification_content,
            sample_event_cohost_group, sample_event_full, sample_event_summary,
            sample_group_summary, sample_inbox_conversation, sample_site_settings,
            sample_template_user, sample_template_user_with_id,
        },
    },
};

use super::*;

#[tokio::test]
async fn test_enqueue_event_canceled_notification_dedupes_attendees_waitlist_and_speakers() {
    // Setup identifiers and overlapping attendee, waitlist, and speaker sets
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let waitlist_id = Uuid::new_v4();
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id]);

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
        .returning(move |_, _, _| Ok(vec![attendee_id, speaker_id]));
    db.expect_list_event_waitlist_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(vec![waitlist_id, attendee_id]));
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 1);

    // Run the workflow
    enqueue_event_canceled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Check one notification reaches each recipient once
    let notifications = enqueued(&notifications);
    let notification = find_notification(&notifications, &NotificationKind::EventCanceled);
    assert_eq!(
        sorted_ids(notification.recipients.clone()),
        sorted_ids(vec![attendee_id, speaker_id, waitlist_id])
    );
    let template: EventCanceled = template_of(notification);
    assert_eq!(template.event.event_id, event_id);
    assert_eq!(
        template.link,
        "https://example.test/test/group/npq6789/event/abc1234"
    );
    assert_eq!(
        template.theme.primary_color,
        sample_site_settings().theme.primary_color
    );
}

#[tokio::test]
async fn test_enqueue_event_canceled_notification_returns_for_empty_recipients() {
    // Setup identifiers and an event without attendees, waitlist, or speakers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[]);

    // Setup database mock forbidding the notification work
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .returning(|_, _, _| Ok(vec![]));
    db.expect_list_event_waitlist_ids()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_get_site_settings().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    enqueue_event_canceled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_canceled_notification_returns_for_test_events() {
    // Setup identifiers and a test event with an attendee
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = EventFull {
        test_event: true,
        ..sample_event_full(community_id, event_id, group_id)
    };

    // Setup database mock forbidding the notification work
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_event_attendees_ids()
        .times(1)
        .returning(|_, _, _| Ok(vec![Uuid::new_v4()]));
    db.expect_list_event_waitlist_ids()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_get_site_settings().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    enqueue_event_canceled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();
}

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

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_cohost_notification_data()
        .times(1)
        .withf(|items| items.len() == 3)
        .returning(move |_| Ok(data.clone()));
    expect_site_settings(&mut db);
    db.expect_list_group_admin_ids().times(2).returning(move |gid| {
        if gid == group_with_admins_id {
            Ok(vec![admin_id])
        } else {
            Ok(vec![])
        }
    });
    let notifications = capture_enqueued(&mut db, 1);

    // Run the workflow
    enqueue_event_cohost_invitation_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        &refs,
    )
    .await
    .unwrap();

    // Check one combined invitation reaches only the admins
    let notifications = enqueued(&notifications);
    let notification = find_notification(&notifications, &NotificationKind::EventCohostInvitation);
    assert_eq!(notification.recipients, vec![admin_id]);
    let template: EventCohostInvitation = template_of(notification);
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
    let result = enqueue_event_cohost_invitation_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        &[],
    )
    .await;

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
    expect_site_settings(&mut db);
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
        &sample_server_cfg("https://example.test/"),
        EventCohostRemovalReason::Removed,
        &refs,
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_cohost_responded_notification_notifies_owner_admins() {
    // Setup identifiers and the response
    let admin_id = Uuid::new_v4();
    let cohost_group_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let invitation_id = Uuid::new_v4();
    let owner_group_id = Uuid::new_v4();
    let response = EventCohostResponse {
        cohost_group_id,
        event_id,
        invitation_id,
        owner_community_id: Uuid::new_v4(),
        owner_group_id,
    };
    let data = vec![sample_cohost_notification_data(cohost_group_id, event_id)];

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_group_admin_ids()
        .times(1)
        .withf(move |gid| *gid == owner_group_id)
        .returning(move |_| Ok(vec![admin_id]));
    db.expect_get_event_cohost_notification_data()
        .times(1)
        .withf(move |refs| {
            refs.len() == 1
                && refs[0].cohost_group_id == cohost_group_id
                && refs[0].event_id == event_id
                && refs[0].invitation_id == invitation_id
        })
        .returning(move |_| Ok(data.clone()));
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 1);

    // Run the workflow
    enqueue_event_cohost_responded_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &response,
        EventCohostStatus::Rejected,
    )
    .await
    .unwrap();

    // Check the owner admins get the response with its status and link
    let notifications = enqueued(&notifications);
    let notification = find_notification(&notifications, &NotificationKind::EventCohostResponded);
    assert_eq!(notification.recipients, vec![admin_id]);
    let template: EventCohostResponded = template_of(notification);
    assert_eq!(template.cohost_group_name, "Cohost Group");
    assert_eq!(template.event.name, "Co-hosted Event");
    assert_eq!(
        template.link,
        "https://example.test/dashboard/group?tab=events"
    );
    assert_eq!(template.owner_group_name, "Owner Group");
    assert_eq!(template.status, EventCohostStatus::Rejected);
    assert_eq!(
        template.theme.primary_color,
        sample_site_settings().theme.primary_color
    );
}

#[tokio::test]
async fn test_enqueue_event_cohost_responded_notification_rejects_missing_data() {
    // Setup the response
    let response = EventCohostResponse {
        cohost_group_id: Uuid::new_v4(),
        event_id: Uuid::new_v4(),
        invitation_id: Uuid::new_v4(),
        owner_community_id: Uuid::new_v4(),
        owner_group_id: Uuid::new_v4(),
    };

    // Setup database mock without co-hosting content
    let mut db = MockDB::new();
    db.expect_list_group_admin_ids()
        .times(1)
        .returning(|_| Ok(vec![Uuid::new_v4()]));
    db.expect_get_event_cohost_notification_data()
        .times(1)
        .returning(|_| Ok(vec![]));
    db.expect_get_site_settings().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    let result = enqueue_event_cohost_responded_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &response,
        EventCohostStatus::Approved,
    )
    .await;

    // Check the missing content fails the required notification
    assert_eq!(
        result.unwrap_err().to_string(),
        "co-hosting notification data not found"
    );
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
        &sample_server_cfg("https://example.test/"),
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
    let event = sample_event_summary(event_id);
    let mut db = MockDB::new();
    db.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    expect_site_settings(&mut db);
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
        ..sample_event_summary(event_id)
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
    let event = sample_event_summary(event_id);
    let related_event = sample_event_summary(related_event_id);

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
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 1);

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
    let notifications = enqueued(&notifications);
    assert_eq!(notifications.len(), 1);
    let notification = &notifications[0];
    assert!(matches!(
        notification.kind,
        NotificationKind::EventPaidConfigured
    ));
    assert_eq!(notification.recipients, vec![admin_id]);
    let template: EventPaidConfigured = template_of(notification);
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
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 3);

    // Run the workflow
    enqueue_event_series_canceled_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        &[event_id, related_event_id, test_event_id],
    )
    .await
    .unwrap();

    // Check notifications match recipient event sets
    let notifications = enqueued(&notifications);
    assert_eq!(notifications.len(), 3);
    let groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesCanceled))
        .map(|notification| {
            let template: EventSeriesCanceled = template_of(notification);
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

    // Setup database mock with each audience loaded once
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![owner_member_id]));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == alpha_group_id)
        .returning(move |_| Ok(sorted_ids(vec![alpha_member_id, owner_member_id])));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == beta_group_id)
        .returning(move |_| Ok(sorted_ids(vec![alpha_member_id, beta_member_id])));
    db.expect_get_event_full()
        .times(1)
        .withf(move |_, _, eid| *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |_, _, eid| *eid == related_event_id)
        .returning(move |_, _, _| Ok(related_event.clone()));
    db.expect_filter_notification_recipient_ids()
        .times(2)
        .withf(|kind, _, _| matches!(kind, NotificationKind::EventSeriesPublished))
        .returning(|_, recipients, _| Ok(recipients.to_vec()));
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 3);

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Collect the recipients, events, and co-host name of every copy
    let notifications = enqueued(&notifications);
    let copies: Vec<(Option<String>, Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .map(|notification| {
            let template: EventSeriesPublished = template_of(notification);
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

    // Check every bundle names the union of its occurrences' groups, which
    // here always includes the related occurrence's owner and co-hosts
    let expected_group_ids = sorted_ids(vec![group_id, alpha_group_id, beta_group_id]);
    for notification in &notifications {
        assert_eq!(notification.group_ids, expected_group_ids);
    }
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_enqueue_event_series_published_notifications_filters_recipients_per_occurrence() {
    // Setup identifiers and two occurrences, only the first co-hosted
    let cohost_group_id = Uuid::new_v4();
    let cohost_member_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let muting_member_id = Uuid::new_v4();
    let owner_member_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let event = EventFull {
        cohosts: vec![sample_event_cohost_group(cohost_group_id, "Cohost")],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let related_event =
        sample_event_full_with_speakers(community_id, related_event_id, group_id, &[speaker_id]);
    let owner_audience = sorted_ids(vec![muting_member_id, owner_member_id]);
    let first_candidates = [owner_audience.clone(), vec![cohost_member_id]].concat();
    let related_candidates = owner_audience.clone();

    // Setup audience expectations
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(owner_audience.clone()));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == cohost_group_id)
        .returning(move |_| Ok(vec![cohost_member_id]));

    // Setup event expectations
    db.expect_get_event_full()
        .times(1)
        .withf(move |_, _, eid| *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_event_full()
        .times(1)
        .withf(move |_, _, eid| *eid == related_event_id)
        .returning(move |_, _, _| Ok(related_event.clone()));

    // Setup eligibility: the muting member muted the co-host of the first occurrence
    db.expect_filter_notification_recipient_ids()
        .times(1)
        .withf(move |kind, recipients, group_ids| {
            matches!(kind, NotificationKind::EventSeriesPublished)
                && recipients == first_candidates.as_slice()
                && group_ids == [group_id, cohost_group_id]
        })
        .returning(move |_, _, _| Ok(vec![owner_member_id, cohost_member_id]));
    db.expect_filter_notification_recipient_ids()
        .times(1)
        .withf(move |kind, recipients, group_ids| {
            matches!(kind, NotificationKind::EventSeriesPublished)
                && recipients == related_candidates.as_slice()
                && group_ids == [group_id]
        })
        .returning(|_, recipients, _| Ok(recipients.to_vec()));

    // Setup notification expectations
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 4);

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Collect the co-host name, recipients, events, and groups of every bundle
    let notifications = enqueued(&notifications);
    let bundles: Vec<SeriesBundle> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesPublished))
        .map(|notification| {
            let template: EventSeriesPublished = template_of(notification);
            let event_ids = template.events.iter().map(|event| event.event.event_id).collect();
            (
                template.cohost_group_name,
                notification.recipients.clone(),
                event_ids,
                notification.group_ids.clone(),
            )
        })
        .collect();

    // Check the muted co-host only removes the occurrence it co-hosts
    assert_eq!(bundles.len(), 3);
    assert!(bundles.contains(&(
        None,
        vec![owner_member_id],
        vec![event_id, related_event_id],
        sorted_ids(vec![group_id, cohost_group_id]),
    )));
    assert!(bundles.contains(&(
        None,
        vec![muting_member_id],
        vec![related_event_id],
        vec![group_id],
    )));
    assert!(bundles.contains(&(
        Some("Cohost".to_string()),
        vec![cohost_member_id],
        vec![event_id],
        sorted_ids(vec![group_id, cohost_group_id]),
    )));

    // Check speakers are not filtered
    let speaker_notification =
        find_notification(&notifications, &NotificationKind::SpeakerSeriesWelcome);
    assert_eq!(speaker_notification.recipients, vec![speaker_id]);
}

#[tokio::test]
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

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(sorted_ids(vec![member_id, speaker_id, team_member_id])));
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
    db.expect_filter_notification_recipient_ids()
        .times(2)
        .withf(|kind, _, _| matches!(kind, NotificationKind::EventSeriesPublished))
        .returning(|_, recipients, _| Ok(recipients.to_vec()));
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 3);

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Check notifications match member and speaker event sets
    let notifications = enqueued(&notifications);
    assert_eq!(notifications.len(), 3);
    let member_groups: Vec<(Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesPublished))
        .map(|notification| {
            let template: EventSeriesPublished = template_of(notification);
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
            let template: SpeakerSeriesWelcome = template_of(notification);
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

    // Setup audience expectations with each audience loaded once
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![owner_member_id]));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == alpha_group_id)
        .returning(move |_| Ok(sorted_ids(vec![alpha_member_id, speaker_id])));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == beta_group_id)
        .returning(move |_| Ok(sorted_ids(vec![alpha_member_id, owner_member_id])));

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
    // Setup eligibility expectations that keep every candidate
    db.expect_filter_notification_recipient_ids()
        .times(2)
        .withf(|kind, _, _| matches!(kind, NotificationKind::EventSeriesPublished))
        .returning(|_, recipients, _| Ok(recipients.to_vec()));

    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 4);

    // Run the workflow
    enqueue_event_series_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        &[event_id, related_event_id],
    )
    .await
    .unwrap();

    // Collect the co-host name, recipients, and events of every published copy
    let notifications = enqueued(&notifications);
    let copies: Vec<(Option<String>, Vec<Uuid>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventSeriesPublished))
        .map(|notification| {
            let template: EventSeriesPublished = template_of(notification);
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
    let template: SpeakerSeriesWelcome = template_of(speaker_notification);
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

    // Setup event expectations
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));

    // Setup audience expectations, each co-host overlapping an earlier audience
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![owner_member_id]));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == alpha_group_id)
        .returning(move |_| Ok(sorted_ids(vec![alpha_member_id, owner_member_id])));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == beta_group_id)
        .returning(move |_| {
            Ok(sorted_ids(vec![
                alpha_member_id,
                beta_member_id,
                speaker_id,
            ]))
        });
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == gamma_group_id)
        .returning(move |_| Ok(sorted_ids(vec![owner_member_id, speaker_id])));

    // Setup notification expectations
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 4);

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Collect the co-host name and recipients of every published copy
    let notifications = enqueued(&notifications);
    let copies: Vec<(Option<String>, Vec<Uuid>)> = notifications
        .iter()
        .filter(|notification| matches!(notification.kind, NotificationKind::EventPublished))
        .map(|notification| {
            let template: EventPublished = template_of(notification);
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

    // Check every published copy names the owner and all approved co-hosts
    let expected_group_ids = vec![group_id, gamma_group_id, beta_group_id, alpha_group_id];
    assert!(
        notifications
            .iter()
            .filter(|notification| matches!(notification.kind, NotificationKind::EventPublished))
            .all(|notification| notification.group_ids == expected_group_ids)
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

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(|_| Ok(vec![]));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == cohost_group_id)
        .returning(move |_| Ok(vec![cohost_member_id]));
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 1);

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Check the co-host copy names the co-host group
    let notifications = enqueued(&notifications);
    let notification = find_notification(&notifications, &NotificationKind::EventPublished);
    assert_eq!(notification.recipients, vec![cohost_member_id]);
    let template: EventPublished = template_of(notification);
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

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| {
            Ok(sorted_ids(vec![
                member_id,
                speaker_member_id,
                team_member_id,
            ]))
        });
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 2);

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Check notifications split member and speaker audiences
    let notifications = enqueued(&notifications);
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
    let _: SpeakerWelcome = template_of(speaker_notification);
}

#[tokio::test]
async fn test_enqueue_event_published_notifications_sends_speakers_without_audience() {
    // Setup identifiers and an event whose owner group has no audience
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id]);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(|_| Ok(vec![]));
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 1);

    // Run the workflow
    enqueue_event_published_notifications(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
    )
    .await
    .unwrap();

    // Check only the speaker welcome was enqueued
    let notifications = enqueued(&notifications);
    assert!(matches!(
        notifications[0].kind,
        NotificationKind::SpeakerWelcome
    ));
    assert_eq!(notifications[0].recipients, vec![speaker_id]);
}

#[tokio::test]
async fn test_enqueue_event_rescheduled_notification_skips_past_events() {
    // Setup an event that already ended
    let starts_at = Utc::now() - Duration::hours(3);
    let before = EventSummary {
        ends_at: Some(starts_at + Duration::hours(1)),
        starts_at: Some(starts_at),
        ..sample_event_summary(Uuid::new_v4())
    };

    // Setup database mock forbidding every read
    let mut db = MockDB::new();
    db.expect_get_event_summary().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        Uuid::new_v4(),
        Uuid::new_v4(),
        before.event_id,
        &before,
        Utc::now(),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_rescheduled_notification_skips_small_shift() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let before = sample_future_event_summary(event_id);
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
    db.expect_get_event_full().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
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
    let before = sample_future_event_summary(event_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|starts_at| starts_at + Duration::minutes(30)),
        ..before.clone()
    };
    let event = sample_event_full_with_speakers(community_id, event_id, group_id, &[speaker_id]);

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
    expect_site_settings(&mut db);
    let notifications = capture_enqueued(&mut db, 1);

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        community_id,
        group_id,
        event_id,
        &before,
        Utc::now(),
    )
    .await
    .unwrap();

    // Check notification matches recipient selection
    let notifications = enqueued(&notifications);
    assert_eq!(notifications.len(), 1);
    let notification = find_notification(&notifications, &NotificationKind::EventRescheduled);
    assert_eq!(
        sorted_ids(notification.recipients.clone()),
        sorted_ids(vec![attendee_id, speaker_id])
    );
    let template: EventRescheduled = template_of(notification);
    assert_eq!(template.event.event_id, event_id);
}

#[tokio::test]
async fn test_enqueue_event_rescheduled_notification_skips_test_events() {
    // Setup a future test event
    let before = EventSummary {
        test_event: true,
        ..sample_future_event_summary(Uuid::new_v4())
    };

    // Setup database mock forbidding every read
    let mut db = MockDB::new();
    db.expect_get_event_summary().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        Uuid::new_v4(),
        Uuid::new_v4(),
        before.event_id,
        &before,
        Utc::now(),
    )
    .await
    .unwrap();
}

#[tokio::test]
async fn test_enqueue_event_rescheduled_notification_skips_unpublished_events() {
    // Setup identifiers and an unpublished event moved by an hour
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let before = EventSummary {
        published: false,
        ..sample_future_event_summary(event_id)
    };
    let after = EventSummary {
        starts_at: before.starts_at.map(|starts_at| starts_at + Duration::hours(1)),
        ..before.clone()
    };

    // Setup database mock forbidding the notification work
    let mut db = MockDB::new();
    db.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(after.clone()));
    db.expect_get_event_full().never();
    db.expect_enqueue_notification().never();

    // Run the workflow
    enqueue_event_rescheduled_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
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
async fn test_enqueue_inbox_message_received_notification_excludes_author() {
    // Setup the posted message and its conversation
    let recipient_id = Uuid::new_v4();
    let posted = sample_posted_inbox_message();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;
    let author_id = conversation.messages[0].author.as_ref().unwrap().user_id;

    // Setup database expectations
    let mut db = MockDB::new();
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == posted.group_id && *cid == posted.inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    db.expect_list_inbox_recipient_ids()
        .times(1)
        .withf(move |gid| *gid == posted.group_id)
        .returning(move |_| Ok(vec![author_id, recipient_id]));
    expect_site_settings(&mut db);
    db.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::InboxMessageReceived)
                && notification.recipients == vec![recipient_id]
                && notification.attachments.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<InboxMessageReceived>(value.clone()).is_ok_and(|template| {
                        template.body == "When do doors open?"
                            && template.community_display_name == "Test Community"
                            && template.group_name == "Test Group"
                            && template.link
                                == format!(
                                    "/dashboard/group?tab=inbox&conversation_id={}",
                                    posted.inbox_conversation_id
                                )
                            && template.sender_name == "Inbox User"
                            && template.event_name.as_deref() == Some("Test Event")
                    })
                })
        })
        .returning(|_| Ok(()));

    // Run the workflow
    let result = enqueue_inbox_message_received_notification(&db, &posted).await;

    // Check the notification was enqueued
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_enqueue_inbox_message_received_notification_keeps_message_without_recipients() {
    // Setup the posted message and its conversation
    let posted = sample_posted_inbox_message();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;

    // Setup database expectations without recipients to email
    let mut db = MockDB::new();
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    db.expect_list_inbox_recipient_ids()
        .times(1)
        .returning(|_| Ok(vec![]));
    expect_site_settings(&mut db);
    db.expect_enqueue_notification().never();

    // Run the workflow
    let result = enqueue_inbox_message_received_notification(&db, &posted).await;

    // Check the message is kept without an email
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_enqueue_inbox_message_received_notification_propagates_enqueue_failure() {
    // Setup the posted message and its conversation
    let posted = sample_posted_inbox_message();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;

    // Setup database expectations with a failing enqueue
    let mut db = MockDB::new();
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    db.expect_list_inbox_recipient_ids()
        .times(1)
        .returning(|_| Ok(vec![Uuid::new_v4()]));
    expect_site_settings(&mut db);
    db.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("enqueue failed")));

    // Run the workflow
    let result = enqueue_inbox_message_received_notification(&db, &posted).await;

    // Check the failure is propagated
    assert_eq!(result.unwrap_err().to_string(), "enqueue failed");
}

#[tokio::test]
async fn test_enqueue_inbox_message_received_notification_rejects_missing_conversation() {
    // Setup the posted message
    let posted = sample_posted_inbox_message();

    // Setup database expectations without the conversation
    let mut db = MockDB::new();
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(|_, _| Ok(None));
    db.expect_list_inbox_recipient_ids()
        .times(1)
        .returning(|_| Ok(vec![Uuid::new_v4()]));
    expect_site_settings(&mut db);
    db.expect_enqueue_notification().never();

    // Run the workflow
    let result = enqueue_inbox_message_received_notification(&db, &posted).await;

    // Check the missing conversation fails the workflow
    assert_eq!(
        result.unwrap_err().to_string(),
        "inbox conversation not found"
    );
}

#[tokio::test]
async fn test_enqueue_inbox_reply_received_notification_notifies_conversation_user() {
    // Setup the posted reply and its conversation
    let posted = sample_posted_inbox_message();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    let user_id = conversation.user.as_ref().unwrap().user_id;
    conversation.messages.push(InboxMessage {
        body: "Doors open at 6pm.".to_string(),
        created_at: conversation.created_at,
        inbox_message_id: posted.inbox_message_id,
        kind: InboxMessageKind::GroupReply,

        author: Some(sample_template_user()),
    });

    // Setup database expectations
    let mut db = MockDB::new();
    db.expect_get_group_inbox_conversation()
        .times(1)
        .withf(move |gid, cid| *gid == posted.group_id && *cid == posted.inbox_conversation_id)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    expect_site_settings(&mut db);
    db.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::InboxReplyReceived)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<InboxReplyReceived>(value.clone()).is_ok_and(|template| {
                        template.body == "Doors open at 6pm."
                            && template.group_name == "Test Group"
                            && template.link
                                == format!(
                                    "/dashboard/user?tab=inbox&conversation_id={}",
                                    posted.inbox_conversation_id
                                )
                            && template.event_name.as_deref() == Some("Test Event")
                    })
                })
        })
        .returning(|_| Ok(()));

    // Run the workflow
    let result = enqueue_inbox_reply_received_notification(&db, &posted).await;

    // Check the notification was enqueued
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_enqueue_inbox_reply_received_notification_rejects_deleted_user() {
    // Setup the posted reply to a conversation whose user was deleted
    let posted = sample_posted_inbox_message();
    let mut conversation = sample_inbox_conversation(posted.inbox_conversation_id);
    conversation.messages[0].inbox_message_id = posted.inbox_message_id;
    conversation.user = None;

    // Setup database expectations
    let mut db = MockDB::new();
    db.expect_get_group_inbox_conversation()
        .times(1)
        .returning(move |_, _| Ok(Some(conversation.clone())));
    expect_site_settings(&mut db);
    db.expect_enqueue_notification().never();

    // Run the workflow
    let result = enqueue_inbox_reply_received_notification(&db, &posted).await;

    // Check the missing recipient fails the workflow
    assert_eq!(
        result.unwrap_err().to_string(),
        "inbox conversation user not found"
    );
}

#[tokio::test]
async fn test_enqueue_tracked_community_custom_notification_builds_content_and_enqueues() {
    // Setup identifiers and input
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_category_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let region_id = Uuid::new_v4();
    let community = sample_community_summary(community_id);
    let expected_template_data = serde_json::to_value(build_community_custom_notification(
        &community,
        &sample_custom_notification_content("Community Update", "Hello, group teams!"),
        &sample_server_cfg("https://example.test/"),
        &sample_site_settings(),
    ))
    .unwrap();
    let input = CommunityCustomNotificationInput {
        actor_user_id,
        community_id,
        content: sample_custom_notification_content("Community Update", "Hello, group teams!"),
        filters: CommunityContactFilters {
            group_category_ids: vec![group_category_id],
            group_ids: vec![group_id],
            regions: vec![
                RegionFilterValue::NoRegion,
                RegionFilterValue::Region(region_id),
            ],
            roles: vec![GroupRole::Admin],
        },
    };

    // Setup database expectations
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(community.clone()));
    expect_site_settings(&mut db);
    db.expect_enqueue_tracked_community_custom_notification()
        .times(1)
        .withf(move |input| {
            input.body == "Hello, group teams!"
                && input.community_id == community_id
                && input.created_by == actor_user_id
                && input.filters.group_category_ids == vec![group_category_id]
                && input.filters.group_ids == vec![group_id]
                && input.filters.regions
                    == vec![
                        RegionFilterValue::NoRegion,
                        RegionFilterValue::Region(region_id),
                    ]
                && input.filters.roles == vec![GroupRole::Admin]
                && input.subject == "Community Update"
                && input.template_data == expected_template_data
        })
        .returning(|_| Ok(3));

    // Run the workflow
    let count = enqueue_tracked_community_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await
    .unwrap();

    // Check the recipient count reported by the database
    assert_eq!(count, 3);
}

#[tokio::test]
async fn test_enqueue_tracked_community_custom_notification_propagates_context_failure() {
    // Setup input
    let input = sample_community_custom_notification_input();

    // Setup database expectations with a failing context load
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .returning(|_| Err(anyhow!("database unavailable")));
    db.expect_get_site_settings()
        .times(0..=1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_enqueue_tracked_community_custom_notification().never();

    // Run the workflow
    let result = enqueue_tracked_community_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await;

    // Check the failure propagates before anything is enqueued
    assert_eq!(result.unwrap_err().to_string(), "database unavailable");
}

#[tokio::test]
async fn test_enqueue_tracked_community_custom_notification_propagates_enqueue_failure() {
    // Setup input
    let input = sample_community_custom_notification_input();
    let community_id = input.community_id;

    // Setup database expectations with a rejected enqueue
    let mut db = MockDB::new();
    db.expect_get_community_summary()
        .times(1)
        .returning(move |_| Ok(sample_community_summary(community_id)));
    expect_site_settings(&mut db);
    db.expect_enqueue_tracked_community_custom_notification()
        .times(1)
        .returning(|_| Err(anyhow!("no group team members match the selected filters")));

    // Run the workflow
    let result = enqueue_tracked_community_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await;

    // Check the database error passes through unchanged
    assert_eq!(
        result.unwrap_err().to_string(),
        "no group team members match the selected filters"
    );
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
    let event = sample_event_summary(event_id);
    let expected_template_data = serde_json::to_value(build_event_custom_notification(
        &event,
        &sample_custom_notification_content("Event Update", "Hello, event attendees!"),
        &sample_server_cfg("https://example.test/"),
        &sample_site_settings(),
    ))
    .unwrap();
    let input = EventCustomNotificationInput {
        actor_user_id,
        community_id,
        content: sample_custom_notification_content("Event Update", "Hello, event attendees!"),
        event_id,
        group_id,
        recipients: vec![attendee_id1, attendee_id2],
    };

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    expect_site_settings(&mut db);
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            matches!(notification.kind, NotificationKind::EventCustom)
                && notification.attachments.is_empty()
                && notification.recipients == vec![attendee_id1, attendee_id2]
                && notification.group_ids == vec![group_id]
                && notification.template_data.as_ref() == Some(&expected_template_data)
                && tracking.body == "Hello, event attendees!"
                && tracking.created_by == actor_user_id
                && matches!(
                    tracking.scope,
                    CustomNotificationScope::Event {
                        community_id: cid,
                        event_id: eid,
                        group_id: gid,
                    } if cid == community_id && eid == event_id && gid == group_id
                )
                && tracking.subject == "Event Update"
        })
        .returning(|_, _| Ok(()));

    // Run the workflow
    enqueue_tracked_event_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
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
        community_id,
        content: sample_custom_notification_content("Subject", "Hello"),
        event_id,
        group_id: Uuid::new_v4(),
        recipients: vec![Uuid::new_v4()],
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
    let result = enqueue_tracked_event_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await;

    // Check the failure propagates
    assert_eq!(result.unwrap_err().to_string(), "database unavailable");
}

#[tokio::test]
async fn test_enqueue_tracked_group_custom_notification_builds_content_and_tracking() {
    // Setup identifiers and data structures
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let member_and_team_id = Uuid::new_v4();
    let team_member_id = Uuid::new_v4();
    let audience_ids = sorted_ids(vec![member_id, member_and_team_id, team_member_id]);
    let expected_recipients = audience_ids.clone();
    let mut group = sample_group_summary(group_id);
    group.slug_pretty = Some("pretty-group".to_string());
    let expected_template_data = serde_json::to_value(build_group_custom_notification(
        &group,
        &sample_custom_notification_content("Important Update", "Hello, group members!"),
        &sample_server_cfg("https://example.test/"),
        &sample_site_settings(),
    ))
    .unwrap();
    let input = GroupCustomNotificationInput {
        actor_user_id,
        community_id,
        content: sample_custom_notification_content("Important Update", "Hello, group members!"),
        group_id,
    };

    // Setup the audience expectation, already deduplicated by the database
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(audience_ids.clone()));

    // Setup context and enqueue expectations
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));
    expect_site_settings(&mut db);
    db.expect_enqueue_tracked_custom_notification()
        .times(1)
        .withf(move |notification, tracking| {
            matches!(notification.kind, NotificationKind::GroupCustom)
                && notification.attachments.is_empty()
                && notification.recipients == expected_recipients
                && notification.group_ids == vec![group_id]
                && notification.template_data.as_ref() == Some(&expected_template_data)
                && tracking.body == "Hello, group members!"
                && tracking.created_by == actor_user_id
                && matches!(
                    tracking.scope,
                    CustomNotificationScope::Group {
                        community_id: cid,
                        group_id: gid,
                    } if cid == community_id && gid == group_id
                )
                && tracking.subject == "Important Update"
        })
        .returning(|_, _| Ok(()));

    // Run the workflow
    let outcome = enqueue_tracked_group_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await
    .unwrap();

    // Check the whole audience was notified
    assert_eq!(outcome, GroupCustomNotificationOutcome::Sent(3));
}

#[tokio::test]
async fn test_enqueue_tracked_group_custom_notification_propagates_context_failure() {
    // Setup input
    let input = GroupCustomNotificationInput {
        actor_user_id: Uuid::new_v4(),
        community_id: Uuid::new_v4(),
        content: sample_custom_notification_content("Subject", "Hello"),
        group_id: Uuid::new_v4(),
    };

    // Setup database mock with a failing context load
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids()
        .times(1)
        .returning(|_| Ok(vec![Uuid::new_v4()]));
    db.expect_get_site_settings()
        .times(0..=1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_summary()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));
    db.expect_enqueue_tracked_custom_notification().never();

    // Run the workflow
    let result = enqueue_tracked_group_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await;

    // Check the failure propagates
    assert_eq!(result.unwrap_err().to_string(), "database unavailable");
}

#[tokio::test]
async fn test_enqueue_tracked_group_custom_notification_returns_no_recipients() {
    // Setup input
    let input = GroupCustomNotificationInput {
        actor_user_id: Uuid::new_v4(),
        community_id: Uuid::new_v4(),
        content: sample_custom_notification_content("Subject", "Hello"),
        group_id: Uuid::new_v4(),
    };

    // Setup database expectations with an empty audience
    let mut db = MockDB::new();
    db.expect_list_group_audience_ids().times(1).returning(|_| Ok(vec![]));
    db.expect_get_group_summary().never();
    db.expect_enqueue_tracked_custom_notification().never();

    // Run the workflow
    let outcome = enqueue_tracked_group_custom_notification(
        &db,
        &sample_server_cfg("https://example.test/"),
        &input,
    )
    .await
    .unwrap();

    // Check nothing was enqueued
    assert_eq!(outcome, GroupCustomNotificationOutcome::NoRecipients);
}

// Types.

/// Co-host name, recipients, event ids, and group ids of one series bundle.
type SeriesBundle = (Option<String>, Vec<Uuid>, Vec<Uuid>, Vec<Uuid>);

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

/// Captures every enqueued notification, expecting exactly `times` enqueues.
fn capture_enqueued(db: &mut MockDB, times: usize) -> Arc<Mutex<Vec<NewNotification>>> {
    let notifications = Arc::new(Mutex::new(Vec::new()));
    let notifications_for_mock = notifications.clone();
    db.expect_enqueue_notification()
        .times(times)
        .returning(move |notification| {
            notifications_for_mock
                .lock()
                .expect("notifications lock not to be poisoned")
                .push(notification.clone());
            Ok(())
        });
    notifications
}

/// Returns the notifications captured by `capture_enqueued`.
fn enqueued(notifications: &Arc<Mutex<Vec<NewNotification>>>) -> Vec<NewNotification> {
    notifications
        .lock()
        .expect("notifications lock not to be poisoned")
        .clone()
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

/// Returns a community custom notification input without filters.
fn sample_community_custom_notification_input() -> CommunityCustomNotificationInput {
    CommunityCustomNotificationInput {
        actor_user_id: Uuid::new_v4(),
        community_id: Uuid::new_v4(),
        content: sample_custom_notification_content("Subject", "Hello"),
        filters: CommunityContactFilters::default(),
    }
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
fn sample_future_event_summary(event_id: Uuid) -> EventSummary {
    let starts_at = Utc::now() + Duration::hours(1);
    EventSummary {
        ends_at: Some(starts_at + Duration::hours(1)),
        starts_at: Some(starts_at),
        ..sample_event_summary(event_id)
    }
}

/// Sorts identifiers for order-independent assertions.
fn sorted_ids(mut ids: Vec<Uuid>) -> Vec<Uuid> {
    ids.sort();
    ids
}
