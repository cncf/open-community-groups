//! HTTP handlers for the event page.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, Uri, header::CACHE_CONTROL},
    response::{Html, IntoResponse, Redirect},
};
use garde::{Error as ValidationError, Path as ValidationPath, Report, Validate};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    auth::AuthSession,
    config::{HttpServerConfig, PaymentsConfig},
    db::{
        DBExt, DynDB,
        event::AttendEventResult,
        payments::{PrepareEventCheckoutPurchaseInput, PrepareEventCheckoutPurchaseResult},
    },
    handlers::{
        extractors::{CurrentUser, ValidatedForm, ValidatedFormQs},
        request_headers_match_site_origin,
        site::not_found,
        trim_public_gallery_images,
    },
    router::{CACHE_CONTROL_NO_STORE, PUBLIC_SHARED_CACHE_HEADERS},
    services::{
        notifications::{
            DynNotificationsManager,
            enqueue::enqueue_event_attendance_cancellation_notifications,
            load_event_notification_context,
            payloads::{
                build_event_waitlist_joined_notification, build_event_waitlist_left_notification,
            },
        },
        payments::{DynPaymentsManager, RequestRefundInput},
    },
    templates::{
        PageId,
        auth::User,
        event::{CfsModal, Page},
    },
    types::{
        event::{EventEnrollmentStatus, EventFull, EventSummary},
        payments::{EventPurchaseStatus, EventTicketType, PreparedEventCheckout},
        questionnaire::{
            OptionalQuestionnaireAnswersForm, QuestionnaireAnswers, QuestionnaireQuestion,
        },
    },
    validation::{
        MAX_EVENT_LABELS_PER_SUBMISSION, MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_S,
        trimmed_non_empty_opt,
    },
};

use super::{error::HandlerError, extractors::CommunityId};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the event page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((community_name, group_slug, event_slug)): Path<(String, String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get community and site settings
    let (community_id, site_settings) = tokio::try_join!(
        db.get_community_id_by_name(&community_name),
        db.get_site_settings()
    )?;
    let Some(community_id) = community_id else {
        return not_found::render(site_settings);
    };

    // Fetch event page data
    let event = db
        .get_event_full_by_slug(community_id, &group_slug, &event_slug)
        .await?;
    let Some(mut event) = event else {
        return not_found::render(site_settings);
    };

    // Redirect generated group slugs to their pretty URL
    if should_redirect_to_pretty_group_slug(&event, &group_slug) {
        let url = public_event_url(
            &community_name,
            event.group.public_slug(),
            &event.slug,
            &uri,
        );
        return Ok(Redirect::temporary(&url).into_response());
    }

    // Trim gallery media
    trim_public_gallery_images(&mut event.photos_urls);

    // Prepare template
    let template = Page {
        base_url: server_cfg.base_url,
        event,
        page_id: PageId::Event,
        path: uri.path().to_string(),
        site_settings,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

/// Handler that renders the CFS submission modal.
#[instrument(skip_all, err)]
pub(crate) async fn cfs_modal(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user_id = auth_session.user.as_ref().map(|user| user.user_id);
    let user = User::from_session(auth_session).await?;

    // Get event details, labels and user's session proposals
    let (event, labels, session_proposals) = tokio::try_join!(
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_cfs_labels(event_id),
        async {
            if let Some(user_id) = user_id {
                db.list_user_session_proposals_for_cfs_event(user_id, event_id).await
            } else {
                Ok(vec![])
            }
        }
    )?;

    // Prepare template
    let template = CfsModal {
        event,
        labels,
        session_proposals,
        user,
        notice: None,
    };

    Ok(Html(template.render()?))
}

// JSON handlers.

/// Handler that returns fresh public availability for the event page.
#[instrument(skip_all)]
pub(crate) async fn availability(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, group_slug, event_slug)): Path<(String, String, String)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get current public event availability
    let event = db
        .get_event_full_by_slug(community_id, &group_slug, &event_slug)
        .await?
        .ok_or(HandlerError::NotFound)?;

    // Prevent volatile seat availability from being cached
    let mut headers = HeaderMap::new();
    headers.insert(
        CACHE_CONTROL,
        HeaderValue::from_static(CACHE_CONTROL_NO_STORE),
    );

    Ok((headers, Json(EventAvailability::from_event(&event))).into_response())
}

