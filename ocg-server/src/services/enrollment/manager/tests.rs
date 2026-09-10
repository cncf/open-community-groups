use std::sync::Arc;

use anyhow::anyhow;
use chrono::{Duration, Utc};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        dashboard::group::{
            EventAdmissionAllocation, EventAdmissionAllocationConflict,
            EventAdmissionAllocationOutcome, EventAdmissionAllocationResult,
            EventAttendeeCancellationOutcome, EventAttendeeCancellationStatus,
        },
        event::{AttendEventConflict, AttendEventResult},
        mock::MockDB,
    },
    services::{
        enrollment::{
            AcceptInvitationRequestInput, AdmissionAllocationOutcome, AttendEventInput,
            AttendOutcome, EnrollmentError, EnrollmentManager, InviteAttendeeInput,
            LeaveEventInput, OrganizerCancellationInput, PgEnrollmentManager, StartCheckoutInput,
        },
        notifications::MockNotificationsManager,
        payments::{MockPaymentsManager, PaymentsError, PrepareCheckoutOutcome},
    },
    types::{
        event::{EventAttendanceInput, EventEnrollmentStatus, EventLeaveOutcome, EventSummary},
        notifications::NotificationKind,
        payments::{
            CheckoutInput, EventPurchaseChargeModel, EventPurchaseStatus, EventPurchaseSummary,
            EventTicketCurrentPrice, EventTicketType, EventTicketTypeAvailability, PaymentProvider,
            PreparedEventCheckout,
        },
        questionnaire::{
            OptionalQuestionnaireAnswersForm, QuestionnaireAnswer, QuestionnaireAnswerValue,
            QuestionnaireAnswers, QuestionnaireQuestion, QuestionnaireQuestionKind,
        },
        tests::{sample_event_summary, sample_group_summary, sample_site_settings},
    },
};

#[tokio::test]
async fn test_accept_invitation_request_returns_allocated() {
    // Setup identifiers and the allocation expectation
    let actor_user_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_accept_event_invitation_request()
        .times(1)
        .withf(move |actor, gid, eid, uid, ticket_type_id, provider| {
            *actor == actor_user_id
                && *gid == group_id
                && *eid == event_id
                && *uid == user_id
                && *ticket_type_id == Some(event_ticket_type_id)
                && *provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _, _| {
            Ok(EventAdmissionAllocationResult::Success(
                EventAdmissionAllocation {
                    outcome: EventAdmissionAllocationOutcome::OfferCreated,
                },
            ))
        });

    // Accept the request
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let outcome = manager
        .accept_invitation_request(&AcceptInvitationRequestInput {
            actor_user_id,
            event_id,
            group_id,
            user_id,

            event_ticket_type_id: Some(event_ticket_type_id),
        })
        .await
        .unwrap();

    // Check the allocation outcome
    assert_eq!(outcome, AdmissionAllocationOutcome::Allocated);
}

#[tokio::test]
async fn test_accept_invitation_request_returns_conflict_code() {
    // Setup a conflicting allocation
    let mut db = MockDB::new();
    db.expect_accept_event_invitation_request()
        .times(1)
        .returning(|_, _, _, _, _, _| {
            Ok(EventAdmissionAllocationResult::Conflict(
                EventAdmissionAllocationConflict::QueueHasPriority,
            ))
        });

    // Accept the request
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let outcome = manager
        .accept_invitation_request(&AcceptInvitationRequestInput {
            actor_user_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),

            event_ticket_type_id: None,
        })
        .await
        .unwrap();

    // Check the stable conflict code
    assert_eq!(
        outcome,
        AdmissionAllocationOutcome::Conflict("queue-has-priority".to_string())
    );
}

#[tokio::test]
async fn test_attend_completes_free_checkout_for_pending_payment() {
    // Setup an event whose selected ticket resolves to a zero-price hold
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 0, false)]);
    let mut purchase = sample_purchase_summary(event_purchase_id, EventPurchaseStatus::Pending);
    purchase.amount_minor = 0;

    // Setup the attendance registration through the pending-payment state
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_attend_event()
        .times(1)
        .withf(move |cid, eid, uid, answers, selected| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && answers.is_none()
                && *selected == Some(ticket_type_id)
        })
        .returning(|_, _, _, _, _| {
            Ok(AttendEventResult::Enrollment(
                EventEnrollmentStatus::PendingPayment,
            ))
        });

    // Setup the checkout hold and free completion
    let mut payments_manager = sample_payments_manager(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .withf(move |cid, eid, uid, input| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && input.event_ticket_type_id == Some(ticket_type_id)
                && input.admission_offer_id.is_none()
                && input.discount_code.is_none()
        })
        .returning(move |_, _, _, _| {
            let purchase = purchase.clone();
            Box::pin(async move {
                Ok(PrepareCheckoutOutcome::Prepared(Box::new(
                    sample_prepared_checkout(event_id, purchase),
                )))
            })
        });
    payments_manager
        .expect_complete_free_checkout()
        .times(1)
        .withf(move |cid, eid, purchase_id, uid| {
            *cid == community_id
                && *eid == event_id
                && *purchase_id == event_purchase_id
                && *uid == user_id
        })
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));
    payments_manager.expect_get_or_create_checkout_redirect_url().never();

    // Attend the event
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap();

    // Check the attendee outcome
    assert_eq!(
        outcome,
        AttendOutcome::Enrolled(EventEnrollmentStatus::Attendee)
    );
}

