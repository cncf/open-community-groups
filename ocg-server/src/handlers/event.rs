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
    db::{DBExt, DynDB, payments::PrepareEventCheckoutPurchaseInput},
    handlers::{
        extractors::{CurrentUser, ValidatedForm, ValidatedFormQs},
        request_matches_site,
        site::not_found,
        trim_public_gallery_images,
    },
    router::{CACHE_CONTROL_NO_STORE, PUBLIC_SHARED_CACHE_HEADERS},
    services::{
        notifications::{
            DynNotificationsManager,
            enqueue::enqueue_event_attendance_cancellation_notifications,
            payloads::{
                build_event_waitlist_joined_notification, build_event_waitlist_left_notification,
                build_event_welcome_notification,
            },
        },
        payments::{DynPaymentsManager, RequestRefundInput},
    },
    templates::{
        PageId,
        auth::User,
        event::{CfsModal, CheckInPage, Page},
    },
    types::{
        event::{EventAttendanceStatus, EventFull, EventSummary},
        payments::{EventPurchaseStatus, EventTicketType, PreparedEventCheckout},
        questionnaire::{
            OptionalQuestionnaireAnswersForm, QuestionnaireAnswers, QuestionnaireQuestion,
        },
    },
    validation::{
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_EVENT_LABELS_PER_SUBMISSION, MAX_LEN_S,
        trimmed_non_empty_opt,
    },
};