// Actions handlers.

/// Handler for attending an event.
#[instrument(skip_all)]
#[allow(clippy::too_many_arguments, clippy::too_many_lines)]
pub(crate) async fn attend_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(payments_manager): State<DynPaymentsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
    ValidatedForm(input): ValidatedForm<EventAttendanceInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate that the event is still attendee-visible before loading its enrollment state
    ensure_attendee_event_is_active(&db, community_id, event_id).await?;

    let event = db.get_event_summary_by_id(community_id, event_id).await?;

    // Match the database fallback for clients that omit the sole public tier
    let event_ticket_type_id = input.event_ticket_type_id.or_else(|| {
        event
            .single_public_ticket_type()
            .map(|ticket_type| ticket_type.event_ticket_type_id)
    });

    // Defer waitlisted users' registration answers until promotion
    let waitlist_join_without_answers =
        should_defer_registration_answers(&event, event_ticket_type_id);
    if !waitlist_join_without_answers {
        // Get registration questions and validate answers
        let registration_questions =
            db.get_event_registration_questions(community_id, event_id).await?;
        validate_registration_answers(
            input.registration_answers.registration_answers.as_ref(),
            &registration_questions,
        )?;
    }

    // Attend event
    let registration_answers = input.registration_answers.registration_answers;
    let mut enrollment_status = match db
        .attend_event(
            community_id,
            event_id,
            user.user_id,
            registration_answers.clone(),
            event_ticket_type_id,
        )
        .await?
    {
        AttendEventResult::Conflict(conflict) => {
            return Ok((
                StatusCode::CONFLICT,
                Json(json!({
                    "conflict": conflict,
                })),
            ));
        }
        AttendEventResult::Enrollment(enrollment_status) => enrollment_status,
    };

    // Recollect answers when authoritative inventory changes from waitlist to checkout
    if waitlist_join_without_answers && enrollment_status == EventEnrollmentStatus::PendingPayment {
        let registration_questions =
            db.get_event_registration_questions(community_id, event_id).await?;
        if registration_answers.is_none() && !registration_questions.is_empty() {
            return Ok((
                StatusCode::CONFLICT,
                Json(json!({
                    "conflict": "registration-answers-required",
                })),
            ));
        }
        validate_registration_answers(registration_answers.as_ref(), &registration_questions)?;
    }

    // Complete or redirect every newly available direct ticket through checkout
    if enrollment_status == EventEnrollmentStatus::PendingPayment {
        let checkout_input = CheckoutInput {
            admission_offer_id: None,
            discount_code: None,
            event_ticket_type_id,
            registration_answers: OptionalQuestionnaireAnswersForm {
                registration_answers,
            },
        };
        let prepared_checkout = match create_checkout_hold(
            &db,
            community_id,
            event_id,
            payments_cfg.as_ref(),
            user.user_id,
            &checkout_input,
        )
        .await?
        {
            PrepareEventCheckoutPurchaseResult::Conflict(conflict) => {
                return Ok((
                    StatusCode::CONFLICT,
                    Json(json!({
                        "conflict": conflict,
                    })),
                ));
            }
            PrepareEventCheckoutPurchaseResult::Prepared(checkout) => *checkout,
        };

        // Resolve checkout states that no longer require payment orchestration
        if let Some(updated_enrollment_status) =
            get_checkout_status_response(prepared_checkout.purchase.status)?
        {
            enrollment_status = updated_enrollment_status;
        } else if prepared_checkout.purchase.amount_minor != 0 {
            // Return snapshot payment details for external pending purchases
            if prepared_checkout.purchase.charge_model.is_external() {
                return Ok((
                    StatusCode::OK,
                    Json(external_pending_payment_response(&prepared_checkout)),
                ));
            }

            // Create or reuse the provider redirect for a paid pending purchase
            let redirect_url = payments_manager
                .get_or_create_checkout_redirect_url(&prepared_checkout, user.user_id)
                .await?;

            // Return the redirect while the checkout hold remains active
            return Ok((
                StatusCode::OK,
                Json(json!({
                    "hold_expires_at": prepared_checkout.purchase.hold_expires_at,
                    "redirect_url": redirect_url,
                    "status": EventEnrollmentStatus::PendingPayment,
                })),
            ));
        } else {
            // Finalize the zero-price purchase and its attendee notification
            payments_manager
                .complete_free_checkout(
                    community_id,
                    event_id,
                    prepared_checkout.purchase.event_purchase_id,
                    user.user_id,
                )
                .await?;
            enrollment_status = EventEnrollmentStatus::Attendee;
        }
    }
    let response = (
        StatusCode::OK,
        Json(json!({
            "status": &enrollment_status,
        })),
    );

    if enrollment_status == EventEnrollmentStatus::Attendee {
        return Ok(response);
    }

    // Get site settings and event details for notifications
    let (event, site_settings) = match load_event_notification_context(
        db.as_ref(),
        community_id,
        event_id,
    )
    .await
    {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event notification context after attendance change");
            return Ok(response);
        }
    };

    // Notify the user only when this request added them to the waitlist
    let notification_result = match &enrollment_status {
        EventEnrollmentStatus::Waitlisted => match build_event_waitlist_joined_notification(
            &event,
            user.user_id,
            &server_cfg,
            &site_settings,
        ) {
            Ok(notification) => notifications_manager.enqueue(&notification).await,
            Err(err) => {
                warn!(error = %err, "failed to build event waitlist join notification");
                Ok(())
            }
        },
        EventEnrollmentStatus::None => {
            unreachable!("attend_event cannot return an unattached enrollment status")
        }
        _ => Ok(()),
    };

    if let Err(err) = notification_result {
        warn!(error = %err, "failed to enqueue event attendance notification");
    }

    Ok(response)
}