#[tokio::test]
async fn test_attend_enqueues_waitlist_joined_notification_best_effort() {
    // Setup a waitlist join on a sold-out ticket without answers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.waitlist_enabled = true;
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 0, true)]);
    let notification_event = event.clone();

    // Setup the registration and notification context reads
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions().never();
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Enrollment(
            EventEnrollmentStatus::Waitlisted,
        ))
    });
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(notification_event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup the single waitlist notification
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistJoined)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Attend the event
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap();

    // Check the waitlist outcome
    assert_eq!(
        outcome,
        AttendOutcome::Enrolled(EventEnrollmentStatus::Waitlisted)
    );
}

#[tokio::test]
async fn test_attend_keeps_waitlist_outcome_when_notification_context_fails() {
    // Setup a waitlist join whose notification context load fails
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.waitlist_enabled = true;
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 0, true)]);

    // Setup the registration and the failing context reload
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Enrollment(
            EventEnrollmentStatus::Waitlisted,
        ))
    });
    db.expect_get_event_summary_by_id()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup the manager, which must not enqueue
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Attend the event
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap();

    // Check the core outcome survives the notification failure
    assert_eq!(
        outcome,
        AttendOutcome::Enrolled(EventEnrollmentStatus::Waitlisted)
    );
}

#[tokio::test]
async fn test_attend_propagates_inactive_event_rejection_before_reads() {
    // Setup an inactive event rejection
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Err(anyhow!("event not found or inactive")));
    db.expect_get_event_summary_by_id().never();
    db.expect_attend_event().never();

    // Attend the event
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let err = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            Uuid::new_v4(),
            None,
            None,
        ))
        .await
        .unwrap_err();

    // Check the database rejection propagates unchanged
    assert!(
        matches!(err, EnrollmentError::Other(err) if err.to_string() == "event not found or inactive")
    );
}

#[tokio::test]
async fn test_attend_rejects_missing_answers_when_questions_exist() {
    // Setup an event with a required registration question
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![sample_question(Uuid::new_v4())]));
    db.expect_attend_event().never();

    // Attend without answers
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let err = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            Uuid::new_v4(),
            None,
            None,
        ))
        .await
        .unwrap_err();

    // Check the rejection message
    assert!(
        matches!(err, EnrollmentError::Rejected(message) if message == "questionnaire answers are required")
    );
}

#[tokio::test]
async fn test_attend_rejects_refund_requested_purchase() {
    // Setup a pending-payment registration whose purchase is in refund
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 2_500, false)]);
    let purchase = sample_purchase_summary(Uuid::new_v4(), EventPurchaseStatus::RefundRequested);

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Enrollment(
            EventEnrollmentStatus::PendingPayment,
        ))
    });

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .returning(move |_, _, _, _| {
            let purchase = purchase.clone();
            Box::pin(async move {
                Ok(PrepareCheckoutOutcome::Prepared(Box::new(
                    sample_prepared_checkout(event_id, purchase),
                )))
            })
        });
    payments_manager.expect_complete_free_checkout().never();
    payments_manager.expect_get_or_create_checkout_redirect_url().never();

    // Attend the event
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let err = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap_err();

    // Check the rejection message
    assert!(matches!(
        err,
        EnrollmentError::Rejected(message)
            if message == "checkout is unavailable while a refund is in progress"
    ));
}

#[tokio::test]
async fn test_attend_requires_answers_when_waitlist_ticket_becomes_available() {
    // Setup a deferred-answers waitlist join that resolves to checkout
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.waitlist_enabled = true;
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 2_500, true)]);

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Enrollment(
            EventEnrollmentStatus::PendingPayment,
        ))
    });
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![sample_question(Uuid::new_v4())]));

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(Some(PaymentProvider::Stripe));
    payments_manager.expect_prepare_checkout().never();

    // Attend without answers
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            Uuid::new_v4(),
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap();

    // Check the answers are requested before any hold is created
    assert_eq!(
        outcome,
        AttendOutcome::Conflict("registration-answers-required".to_string())
    );
}

