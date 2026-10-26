//! Contract tests for the `DBNotifications` functions.

use std::collections::HashMap;

use anyhow::{Context, Result};
use chrono::{NaiveDate, Utc};
use uuid::Uuid;

use crate::{
    db::{
        DBUnitOfWork, PgExecutor, PgUnitOfWork,
        dashboard::group::DBDashboardGroup,
        notifications::{
            CommunityCustomNotificationEnqueue, CustomNotificationScope,
            CustomNotificationTracking, DBNotifications,
        },
    },
    types::{
        dashboard::{
            community::contact::CommunityContactFilters,
            group::{
                events::EventInput,
                surveys::{EventSurveyStatusAction, EventSurveyStatusForm},
            },
        },
        event::EventSummary,
        notifications::{NewNotification, NotificationKind},
    },
};

use super::helpers::*;

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_claim_pending_notification_deserializes() -> Result<()> {
    // Setup a rolled-back unit of work
    let uow = contract_unit_of_work().await?;

    // Claim the seeded notification through the production wrapper
    let claim_started_at = Utc::now();
    let notification = uow
        .claim_pending_notification()
        .await?
        .context("pending contract notification should be claimable")?;
    let claim_finished_at = Utc::now();

    // Check the complete delivery contract and claim identity were decoded
    assert!(notification.attachments.is_empty());
    let clock_tolerance = chrono::Duration::seconds(1);
    assert!(notification.delivery_claimed_at >= claim_started_at - clock_tolerance);
    assert!(notification.delivery_claimed_at <= claim_finished_at + clock_tolerance);
    assert_eq!(notification.email, "organizer.contract@example.com");
    assert_eq!(notification.kind.to_string(), "event-welcome");
    assert_eq!(notification.notification_id, notification_id());
    assert!(notification.template_data.is_none());

    // Finalize through the production wrapper to verify the claim identity round trip
    uow.update_notification(&notification, None).await?;

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_due_event_survey_notifications_enqueues_opening_emails() -> Result<()>
{
    // Setup a rolled-back unit of work where the survey email event is not a
    // test event and one of its surveys has no closing date
    let uow = contract_unit_of_work().await?;
    uow.execute(
        "update event set test_event = false where event_id = $1::uuid",
        &[&survey_email_event_id()],
    )
    .await?;
    uow.execute(
        "update event_survey set closes_at = null where event_survey_id = $1::uuid",
        &[&survey_email_close_race_id()],
    )
    .await?;

    // Run the survey opening email job
    let count = uow.enqueue_due_event_survey_notifications().await?;

    // Check the count matches the enqueued notifications
    let enqueued: i64 = uow
        .fetch_scalar_one(
            "select count(*) from notification
            where kind = 'event-survey-opened'
            and created_at = current_timestamp",
            &[],
        )
        .await?;
    assert_eq!(count, usize::try_from(enqueued)?);

    // Check both template payloads carry a decodable event and the closing
    // date only when the survey has one
    let dated = survey_opened_template_data(&uow, "Contract email survey").await?;
    let event: EventSummary = serde_json::from_value(dated["event"].clone())?;
    assert_eq!(event.event_id, survey_email_event_id());
    assert_eq!(
        dated.get("closes_at").and_then(serde_json::Value::as_i64),
        Some(4_070_908_800)
    );
    let open_ended = survey_opened_template_data(&uow, "Contract email close race survey").await?;
    let event: EventSummary = serde_json::from_value(open_ended["event"].clone())?;
    assert_eq!(event.event_id, survey_email_event_id());
    assert!(open_ended.get("closes_at").is_none());

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_due_event_survey_notifications_rechecks_event_rescheduled_concurrently()
-> Result<()> {
    // Setup reschedule and job connections, and an earlier past schedule
    let reschedule_uow = contract_unit_of_work().await?;
    let job_uow = contract_unit_of_work().await?;
    let payload = EventInput {
        ends_at: NaiveDate::from_ymd_opt(2025, 3, 31).and_then(|day| day.and_hms_opt(19, 0, 0)),
        starts_at: NaiveDate::from_ymd_opt(2025, 3, 31).and_then(|day| day.and_hms_opt(17, 0, 0)),
        ..contract_event_input("Contract Survey Reschedule Event", 1)
    }
    .to_db_payload()?;

    // Reschedule the event while retaining its lock
    reschedule_uow
        .update_event(
            organizer_id(),
            subgroup_id(),
            survey_reschedule_event_id(),
            &payload,
            &HashMap::new(),
            None,
        )
        .await?;

    // Check the job skips the survey of the locked event without waiting
    job_uow.enqueue_due_event_survey_notifications().await?;
    assert_eq!(
        survey_open_notification_recipients(&job_uow, survey_email_reschedule_race_id()).await?,
        None
    );
    Box::new(job_uow).rollback().await?;

    // Commit the reschedule and run the job again on a non-test event
    Box::new(reschedule_uow).commit().await?;
    let rerun_uow = contract_unit_of_work().await?;
    rerun_uow
        .execute(
            "update event set test_event = false where event_id = $1::uuid",
            &[&survey_reschedule_event_id()],
        )
        .await?;
    rerun_uow.enqueue_due_event_survey_notifications().await?;

    // Check the survey is handled once the rescheduled event is released
    assert_eq!(
        survey_open_notification_recipients(&rerun_uow, survey_email_reschedule_race_id()).await?,
        Some(1)
    );

    // Check the email carries the rescheduled start
    let email_starts_at: i64 = rerun_uow
        .fetch_scalar_one(
            "select (ntd.data->'event'->>'starts_at')::bigint
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.kind = 'event-survey-opened'
            and ntd.data->>'survey_title' = 'Contract email reschedule race survey'",
            &[],
        )
        .await?;
    let stored_starts_at: i64 = rerun_uow
        .fetch_scalar_one(
            "select extract(epoch from starts_at)::bigint from event where event_id = $1::uuid",
            &[&survey_reschedule_event_id()],
        )
        .await?;
    assert_eq!(email_starts_at, stored_starts_at);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_due_event_survey_notifications_skips_concurrent_run() -> Result<()> {
    // Setup two job connections
    let first_uow = contract_unit_of_work().await?;
    let second_uow = contract_unit_of_work().await?;

    // Run the job while retaining its advisory lock
    first_uow.enqueue_due_event_survey_notifications().await?;
    assert_eq!(
        survey_open_notification_recipients(&first_uow, survey_identified_id()).await?,
        Some(0)
    );

    // Check a concurrent run leaves every survey to the first one
    let second_count = second_uow.enqueue_due_event_survey_notifications().await?;
    assert_eq!(second_count, 0);
    assert_eq!(
        survey_open_notification_recipients(&second_uow, survey_identified_id()).await?,
        None
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_due_event_survey_notifications_skips_survey_closed_concurrently()
-> Result<()> {
    // Setup close and job connections
    let close_uow = contract_unit_of_work().await?;
    let job_uow = contract_unit_of_work().await?;

    // Close the survey while retaining the event and survey locks
    close_uow
        .change_event_survey_status(
            organizer_id(),
            subgroup_id(),
            survey_email_event_id(),
            survey_email_close_race_id(),
            &EventSurveyStatusForm {
                action: EventSurveyStatusAction::Close,
                revision: 1,

                expected_effective_opens_at: None,
            },
        )
        .await?;

    // Check the job skips the surveys of the locked event without waiting
    job_uow.enqueue_due_event_survey_notifications().await?;
    assert_eq!(
        survey_open_notification_recipients(&job_uow, survey_email_close_race_id()).await?,
        None
    );
    assert_eq!(
        survey_open_notification_recipients(&job_uow, survey_email_id()).await?,
        None
    );
    Box::new(job_uow).rollback().await?;

    // Commit the close and run the job again
    Box::new(close_uow).commit().await?;
    let rerun_uow = contract_unit_of_work().await?;
    rerun_uow.enqueue_due_event_survey_notifications().await?;

    // Check the closed survey is never handled while its open sibling is
    assert_eq!(
        survey_open_notification_recipients(&rerun_uow, survey_email_close_race_id()).await?,
        None
    );
    assert!(
        survey_open_notification_recipients(&rerun_uow, survey_email_id())
            .await?
            .is_some()
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_notification_filters_all_group_scoped_recipients() -> Result<()> {
    // Setup the contract database and a dedicated muted recipient
    let db = contract_tests_db()?;
    let client = contract_tests_pool()?.get().await?;

    // Enqueue a group-mutable notification where every recipient opted out by group mute
    db.enqueue_notification(&NewNotification {
        attachments: vec![],
        group_ids: vec![subgroup_id()],
        kind: NotificationKind::GroupCustom,
        recipients: vec![notification_preferences_user_id()],

        template_data: Some(serde_json::json!({
            "body": "Muted contract announcement",
            "subject": "Muted contract announcement"
        })),
    })
    .await?;

    // Check the enqueue accepted the request without writing filtered notifications
    let notification_count: i64 = client
        .query_one(
            "select count(*)
            from notification
            where kind = 'group-custom'
            and user_id = $1::uuid",
            &[&notification_preferences_user_id()],
        )
        .await?
        .get(0);
    assert_eq!(notification_count, 0);

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_tracked_community_custom_notification_enqueues_and_tracks()
-> Result<()> {
    // Setup a rolled-back unit of work and filters selecting two groups
    let uow = contract_unit_of_work().await?;
    let subject = "Contract community contact groups";

    // Enqueue the notification for the selected groups only
    let count = uow
        .enqueue_tracked_community_custom_notification(CommunityCustomNotificationEnqueue {
            body: "Hello selected group teams".to_string(),
            community_id: contact_community_id(),
            created_by: contact_manager_id(),
            filters: CommunityContactFilters {
                group_ids: vec![contact_inactive_group_id(), contact_group_b_id()],
                ..Default::default()
            },
            subject: subject.to_string(),
            template_data: serde_json::json!({ "subject": subject }),
        })
        .await?;

    // Check only the team member of the active selected group was notified
    assert_eq!(count, 1);
    let recipients: Vec<Uuid> = uow
        .client()
        .await?
        .query(
            "select n.user_id
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.kind = 'community-custom'
            and ntd.data->>'subject' = $1::text",
            &[&subject],
        )
        .await?
        .iter()
        .map(|row| row.get(0))
        .collect();
    assert_eq!(recipients, vec![contact_admin_id()]);

    // Check the custom notification is tracked against the community
    let tracked_community_id: Option<Uuid> = uow
        .fetch_scalar_one(
            "select community_id from custom_notification where subject = $1::text",
            &[&subject],
        )
        .await?;
    assert_eq!(tracked_community_id, Some(contact_community_id()));

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_enqueue_tracked_custom_notification_tracks_group_scope() -> Result<()> {
    // Setup a rolled-back unit of work
    let uow = contract_unit_of_work().await?;
    let subject = "Contract group scope";

    // Enqueue a group notification through the production wrapper
    uow.enqueue_tracked_custom_notification(
        &NewNotification {
            attachments: vec![],
            group_ids: vec![contact_group_a_id()],
            kind: NotificationKind::GroupCustom,
            recipients: vec![contact_manager_id()],

            template_data: Some(serde_json::json!({ "subject": subject })),
        },
        CustomNotificationTracking {
            body: "Hello group".to_string(),
            created_by: contact_admin_id(),
            scope: CustomNotificationScope::Group {
                community_id: contact_community_id(),
                group_id: contact_group_a_id(),
            },
            subject: subject.to_string(),
        },
    )
    .await?;

    // Check the custom notification is tracked against the group only
    let tracked = uow
        .client()
        .await?
        .query_one(
            "select community_id, event_id, group_id
            from custom_notification
            where subject = $1::text",
            &[&subject],
        )
        .await?;
    assert_eq!(tracked.get::<_, Option<Uuid>>("community_id"), None);
    assert_eq!(tracked.get::<_, Option<Uuid>>("event_id"), None);
    assert_eq!(
        tracked.get::<_, Option<Uuid>>("group_id"),
        Some(contact_group_a_id())
    );

    // Check the audit row carries the community of the group and the recipient count
    let audit = uow
        .client()
        .await?
        .query_one(
            "select community_id, group_id, details->>'recipient_count' as recipient_count
            from audit_log
            where action = 'group_custom_notification_sent'
            and details->>'subject' = $1::text",
            &[&subject],
        )
        .await?;
    assert_eq!(
        audit.get::<_, Option<Uuid>>("community_id"),
        Some(contact_community_id())
    );
    assert_eq!(
        audit.get::<_, Option<Uuid>>("group_id"),
        Some(contact_group_a_id())
    );
    assert_eq!(
        audit.get::<_, Option<String>>("recipient_count").as_deref(),
        Some("1")
    );

    Ok(())
}

#[tokio::test]
#[ignore = "requires the contract test database"]
async fn db_contracts_filter_notification_recipient_ids_preserves_eligible_order() -> Result<()> {
    // Setup the contract database and ordered recipient candidates
    let db = contract_tests_db()?;
    let recipients = vec![
        notification_preferences_user_id(),
        notification_eligible_user_id(),
        organizer_id(),
    ];

    // Filter group-scoped recipients through the production wrapper
    let filtered = db
        .filter_notification_recipient_ids(
            &NotificationKind::GroupCustom,
            &recipients,
            &[subgroup_id()],
        )
        .await?;

    // Check muted recipients are removed without reordering the eligible users
    assert_eq!(
        filtered,
        vec![notification_eligible_user_id(), organizer_id()]
    );

    Ok(())
}

// Helpers.

/// Returns the template data of the survey opening email sent for the given
/// survey title.
async fn survey_opened_template_data(
    uow: &PgUnitOfWork,
    survey_title: &str,
) -> Result<serde_json::Value> {
    uow.fetch_scalar_one(
        "select ntd.data
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.kind = 'event-survey-opened'
            and ntd.data->>'survey_title' = $1::text",
        &[&survey_title],
    )
    .await
}

/// Returns the opening email recipients a survey recorded, when it was handled.
async fn survey_open_notification_recipients(
    uow: &PgUnitOfWork,
    event_survey_id: Uuid,
) -> Result<Option<i32>> {
    uow.fetch_scalar_opt(
        "select open_notification_recipients
        from event_survey
        where event_survey_id = $1::uuid
        and open_notification_processed_at is not null",
        &[&event_survey_id],
    )
    .await
}
