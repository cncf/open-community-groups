use std::sync::Arc;

use anyhow::anyhow;
use chrono::Utc;
use mockall::Sequence;
use serde_json::{from_value, json};
use uuid::Uuid;

use crate::{
    config::{HttpClientConfig, HttpServerConfig, MeetingsConfig, MeetingsZoomConfig},
    db::mock::MockDB,
    services::{
        events::{
            AddEventInput, AutomaticTaxCheckError, EventActionInput, EventsError, EventsManager,
            UpdateEventInput,
        },
        payments::{
            AutomaticTaxReadiness, AutomaticTaxReadinessError, FiscalSponsorReadinessError,
            MockPaymentsManager,
        },
    },
    templates::notifications::{
        EventCanceled, EventPaidConfigured, EventPublished, EventRescheduled, EventSeriesCanceled,
        EventSeriesPublished, SpeakerWelcome,
    },
    types::{
        dashboard::group::events::{EventActionScope, EventInput, EventRecurrencePattern},
        event::{EventFull, EventSummary, Speaker},
        meetings::MeetingProvider,
        notifications::NotificationKind,
        payments::{
            EventTicketPriceWindow, EventTicketType, PaymentProvider, TicketTaxBehavior,
            TicketTaxCalculationMode, TicketTaxRate,
        },
        tests::{
            sample_event_form, sample_event_full, sample_event_summary,
            sample_group_payment_recipient, sample_paid_event_body, sample_site_settings,
            sample_template_user_with_id,
        },
    },
};

use super::{PgEventsManager, is_event_payload_paid_capable};