#[tokio::test]
async fn test_attend_resolves_omitted_single_public_ticket_type() {
    // Setup an event with exactly one public ticket type
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 0, false)]);

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_attend_event()
        .times(1)
        .withf(move |_, _, _, _, selected| *selected == Some(ticket_type_id))
        .returning(|_, _, _, _, _| {
            Ok(AttendEventResult::Enrollment(
                EventEnrollmentStatus::Attendee,
            ))
        });

    // Attend without selecting a ticket type
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            user_id,
            None,
            None,
        ))
        .await
        .unwrap();

    // Check the attendee outcome
    assert_eq!(
        outcome,
        AttendOutcome::Enrolled(EventEnrollmentStatus::Attendee)
    );
}

#[tokio::test]
async fn test_attend_returns_capacity_conflict() {
    // Setup a registration that hits the capacity conflict
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Conflict(
            AttendEventConflict::EventCapacityUnavailable,
        ))
    });

    // Attend the event
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            Uuid::new_v4(),
            None,
            None,
        ))
        .await
        .unwrap();

    // Check the stable conflict code
    assert_eq!(
        outcome,
        AttendOutcome::Conflict("event-capacity-unavailable".to_string())
    );
}

#[tokio::test]
async fn test_attend_returns_checkout_conflict() {
    // Setup a pending-payment registration whose hold cannot be reserved
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 2_500, false)]);

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Enrollment(
            EventEnrollmentStatus::PendingPayment,
        ))
    });

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .returning(|_, _, _, _| {
            Box::pin(async {
                Ok(PrepareCheckoutOutcome::Conflict(
                    "ticket-type-sold-out".to_string(),
                ))
            })
        });

    // Attend the event
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            Uuid::new_v4(),
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap();

    // Check the checkout conflict propagates
    assert_eq!(
        outcome,
        AttendOutcome::Conflict("ticket-type-sold-out".to_string())
    );
}

#[tokio::test]
async fn test_attend_returns_checkout_redirect_for_paid_ticket() {
    // Setup a paid ticket registration with submitted answers
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let question_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 2_500, false)]);
    let answers = sample_answers(question_id);
    let hold_expires_at = Utc::now() + Duration::minutes(15);
    let mut purchase = sample_purchase_summary(event_purchase_id, EventPurchaseStatus::Pending);
    purchase.hold_expires_at = Some(hold_expires_at);

    // Setup the registration with validated answers
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(move |_, _| Ok(vec![sample_question(question_id)]));
    db.expect_attend_event()
        .times(1)
        .withf(move |_, _, _, submitted, _| {
            submitted.as_ref().is_some_and(|submitted| {
                submitted.answers.len() == 1 && submitted.answers[0].question_id == question_id
            })
        })
        .returning(|_, _, _, _, _| {
            Ok(AttendEventResult::Enrollment(
                EventEnrollmentStatus::PendingPayment,
            ))
        });

    // Setup the checkout hold and provider redirect
    let mut payments_manager = sample_payments_manager(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .withf(move |_, _, _, input| {
            input.registration_answers.registration_answers.is_some()
                && input.event_ticket_type_id == Some(ticket_type_id)
        })
        .returning(move |_, _, _, _| {
            let purchase = purchase.clone();
            Box::pin(async move {
                Ok(PrepareCheckoutOutcome::Prepared(Box::new(
                    sample_prepared_checkout(event_id, purchase),
                )))
            })
        });
    payments_manager
        .expect_get_or_create_checkout_redirect_url()
        .times(1)
        .withf(move |prepared_checkout, uid| {
            prepared_checkout.purchase.event_purchase_id == event_purchase_id && *uid == user_id
        })
        .returning(|_, _| Box::pin(async { Ok("https://checkout.test/session".to_string()) }));
    payments_manager.expect_complete_free_checkout().never();

    // Attend the event
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
            Some(answers),
        ))
        .await
        .unwrap();

    // Check the redirect outcome keeps the hold deadline
    assert_eq!(
        outcome,
        AttendOutcome::CheckoutRedirect {
            hold_expires_at: Some(hold_expires_at),
            redirect_url: "https://checkout.test/session".to_string(),
        }
    );
}