/// Handler for canceling an active checkout hold.
#[instrument(skip_all)]
pub(crate) async fn cancel_checkout(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, HandlerError> {
    db.cancel_event_checkout(
        community_id,
        event_id,
        user.user_id,
        payments_cfg.as_ref().map(PaymentsConfig::provider),
    )
    .await?;

    // Return the authoritative enrollment state restored by cancellation
    let enrollment = db.get_event_enrollment(community_id, event_id, user.user_id).await?;

    Ok((
        StatusCode::OK,
        Json(json!({
            "status": enrollment.status,
        })),
    ))
}

/// Handler that returns the current user's event enrollment state.
#[instrument(skip_all, err)]
pub(crate) async fn enrollment_state(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, HandlerError> {
    // Load enrollment state without failing when the event is stale or inactive
    let enrollment = db.get_event_enrollment(community_id, event_id, user.user_id).await?;
    let can_request_refund = if enrollment.status == EventEnrollmentStatus::Attendee
        && enrollment
            .purchase_amount_minor
            .is_some_and(|purchase_amount_minor| purchase_amount_minor > 0)
        && enrollment.refund_request_status.is_none()
    {
        let event = db.get_event_summary_by_id(community_id, event_id).await?;
        enrollment.can_request_refund(event.starts_at)
    } else {
        false
    };

    Ok(Json(json!({
        "admission_offer_id": enrollment.admission_offer_id,
        "can_request_refund": can_request_refund,
        "event_ticket_type_id": enrollment.event_ticket_type_id,
        "external_payment": enrollment.external_payment,
        "is_checked_in": enrollment.is_checked_in,
        "manually_invited": enrollment.manually_invited,
        "purchase_amount_minor": enrollment.purchase_amount_minor,
        "refund_rejection_reason": enrollment.refund_rejection_reason,
        "refund_request_status": enrollment.refund_request_status,
        "resume_checkout_url": enrollment.resume_checkout_url,
        "status": enrollment.status
    })))
}

/// Handler for leaving an event.
#[instrument(skip_all)]
pub(crate) async fn leave_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave event and enqueue required attendee cancellation notifications
    let payment_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);
    let required_notification_server_cfg = server_cfg.clone();
    let leave_result = db
        .as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Leave the event
                let leave_result = tx
                    .leave_event(community_id, event_id, user.user_id, payment_provider)
                    .await?;

                // Enqueue required cancellation notifications before committing
                if leave_result.left_status == EventEnrollmentStatus::Attendee {
                    enqueue_event_attendance_cancellation_notifications(
                        tx,
                        &required_notification_server_cfg,
                        community_id,
                        event_id,
                        user.user_id,
                    )
                    .await?;
                }

                Ok(leave_result)
            })
        })
        .await?;
    let response = (
        StatusCode::OK,
        Json(json!({
            "left_status": &leave_result.left_status
        })),
    );

    // Enqueue waitlist leave notifications best-effort
    match leave_result.left_status {
        EventEnrollmentStatus::Waitlisted => {
            // Get site settings and event details for notifications
            let (event, site_settings) = match load_event_notification_context(
                db.as_ref(),
                community_id,
                event_id,
            )
            .await
            {
                Ok(context) => context,
                Err(err) => {
                    warn!(error = %err, "failed to load event notification context after waitlist change");
                    return Ok(response);
                }
            };

            // Confirm the waitlist exit
            match build_event_waitlist_left_notification(
                &event,
                user.user_id,
                &server_cfg,
                &site_settings,
            ) {
                Ok(notification) => {
                    if let Err(err) = notifications_manager.enqueue(&notification).await {
                        warn!(error = %err, "failed to enqueue event waitlist leave notification");
                    }
                }
                Err(err) => {
                    warn!(error = %err, "failed to build event waitlist leave notification");
                }
            }
        }
        EventEnrollmentStatus::Attendee | EventEnrollmentStatus::PendingApproval => {}
        _ => unreachable!("leave_event cannot return this left status"),
    }

    Ok(response)
}

