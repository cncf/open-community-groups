//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, RawQuery, State},
    http::{
        StatusCode,
        header::{CONTENT_DISPOSITION, CONTENT_TYPE},
    },
    response::{Html, IntoResponse, Response},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, PaymentsConfig},
    db::{
        DBExt, DynDB,
        dashboard::group::{
            EventAdmissionAllocationResult, EventAttendeeCancellationStatus,
            EventAttendeeInvitationInput,
        },
        notifications::CustomNotificationTracking,
    },
    handlers::{
        error::HandlerError,
        extractors::{
            CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm, ValidatedFormQs,
        },
    },
    router::serde_qs_config,
    services::{
        notifications::{
            NewNotification, NotificationKind,
            enqueue::enqueue_event_attendance_cancellation_notifications,
            load_event_notification_context,
        },
        payments::{ApproveRefundRequestInput, DynPaymentsManager, RejectRefundRequestInput},
    },
    templates::{
        dashboard::group::attendees::{
            self, Attendee, AttendeeEnrollmentStatus, AttendeeEnrollmentStatusFilter,
            AttendeesFilters,
        },
        notifications::EventCustom,
    },
    types::{
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
        questionnaire::QuestionnaireQuestion,
    },
    util::base_url_without_trailing_slash,
    validation::{
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_M, MAX_LEN_NOTIFICATION_BODY, trimmed_non_empty,
        trimmed_non_empty_opt,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the list of attendees for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Parse and validate attendee filters
    let filters: AttendeesFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    filters.validate()?;

    // Load permissions and attendee context concurrently
    let (
        can_manage_check_ins,
        can_manage_events,
        event,
        registration_questions,
        search_attendees_results,
    ) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::CheckInsWrite
        ),
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary_dashboard(community_id, group_id, event_id),
        db.get_event_registration_questions(community_id, event_id),
        db.search_event_attendees(group_id, event_id, &filters)
    )?;

    // Prepare pagination and template context
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        search_attendees_results.total,
        &format!("/dashboard/group/events/{event_id}/attendees"),
        &format!("/dashboard/group/events/{event_id}/attendees"),
    )?;
    let refresh_url = pagination::build_url(
        &format!("/dashboard/group/events/{event_id}/attendees"),
        &filters,
    )?;
    let status = filters.status.unwrap_or(if event.canceled {
        AttendeeEnrollmentStatusFilter::All
    } else {
        AttendeeEnrollmentStatusFilter::Current
    });
    let template = attendees::ListPage {
        all_attendees_email_recipient_total: search_attendees_results
            .all_attendees_email_recipient_total,
        attendees: search_attendees_results.attendees,
        can_manage_check_ins,
        can_manage_events,
        event,
        navigation_links,
        refresh_url,
        status,
        total: search_attendees_results.total,
        checked_in: filters.checked_in,
        event_ticket_type_ids: filters.event_ticket_type_ids,
        limit: filters.limit,
        offset: filters.offset,
        registration_questions,
        sort: filters.sort,
        title: filters.title,
        ts_query: filters.ts_query,
    };

    // Render the attendee list
    Ok(Html(template.render()?))
}

// Actions handlers.

/// Accepts an event invitation request.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn accept_invitation_request(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(_community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
    ValidatedForm(acceptance): ValidatedForm<EventInvitationRequestAcceptance>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept the request and allocate event admission
    let allocation = db
        .accept_event_invitation_request(
            user.user_id,
            group_id,
            event_id,
            user_id,
            acceptance.event_ticket_type_id,
            payments_cfg.as_ref().map(PaymentsConfig::provider),
        )
        .await?;

    Ok(event_admission_allocation_response(
        &allocation,
        StatusCode::NO_CONTENT,
        "refresh-event-attendees, refresh-event-invitation-requests",
    ))
}

/// Approves an attendee refund request.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn approve_refund_request(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(payments_manager): State<DynPaymentsManager>,
    Path(event_purchase_id): Path<Uuid>,
    ValidatedForm(review): ValidatedForm<RefundApprovalInput>,
) -> Result<impl IntoResponse, HandlerError> {
    payments_manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id: user.user_id,
            event_purchase_id,
            group_id,

            review_note: review.review_note.clone(),
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-group-refunds",
        )],
    )
        .into_response())
}