#[tokio::test]
async fn test_attend_returns_external_pending_payment() {
    // Setup a paid ticket collected outside the platform
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let mut event = sample_event_summary(event_id, group_id);
    event.ticket_types = Some(vec![sample_ticket_type(ticket_type_id, 2_500, false)]);
    let mut purchase = sample_purchase_summary(Uuid::new_v4(), EventPurchaseStatus::Pending);
    purchase.charge_model = EventPurchaseChargeModel::External;
    let expected_checkout = sample_prepared_checkout(event_id, purchase.clone());

    // Setup database mock
    let mut db = MockDB::new();
    expect_active_event(&mut db, community_id, event_id, event);
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));
    db.expect_attend_event().times(1).returning(|_, _, _, _, _| {
        Ok(AttendEventResult::Enrollment(
            EventEnrollmentStatus::PendingPayment,
        ))
    });

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(None);
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .returning(move |_, _, _, _| {
            let purchase = purchase.clone();
            Box::pin(async move {
                Ok(PrepareCheckoutOutcome::Prepared(Box::new(
                    sample_prepared_checkout(event_id, purchase),
                )))
            })
        });
    payments_manager.expect_get_or_create_checkout_redirect_url().never();

    // Attend the event
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .attend_event(&sample_attend_input(
            community_id,
            event_id,
            Uuid::new_v4(),
            Some(ticket_type_id),
            None,
        ))
        .await
        .unwrap();

    // Check the external payment snapshot is returned
    assert_eq!(
        outcome,
        AttendOutcome::ExternalPendingPayment(Box::new(expected_checkout))
    );
}

#[tokio::test]
async fn test_cancel_attendance_as_organizer_commits_cancellation_with_notification() {
    // Setup identifiers and the transactional cancellation
    let actor_user_id = Uuid::new_v4();
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_cancel_event_attendee_attendance()
        .times(1)
        .withf(move |actor, gid, eid, uid, provider| {
            *actor == actor_user_id
                && *gid == group_id
                && *eid == event_id
                && *uid == user_id
                && *provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _, _| {
            Ok(EventAttendeeCancellationOutcome {
                cancellation_status: EventAttendeeCancellationStatus::AttendanceCanceled,
            })
        });
    tx.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventAttendanceCanceled)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Ok(()));

    // Setup database mock
    let mut db = MockDB::new();
    expect_successful_transaction(&mut db, tx);

    // Cancel the attendance
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    manager
        .cancel_attendance_as_organizer(&OrganizerCancellationInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id,
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn test_cancel_attendance_as_organizer_queues_paid_refund_without_notification() {
    // Setup a paid attendee whose refund is queued
    let mut tx = MockDB::new();
    tx.expect_cancel_event_attendee_attendance()
        .times(1)
        .returning(|_, _, _, _, _| {
            Ok(EventAttendeeCancellationOutcome {
                cancellation_status: EventAttendeeCancellationStatus::RefundQueued,
            })
        });
    tx.expect_get_event_summary_by_id().never();
    tx.expect_get_site_settings().never();
    tx.expect_enqueue_notification().never();

    // Setup database mock
    let mut db = MockDB::new();
    expect_successful_transaction(&mut db, tx);

    // Cancel the attendance
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    manager
        .cancel_attendance_as_organizer(&sample_organizer_cancellation_input())
        .await
        .unwrap();
}

#[tokio::test]
async fn test_cancel_attendance_as_organizer_rolls_back_when_notification_enqueue_fails() {
    // Setup an immediate cancellation whose required notification fails
    let event = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_cancel_event_attendee_attendance()
        .times(1)
        .returning(|_, _, _, _, _| {
            Ok(EventAttendeeCancellationOutcome {
                cancellation_status: EventAttendeeCancellationStatus::AttendanceCanceled,
            })
        });
    tx.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("queue unavailable")));

    // Setup database mock
    let mut db = MockDB::new();
    expect_rolled_back_transaction(&mut db, tx);

    // Cancel the attendance
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let err = manager
        .cancel_attendance_as_organizer(&sample_organizer_cancellation_input())
        .await
        .unwrap_err();

    // Check the required side-effect failure propagates
    assert!(matches!(err, EnrollmentError::Other(err) if err.to_string() == "queue unavailable"));
}

#[tokio::test]
async fn test_invite_returns_allocated_for_email_target() {
    // Setup identifiers and the invitation expectation
    let actor_user_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_ticket_type_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_invite_event_attendee()
        .times(1)
        .withf(move |actor, gid, eid, invitation, provider| {
            *actor == actor_user_id
                && *gid == group_id
                && *eid == event_id
                && invitation.email.as_deref() == Some("guest@example.test")
                && invitation.event_ticket_type_id == Some(event_ticket_type_id)
                && invitation.user_id.is_none()
                && provider.is_none()
        })
        .returning(|_, _, _, _, _| {
            Ok(EventAdmissionAllocationResult::Success(
                EventAdmissionAllocation {
                    outcome: EventAdmissionAllocationOutcome::OfferCreated,
                },
            ))
        });

    // Invite the email address
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let outcome = manager
        .invite_event_attendee(&InviteAttendeeInput {
            actor_user_id,
            event_id,
            group_id,

            email: Some("guest@example.test".to_string()),
            event_ticket_type_id: Some(event_ticket_type_id),
            user_id: None,
        })
        .await
        .unwrap();

    // Check the allocation outcome
    assert_eq!(outcome, AdmissionAllocationOutcome::Allocated);
}