/// Handler for requesting a refund.
#[instrument(skip_all, err)]
pub(crate) async fn request_refund(
    CurrentUser(user): CurrentUser,
    State(payments_manager): State<DynPaymentsManager>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
    ValidatedForm(input): ValidatedForm<RefundRequestInput>,
) -> Result<impl IntoResponse, HandlerError> {
    payments_manager
        .request_refund(&RequestRefundInput {
            community_id,
            event_id,
            user_id: user.user_id,

            requested_reason: input.requested_reason.clone(),
        })
        .await?;

    Ok((
        StatusCode::OK,
        Json(json!({
            "status": "refund-requested",
        })),
    ))
}

/// Handler for starting or resuming event checkout.
#[instrument(skip_all)]
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn start_checkout(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(payments_manager): State<DynPaymentsManager>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
    ValidatedForm(input): ValidatedForm<CheckoutInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event
    load_checkoutable_event(&db, community_id, event_id).await?;

    // Get registration questions and validate answers
    let registration_questions =
        db.get_event_registration_questions(community_id, event_id).await?;
    validate_registration_answers(
        input.registration_answers.registration_answers.as_ref(),
        &registration_questions,
    )?;

    // Reserve a purchase hold for the attendee
    let prepared_checkout = match create_checkout_hold(
        &db,
        community_id,
        event_id,
        payments_cfg.as_ref(),
        user.user_id,
        &input,
    )
    .await?
    {
        PrepareEventCheckoutPurchaseResult::Conflict(conflict) => {
            return Ok((
                StatusCode::CONFLICT,
                Json(json!({
                    "conflict": conflict,
                })),
            ));
        }
        PrepareEventCheckoutPurchaseResult::Prepared(checkout) => *checkout,
    };

    // Return early when the attendee already has a purchase state that should not reopen checkout
    if let Some(enrollment_status) =
        get_checkout_status_response(prepared_checkout.purchase.status)?
    {
        return Ok((
            StatusCode::OK,
            Json(json!({
                "status": enrollment_status,
            })),
        ));
    }

    // Finalize free tickets immediately and send welcome notification
    if prepared_checkout.purchase.amount_minor == 0 {
        payments_manager
            .complete_free_checkout(
                community_id,
                event_id,
                prepared_checkout.purchase.event_purchase_id,
                user.user_id,
            )
            .await?;

        return Ok((
            StatusCode::OK,
            Json(json!({
                "status": EventEnrollmentStatus::Attendee,
            })),
        ));
    }

    // Return snapshot payment details for external pending purchases
    if prepared_checkout.purchase.charge_model.is_external() {
        return Ok((
            StatusCode::OK,
            Json(external_pending_payment_response(&prepared_checkout)),
        ));
    }

    // Reuse an existing provider checkout when possible, otherwise create and persist a new one
    let redirect_url = payments_manager
        .get_or_create_checkout_redirect_url(&prepared_checkout, user.user_id)
        .await?;

    // Return the payment redirect details while the ticket hold is still active
    Ok((
        StatusCode::OK,
        Json(json!({
            "hold_expires_at": prepared_checkout.purchase.hold_expires_at,
            "redirect_url": redirect_url,
            "status": EventEnrollmentStatus::PendingPayment,
        })),
    ))
}