/// Cancels an active group-scoped admission offer.
#[instrument(skip_all, err)]
pub(crate) async fn cancel_event_admission_offer(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    Path(admission_offer_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Cancel the admission offer and reconcile released inventory
    db.cancel_event_admission_offer(
        user.user_id,
        group_id,
        admission_offer_id,
        payments_cfg.as_ref().map(PaymentsConfig::provider),
    )
    .await?;

    // Refresh every dashboard view affected by the cancellation
    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist",
        )],
    )
        .into_response())
}

/// Cancels free attendance or queues a paid attendance refund.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn cancel_event_attendee_attendance(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Apply the cancellation workflow and any immediate notification atomically
    let payment_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);
    let required_notification_server_cfg = server_cfg.clone();
    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Cancel free attendance or queue a paid refund
                let outcome = tx
                    .cancel_event_attendee_attendance(
                        user.user_id,
                        group_id,
                        event_id,
                        user_id,
                        payment_provider,
                    )
                    .await?;

                // Notify only after attendance is removed immediately
                if outcome.cancellation_status
                    == EventAttendeeCancellationStatus::AttendanceCanceled
                {
                    enqueue_event_attendance_cancellation_notifications(
                        tx,
                        &required_notification_server_cfg,
                        community_id,
                        event_id,
                        user_id,
                    )
                    .await?;
                }

                Ok(())
            })
        })
        .await?;

    // Refresh attendee and refund views after the transaction commits
    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-group-refunds",
        )],
    )
        .into_response())
}

/// Invites a user to attend an event.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn invite_event_attendee(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(_community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    Path(event_id): Path<Uuid>,
    ValidatedForm(invitation): ValidatedForm<EventAttendeeInvitation>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate target shape
    if (invitation.user_id.is_none() && invitation.email.is_none())
        || (invitation.user_id.is_some() && invitation.email.is_some())
    {
        return Ok((StatusCode::BAD_REQUEST, "provide exactly one invite target").into_response());
    }

    // Allocate the organizer invitation
    let payment_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);
    let invitation = EventAttendeeInvitationInput {
        email: invitation.email,
        event_ticket_type_id: invitation.event_ticket_type_id,
        user_id: invitation.user_id,
    };
    let allocation = db
        .invite_event_attendee(
            user.user_id,
            group_id,
            event_id,
            &invitation,
            payment_provider,
        )
        .await?;

    Ok(event_admission_allocation_response(
        &allocation,
        StatusCode::CREATED,
        "refresh-event-attendees, refresh-event-waitlist",
    ))
}

/// Manually checks in a confirmed attendee for an event.
#[instrument(skip_all, err)]
pub(crate) async fn manual_check_in(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate event belongs to the selected group
    db.get_event_summary(community_id, group_id, event_id).await?;

    // Check in with shared idempotent auditing
    db.check_in_event(user.user_id, community_id, event_id, user_id)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Rejects an event invitation request.
#[instrument(skip_all, err)]
pub(crate) async fn reject_invitation_request(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    db.reject_event_invitation_request(user.user_id, group_id, event_id, user_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-invitation-requests")],
    )
        .into_response())
}

/// Rejects an attendee refund request.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn reject_refund_request(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(payments_manager): State<DynPaymentsManager>,
    Path(event_purchase_id): Path<Uuid>,
    ValidatedForm(review): ValidatedForm<RefundRejectionInput>,
) -> Result<impl IntoResponse, HandlerError> {
    payments_manager
        .reject_refund_request(&RejectRefundRequestInput {
            actor_user_id: user.user_id,
            event_purchase_id,
            group_id,

            review_note: review.review_note.clone(),
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-group-refunds",
        )],
    )
        .into_response())
}

/// Requeues an exhausted retryable attendee refund.
#[instrument(skip_all, err)]
pub(crate) async fn retry_refund(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_purchase_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    db.requeue_event_purchase_refund(group_id, event_purchase_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-group-refunds",
        )],
    )
        .into_response())
}