#[tokio::test]
async fn test_invite_returns_conflict_code() {
    // Setup a sold-out invitation
    let mut db = MockDB::new();
    db.expect_invite_event_attendee().times(1).returning(|_, _, _, _, _| {
        Ok(EventAdmissionAllocationResult::Conflict(
            EventAdmissionAllocationConflict::TicketTypeSoldOut,
        ))
    });

    // Invite a registered user
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let outcome = manager
        .invite_event_attendee(&InviteAttendeeInput {
            actor_user_id: Uuid::new_v4(),
            event_id: Uuid::new_v4(),
            group_id: Uuid::new_v4(),

            email: None,
            event_ticket_type_id: None,
            user_id: Some(Uuid::new_v4()),
        })
        .await
        .unwrap();

    // Check the stable conflict code
    assert_eq!(
        outcome,
        AdmissionAllocationOutcome::Conflict("ticket-type-sold-out".to_string())
    );
}

#[tokio::test]
async fn test_join_group_enqueues_welcome_notification() {
    // Setup identifiers and the membership mutation
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut group = sample_group_summary(group_id);
    group.slug_pretty = Some("pretty-group".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_join_group()
        .times(1)
        .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _| Ok(()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_summary()
        .times(1)
        .withf(move |cid, gid| *cid == community_id && *gid == group_id)
        .returning(move |_, _| Ok(group.clone()));

    // Setup the welcome notification expectation
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::GroupWelcome)
                && notification.recipients == vec![user_id]
                && notification.template_data.as_ref().is_some_and(|data| {
                    data.get("link").and_then(|link| link.as_str())
                        == Some("/test-community/group/pretty-group")
                })
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Join the group
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    manager.join_group(community_id, group_id, user_id).await.unwrap();
}

#[tokio::test]
async fn test_join_group_keeps_success_when_welcome_notification_fails() {
    // Setup the membership mutation and a failing context load
    let mut db = MockDB::new();
    db.expect_join_group().times(1).returning(|_, _, _| Ok(()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    db.expect_get_group_summary()
        .times(1)
        .returning(|_, _| Err(anyhow!("database unavailable")));

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Join the group
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    manager
        .join_group(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4())
        .await
        .unwrap();
}

#[tokio::test]
async fn test_join_group_propagates_database_failure() {
    // Setup a failing membership mutation
    let mut db = MockDB::new();
    db.expect_join_group()
        .times(1)
        .returning(|_, _, _| Err(anyhow!("database failure")));
    db.expect_get_site_settings().never();

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Join the group
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    let err = manager
        .join_group(Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4())
        .await
        .unwrap_err();

    // Check the failure propagates without a notification
    assert!(matches!(err, EnrollmentError::Other(err) if err.to_string() == "database failure"));
}

#[tokio::test]
async fn test_leave_commits_attendee_cancellation_with_notification() {
    // Setup identifiers and the transactional leave
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_leave_event()
        .times(1)
        .withf(move |cid, eid, uid, provider| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && *provider == Some(PaymentProvider::Stripe)
        })
        .returning(|_, _, _, _| {
            Ok(EventLeaveOutcome {
                left_status: EventEnrollmentStatus::Attendee,
            })
        });
    tx.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventAttendanceCanceled)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Ok(()));

    // Setup database mock
    let mut db = MockDB::new();
    expect_successful_transaction(&mut db, tx);

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Leave the event
    let manager = sample_manager(
        db,
        notifications_manager,
        sample_payments_manager(Some(PaymentProvider::Stripe)),
    );
    let outcome = manager
        .leave_event(&LeaveEventInput {
            community_id,
            event_id,
            user_id,
        })
        .await
        .unwrap();

    // Check the prior status is returned
    assert_eq!(outcome.left_status, EventEnrollmentStatus::Attendee);
}

#[tokio::test]
async fn test_leave_enqueues_waitlist_left_notification_after_commit() {
    // Setup a waitlist exit with its best-effort confirmation
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let event = sample_event_summary(event_id, group_id);

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_leave_event().times(1).returning(|_, _, _, _| {
        Ok(EventLeaveOutcome {
            left_status: EventEnrollmentStatus::Waitlisted,
        })
    });
    tx.expect_enqueue_notification().never();

    // Setup database mock
    let mut db = MockDB::new();
    expect_successful_transaction(&mut db, tx);
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager
        .expect_enqueue()
        .times(1)
        .withf(move |notification| {
            matches!(notification.kind, NotificationKind::EventWaitlistLeft)
                && notification.recipients == vec![user_id]
        })
        .returning(|_| Box::pin(async { Ok(()) }));

    // Leave the waitlist
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    let outcome = manager
        .leave_event(&LeaveEventInput {
            community_id,
            event_id,
            user_id,
        })
        .await
        .unwrap();

    // Check the prior status is returned
    assert_eq!(outcome.left_status, EventEnrollmentStatus::Waitlisted);
}