/// Handler for submitting a CFS proposal to an event.
#[instrument(skip_all, err)]
pub(crate) async fn submit_cfs_submission(
    CurrentUser(user): CurrentUser,
    auth_session: AuthSession,
    State(db): State<DynDB>,
    Path((_, event_id)): Path<(String, Uuid)>,
    CommunityId(community_id): CommunityId,
    ValidatedFormQs(input): ValidatedFormQs<CfsSubmissionInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare the authenticated user context
    let user_id = user.user_id;
    let user = User::from_session(auth_session).await?;

    // Add CFS submission to database
    db.add_cfs_submission(
        community_id,
        event_id,
        user_id,
        input.session_proposal_id,
        &input.label_ids,
    )
    .await?;

    // Prepare template
    let (event, labels, session_proposals) = tokio::try_join!(
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_cfs_labels(event_id),
        db.list_user_session_proposals_for_cfs_event(user_id, event_id),
    )?;
    let template = CfsModal {
        event,
        labels,
        session_proposals,
        user,
        notice: Some("Submission received. We'll review it soon.".to_string()),
    };

    Ok(Html(template.render()?))
}

/// Tracks an event page view.
#[instrument(skip_all)]
pub(crate) async fn track_view(
    headers: HeaderMap,
    State(activity_tracker): State<DynActivityTracker>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Require same-origin evidence before accepting analytics activity
    if !request_headers_match_site_origin(&server_cfg, &headers)? {
        return Ok(StatusCode::FORBIDDEN);
    }

    // Record the verified page view
    activity_tracker.track(Activity::EventView { event_id }).await?;

    Ok(StatusCode::NO_CONTENT)
}

// Types.

/// Submitted CFS proposal form data.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CfsSubmissionInput {
    /// Labels selected by the submitter for this proposal.
    #[serde(default)]
    #[garde(length(max = MAX_EVENT_LABELS_PER_SUBMISSION))]
    label_ids: Vec<Uuid>,
    /// Session proposal being submitted to the event CFS.
    #[garde(skip)]
    session_proposal_id: Uuid,
}