/// Sends a custom notification to event attendees.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn send_event_custom_notification(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    ValidatedFormQs(notification): ValidatedFormQs<EventCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Normalize recipient scope input before resolving eligible recipients
    let requested_user_ids = match notification.recipient_scope {
        EventCustomNotificationRecipientScope::All => None,
        EventCustomNotificationRecipientScope::Selected => {
            if notification.recipient_user_ids.is_empty() {
                return Ok(
                    (StatusCode::BAD_REQUEST, "Select at least one attendee.").into_response()
                );
            }
            Some(notification.recipient_user_ids.clone())
        }
    };

    // Get event data and site settings
    let ((event, site_settings), event_attendees_ids) = tokio::try_join!(
        load_event_notification_context(db.as_ref(), community_id, event_id),
        db.resolve_event_custom_notification_recipient_ids(
            group_id,
            event_id,
            notification.recipient_scope.as_ref(),
            requested_user_ids
        ),
    )?;

    // Reject empty recipient sets so stale pages cannot report a false success
    if event_attendees_ids.is_empty() {
        let message = match notification.recipient_scope {
            EventCustomNotificationRecipientScope::All => {
                "No attendees with verified email addresses and email notifications enabled."
            }
            EventCustomNotificationRecipientScope::Selected => {
                "No selected attendees can receive this email."
            }
        };
        return Ok((StatusCode::BAD_REQUEST, message).into_response());
    }

    // Build and enqueue the custom notification with its audit entry
    let base_url = base_url_without_trailing_slash(&server_cfg.base_url);
    let link = format!(
        "{}/{}/group/{}/event/{}",
        base_url,
        event.community_name,
        event.public_group_slug(),
        event.slug
    );
    let template_data = EventCustom {
        body: notification.body.clone(),
        event,
        link,
        subject: notification.subject.clone(),
        theme: site_settings.theme,
    };
    let new_notification = NewNotification {
        attachments: vec![],
        kind: NotificationKind::EventCustom,
        recipients: event_attendees_ids,
        template_data: Some(serde_json::to_value(&template_data)?),
    };
    db.enqueue_tracked_custom_notification(
        &new_notification,
        CustomNotificationTracking {
            body: notification.body.clone(),
            created_by: user.user_id,
            event_id: Some(event_id),
            group_id: Some(group_id),
            recipient_count: new_notification.recipients.len(),
            subject: notification.subject.clone(),
        },
    )
    .await?;

    Ok(StatusCode::NO_CONTENT.into_response())
}

// Download handlers.

/// Downloads a CSV file with all attendees for a specific event.
#[instrument(skip_all, err)]
pub(crate) async fn download_csv(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary and all attendee rows
    let filters = AttendeesFilters::default();
    let (event, search_attendees_results) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_attendees(group_id, event_id, &filters)
    )?;

    // Build CSV payload without registration question answers
    let csv = build_attendees_csv(&search_attendees_results.attendees, None)?;
    let file_name = format!("event-{}-attendees.csv", event.slug);

    Ok((
        [
            (CONTENT_TYPE, "text/csv; charset=utf-8".to_string()),
            (
                CONTENT_DISPOSITION,
                format!("attachment; filename=\"{file_name}\""),
            ),
        ],
        csv,
    ))
}

/// Downloads a CSV file with attendees and their registration question answers.
#[instrument(skip_all, err)]
pub(crate) async fn download_csv_with_answers(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch event summary, registration questions, and all attendee rows
    let filters = AttendeesFilters::default();
    let (event, registration_questions, search_attendees_results) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id),
        db.get_event_registration_questions(community_id, event_id),
        db.search_event_attendees(group_id, event_id, &filters)
    )?;

    // Build CSV payload that also includes registration question answers
    let csv = build_attendees_csv(
        &search_attendees_results.attendees,
        Some(&registration_questions),
    )?;
    let file_name = format!("event-{}-attendees-with-answers.csv", event.slug);

    Ok((
        [
            (CONTENT_TYPE, "text/csv; charset=utf-8".to_string()),
            (
                CONTENT_DISPOSITION,
                format!("attachment; filename=\"{file_name}\""),
            ),
        ],
        csv,
    ))
}

// Types.