#[tokio::test]
async fn test_leave_propagates_paid_attendee_rejection_and_rolls_back() {
    // Setup the database rejection raised for paid attendees
    let mut tx = MockDB::new();
    tx.expect_leave_event()
        .times(1)
        .returning(|_, _, _, _| Err(anyhow!("paid attendance must be refunded before leaving")));
    tx.expect_enqueue_notification().never();

    // Setup database mock
    let mut db = MockDB::new();
    expect_rolled_back_transaction(&mut db, tx);

    // Leave the event
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let err = manager.leave_event(&sample_leave_input()).await.unwrap_err();

    // Check the rejection propagates unchanged for SQLSTATE classification
    assert!(matches!(
        err,
        EnrollmentError::Other(err)
            if err.to_string() == "paid attendance must be refunded before leaving"
    ));
}

#[tokio::test]
async fn test_leave_rolls_back_when_notification_enqueue_fails() {
    // Setup an attendee leave whose required notification fails
    let event = sample_event_summary(Uuid::new_v4(), Uuid::new_v4());

    // Setup transaction mock
    let mut tx = MockDB::new();
    tx.expect_leave_event().times(1).returning(|_, _, _, _| {
        Ok(EventLeaveOutcome {
            left_status: EventEnrollmentStatus::Attendee,
        })
    });
    tx.expect_get_event_summary_by_id()
        .times(1)
        .returning(move |_, _| Ok(event.clone()));
    tx.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));
    tx.expect_enqueue_notification()
        .times(1)
        .returning(|_| Err(anyhow!("queue unavailable")));

    // Setup database mock
    let mut db = MockDB::new();
    expect_rolled_back_transaction(&mut db, tx);

    // Leave the event
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    let err = manager.leave_event(&sample_leave_input()).await.unwrap_err();

    // Check the required side-effect failure propagates
    assert!(matches!(err, EnrollmentError::Other(err) if err.to_string() == "queue unavailable"));
}

#[tokio::test]
async fn test_leave_skips_notifications_for_pending_approval() {
    // Setup a pending approval withdrawal
    let mut tx = MockDB::new();
    tx.expect_leave_event().times(1).returning(|_, _, _, _| {
        Ok(EventLeaveOutcome {
            left_status: EventEnrollmentStatus::PendingApproval,
        })
    });
    tx.expect_enqueue_notification().never();

    // Setup database mock
    let mut db = MockDB::new();
    expect_successful_transaction(&mut db, tx);
    db.expect_get_event_summary_by_id().never();

    // Setup notifications manager mock
    let mut notifications_manager = MockNotificationsManager::new();
    notifications_manager.expect_enqueue().never();

    // Leave the event
    let manager = sample_manager(db, notifications_manager, sample_payments_manager(None));
    let outcome = manager.leave_event(&sample_leave_input()).await.unwrap();

    // Check the prior status is returned
    assert_eq!(outcome.left_status, EventEnrollmentStatus::PendingApproval);
}

#[tokio::test]
async fn test_leave_group_removes_membership() {
    // Setup identifiers and the membership removal
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_leave_group()
        .times(1)
        .withf(move |cid, gid, uid| *cid == community_id && *gid == group_id && *uid == user_id)
        .returning(|_, _, _| Ok(()));

    // Leave the group
    let manager = sample_manager(
        db,
        MockNotificationsManager::new(),
        sample_payments_manager(None),
    );
    manager.leave_group(community_id, group_id, user_id).await.unwrap();
}

#[tokio::test]
async fn test_start_checkout_completes_free_ticket() {
    // Setup a free ticket checkout
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut purchase = sample_purchase_summary(event_purchase_id, EventPurchaseStatus::Pending);
    purchase.amount_minor = 0;

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(None);
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .withf(move |cid, eid, uid, input| {
            *cid == community_id
                && *eid == event_id
                && *uid == user_id
                && input.event_ticket_type_id == Some(ticket_type_id)
        })
        .returning(move |_, _, _, _| {
            let purchase = purchase.clone();
            Box::pin(async move {
                Ok(PrepareCheckoutOutcome::Prepared(Box::new(
                    sample_prepared_checkout(event_id, purchase),
                )))
            })
        });
    payments_manager
        .expect_complete_free_checkout()
        .times(1)
        .withf(move |cid, eid, purchase_id, uid| {
            *cid == community_id
                && *eid == event_id
                && *purchase_id == event_purchase_id
                && *uid == user_id
        })
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

    // Start the checkout
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .start_checkout(&sample_start_checkout_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
        ))
        .await
        .unwrap();

    // Check the attendee outcome
    assert_eq!(
        outcome,
        AttendOutcome::Enrolled(EventEnrollmentStatus::Attendee)
    );
}