/// Ticket checkout form data.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CheckoutInput {
    /// Admission offer being claimed by the attendee.
    #[garde(skip)]
    admission_offer_id: Option<Uuid>,
    /// Optional discount code entered by the attendee.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    discount_code: Option<String>,
    /// Ticket type selected by the attendee.
    #[garde(skip)]
    event_ticket_type_id: Option<Uuid>,
    /// Questionnaire answers encoded as JSON.
    #[serde(default, flatten)]
    #[garde(dive)]
    registration_answers: OptionalQuestionnaireAnswersForm,
}

/// Public RSVP, approval request, or waitlist form data.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct EventAttendanceInput {
    /// Ticket type selected by the attendee.
    #[garde(skip)]
    event_ticket_type_id: Option<Uuid>,
    /// Questionnaire answers encoded as JSON.
    #[serde(default, flatten)]
    #[garde(dive)]
    registration_answers: OptionalQuestionnaireAnswersForm,
}

/// Public event availability returned to hydrate cached event pages.
#[derive(Debug, Serialize)]
#[allow(clippy::struct_excessive_bools)]
struct EventAvailability {
    /// Whether attendance requests require organizer approval.
    attendee_approval_required: bool,
    /// Current number of event attendees.
    attendee_count: i32,
    /// Whether the event has been canceled.
    canceled: bool,
    /// Whether every public ticket type currently has a zero price.
    has_only_free_ticket_types: bool,
    /// Whether the event has at least one ticket type selectable now.
    has_sellable_ticket_types: bool,
    /// Whether the event page has at least one sold-out public ticket type.
    has_sold_out_ticket_types: bool,
    /// Whether the event page has at least one public ticket type.
    has_visible_ticket_types: bool,
    /// Whether the event is live for attendee-facing access.
    is_live: bool,
    /// Whether the event has already ended or started without an end time.
    is_past: bool,
    /// Whether the event can use the plain RSVP experience.
    is_simple_rsvp: bool,
    /// Whether any public ticket configuration can require payment.
    paid_capable: bool,
    /// Whether attendee registration is currently open.
    registration_window_open: bool,
    /// Current public availability for each ticket type.
    ticket_types: Vec<EventTicketAvailability>,
    /// Current number of users on the waiting list.
    waitlist_count: i32,
    /// Whether joining the waiting list is enabled.
    waitlist_enabled: bool,

    /// Maximum capacity for the event.
    capacity: Option<i32>,
    /// Message describing the configured registration window.
    registration_window_message: Option<String>,
    /// Disabled-control title explaining why registration is unavailable.
    registration_window_unavailable_title: Option<String>,
    /// Remaining capacity after subtracting registered attendees.
    remaining_capacity: Option<i32>,
}

impl EventAvailability {
    /// Builds a public availability payload from the current event state.
    fn from_event(event: &EventFull) -> Self {
        Self {
            attendee_approval_required: event.attendee_approval_required,
            attendee_count: event.attendee_count,
            canceled: event.canceled,
            has_only_free_ticket_types: event.has_only_free_visible_ticket_types(),
            has_sellable_ticket_types: event.has_sellable_ticket_types(),
            has_sold_out_ticket_types: event.has_sold_out_visible_ticket_types(),
            has_visible_ticket_types: event.has_visible_ticket_types(),
            is_live: event.is_live(),
            is_past: event.is_past(),
            is_simple_rsvp: event.has_single_free_public_ticket_type(),
            paid_capable: event.is_paid_capable(),
            registration_window_open: event.registration_window_is_open(),
            ticket_types: event
                .ticket_types
                .as_deref()
                .unwrap_or_default()
                .iter()
                .map(|ticket_type| {
                    EventTicketAvailability::from_ticket_type(
                        ticket_type,
                        event.payment_currency_code.as_deref(),
                    )
                })
                .collect(),
            waitlist_count: event.waitlist_count,
            waitlist_enabled: event.waitlist_enabled,

            capacity: event.capacity,
            registration_window_message: event.registration_window_message(),
            registration_window_unavailable_title: event.registration_window_unavailable_title(),
            remaining_capacity: event.remaining_capacity,
        }
    }
}