/// Form data for organizer-created event invitations.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct EventAttendeeInvitation {
    /// Email address used to create or reissue an invitation.
    #[garde(email, length(max = MAX_LEN_M))]
    pub email: Option<String>,
    /// Admission tier assigned to the organizer invitation.
    #[garde(skip)]
    pub event_ticket_type_id: Option<Uuid>,
    /// Existing registered user identifier.
    #[garde(skip)]
    pub user_id: Option<Uuid>,
}

/// Form data for custom event notifications.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct EventCustomNotification {
    /// Body text for the notification.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_NOTIFICATION_BODY))]
    pub body: String,
    /// Recipient scope for the notification.
    #[serde(default)]
    #[garde(skip)]
    pub recipient_scope: EventCustomNotificationRecipientScope,
    /// Selected recipient user identifiers.
    #[serde(default)]
    #[garde(skip)]
    pub recipient_user_ids: Vec<Uuid>,
    /// Subject line for the notification email.
    #[serde(alias = "title")]
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub subject: String,
}

/// Recipient scope for custom event notifications.
#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Serialize, strum::AsRefStr)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventCustomNotificationRecipientScope {
    /// Send to all attendees eligible for email.
    #[default]
    #[strum(serialize = "all-attendees")]
    All,
    /// Send only to selected attendees eligible for email.
    #[strum(serialize = "selected-attendees")]
    Selected,
}

/// Form data for accepting or reissuing an event invitation request.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct EventInvitationRequestAcceptance {
    /// Invitation-only ticket type assigned to a generic ticket request.
    #[garde(skip)]
    pub event_ticket_type_id: Option<Uuid>,
}

/// Form data for refund approvals.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct RefundApprovalInput {
    /// Optional internal note captured when approving a request.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub review_note: Option<String>,
}

/// Form data for refund rejections.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct RefundRejectionInput {
    /// Attendee-visible reason for rejecting the request.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub review_note: String,
}

// Helpers.

/// Builds the CSV payload for confirmed attendees, optionally appending one
/// column per registration question with the attendee's answer.
fn build_attendees_csv(
    attendees: &[Attendee],
    registration_questions: Option<&[QuestionnaireQuestion]>,
) -> Result<Vec<u8>, HandlerError> {
    let mut writer = csv::WriterBuilder::new()
        .terminator(csv::Terminator::Any(b'\n'))
        .from_writer(vec![]);

    // Write header row
    let mut headers = vec![
        "Name".to_string(),
        "Company".to_string(),
        "Title".to_string(),
        "Invited".to_string(),
    ];
    if let Some(questions) = registration_questions {
        headers.extend(questions.iter().map(|question| question.prompt.clone()));
    }
    writer.write_record(headers).map_err(anyhow::Error::from)?;

    // Write one row per confirmed attendee
    for attendee in attendees
        .iter()
        .filter(|attendee| attendee.enrollment_status == AttendeeEnrollmentStatus::Confirmed)
    {
        let mut row = vec![
            attendee
                .user
                .name
                .as_deref()
                .unwrap_or(&attendee.user.username)
                .to_string(),
            attendee.user.company.clone().unwrap_or_default(),
            attendee.user.title.clone().unwrap_or_default(),
            if attendee.manually_invited {
                "Yes"
            } else {
                "No"
            }
            .to_string(),
        ];
        if let Some(questions) = registration_questions {
            row.extend(
                questions
                    .iter()
                    .map(|question| question.format_answer(attendee.registration_answers.as_ref())),
            );
        }
        writer.write_record(row).map_err(anyhow::Error::from)?;
    }

    writer.into_inner().map_err(|err| anyhow::Error::from(err).into())
}

/// Converts an organizer allocation result into the stable HTTP contract.
fn event_admission_allocation_response(
    allocation: &EventAdmissionAllocationResult,
    success_status: StatusCode,
    success_trigger: &'static str,
) -> Response {
    match allocation {
        EventAdmissionAllocationResult::Conflict(conflict) => (
            StatusCode::CONFLICT,
            Json(json!({
                "conflict": conflict,
            })),
        )
            .into_response(),
        EventAdmissionAllocationResult::Success(_) => {
            (success_status, [("HX-Trigger", success_trigger)]).into_response()
        }
    }
}