#[tokio::test]
async fn test_start_checkout_rejects_inactive_event_before_ticket_checks() {
    // Setup an inactive event rejection
    let mut db = MockDB::new();
    db.expect_ensure_event_is_active()
        .times(1)
        .returning(|_, _| Err(anyhow!("event not found or inactive")));
    db.expect_get_event_registration_questions().never();

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(None);
    payments_manager.expect_prepare_checkout().never();

    // Start the checkout
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let err = manager
        .start_checkout(&sample_start_checkout_input(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
        ))
        .await
        .unwrap_err();

    // Check the database rejection propagates unchanged
    assert!(
        matches!(err, EnrollmentError::Other(err) if err.to_string() == "event not found or inactive")
    );
}

#[tokio::test]
async fn test_start_checkout_rejects_missing_ticket_type() {
    // Setup an active event whose checkout rejects the missing ticket
    let mut db = MockDB::new();
    db.expect_ensure_event_is_active().times(1).returning(|_, _| Ok(()));
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(None);
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .returning(|_, _, _, _| {
            Box::pin(async {
                Err(PaymentsError::Rejected(
                    "ticket type is required".to_string(),
                ))
            })
        });

    // Start the checkout
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let err = manager
        .start_checkout(&sample_start_checkout_input(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            None,
        ))
        .await
        .unwrap_err();

    // Check the payments rejection maps to an enrollment rejection
    assert!(
        matches!(err, EnrollmentError::Rejected(message) if message == "ticket type is required")
    );
}

#[tokio::test]
async fn test_start_checkout_returns_redirect_for_paid_ticket() {
    // Setup a paid ticket checkout
    let community_id = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let event_purchase_id = Uuid::new_v4();
    let ticket_type_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let purchase = sample_purchase_summary(event_purchase_id, EventPurchaseStatus::Pending);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_ensure_event_is_active().times(1).returning(|_, _| Ok(()));
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![]));

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(Some(PaymentProvider::Stripe));
    payments_manager
        .expect_prepare_checkout()
        .times(1)
        .returning(move |_, _, _, _| {
            let purchase = purchase.clone();
            Box::pin(async move {
                Ok(PrepareCheckoutOutcome::Prepared(Box::new(
                    sample_prepared_checkout(event_id, purchase),
                )))
            })
        });
    payments_manager
        .expect_get_or_create_checkout_redirect_url()
        .times(1)
        .withf(move |prepared_checkout, uid| {
            prepared_checkout.purchase.event_purchase_id == event_purchase_id && *uid == user_id
        })
        .returning(|_, _| Box::pin(async { Ok("https://checkout.test/session".to_string()) }));
    payments_manager.expect_complete_free_checkout().never();

    // Start the checkout
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let outcome = manager
        .start_checkout(&sample_start_checkout_input(
            community_id,
            event_id,
            user_id,
            Some(ticket_type_id),
        ))
        .await
        .unwrap();

    // Check the redirect outcome
    assert_eq!(
        outcome,
        AttendOutcome::CheckoutRedirect {
            hold_expires_at: None,
            redirect_url: "https://checkout.test/session".to_string(),
        }
    );
}

#[tokio::test]
async fn test_start_checkout_validates_registration_answers() {
    // Setup an event with a required question and no answers
    let mut db = MockDB::new();
    db.expect_ensure_event_is_active().times(1).returning(|_, _| Ok(()));
    db.expect_get_event_registration_questions()
        .times(1)
        .returning(|_, _| Ok(vec![sample_question(Uuid::new_v4())]));

    // Setup payments manager mock
    let mut payments_manager = sample_payments_manager(None);
    payments_manager.expect_prepare_checkout().never();

    // Start the checkout
    let manager = sample_manager(db, MockNotificationsManager::new(), payments_manager);
    let err = manager
        .start_checkout(&sample_start_checkout_input(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Some(Uuid::new_v4()),
        ))
        .await
        .unwrap_err();

    // Check the rejection is decided before any hold is created
    assert!(
        matches!(err, EnrollmentError::Rejected(message) if message == "questionnaire answers are required")
    );
}

// Helpers.