/// Public ticket type availability returned to hydrate cached event pages.
#[derive(Debug, Serialize)]
struct EventTicketAvailability {
    /// Whether the ticket type is active.
    active: bool,
    /// Unique identifier for the ticket type.
    event_ticket_type_id: Uuid,
    /// Whether attendees can currently select this ticket type.
    is_sellable_now: bool,
    /// Whether all seats for this ticket type are currently reserved.
    sold_out: bool,
    /// Ticket type display name.
    title: String,

    /// Current attendee-facing price label for this ticket type.
    current_price_label: Option<String>,
    /// Current ticket price in minor units.
    current_price_minor: Option<i64>,
    /// Optional subtitle shown below the ticket type name.
    description: Option<String>,
    /// Number of seats still available for this ticket type.
    remaining_seats: Option<i32>,
}

impl EventTicketAvailability {
    /// Builds a public availability payload for one ticket type.
    fn from_ticket_type(
        ticket_type: &EventTicketType,
        payment_currency_code: Option<&str>,
    ) -> Self {
        Self {
            active: ticket_type.active,
            event_ticket_type_id: ticket_type.event_ticket_type_id,
            is_sellable_now: ticket_type.is_sellable_now(),
            sold_out: ticket_type.sold_out,
            title: ticket_type.title.clone(),

            current_price_label: match ticket_type.current_amount_minor() {
                Some(0) => Some("Free".to_string()),
                Some(_) => payment_currency_code
                    .and_then(|currency_code| ticket_type.formatted_current_price(currency_code)),
                None => None,
            },
            current_price_minor: ticket_type.current_amount_minor(),
            description: ticket_type.description.clone(),
            remaining_seats: ticket_type.remaining_seats,
        }
    }
}

/// Refund request form data.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct RefundRequestInput {
    /// Optional reason provided by the attendee.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    requested_reason: Option<String>,
}

// Helpers.

/// Creates or reuses a pending checkout hold for the attendee.
async fn create_checkout_hold(
    db: &DynDB,
    community_id: Uuid,
    event_id: Uuid,
    payments_cfg: Option<&PaymentsConfig>,
    user_id: Uuid,
    input: &CheckoutInput,
) -> Result<PrepareEventCheckoutPurchaseResult, HandlerError> {
    // Require an explicit ticket selection before opening checkout
    let event_ticket_type_id = input
        .event_ticket_type_id
        .ok_or_else(|| HandlerError::Database("ticket type is required".to_string()))?;

    // Prepare the attendee's current checkout purchase state
    db.prepare_event_checkout_purchase(
        community_id,
        &PrepareEventCheckoutPurchaseInput {
            event_id,
            event_ticket_type_id,
            platform_fee_bps: payments_cfg
                .map(PaymentsConfig::platform_fee_bps)
                .map_or(0, i32::from),
            user_id,

            admission_offer_id: input.admission_offer_id,
            discount_code: input.discount_code.clone(),
            payment_provider: payments_cfg.map(PaymentsConfig::provider),
            registration_answers: input.registration_answers.registration_answers.clone(),
        },
    )
    .await
    .map_err(HandlerError::from)
}

/// Ensures attendee-facing event flows only continue for active events.
async fn ensure_attendee_event_is_active(
    db: &DynDB,
    community_id: Uuid,
    event_id: Uuid,
) -> Result<(), HandlerError> {
    db.ensure_event_is_active(community_id, event_id)
        .await
        .map_err(|err| match HandlerError::from(err) {
            HandlerError::Other(err) if err.to_string() == "event not found or inactive" => {
                HandlerError::Database("event not found or inactive".to_string())
            }
            other => other,
        })
}