use super::{error::HandlerError, extractors::AllianceId};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the event page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug, event_slug)): Path<(String, String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get alliance and site settings
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    // Fetch event page data
    let event = db
        .get_event_full_by_slug(alliance_id, &group_slug, &event_slug)
        .await?;
    let Some(mut event) = event else {
        return not_found::render(site_settings);
    };

    // Redirect generated group slugs to their pretty URL
    if should_redirect_to_pretty_group_slug(&event, &group_slug) {
        let url = public_event_url(&alliance_name, event.group.public_slug(), &event.slug, &uri);
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

/// Handler that renders the check-in page.
#[instrument(skip_all, err)]
pub(crate) async fn check_in_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get site settings and event details
    let (event, site_settings, attendance, check_in_window_open) = tokio::try_join!(
        db.get_event_summary_by_id(alliance_id, event_id),
        db.get_site_settings(),
        db.get_event_attendance(alliance_id, event_id, user.user_id),
        db.is_event_check_in_window_open(alliance_id, event_id),
    )?;

    // Prepare template
    let template = CheckInPage {
        check_in_window_open,
        event,
        page_id: PageId::CheckIn,
        path: uri.path().to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
        user_is_attendee: attendance.status == EventAttendanceStatus::Attendee,
        user_is_checked_in: attendance.is_checked_in,
    };

    Ok(Html(template.render()?))
}

/// Handler that renders the CFS submission modal.
#[instrument(skip_all, err)]
pub(crate) async fn cfs_modal(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user_id = auth_session.user.as_ref().map(|user| user.user_id);
    let user = User::from_session(auth_session).await?;

    // Get event details, labels and user's session proposals
    let (event, labels, session_proposals) = tokio::try_join!(
        db.get_event_summary_by_id(alliance_id, event_id),
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
    AllianceId(alliance_id): AllianceId,
    Path((_, group_slug, event_slug)): Path<(String, String, String)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get current public event availability
    let event = db
        .get_event_full_by_slug(alliance_id, &group_slug, &event_slug)
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
pub(crate) async fn attend_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<OptionalQuestionnaireAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate that the event is still attendee-visible before checking ticketing
    ensure_attendee_event_is_active(&db, alliance_id, event_id).await?;

    // Require checkout before users can RSVP to ticketed events
    let event = db.get_event_summary_by_id(alliance_id, event_id).await?;
    if event.is_ticketed() {
        return Err(anyhow::anyhow!("ticketed events must be purchased before attending").into());
    }

    // Users joining a waitlist answer registration questions only after promotion.
    let waitlist_join_without_answers = !event.attendee_approval_required
        && event.waitlist_enabled
        && event.remaining_capacity == Some(0);
    if !waitlist_join_without_answers {
        // Get registration questions and validate answers
        let registration_questions =
            db.get_event_registration_questions(alliance_id, event_id).await?;
        validate_registration_answers(
            input.registration_answers.as_ref(),
            &registration_questions,
        )?;
    }

    // Attend event
    let attend_result = db
        .attend_event(
            alliance_id,
            event_id,
            user.user_id,
            input.registration_answers,
        )
        .await?;
    let response = (
        StatusCode::OK,
        Json(json!({
            "status": &attend_result,
        })),
    );

    // Enqueue attendee or waitlist notification best-effort after the RSVP succeeds

    // Get site settings and event details for notifications
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(alliance_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event notification context after attendance change");
            return Ok(response);
        }
    };

    // Build the notification that matches the new attendance status
    let notification_result = match &attend_result {
        EventAttendanceStatus::Attendee => {
            // Confirm the RSVP with the event details and calendar attachment
            match build_event_welcome_notification(
                &event,
                user.user_id,
                &server_cfg,
                &site_settings,
                true,
            ) {
                Ok(notification) => notifications_manager.enqueue(&notification).await,
                Err(err) => {
                    warn!(error = %err, "failed to build event welcome notification");
                    Ok(())
                }
            }
        }
        EventAttendanceStatus::InvitationApproved
        | EventAttendanceStatus::PendingApproval
        | EventAttendanceStatus::PendingPayment
        | EventAttendanceStatus::RegistrationQuestionsPending
        | EventAttendanceStatus::Rejected => Ok(()),
        EventAttendanceStatus::Waitlisted => {
            // Let the user know they were added to the waitlist
            match build_event_waitlist_joined_notification(
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
            }
        }
        EventAttendanceStatus::None => {
            unreachable!("attend_event cannot return an unattached attendance status")
        }
    };

    if let Err(err) = notification_result {
        warn!(error = %err, "failed to enqueue event attendance notification");
    }

    Ok(response)
}

/// Handler for checking event attendance status.
#[instrument(skip_all)]
pub(crate) async fn attendance_status(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load attendance status without failing when the event is stale or inactive
    let attendance = db.get_event_attendance(alliance_id, event_id, user.user_id).await?;
    let can_request_refund = if attendance.status == EventAttendanceStatus::Attendee
        && attendance
            .purchase_amount_minor
            .is_some_and(|purchase_amount_minor| purchase_amount_minor > 0)
        && attendance.refund_request_status.is_none()
    {
        let event = db.get_event_summary_by_id(alliance_id, event_id).await?;
        attendance.can_request_refund(event.starts_at)
    } else {
        false
    };

    Ok(Json(json!({
        "can_request_refund": can_request_refund,
        "is_checked_in": attendance.is_checked_in,
        "purchase_amount_minor": attendance.purchase_amount_minor,
        "refund_request_status": attendance.refund_request_status,
        "resume_checkout_url": attendance.resume_checkout_url,
        "status": attendance.status
    })))
}

/// Handler for canceling an active checkout hold.
#[instrument(skip_all)]
pub(crate) async fn cancel_checkout(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    db.cancel_event_checkout(alliance_id, event_id, user.user_id).await?;

    Ok((
        StatusCode::OK,
        Json(json!({
            "status": EventAttendanceStatus::None,
        })),
    ))
}

/// Handler that marks the authenticated attendee as checked in.
#[instrument(skip_all)]
pub(crate) async fn check_in(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check in event (bypass_window = false for user self check-in)
    db.check_in_event(alliance_id, event_id, user.user_id, false).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for leaving an event.
#[instrument(skip_all)]
pub(crate) async fn leave_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave event and enqueue required attendee cancellation notifications
    let required_notification_server_cfg = server_cfg.clone();
    let leave_result = db
        .as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Leave the event and collect any waitlist promotions
                let leave_result = tx.leave_event(alliance_id, event_id, user.user_id).await?;

                // Enqueue required cancellation and promotion notifications before committing
                if leave_result.left_status == EventAttendanceStatus::Attendee {
                    enqueue_event_attendance_cancellation_notifications(
                        tx,
                        &required_notification_server_cfg,
                        alliance_id,
                        event_id,
                        user.user_id,
                        leave_result.promoted_user_ids.clone(),
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
        EventAttendanceStatus::Waitlisted => {
            // Get site settings and event details for notifications
            let (site_settings, event) = match tokio::try_join!(
                db.get_site_settings(),
                db.get_event_summary_by_id(alliance_id, event_id)
            ) {
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
        EventAttendanceStatus::Attendee | EventAttendanceStatus::PendingApproval => {}
        _ => unreachable!("leave_event cannot return this left status"),
    }

    Ok(response)
}

/// Handler for requesting a refund.
#[instrument(skip_all, err)]
pub(crate) async fn request_refund(
    CurrentUser(user): CurrentUser,
    State(payments_manager): State<DynPaymentsManager>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<RefundRequestInput>,
) -> Result<impl IntoResponse, HandlerError> {
    payments_manager
        .request_refund(&RequestRefundInput {
            alliance_id,
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

/// Handler for starting or resuming a checkout for a ticketed event.
#[instrument(skip_all)]
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn start_checkout(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(payments_manager): State<DynPaymentsManager>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<CheckoutInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event
    load_checkoutable_event(&db, alliance_id, event_id).await?;

    // Get registration questions and validate answers
    let registration_questions = db.get_event_registration_questions(alliance_id, event_id).await?;
    validate_registration_answers(
        input.registration_answers.registration_answers.as_ref(),
        &registration_questions,
    )?;

    // Reserve a purchase hold for the attendee
    let prepared_checkout = create_checkout_hold(
        &db,
        alliance_id,
        event_id,
        payments_cfg.as_ref(),
        user.user_id,
        &input,
    )
    .await?;

    // Return early when the attendee already has a purchase state that should not reopen checkout
    if let Some(status) = get_checkout_status_response(prepared_checkout.purchase.status)? {
        return Ok((
            StatusCode::OK,
            Json(json!({
                "status": status,
            })),
        ));
    }

    // Finalize free tickets immediately and send welcome notification
    if prepared_checkout.purchase.amount_minor == 0 {
        payments_manager
            .complete_free_checkout(
                alliance_id,
                event_id,
                prepared_checkout.purchase.event_purchase_id,
                user.user_id,
            )
            .await?;

        return Ok((
            StatusCode::OK,
            Json(json!({
                "status": EventAttendanceStatus::Attendee,
            })),
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
            "status": EventAttendanceStatus::PendingPayment,
        })),
    ))
}

/// Handler for submitting a CFS proposal to an event.
#[instrument(skip_all, err)]
pub(crate) async fn submit_cfs_submission(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, event_id)): Path<(String, Uuid)>,
    ValidatedFormQs(input): ValidatedFormQs<CfsSubmissionInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user_id = auth_session
        .user
        .as_ref()
        .map(|user| user.user_id)
        .expect("user to be logged in");
    let user = User::from_session(auth_session).await?;

    // Add CFS submission to database
    db.add_cfs_submission(
        alliance_id,
        event_id,
        user_id,
        input.session_proposal_id,
        &input.label_ids,
    )
    .await?;

    // Prepare template
    let (event, labels, session_proposals) = tokio::try_join!(
        db.get_event_summary_by_id(alliance_id, event_id),
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
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker.track(Activity::EventView { event_id }).await?;
    }

    Ok(StatusCode::NO_CONTENT)
}

// Types.

/// Submitted CFS proposal form data.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CfsSubmissionInput {
    /// Labels selected by the submitter for this proposal.
    #[serde(default)]
    #[garde(length(max = MAX_LEN_EVENT_LABELS_PER_SUBMISSION))]
    label_ids: Vec<Uuid>,
    /// Session proposal being submitted to the event CFS.
    #[garde(skip)]
    session_proposal_id: Uuid,
}

/// Ticket checkout form data.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CheckoutInput {
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
    /// Whether the event has at least one ticket type selectable now.
    has_sellable_ticket_types: bool,
    /// Whether the event is live for attendee-facing access.
    is_live: bool,
    /// Whether the event has already ended or started without an end time.
    is_past: bool,
    /// Whether the event uses the ticketing flow.
    is_ticketed: bool,
    /// Current public availability for each ticket type.
    ticket_types: Vec<EventTicketAvailability>,
    /// Current number of users on the waiting list.
    waitlist_count: i32,
    /// Whether joining the waiting list is enabled.
    waitlist_enabled: bool,

    /// Maximum capacity for the event.
    capacity: Option<i32>,
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
            has_sellable_ticket_types: event.has_sellable_ticket_types(),
            is_live: event.is_live(),
            is_past: event.is_past(),
            is_ticketed: event.is_ticketed(),
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

    /// Current attendee-facing price label for this ticket type.
    current_price_label: Option<String>,
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

            current_price_label: payment_currency_code
                .and_then(|currency_code| ticket_type.formatted_current_price(currency_code)),
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
    alliance_id: Uuid,
    event_id: Uuid,
    payments_cfg: Option<&PaymentsConfig>,
    user_id: Uuid,
    input: &CheckoutInput,
) -> Result<PreparedEventCheckout, HandlerError> {
    // Require an explicit ticket selection before opening checkout
    let event_ticket_type_id = input
        .event_ticket_type_id
        .ok_or_else(|| HandlerError::Database("ticket type is required".to_string()))?;

    // Prepare the attendee's current checkout purchase state
    db.prepare_event_checkout_purchase(
        alliance_id,
        &PrepareEventCheckoutPurchaseInput {
            configured_provider: payments_cfg.map(PaymentsConfig::provider),
            discount_code: input.discount_code.clone(),
            event_id,
            event_ticket_type_id,
            registration_answers: input.registration_answers.registration_answers.clone(),
            user_id,
        },
    )
    .await
    .map_err(Into::into)
}

/// Ensures attendee-facing event flows only continue for active events.
async fn ensure_attendee_event_is_active(
    db: &DynDB,
    alliance_id: Uuid,
    event_id: Uuid,
) -> Result<(), HandlerError> {
    db.ensure_event_is_active(alliance_id, event_id).await.map_err(|err| {
        match HandlerError::from(err) {
            HandlerError::Other(err) if err.to_string() == "event not found or inactive" => {
                HandlerError::Database("event not found or inactive".to_string())
            }
            other => other,
        }
    })
}

/// Returns the attendee-facing status when checkout should not continue.
fn get_checkout_status_response(
    purchase_status: EventPurchaseStatus,
) -> Result<Option<EventAttendanceStatus>, HandlerError> {
    match purchase_status {
        EventPurchaseStatus::Completed => Ok(Some(EventAttendanceStatus::Attendee)),
        EventPurchaseStatus::Pending => Ok(None),
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
    alliance_id: Uuid,
    event_id: Uuid,
) -> Result<EventSummary, HandlerError> {
    // Stop checkout when the event is no longer attendee-visible
    ensure_attendee_event_is_active(db, alliance_id, event_id).await?;

    // Ensure the event actually offers attendee-purchasable tickets
    let event = db.get_event_summary_by_id(alliance_id, event_id).await?;
    if !event.is_ticketed() {
        return Err(anyhow::anyhow!("event does not use ticket purchases").into());
    }
    if !event.has_sellable_ticket_types() {
        return Err(HandlerError::Database(
            "tickets are currently unavailable for this event".to_string(),
        ));
    }

    Ok(event)
}

/// Builds a public event URL with the original query string, if present.
fn public_event_url(alliance_name: &str, group_slug: &str, event_slug: &str, uri: &Uri) -> String {
    let mut url = format!("/{alliance_name}/group/{group_slug}/event/{event_slug}");
    if let Some(query) = uri.query() {
        url.push('?');
        url.push_str(query);
    }

    url
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