#[tokio::test]
async fn test_add_free_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(
            move |uid, id, event, cfg_max_participants, payment_provider| {
                let event_name = event
                    .get("name")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_default();
                *uid == user_id
                    && *id == group_id
                    && event_name == event_form.name
                    && cfg_max_participants.get(&MeetingProvider::Zoom) == Some(&100)
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _| Ok(event_id));
    expect_successful_transaction(&mut db, tx);

    // Setup meetings config with Zoom
    let meetings_cfg = sample_zoom_meetings_cfg();

    // Run the workflow through the manager
    let manager = sample_manager(db, Some(&meetings_cfg), sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the created event identifiers
    assert_eq!(result.unwrap()[0], event_id);
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_paid_event_notification_failure_rolls_back() {
    // Setup identifiers and paid event input
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let body = sample_paid_event_body();
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup authentication and permission checks
    let mut db = MockDB::new();

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup a successful mutation followed by a required notification failure
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(move |uid, gid, _, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(move |_, _, _, _, _| Ok(event_id));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("notification error")));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        None,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the internal failure propagates
    assert!(
        matches!(result.unwrap_err(), EventsError::Other(err) if err.to_string() == "notification error")
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_paid_recurring_success() {
    // Setup identifiers and recurring paid event input
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let third_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event_form = sample_event_form();
    event_form.ends_at = Some((Utc::now() + chrono::Duration::days(8)).naive_utc());
    event_form.recurrence_additional_occurrences = Some(2);
    event_form.recurrence_pattern = Some(EventRecurrencePattern::Weekly);
    event_form.starts_at = Some((Utc::now() + chrono::Duration::days(7)).naive_utc());
    let body = format!(
        concat!(
            "{}",
            "&payment_currency_code=USD",
            "&ticket_types_present=true",
            "&ticket_types[0][active]=true",
            "&ticket_types[0][order]=1",
            "&ticket_types[0][price_windows][0][amount_minor]=1500",
            "&ticket_types[0][seats_total]=25",
            "&ticket_types[0][title]=General%20admission"
        ),
        serde_qs::to_string(&event_form).unwrap(),
    );

    // Setup authentication and permission checks
    let mut db = MockDB::new();

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup atomic recurring creation and aggregate notification expectations
    let mut tx = MockDB::new();
    tx.expect_add_event().never();
    let returned_event_ids = vec![event_id, related_event_id, third_event_id];
    tx.expect_add_event_series()
        .times(1)
        .withf(move |uid, gid, events, _, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && events.len() == 3
                && events.iter().all(|event| {
                    event["ticket_types"][0]["price_windows"][0]["amount_minor"].as_i64()
                        == Some(1500)
                })
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(move |_, _, _, _, _, _| Ok(returned_event_ids.clone()));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    let event_summary = sample_event_summary(event_id, group_id);
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    let related_event_summary = sample_event_summary(related_event_id, group_id);
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    let third_event_summary = sample_event_summary(third_event_id, group_id);
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == third_event_id
        })
        .returning(move |_, _, _| Ok(third_event_summary.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    let expected_event_ids = vec![event_id, related_event_id, third_event_id];
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPaidConfigured)
                && notification.recipients == vec![admin_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPaidConfigured>(value.clone()).is_ok_and(|template| {
                        template.events.iter().map(|event| event.event_id).collect::<Vec<_>>()
                            == expected_event_ids
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        None,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the created event identifiers
    assert_eq!(result.unwrap()[0], event_id);
}

#[tokio::test]
async fn test_add_paid_rejects_unready_fiscal_sponsor_without_persisting() {
    // Setup an authenticated automatic-tax paid event request
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let body = format!(
        "{}&venue_address=123%20Main%20St&venue_city=San%20Francisco&venue_country_code=us&venue_name=Main%20Venue&venue_state_code=ca&venue_zip_code=94105",
        sample_paid_event_body().replace("kind_id=virtual", "kind_id=in-person")
    );

    // Authorize the request and return its configured sponsor
    let mut db = MockDB::new();
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Reject the sponsor before the event transaction can start
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_validate_fiscal_sponsor()
        .withf(|recipient, automatic_tax_jurisdiction| {
            recipient.provider == PaymentProvider::Stripe
                && recipient.recipient_id == "acct_test"
                && automatic_tax_jurisdiction.as_ref().is_some_and(|jurisdiction| {
                    jurisdiction.country_code == "US"
                        && jurisdiction.state_code.as_deref() == Some("CA")
                })
        })
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Err(FiscalSponsorReadinessError::NotReady(
                    "Stripe Tax is not active".to_string(),
                ))
            })
        });

    // Run the workflow through the manager
    let manager = sample_manager(db, None, payments_manager);
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the rejection message
    assert!(matches!(result.unwrap_err(), EventsError::Rejected(_)));
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_add_paid_success() {
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let body = sample_paid_event_body();
    let event_summary = sample_event_summary(event_id, group_id);

    // Setup authentication and permission checks
    let mut db = MockDB::new();

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup atomic creation and notification expectations
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(move |uid, gid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && event
                    .get("ticket_types")
                    .and_then(serde_json::Value::as_array)
                    .is_some_and(|ticket_types| !ticket_types.is_empty())
                && event.get("_payment_validation").is_some_and(|validation| {
                    validation["require_automatic_tax"] == true
                        && validation["expected_payment_recipient"]["recipient_id"] == "acct_test"
                        && validation["validated_payment_recipient"]["recipient_id"] == "acct_test"
                })
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(move |_, _, _, _, _| Ok(event_id));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPaidConfigured)
                && notification.recipients == vec![admin_id]
                && notification.attachments.is_empty()
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPaidConfigured>(value.clone()).is_ok_and(|template| {
                        template.event_count == 1 && template.events[0].event_id == event_id
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        None,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the created event identifiers
    assert_eq!(result.unwrap()[0], event_id);
}

#[tokio::test]
async fn test_add_recurring_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let third_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event_form = sample_event_form();
    event_form.ends_at = Some((Utc::now() + chrono::Duration::days(8)).naive_utc());
    event_form.recurrence_additional_occurrences = Some(2);
    event_form.recurrence_pattern = Some(EventRecurrencePattern::Weekly);
    event_form.starts_at = Some((Utc::now() + chrono::Duration::days(7)).naive_utc());
    let event_name = event_form.name.clone();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_add_event().never();
    tx.expect_add_event_series()
        .times(1)
        .withf(
            move |uid, id, events, recurrence, cfg_max_participants, payment_provider| {
                let names_match = events.iter().all(|event| {
                    event
                        .get("name")
                        .and_then(serde_json::Value::as_str)
                        .is_some_and(|name| name == event_name)
                });

                *uid == user_id
                    && *id == group_id
                    && events.len() == 3
                    && names_match
                    && recurrence
                        .get("additional_occurrences")
                        .and_then(serde_json::Value::as_i64)
                        == Some(2)
                    && recurrence.get("pattern").and_then(serde_json::Value::as_str)
                        == Some("weekly")
                    && cfg_max_participants.get(&MeetingProvider::Zoom) == Some(&100)
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(vec![event_id, related_event_id, third_event_id]));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        Some(&sample_zoom_meetings_cfg()),
        sample_payments_manager(None),
    );
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the created event identifiers
    assert_eq!(result.unwrap()[0], event_id);
}

#[tokio::test]
async fn test_add_validation_rejects_paid_event_without_payments() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let body = sample_paid_event_body();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_group_payment_recipient().times(0);

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_add_event()
        .times(1)
        .withf(move |uid, gid, _, _, payment_provider| {
            *uid == user_id && *gid == group_id && payment_provider.is_none()
        })
        .returning(|_, _, _, _, _| Err(anyhow!("payments are not configured on this server")));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .add(&AddEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            group_id,
        })
        .await;

    // Check the database rejection propagates unchanged for SQLSTATE classification
    assert!(matches!(
        result.unwrap_err(),
        EventsError::Other(err) if err.to_string() == "payments are not configured on this server"
    ));
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_cancel_series_sends_aggregate_notification() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event_summary = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: true,
        ..sample_event_summary(related_event_id, group_id)
    };
    let event_full = EventFull {
        event_id,
        name: "First Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let related_event_full = EventFull {
        event_id: related_event_id,
        name: "Second Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, related_event_id, group_id)
    };
    let series_event_ids = vec![event_id, related_event_id];
    let expected_lock_event_ids = series_event_ids.clone();
    let expected_series_event_ids = series_event_ids.clone();
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();

    // Setup database mock
    let mut db = MockDB::new();
    let mut sequence = Sequence::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_list_event_series_cancelable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| {
            *gid == group_id && event_ids == expected_lock_event_ids.as_slice()
        })
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_cancel_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(2)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && (*eid == event_id || *eid == related_event_id) && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id]));
    tx.expect_list_event_waitlist_ids()
        .times(2)
        .withf(move |gid, eid| *gid == group_id && (*eid == event_id || *eid == related_event_id))
        .returning(move |_, _| Ok(vec![]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventSeriesCanceled)
                && notification.attachments.is_empty()
                && notification.recipients == vec![attendee_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventSeriesCanceled>(value.clone()).is_ok_and(|template| {
                        template.event_count == 2
                            && template.events.len() == 2
                            && template.theme.primary_color
                                == site_settings_for_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .cancel(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::Series,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_cancel_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let series_event_ids = vec![event_id, related_event_id];
    let expected_lock_event_ids = series_event_ids.clone();
    let expected_series_event_ids = series_event_ids.clone();
    let event_summary = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: false,
        ..sample_event_summary(related_event_id, group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    let mut sequence = Sequence::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_list_event_series_cancelable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| {
            *gid == group_id && event_ids == expected_lock_event_ids.as_slice()
        })
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_cancel_event().times(0);
    tx.expect_cancel_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .cancel(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::Series,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_cancel_success() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event_summary = sample_event_summary(event_id, group_id);
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_notifications = site_settings.clone();

    // Setup database mock
    let mut db = MockDB::new();
    let mut sequence = Sequence::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_cancel_event()
        .times(1)
        .withf(move |uid, id, eid| *uid == user_id && *id == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id]));
    tx.expect_list_event_waitlist_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(vec![]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventCanceled)
                && notification.recipients.len() == 2
                && notification.recipients.contains(&attendee_id)
                && notification.recipients.contains(&speaker_id)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventCanceled>(value.clone()).is_ok_and(|template| {
                        template.link == "/test/group/npq6789/event/abc1234"
                            && template.theme.primary_color
                                == site_settings_for_notifications.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .cancel(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_cancel_test_event_no_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let test_event = EventSummary {
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    let mut sequence = Sequence::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_events_for_cancellation()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(test_event.clone()));
    tx.expect_cancel_event()
        .times(1)
        .withf(move |uid, id, eid| *uid == user_id && *id == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .cancel(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_check_automatic_tax_readiness_rejects_missing_fiscal_sponsor() {
    // Setup a persisted event without a configured sponsor
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_get_group_payment_recipient()
        .times(1)
        .returning(|_, _| Ok(None));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Check the readiness
    let manager = sample_manager(db, None, payments_manager);
    let error = manager
        .check_automatic_tax_readiness(community_id, group_id, event_id)
        .await
        .unwrap_err();

    // Check the sponsor requirement is reported as correctable
    assert!(matches!(
        error,
        AutomaticTaxCheckError::Readiness(AutomaticTaxReadinessError::FiscalSponsorNotReady(message))
            if message == "configure a fiscal sponsor before checking automatic tax"
    ));
}

#[tokio::test]
async fn test_check_automatic_tax_readiness_keeps_context_failures_distinct() {
    // Setup a context load that fails before any provider call
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("database unavailable")));
    db.expect_get_group_payment_recipient()
        .times(..=1)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Check the readiness
    let manager = sample_manager(db, None, payments_manager);
    let error = manager
        .check_automatic_tax_readiness(community_id, group_id, event_id)
        .await
        .unwrap_err();

    // Check the failure is not classified as a provider readiness outcome
    assert!(matches!(
        error,
        AutomaticTaxCheckError::Other(err) if err.to_string() == "database unavailable"
    ));
}

#[tokio::test]
async fn test_check_automatic_tax_readiness_uses_persisted_venue() {
    // Setup a persisted venue and its configured sponsor
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.venue_address = Some("1 Main St".to_string());
    event.venue_city = Some("Málaga".to_string());
    event.venue_country_code = Some("ES".to_string());
    event.venue_name = Some("Venue".to_string());
    event.venue_state_code = Some("MA".to_string());
    event.venue_zip_code = Some("29006".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Return a matching provider location for the persisted venue
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .withf(|recipient, venue| {
            recipient.recipient_id == "acct_test"
                && venue.country_code == "ES"
                && venue.state_code.as_deref() == Some("MA")
        })
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Ok(AutomaticTaxReadiness {
                    cached: true,
                    fingerprint: "fingerprint".to_string(),
                    provider_tax_location_id: "loc_cached".to_string(),
                    state_code: Some("MA".to_string()),
                })
            })
        });

    // Check the readiness
    let manager = sample_manager(db, None, payments_manager);
    let readiness = manager
        .check_automatic_tax_readiness(community_id, group_id, event_id)
        .await
        .unwrap();

    // Check the provider result is returned unchanged
    assert!(readiness.cached);
    assert_eq!(readiness.state_code.as_deref(), Some("MA"));
}

#[tokio::test]
async fn test_delete_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_event_series_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    db.expect_delete_event().times(0);
    db.expect_delete_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .delete(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::Series,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_delete_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_delete_event()
        .times(1)
        .withf(move |uid, gid, eid| *uid == user_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .delete(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[test]
fn test_is_event_payload_paid_capable_accepts_any_positive_price() {
    let payload = json!({
        "ticket_types": [
            {
                "active": false,
                "availability": "invitation_only",
                "price_windows": [
                    {"amount_minor": 0},
                    {"amount_minor": 1}
                ]
            }
        ]
    });

    assert!(is_event_payload_paid_capable(&payload));
}

#[test]
fn test_is_event_payload_paid_capable_rejects_missing_ticket_types() {
    assert!(!is_event_payload_paid_capable(&json!({})));
    assert!(!is_event_payload_paid_capable(
        &json!({"ticket_types": null})
    ));
}

#[test]
fn test_is_event_payload_paid_capable_rejects_zero_prices() {
    let payload = json!({
        "ticket_types": [
            {
                "price_windows": [
                    {"amount_minor": 0},
                    {"amount_minor": -1}
                ]
            }
        ]
    });

    assert!(!is_event_payload_paid_capable(&payload));
}

#[tokio::test]
async fn test_list_tax_rates_rejects_missing_fiscal_sponsor() {
    // Setup a group without a configured sponsor
    let mut db = MockDB::new();
    db.expect_get_group_payment_recipient()
        .times(1)
        .returning(|_, _| Ok(None));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_list_tax_rates().never();

    // List the rates
    let manager = sample_manager(db, None, payments_manager);
    let error = manager
        .list_tax_rates(Uuid::new_v4(), Uuid::new_v4(), TicketTaxBehavior::Exclusive)
        .await
        .unwrap_err();

    // Check the sponsor requirement is rejected
    assert!(matches!(
        error,
        EventsError::Rejected(message)
            if message == "configure a fiscal sponsor before selecting Stripe Tax Rates"
    ));
}

#[tokio::test]
async fn test_list_tax_rates_returns_provider_rates() {
    // Setup the configured sponsor and its provider rates
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .withf(|recipient, jurisdiction| {
            recipient.recipient_id == "acct_test" && jurisdiction.is_none()
        })
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_list_tax_rates()
        .times(1)
        .withf(|recipient, tax_behavior| {
            recipient.recipient_id == "acct_test" && *tax_behavior == TicketTaxBehavior::Inclusive
        })
        .returning(|_, _| {
            Box::pin(async {
                Ok(vec![TicketTaxRate {
                    display_name: "VAT".to_string(),
                    id: "txr_vat".to_string(),
                    inclusive: true,
                    percentage: "21".to_string(),

                    jurisdiction: Some("ES".to_string()),
                }])
            })
        });

    // List the rates
    let manager = sample_manager(db, None, payments_manager);
    let rates = manager
        .list_tax_rates(community_id, group_id, TicketTaxBehavior::Inclusive)
        .await
        .unwrap();

    // Check the provider rates are returned
    assert_eq!(rates.len(), 1);
    assert_eq!(rates[0].id, "txr_vat");
}

#[tokio::test]
async fn test_publish_already_published_no_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    // Event is already published, so no notification should be sent
    let already_published_event = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(already_published_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no enqueue expected)

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .publish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_publish_series_sends_aggregate_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event_summary = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: false,
        ..sample_event_summary(related_event_id, group_id)
    };
    let event_full = EventFull {
        event_id,
        name: "First Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let related_event_full = EventFull {
        event_id: related_event_id,
        name: "Second Series Event".to_string(),
        speakers: vec![],
        ..sample_event_full(community_id, related_event_id, group_id)
    };
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_list_event_series_publishable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    let locked_event_ids = expected_series_event_ids.clone();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == locked_event_ids)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_publish_event_series_events()
        .times(1)
        .withf(
            move |uid, gid, event_ids, payment_provider, payment_validation| {
                *uid == user_id
                    && *gid == group_id
                    && event_ids == expected_series_event_ids.as_slice()
                    && payment_provider.is_none()
                    && payment_validation.is_none()
            },
        )
        .returning(move |_, _, _, _, _| Ok(()));
    tx.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id]));
    tx.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_full.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventSeriesPublished)
                && notification.attachments.is_empty()
                && notification.recipients == vec![member_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventSeriesPublished>(value.clone()).is_ok_and(|template| {
                        template.event_count == 2
                            && template.events.len() == 2
                            && template.theme.primary_color
                                == site_settings_for_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .publish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::Series,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_publish_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event_summary = EventSummary {
        published: true,
        ..sample_event_summary(event_id, group_id)
    };
    let related_event_summary = EventSummary {
        event_id: related_event_id,
        published: true,
        ..sample_event_summary(related_event_id, group_id)
    };
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_list_event_series_publishable_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    let locked_event_ids = expected_series_event_ids.clone();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == locked_event_ids)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_summary.clone()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| {
            *cid == community_id && *gid == group_id && *eid == related_event_id
        })
        .returning(move |_, _, _| Ok(related_event_summary.clone()));
    tx.expect_publish_event().times(0);
    tx.expect_publish_event_series_events()
        .times(1)
        .withf(
            move |uid, gid, event_ids, payment_provider, payment_validation| {
                *uid == user_id
                    && *gid == group_id
                    && event_ids == expected_series_event_ids.as_slice()
                    && payment_provider.is_none()
                    && payment_validation.is_none()
            },
        )
        .returning(move |_, _, _, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .publish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::Series,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_publish_speakers_only() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let unpublished_event = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_speaker_notification = site_settings.clone();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    // No group members
    tx.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    tx.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::SpeakerWelcome)
                && notification.recipients == vec![speaker_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SpeakerWelcome>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_speaker_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .publish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_publish_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let member_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let team_member_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let unpublished_event = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_member_notification = site_settings.clone();
    let site_settings_for_speaker_notification = site_settings.clone();
    let mut expected_member_recipients = vec![member_id, team_member_id];
    expected_member_recipients.sort();

    // Setup database mock
    let mut db = MockDB::new();
    let mut sequence = Sequence::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(unpublished_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .in_sequence(&mut sequence)
        .returning(move |_, _, _, _, _| Ok(()));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_group_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![member_id]));
    tx.expect_list_group_team_members_ids()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(move |_| Ok(vec![team_member_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPublished)
                && notification.recipients == expected_member_recipients
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPublished>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_member_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::SpeakerWelcome)
                && notification.recipients == vec![speaker_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<SpeakerWelcome>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_speaker_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .publish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_publish_test_event_no_notification() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let unpublished_test_event = EventSummary {
        published: false,
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(unpublished_test_event.clone()));
    tx.expect_publish_event()
        .times(1)
        .withf(move |uid, gid, eid, payment_provider, payment_validation| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && payment_provider.is_none()
                && payment_validation.is_none()
        })
        .returning(move |_, _, _, _, _| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .publish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_publish_validation_rechecks_every_manual_tax_selection() {
    // Setup paid and free manual-tax events with separate rate selections
    let community_id = Uuid::new_v4();
    let free_event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let paid_event_id = Uuid::new_v4();
    let mut paid_event = sample_event_full(community_id, paid_event_id, group_id);
    paid_event.manual_tax_rate_ids = vec!["txr_state".to_string(), "txr_local".to_string()];
    paid_event.payment_currency_code = Some("USD".to_string());
    paid_event.tax_behavior = TicketTaxBehavior::Exclusive;
    paid_event.tax_calculation_mode = TicketTaxCalculationMode::Manual;
    paid_event.ticket_types = Some(vec![EventTicketType {
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        price_windows: vec![EventTicketPriceWindow {
            amount_minor: 2500,
            ..Default::default()
        }],
        title: "General admission".to_string(),
        ..Default::default()
    }]);
    let mut free_event = sample_event_full(community_id, free_event_id, group_id);
    free_event.manual_tax_rate_ids = vec!["txr_free".to_string()];
    free_event.tax_behavior = TicketTaxBehavior::Inclusive;
    free_event.tax_calculation_mode = TicketTaxCalculationMode::Manual;

    // Return both events and their shared connected fiscal sponsor
    let mut db = MockDB::new();
    db.expect_get_event_full().times(2).returning(move |_, _, event_id| {
        if event_id == paid_event_id {
            Ok(paid_event.clone())
        } else {
            Ok(free_event.clone())
        }
    });
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Revalidate sponsor readiness once and every event-level Tax Rate selection
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .withf(|recipient, automatic_tax_jurisdiction| {
            recipient.recipient_id == "acct_test" && automatic_tax_jurisdiction.is_none()
        })
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_validate_tax_rates()
        .times(2)
        .withf(|recipient, rate_ids, behavior, jurisdiction| {
            recipient.recipient_id == "acct_test"
                && (rate_ids == ["txr_state", "txr_local"]
                    && *behavior == TicketTaxBehavior::Exclusive
                    || rate_ids == ["txr_free"] && *behavior == TicketTaxBehavior::Inclusive)
                && jurisdiction.as_ref().is_some_and(|jurisdiction| {
                    jurisdiction.country_code == "US"
                        && jurisdiction.state_code.as_deref() == Some("CA")
                })
        })
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

    // Validate the full publish set and retain the paid mutation binding
    let validation = sample_manager(db, None, payments_manager)
        .validate_publish_fiscal_sponsor(community_id, group_id, &[paid_event_id, free_event_id])
        .await
        .expect("manual Tax Rates to be ready")
        .expect("paid publish validation binding to be returned");

    assert!(!validation.require_automatic_tax);
    assert_eq!(
        validation.manual_tax_rate_ids,
        Some(vec!["txr_state".to_string(), "txr_local".to_string()])
    );
}

#[tokio::test]
async fn test_publish_validation_requires_automatic_tax_location_readiness() {
    // Setup a paid automatic-tax event and its connected fiscal sponsor
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.payment_currency_code = Some("USD".to_string());
    event.tax_calculation_mode = TicketTaxCalculationMode::Automatic;
    event.ticket_types = Some(vec![EventTicketType {
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        price_windows: vec![EventTicketPriceWindow {
            amount_minor: 2500,
            ..Default::default()
        }],
        title: "General admission".to_string(),
        ..Default::default()
    }]);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_group_payment_recipient()
        .times(1)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Reject the venue after sponsor readiness succeeds
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .returning(|_, _| {
            Box::pin(async {
                Err(AutomaticTaxReadinessError::StateCodeInvalid {
                    country_code: "ES".to_string(),
                    state_code: "ZZ".to_string(),
                })
            })
        });

    // Check publication stops before a database publish mutation is possible
    let error = sample_manager(db, None, payments_manager)
        .validate_publish_fiscal_sponsor(community_id, group_id, &[event_id])
        .await
        .expect_err("invalid provider location to stop publication");

    assert!(matches!(
        error,
        EventsError::Rejected(message)
            if message == "the state code ZZ is invalid for ES"
    ));
}

#[tokio::test]
async fn test_publish_validation_skips_external_paid_events() {
    // Setup a paid external event that must not trigger Stripe sponsor checks
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_full(community_id, event_id, group_id);
    event.external_payment_url = Some("https://pay.example.test/publish".to_string());
    event.payment_currency_code = Some("KRW".to_string());
    event.tax_calculation_mode = TicketTaxCalculationMode::None;
    event.ticket_types = Some(vec![EventTicketType {
        event_ticket_type_id: Uuid::new_v4(),
        order: 1,
        price_windows: vec![EventTicketPriceWindow {
            amount_minor: 5000,
            ..Default::default()
        }],
        title: "General admission".to_string(),
        ..Default::default()
    }]);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(event.clone()));
    db.expect_get_group_payment_recipient().never();

    // Skip every Stripe sponsor and tax call for external paid events
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_ensure_automatic_tax_readiness().never();
    payments_manager.expect_validate_tax_rates().never();

    // Check publication proceeds without a Stripe validation binding
    let validation = sample_manager(db, None, payments_manager)
        .validate_publish_fiscal_sponsor(community_id, group_id, &[event_id])
        .await
        .expect("external paid events to skip Stripe publish validation");

    assert!(validation.is_none());
}

#[tokio::test]
async fn test_unpublish_series_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let related_event_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let series_event_ids = vec![event_id, related_event_id];
    let expected_series_event_ids = series_event_ids.clone();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_list_event_series_event_ids()
        .times(1)
        .withf(move |gid, eid| *gid == group_id && *eid == event_id)
        .returning(move |_, _| Ok(series_event_ids.clone()));
    db.expect_unpublish_event().times(0);
    db.expect_unpublish_event_series_events()
        .times(1)
        .withf(move |uid, gid, event_ids| {
            *uid == user_id && *gid == group_id && event_ids == expected_series_event_ids.as_slice()
        })
        .returning(move |_, _, _| Ok(()));

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .unpublish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::Series,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_unpublish_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_unpublish_event()
        .times(1)
        .withf(move |uid, gid, eid| *uid == user_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(()));

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let result = manager
        .unpublish(&EventActionInput {
            actor_user_id: user_id,
            community_id,
            event_id,
            group_id,
            scope: EventActionScope::This,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_free_manual_event_without_tax_rates_skips_fiscal_sponsor_validation() {
    // Setup a free manual-tax event submission with an explicit empty selection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let after = before.clone();
    let mut event_form = sample_event_form();
    event_form.manual_tax_rate_ids_present = Some(true);
    event_form.tax_calculation_mode = TicketTaxCalculationMode::Manual;
    let body = serde_qs::to_string(&event_form).unwrap();

    // Authorize the update and report that free ticketing needs no provider validation
    let mut db = MockDB::new();
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event["manual_tax_rate_ids"] == json!([])
                && event["tax_calculation_mode"] == "manual"
                && event.get("manual_tax_rate_ids_present").is_none()
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_get_group_payment_recipient().never();

    // Persist the explicit empty selection without a provider validation snapshot
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && event["manual_tax_rate_ids"] == json!([])
                && event["tax_calculation_mode"] == "manual"
                && event.get("_payment_validation").is_none()
                && event.get("manual_tax_rate_ids_present").is_none()
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Keep free empty selections independent of fiscal sponsor availability
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_validate_tax_rates().never();

    // Run the workflow through the manager
    let manager = sample_manager(db, None, payments_manager);
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_free_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let after = before.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_free_test_to_paid_live_sends_admin_notification() {
    // Setup identifiers and a test-event promotion with paid tickets
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = EventSummary {
        published: false,
        test_event: true,
        ..sample_event_summary(event_id, group_id)
    };
    let after = EventSummary {
        published: false,
        test_event: false,
        ..sample_event_summary(event_id, group_id)
    };
    let body = format!("{}&test_event=false", sample_paid_event_body());

    // Setup authentication and permission checks
    let mut db = MockDB::new();

    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(true));

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| {
            Ok(EventFull {
                published: false,
                ..sample_event_full(community_id, event_id, group_id)
            })
        });

    // Setup the ordered state transition and notification expectations
    let mut sequence = Sequence::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .in_sequence(&mut sequence)
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(before.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
                && event.get("test_event").and_then(serde_json::Value::as_bool) == Some(false)
                && event.get("_payment_validation").is_some_and(|validation| {
                    validation["require_automatic_tax"] == true
                        && validation["expected_payment_recipient"]["recipient_id"] == "acct_test"
                })
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .in_sequence(&mut sequence)
        .returning(|_, _, _, _, _, _| Ok(true));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .in_sequence(&mut sequence)
        .returning(move |_, _, _| Ok(after.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventPaidConfigured)
                && notification.recipients == vec![admin_id]
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventPaidConfigured>(value.clone()).is_ok_and(|template| {
                        template.event_count == 1 && template.events[0].event_id == event_id
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        None,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_update_paid_event_without_payment_recipient_returns_unprocessable_entity() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let body = sample_paid_event_body();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_group_payment_recipient()
        .times(2)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(None));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(sample_event_full(community_id, event_id, group_id)));
    db.expect_begin().never();

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        None,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the rejection message
    assert!(
        matches!(result.unwrap_err(), EventsError::Rejected(message) if message == "configure a fiscal sponsor before updating this published event")
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_paid_notification_failure_rolls_back() {
    // Setup identifiers and paid update input
    let admin_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let body = sample_paid_event_body();

    // Setup authentication and permission checks
    let mut db = MockDB::new();

    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(true));

    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    db.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| {
            Ok(EventFull {
                published: false,
                ..sample_event_full(community_id, event_id, group_id)
            })
        });

    // Setup a successful update followed by a required notification failure
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(before.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, _, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| Ok(true));
    tx.expect_list_community_admin_ids()
        .times(1)
        .withf(move |cid| *cid == community_id)
        .returning(move |_| Ok(vec![admin_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("notification error")));
    tx.expect_get_event_full().never();
    tx.expect_list_event_attendees_ids().never();
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(
        db,
        None,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the internal failure propagates
    assert!(
        matches!(result.unwrap_err(), EventsError::Other(err) if err.to_string() == "notification error")
    );
}

#[tokio::test]
async fn test_update_published_automatic_tax_event_stops_before_mutation_when_not_ready() {
    // Setup a paid automatic-tax update for an already-published event
    let body = sample_paid_event_body();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .returning(|_, _, _, _| Ok(true));
    db.expect_get_group_payment_recipient()
        .times(2)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));
    let mut persisted_event = sample_event_full(community_id, event_id, group_id);
    persisted_event.published = true;
    db.expect_get_event_full()
        .times(1)
        .returning(move |_, _, _| Ok(persisted_event.clone()));
    db.expect_begin().never();

    // Allow sponsor validation but reject the proposed venue location
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .returning(|_, _| Box::pin(async { Err(AutomaticTaxReadinessError::InvalidAddress) }));

    // Run the workflow through the manager
    let manager = sample_manager(db, None, payments_manager);
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the rejection message
    assert!(
        matches!(result.unwrap_err(), EventsError::Rejected(message) if message == "the venue address is invalid")
    );
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_reschedule_notification_success() {
    // Setup identifiers and data structures
    let attendee_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_full = EventFull {
        speakers: vec![Speaker {
            featured: false,
            user: sample_template_user_with_id(speaker_id),
        }],
        ..sample_event_full(community_id, event_id, group_id)
    };
    let site_settings = sample_site_settings();
    let site_settings_for_reschedule_notification = site_settings.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut call_count = 0;
            move |_, _, _| {
                call_count += 1;
                match call_count {
                    1 => Ok(before.clone()),
                    2 => Ok(after.clone()),
                    _ => unreachable!(),
                }
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![attendee_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRescheduled)
                && notification.recipients.len() == 2
                && notification.recipients.contains(&attendee_id)
                && notification.recipients.contains(&speaker_id)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventRescheduled>(value.clone()).is_ok_and(|template| {
                        template.link == "/test/group/npq6789/event/abc1234"
                            && template.theme.primary_color
                                == site_settings_for_reschedule_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Ok(()));
    expect_successful_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_reschedule_rollback_on_enqueue_failure() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_full = sample_event_full(community_id, event_id, group_id);
    let site_settings = sample_site_settings();
    let site_settings_for_notification = site_settings.clone();
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    tx.expect_get_event_full()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(event_full.clone()));
    tx.expect_list_event_attendees_ids()
        .times(1)
        .withf(move |gid, eid, checked_in_only| {
            *gid == group_id && *eid == event_id && !checked_in_only
        })
        .returning(move |_, _, _| Ok(vec![user_id]));
    tx.expect_get_site_settings()
        .times(1)
        .returning(move || Ok(site_settings.clone()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventRescheduled)
                && notification.template_data.as_ref().is_some_and(|value| {
                    from_value::<EventRescheduled>(value.clone()).is_ok_and(|template| {
                        template.theme.primary_color
                            == site_settings_for_notification.theme.primary_color
                    })
                })
        })
        .returning(|_| Err(anyhow!("notification error")));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the internal failure propagates
    assert!(
        matches!(result.unwrap_err(), EventsError::Other(err) if err.to_string() == "notification error")
    );
}

#[tokio::test]
async fn test_update_reschedule_rollback_on_notification_context_failure() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut call_count = 0;
            move |_, _, _| {
                call_count += 1;
                match call_count {
                    1 => Ok(before.clone()),
                    2 => Err(anyhow!("db error")),
                    _ => unreachable!(),
                }
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_rolled_back_transaction(&mut db, tx);

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the internal failure propagates
    assert!(
        matches!(result.unwrap_err(), EventsError::Other(err) if err.to_string() == "db error")
    );
}

#[tokio::test]
async fn test_update_reschedule_skips_notification_when_shift_too_small() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    // Shift by only 10 minutes (below MIN_RESCHEDULE_SHIFT of 15 minutes)
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(10)),
        ..before.clone()
    };
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no enqueue expected - shift too small)

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_update_reschedule_skips_notification_when_unpublished() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    // Event is unpublished, so no reschedule notification should be sent
    let before = EventSummary {
        published: false,
        ..sample_event_summary(event_id, group_id)
    };
    // Significant reschedule (30 minutes), but event is unpublished
    let after = EventSummary {
        starts_at: before.starts_at.map(|ts| ts + chrono::Duration::minutes(30)),
        ..before.clone()
    };
    let event_form = sample_event_form();
    let body = serde_qs::to_string(&event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning({
            let mut first_call = true;
            move |_, _, _| {
                let result = if first_call {
                    first_call = false;
                    before.clone()
                } else {
                    after.clone()
                };
                Ok(result)
            }
        });
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some(event_form.name.as_str())
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no enqueue expected - event unpublished)

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_update_skips_notification_for_past_event() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let past_event = {
        let past_time = Utc::now() - chrono::Duration::hours(2);
        EventSummary {
            ends_at: Some(past_time + chrono::Duration::hours(1)),
            starts_at: Some(past_time),
            ..sample_event_summary(event_id, group_id)
        }
    };
    let mut past_event_form = sample_event_form();
    past_event_form.description = "Updated past event description".to_string();
    past_event_form.name = "Past Event Updated".to_string();
    let body = serde_qs::to_string(&past_event_form).unwrap();

    // Setup database mock
    let mut db = MockDB::new();

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(1)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(past_event.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(
            move |uid, gid, eid, event, cfg_max_participants, payment_provider| {
                *uid == user_id
                    && *gid == group_id
                    && *eid == event_id
                    && event.get("description").and_then(serde_json::Value::as_str)
                        == Some("Updated past event description")
                    && event.get("name").and_then(serde_json::Value::as_str)
                        == Some("Past Event Updated")
                    && cfg_max_participants.is_empty()
                    && payment_provider.is_none()
            },
        )
        .returning(move |_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock (no expectations - past events don't notify)

    // Run the workflow through the manager
    let manager = sample_manager(db, None, sample_payments_manager(None));
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn test_update_unrelated_paid_event_edit_skips_fiscal_sponsor_validation() {
    // Setup an unrelated mutation whose submitted ticketing configuration is unchanged
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let before = sample_event_summary(event_id, group_id);
    let body = sample_paid_event_body();

    // Authorize the update and report that paid-ticket readiness fields are unchanged
    let mut db = MockDB::new();
    db.expect_event_ticketing_configuration_changed()
        .times(1)
        .withf(move |cid, gid, eid, event| {
            *cid == community_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
        })
        .returning(|_, _, _, _| Ok(false));
    db.expect_get_group_payment_recipient().never();

    // Persist the unrelated edit without entering a notifiable paid state
    let mut tx = MockDB::new();
    tx.expect_lock_group_events()
        .times(1)
        .withf(move |gid, event_ids| *gid == group_id && event_ids == [event_id].as_slice())
        .returning(|_, _| Ok(()));
    tx.expect_get_event_summary()
        .times(2)
        .withf(move |cid, gid, eid| *cid == community_id && *gid == group_id && *eid == event_id)
        .returning(move |_, _, _| Ok(before.clone()));
    tx.expect_update_event()
        .times(1)
        .withf(move |uid, gid, eid, event, _, payment_provider| {
            *uid == user_id
                && *gid == group_id
                && *eid == event_id
                && event.get("ticket_types").is_some()
                && *payment_provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| Ok(false));
    expect_successful_transaction(&mut db, tx);

    // Keep unrelated edits independent of live provider availability
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_configured_provider()
        .times(1)
        .return_const(Some(PaymentProvider::Stripe));
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Run the workflow through the manager
    let manager = sample_manager(db, None, payments_manager);
    let event = parse_event_form(&body);
    let result = manager
        .update(&UpdateEventInput {
            actor_user_id: user_id,
            community_id,
            event,
            event_id,
            group_id,
        })
        .await;

    // Check the workflow succeeded
    result.unwrap();
}

#[tokio::test]
async fn test_validate_group_fiscal_sponsor_omits_invalid_form_jurisdiction() {
    // Setup an automatic-tax form without a valid physical venue
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let mut event = sample_event_form();
    event.kind_id = "in-person".to_string();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(|_, _| Ok(Some(sample_group_payment_recipient())));

    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .withf(|recipient, jurisdiction| {
            recipient.recipient_id == "acct_test" && jurisdiction.is_none()
        })
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager.expect_validate_tax_rates().never();

    // Validate sponsor ownership without sending an empty country to Stripe
    let validation = sample_manager(db, None, payments_manager)
        .validate_group_fiscal_sponsor(community_id, group_id, &event)
        .await
        .expect("account-only sponsor validation to succeed");

    // Preserve the automatic-tax binding for the database venue validation
    assert!(validation.require_automatic_tax);
}

// Helpers.

/// Expects a transaction that rolls back without committing.
fn expect_rolled_back_transaction(db: &mut MockDB, mut tx: MockDB) {
    tx.expect_commit().never();
    tx.expect_rollback().times(1).returning(|| Ok(()));
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
}

/// Expects a transaction that commits without rolling back.
fn expect_successful_transaction(db: &mut MockDB, mut tx: MockDB) {
    tx.expect_commit().times(1).returning(|| Ok(()));
    tx.expect_rollback().never();
    db.expect_begin().times(1).return_once(|| Ok(Box::new(tx)));
}

/// Parses a dashboard event form body the same way the extractor does.
fn parse_event_form(body: &str) -> EventInput {
    serde_qs::Config::new()
        .max_depth(6)
        .use_form_encoding(true)
        .deserialize_str(body)
        .expect("event form body to deserialize")
}

/// Creates an events manager with the supplied test doubles.
fn sample_manager(
    db: MockDB,
    meetings_cfg: Option<&MeetingsConfig>,
    payments_manager: MockPaymentsManager,
) -> PgEventsManager {
    PgEventsManager::new(
        Arc::new(db),
        meetings_cfg,
        Arc::new(payments_manager),
        HttpServerConfig::default(),
    )
}

/// Creates a payments manager mock with the configured provider and a ready sponsor.
fn sample_payments_manager(provider: Option<PaymentProvider>) -> MockPaymentsManager {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_configured_provider().return_const(provider);
    payments_manager
        .expect_validate_fiscal_sponsor()
        .returning(|_, _| Box::pin(async { Ok(()) }));
    payments_manager
}

/// Creates a meetings configuration with the Zoom provider enabled.
fn sample_zoom_meetings_cfg() -> MeetingsConfig {
    MeetingsConfig {
        zoom: Some(MeetingsZoomConfig {
            account_id: "account-id".to_string(),
            client_id: "client-id".to_string(),
            client_secret: "client-secret".to_string(),
            enabled: true,
            host_pool_users: vec!["host@example.com".to_string()],
            max_participants: 100,
            max_simultaneous_meetings_per_host: 1,
            webhook_secret_token: "test-token".to_string(),

            http_client: HttpClientConfig::default(),
        }),
    }
}