/// Expects the active-event guard and the event summary read used by attendance.
fn expect_active_event(db: &mut MockDB, community_id: Uuid, event_id: Uuid, event: EventSummary) {
    db.expect_ensure_event_is_active()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(|_, _| Ok(()));
    db.expect_get_event_summary_by_id()
        .times(1)
        .withf(move |cid, eid| *cid == community_id && *eid == event_id)
        .returning(move |_, _| Ok(event.clone()));
}

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

/// Builds a free-text answer for the given question.
fn sample_answers(question_id: Uuid) -> QuestionnaireAnswers {
    QuestionnaireAnswers {
        answers: vec![QuestionnaireAnswer {
            question_id,
            value: QuestionnaireAnswerValue::One("Vegetarian".to_string()),
        }],
    }
}

/// Builds an attendance input for the given selection.
fn sample_attend_input(
    community_id: Uuid,
    event_id: Uuid,
    user_id: Uuid,
    event_ticket_type_id: Option<Uuid>,
    registration_answers: Option<QuestionnaireAnswers>,
) -> AttendEventInput {
    AttendEventInput {
        attendance: EventAttendanceInput {
            event_ticket_type_id,
            registration_answers: OptionalQuestionnaireAnswersForm {
                registration_answers,
            },
        },
        community_id,
        event_id,
        user_id,
    }
}

/// Builds a leave input with fresh identifiers.
fn sample_leave_input() -> LeaveEventInput {
    LeaveEventInput {
        community_id: Uuid::new_v4(),
        event_id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
    }
}

/// Creates an enrollment manager with the supplied test doubles.
fn sample_manager(
    db: MockDB,
    notifications_manager: MockNotificationsManager,
    payments_manager: MockPaymentsManager,
) -> PgEnrollmentManager {
    PgEnrollmentManager::new(
        Arc::new(db),
        Arc::new(notifications_manager),
        Arc::new(payments_manager),
        HttpServerConfig::default(),
    )
}

/// Builds an organizer cancellation input with fresh identifiers.
fn sample_organizer_cancellation_input() -> OrganizerCancellationInput {
    OrganizerCancellationInput {
        actor_user_id: Uuid::new_v4(),
        community_id: Uuid::new_v4(),
        event_id: Uuid::new_v4(),
        group_id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
    }
}

/// Creates a payments manager mock reporting the given configured provider.
fn sample_payments_manager(provider: Option<PaymentProvider>) -> MockPaymentsManager {
    // Setup payments manager mock
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_configured_provider().return_const(provider);
    payments_manager
}

/// Builds a prepared checkout around the given purchase.
fn sample_prepared_checkout(
    event_id: Uuid,
    purchase: EventPurchaseSummary,
) -> PreparedEventCheckout {
    PreparedEventCheckout {
        community_name: "test-community".to_string(),
        event_id,
        event_slug: "event".to_string(),
        group_slug: "group".to_string(),
        purchase,

        ..PreparedEventCheckout::default()
    }
}

/// Builds a purchase summary in the given status.
fn sample_purchase_summary(
    event_purchase_id: Uuid,
    status: EventPurchaseStatus,
) -> EventPurchaseSummary {
    EventPurchaseSummary {
        amount_minor: 2_500,
        currency_code: Some("USD".to_string()),
        event_purchase_id,
        status,
        ticket_title: "General admission".to_string(),

        ..EventPurchaseSummary::default()
    }
}

/// Builds a required free-text registration question.
fn sample_question(question_id: Uuid) -> QuestionnaireQuestion {
    QuestionnaireQuestion {
        id: question_id,
        kind: QuestionnaireQuestionKind::FreeText,
        prompt: "Meal preference".to_string(),
        required: true,

        options: vec![],
    }
}

/// Builds a checkout input for the given selection.
fn sample_start_checkout_input(
    community_id: Uuid,
    event_id: Uuid,
    user_id: Uuid,
    event_ticket_type_id: Option<Uuid>,
) -> StartCheckoutInput {
    StartCheckoutInput {
        checkout: CheckoutInput {
            event_ticket_type_id,
            ..CheckoutInput::default()
        },
        community_id,
        event_id,
        user_id,
    }
}

/// Builds a public ticket type with the given price and availability.
fn sample_ticket_type(
    event_ticket_type_id: Uuid,
    amount_minor: i64,
    sold_out: bool,
) -> EventTicketType {
    EventTicketType {
        active: true,
        availability: EventTicketTypeAvailability::Public,
        event_ticket_type_id,
        order: 1,
        title: "General admission".to_string(),

        current_price: Some(EventTicketCurrentPrice {
            amount_minor,

            ends_at: None,
            starts_at: None,
        }),
        remaining_seats: Some(if sold_out { 0 } else { 10 }),
        seats_total: Some(10),
        sold_out,
        ..EventTicketType::default()
    }
}
