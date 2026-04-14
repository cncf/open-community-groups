//! HTTP handlers for the event page.

use askama::Template;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{Html, IntoResponse},
};
use chrono::Duration;
use garde::Validate;
use serde::Deserialize;
use serde_json::{json, to_value};
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    auth::AuthSession,
    config::{HttpServerConfig, PaymentsConfig},
    db::{DynDB, payments::PrepareEventCheckoutPurchaseInput},
    handlers::{
        extractors::{CurrentUser, ValidatedForm, ValidatedFormQs},
        prepare_headers, request_matches_site, trim_public_gallery_images,
    },
    services::{
        notifications::{DynNotificationsManager, NewNotification, NotificationKind},
        payments::{DynPaymentsManager, RequestRefundInput},
    },
    templates::{
        PageId,
        auth::User,
        event::{CfsModal, CheckInPage, Page},
        notifications::{EventWaitlistJoined, EventWaitlistLeft, EventWaitlistPromoted, EventWelcome},
    },
    types::{
        event::{EventAttendanceStatus, EventSummary},
        payments::{EventPurchaseStatus, EventPurchaseSummary},
    },
    util::{build_event_calendar_attachment, build_event_page_link},
    validation::{
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_EVENT_LABELS_PER_SUBMISSION, MAX_LEN_S, trimmed_non_empty_opt,
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
    CommunityId(community_id): CommunityId,
    Path((_, group_slug, event_slug)): Path<(String, String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (mut event, site_settings) = tokio::try_join!(
        db.get_event_full_by_slug(community_id, &group_slug, &event_slug),
        db.get_site_settings()
    )?;
    trim_public_gallery_images(&mut event.photos_urls);
    let template = Page {
        event,
        page_id: PageId::Event,
        path: uri.path().to_string(),
        site_settings,
        user: User::default(),
    };

    // Prepare response headers
    let headers = prepare_headers(Duration::hours(1), &[])?;

    Ok((headers, Html(template.render()?)))
}

/// Handler that renders the check-in page.
#[instrument(skip_all, err)]
pub(crate) async fn check_in_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get site settings and event details
    let (event, site_settings, attendance, check_in_window_open) = tokio::try_join!(
        db.get_event_summary_by_id(community_id, event_id),
        db.get_site_settings(),
        db.get_event_attendance(community_id, event_id, user.user_id),
        db.is_event_check_in_window_open(community_id, event_id),
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
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
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

// Actions handlers.

/// Handler for attending an event.
#[instrument(skip_all)]
pub(crate) async fn attend_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Require checkout before users can RSVP to ticketed events
    let event = db.get_event_summary_by_id(community_id, event_id).await?;
    if event.is_ticketed() {
        return Err(anyhow::anyhow!("ticketed events must be purchased before attending").into());
    }

    // Attend event
    let attend_result = db.attend_event(community_id, event_id, user.user_id).await?;
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
        db.get_event_summary_by_id(community_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event notification context after attendance change");
            return Ok(response);
        }
    };

    // Prepare the event page link for notifications
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = build_event_page_link(base_url, &event);

    // Build the notification that matches the new attendance status
    let notification_result = match &attend_result {
        EventAttendanceStatus::Attendee => {
            // Confirm the RSVP with the event details and calendar attachment
            let calendar_ics = build_event_calendar_attachment(base_url, &event);
            let template_data = EventWelcome {
                link: link.clone(),
                event: event.clone(),
                theme: site_settings.theme.clone(),
            };
            let notification = NewNotification {
                attachments: vec![calendar_ics],
                kind: NotificationKind::EventWelcome,
                recipients: vec![user.user_id],
                template_data: Some(to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await
        }
        EventAttendanceStatus::Waitlisted => {
            // Let the user know they were added to the waitlist
            let template_data = EventWaitlistJoined {
                event: event.clone(),
                link: link.clone(),
                theme: site_settings.theme.clone(),
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::EventWaitlistJoined,
                recipients: vec![user.user_id],
                template_data: Some(to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await
        }
        EventAttendanceStatus::PendingPayment => Ok(()),
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
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load attendance status and event summary
    let (attendance, event) = tokio::try_join!(
        db.get_event_attendance(community_id, event_id, user.user_id),
        db.get_event_summary_by_id(community_id, event_id),
    )?;

    Ok(Json(json!({
        "can_request_refund": attendance.can_request_refund(event.starts_at),
        "is_checked_in": attendance.is_checked_in,
        "purchase_amount_minor": attendance.purchase_amount_minor,
        "refund_request_status": attendance.refund_request_status,
        "resume_checkout_url": attendance.resume_checkout_url,
        "status": attendance.status
    })))
}

/// Handler that marks the authenticated attendee as checked in.
#[instrument(skip_all)]
pub(crate) async fn check_in(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check in event (bypass_window = false for user self check-in)
    db.check_in_event(community_id, event_id, user.user_id, false).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for leaving an event.
#[instrument(skip_all)]
pub(crate) async fn leave_event(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave event
    let leave_result = db.leave_event(community_id, event_id, user.user_id).await?;
    let response = (
        StatusCode::OK,
        Json(json!({
            "left_status": &leave_result.left_status
        })),
    );

    // Enqueue waitlist leave and promotion notifications best-effort after the leave action succeeds

    // Get site settings and event details for notifications
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event notification context after attendance change");
            return Ok(response);
        }
    };

    // Prepare the event page link for notifications
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
    let link = build_event_page_link(base_url, &event);

    // Only send a leave notification when the user exits the waitlist
    if leave_result.left_status == EventAttendanceStatus::Waitlisted {
        let template_data = EventWaitlistLeft {
            event: event.clone(),
            link: link.clone(),
            theme: site_settings.theme.clone(),
        };
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::EventWaitlistLeft,
            recipients: vec![user.user_id],
            template_data: Some(to_value(&template_data)?),
        };
        if let Err(err) = notifications_manager.enqueue(&notification).await {
            warn!(error = %err, "failed to enqueue event waitlist leave notification");
        }
    }

    // Notify users promoted off the waitlist after a spot opens up
    if !leave_result.promoted_user_ids.is_empty() {
        let calendar_ics = build_event_calendar_attachment(base_url, &event);
        let template_data = EventWaitlistPromoted {
            event: event.clone(),
            link: link.clone(),
            theme: site_settings.theme.clone(),
        };
        let notification = NewNotification {
            attachments: vec![calendar_ics],
            kind: NotificationKind::EventWaitlistPromoted,
            recipients: leave_result.promoted_user_ids.clone(),
            template_data: Some(to_value(&template_data)?),
        };
        if let Err(err) = notifications_manager.enqueue(&notification).await {
            warn!(error = %err, "failed to enqueue waitlist promotion notification");
        }
    }

    Ok(response)
}

/// Handler for requesting a refund.
#[instrument(skip_all, err)]
pub(crate) async fn request_refund(
    CurrentUser(user): CurrentUser,
    State(payments_manager): State<DynPaymentsManager>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
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

/// Handler for starting or resuming a checkout for a ticketed event.
#[instrument(skip_all)]
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_lines)]
pub(crate) async fn start_checkout(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(payments_manager): State<DynPaymentsManager>,
    CommunityId(community_id): CommunityId,
    Path((_, event_id)): Path<(String, Uuid)>,
    ValidatedForm(input): ValidatedForm<CheckoutInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the event and reserve a purchase hold for the attendee
    let event = load_checkoutable_event(&db, community_id, event_id).await?;
    let purchase = create_checkout_hold(
        &db,
        community_id,
        event_id,
        payments_cfg.as_ref(),
        user.user_id,
        &input,
    )
    .await?;

    // Return early when the attendee already has a purchase state that should not reopen checkout
    if let Some(status) = get_checkout_status_response(purchase.status)? {
        return Ok((
            StatusCode::OK,
            Json(json!({
                "status": status,
            })),
        ));
    }

    // Finalize free tickets immediately and send welcome notification
    if purchase.amount_minor == 0 {
        payments_manager
            .complete_free_checkout(community_id, event_id, purchase.event_purchase_id, user.user_id)
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
        .get_or_create_checkout_redirect_url(community_id, &event, &purchase, user.user_id)
        .await?;

    // Return the payment redirect details while the ticket hold is still active
    Ok((
        StatusCode::OK,
        Json(json!({
            "hold_expires_at": purchase.hold_expires_at,
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
    CommunityId(community_id): CommunityId,
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
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker.track(Activity::EventView { event_id }).await?;
    }

    Ok(StatusCode::NO_CONTENT)
}

// Types.

#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CfsSubmissionInput {
    #[serde(default)]
    #[garde(length(max = MAX_LEN_EVENT_LABELS_PER_SUBMISSION))]
    label_ids: Vec<Uuid>,
    #[garde(skip)]
    session_proposal_id: Uuid,
}

#[derive(Debug, Deserialize, Validate)]
pub(crate) struct CheckoutInput {
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_S))]
    discount_code: Option<String>,
    #[garde(skip)]
    event_ticket_type_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, Validate)]
pub(crate) struct RefundRequestInput {
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
) -> Result<EventPurchaseSummary, HandlerError> {
    db.prepare_event_checkout_purchase(
        community_id,
        &PrepareEventCheckoutPurchaseInput {
            configured_provider: payments_cfg.map(PaymentsConfig::provider),
            discount_code: input.discount_code.clone(),
            event_id,
            event_ticket_type_id: input
                .event_ticket_type_id
                .ok_or_else(|| anyhow::anyhow!("ticket type is required"))?,
            user_id,
        },
    )
    .await
    .map_err(Into::into)
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
    community_id: Uuid,
    event_id: Uuid,
) -> Result<EventSummary, HandlerError> {
    let event = db.get_event_summary_by_id(community_id, event_id).await?;
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