/// Builds the attendee-facing pending-payment payload for an external purchase.
fn external_pending_payment_response(
    prepared_checkout: &PreparedEventCheckout,
) -> serde_json::Value {
    json!({
        "external_payment": {
            "amount_minor": prepared_checkout.purchase.amount_minor,
            "currency_code": prepared_checkout.purchase.currency_code,
            "deadline": prepared_checkout.purchase.hold_expires_at.map(|deadline| deadline.timestamp()),
            "instructions": prepared_checkout.purchase.external_payment_instructions,
            "reference": prepared_checkout.purchase.event_purchase_id,
            "url": prepared_checkout.purchase.external_payment_url,
        },
        "hold_expires_at": prepared_checkout
            .purchase
            .hold_expires_at
            .map(|deadline| deadline.timestamp()),
        "status": EventEnrollmentStatus::PendingPayment,
    })
}

/// Returns the attendee-facing status when checkout should not continue.
fn get_checkout_status_response(
    purchase_status: EventPurchaseStatus,
) -> Result<Option<EventEnrollmentStatus>, HandlerError> {
    match purchase_status {
        EventPurchaseStatus::Completed => Ok(Some(EventEnrollmentStatus::Attendee)),
        EventPurchaseStatus::Pending => Ok(None),
        EventPurchaseStatus::RefundRecoveryPending => Err(HandlerError::Database(
            "checkout is unavailable while refund recovery is in progress".to_string(),
        )),
        EventPurchaseStatus::RefundRequested => Err(HandlerError::Database(
            "checkout is unavailable while a refund is in progress".to_string(),
        )),
        _ => Err(HandlerError::Database(
            "checkout is unavailable for this purchase".to_string(),
        )),
    }
}

/// Loads an event and ensures it currently supports attendee checkout.
async fn load_checkoutable_event(
    db: &DynDB,
    community_id: Uuid,
    event_id: Uuid,
) -> Result<EventSummary, HandlerError> {
    // Stop checkout when the event is no longer attendee-visible
    ensure_attendee_event_is_active(db, community_id, event_id).await?;

    // The DB validates ticket and hold availability for every event
    db.get_event_summary_by_id(community_id, event_id)
        .await
        .map_err(HandlerError::from)
}

/// Builds a public event URL with the original query string, if present.
fn public_event_url(community_name: &str, group_slug: &str, event_slug: &str, uri: &Uri) -> String {
    let mut url = format!("/{community_name}/group/{group_slug}/event/{event_slug}");
    if let Some(query) = uri.query() {
        url.push('?');
        url.push_str(query);
    }

    url
}

/// Returns whether registration answers should be deferred until waitlist promotion.
fn should_defer_registration_answers(
    event: &EventSummary,
    event_ticket_type_id: Option<Uuid>,
) -> bool {
    !event.attendee_approval_required
        && event.waitlist_enabled
        && event_ticket_type_id.is_some_and(|event_ticket_type_id| {
            event
                .ticket_types
                .as_deref()
                .unwrap_or_default()
                .iter()
                .any(|ticket_type| {
                    ticket_type.event_ticket_type_id == event_ticket_type_id && ticket_type.sold_out
                })
        })
}

/// Returns whether a public event request should canonicalize to a pretty group slug.
fn should_redirect_to_pretty_group_slug(event: &EventFull, group_slug: &str) -> bool {
    event
        .group
        .slug_pretty
        .as_deref()
        .is_some_and(|_| group_slug == event.group.slug)
}

/// Validates submitted registration answers against the event questionnaire.
fn validate_registration_answers(
    registration_answers: Option<&QuestionnaireAnswers>,
    registration_questions: &[QuestionnaireQuestion],
) -> Result<(), HandlerError> {
    match registration_answers {
        Some(answers) => answers
            .validate_against_questions(registration_questions)
            .map_err(validation_error),
        None if registration_questions.is_empty() => Ok(()),
        None => Err(validation_error("questionnaire answers are required")),
    }
}

/// Builds a validation error for registration answer checks.
fn validation_error(message: impl Into<String>) -> HandlerError {
    let mut report = Report::new();
    report.append(
        ValidationPath::new("registration_answers"),
        ValidationError::new(message.into()),
    );
    HandlerError::Validation(report)
}
