//! HTTP handlers for the attendees section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{
        StatusCode,
        header::{CACHE_CONTROL, CONTENT_DISPOSITION, CONTENT_TYPE},
    },
    response::{Html, IntoResponse},
};
use garde::Validate;
use qrcode::render::svg;
use serde::{Deserialize, Serialize};
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, notifications::CustomNotificationTracking},
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::{
        notifications::{
            DynNotificationsManager, NewNotification, NotificationKind,
            helpers::{
                build_event_attendance_canceled_notification, build_event_invitation_notification,
                build_event_waitlist_promoted_notification, build_event_welcome_notification,
                should_send_waitlist_promoted_notification,
            },
        },
        payments::{ApproveRefundRequestInput, DynPaymentsManager, RejectRefundRequestInput},
    },
    templates::{
        dashboard::group::attendees::{
            self, Attendee, AttendeesFilters, AttendeesPaginationFilters,
        },
        notifications::EventCustom,
    },
    types::{
        pagination::NavigationLinks, permissions::GroupPermission,
        questionnaire::QuestionnaireQuestion,
    },
    validation::{
        MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_M, MAX_LEN_NOTIFICATION_BODY, trimmed_non_empty,
        trimmed_non_empty_opt,
    },
};

#[cfg(test)]
mod tests;

/// Status used for rows that represent confirmed event attendees.
const ATTENDEE_STATUS_CONFIRMED: &str = "confirmed";

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
    // Fetch event summary and attendees
    let page_filters: AttendeesPaginationFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let search_filters = AttendeesFilters {
        event_id,
        limit: page_filters.limit,
        offset: page_filters.offset,
    };
    let (can_manage_events, event, registration_questions, search_attendees_results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::EventsWrite
        ),
        db.get_event_summary(community_id, group_id, event_id),
        db.get_event_registration_questions(community_id, event_id),
        db.search_event_attendees(group_id, &search_filters)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &page_filters,
        search_attendees_results.total,
        &format!("/dashboard/group/events/{event_id}/attendees"),
        &format!("/dashboard/group/events/{event_id}/attendees"),
    )?;
    let template = attendees::ListPage {
        attendees: search_attendees_results.attendees,
        can_manage_events,
        event,
        navigation_links,
        notification_recipient_total: search_attendees_results.notification_recipient_total,
        registration_questions,
        total: search_attendees_results.total,
        limit: page_filters.limit,
        offset: page_filters.offset,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Accepts an event invitation request.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn accept_invitation_request(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    db.accept_event_invitation_request(user.user_id, group_id, event_id, user_id)
        .await?;

    // Load attendee welcome notification context after approval succeeds
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event invitation acceptance notification context");
            return Ok((
                StatusCode::NO_CONTENT,
                [(
                    "HX-Trigger",
                    "refresh-event-attendees, refresh-event-invitation-requests",
                )],
            )
                .into_response());
        }
    };

    // Send the attendee welcome notification
    match build_event_welcome_notification(&event, user_id, &server_cfg, &site_settings, true) {
        Ok(notification) => {
            if let Err(err) = notifications_manager.enqueue(&notification).await {
                warn!(error = %err, "failed to enqueue event invitation acceptance notification");
            }
        }
        Err(err) => {
            warn!(error = %err, "failed to build event invitation acceptance notification");
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-event-invitation-requests",
        )],
    )
        .into_response())
}

/// Approves an attendee refund request.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn approve_refund_request(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(payments_manager): State<DynPaymentsManager>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
    ValidatedForm(review): ValidatedForm<RefundReviewInput>,
) -> Result<impl IntoResponse, HandlerError> {
    payments_manager
        .approve_refund_request(&ApproveRefundRequestInput {
            actor_user_id: user.user_id,
            community_id,
            event_id,
            group_id,
            user_id,

            review_note: review.review_note.clone(),
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-attendees")],
    )
        .into_response())
}

/// Cancels a confirmed attendee's event attendance.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn cancel_event_attendee_attendance(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Cancel the attendee and collect any waitlist promotions
    let cancel_result = db
        .cancel_event_attendee_attendance(user.user_id, group_id, event_id, user_id)
        .await?;

    // Load notification context after cancellation succeeds
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event attendance cancellation notification context");
            return Ok((
                StatusCode::NO_CONTENT,
                [("HX-Trigger", "refresh-event-attendees")],
            )
                .into_response());
        }
    };

    // Confirm the canceled attendance to the attendee
    match build_event_attendance_canceled_notification(&event, user_id, &server_cfg, &site_settings)
    {
        Ok(notification) => {
            if let Err(err) = notifications_manager.enqueue(&notification).await {
                warn!(error = %err, "failed to enqueue event attendance cancellation notification");
            }
        }
        Err(err) => {
            warn!(error = %err, "failed to build event attendance cancellation notification");
        }
    }

    // Notify users promoted off the waitlist after a spot opens up
    if should_send_waitlist_promoted_notification(&event, &cancel_result.promoted_user_ids) {
        match build_event_waitlist_promoted_notification(
            &event,
            cancel_result.promoted_user_ids,
            &server_cfg,
            &site_settings,
        ) {
            Ok(notification) => {
                if let Err(err) = notifications_manager.enqueue(&notification).await {
                    warn!(error = %err, "failed to enqueue waitlist promotion notification");
                }
            }
            Err(err) => {
                warn!(error = %err, "failed to build waitlist promotion notification");
            }
        }
    }

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-attendees")],
    )
        .into_response())
}

/// Cancels a pending organizer-created event invitation.
#[instrument(skip_all, err)]
pub(crate) async fn cancel_event_attendee_invitation(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    db.cancel_event_attendee_invitation(user.user_id, group_id, event_id, user_id)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-attendees")],
    )
        .into_response())
}

/// Generates a QR code for event check-in.
#[instrument(skip_all, err)]
pub(crate) async fn generate_check_in_qr_code(
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get community name (cached) and ensure event belongs to selected group
    let (community_name, _) = tokio::try_join!(
        db.get_community_name_by_id(community_id),
        db.get_event_summary(community_id, group_id, event_id)
    )?;
    let Some(community_name) = community_name else {
        return Err(anyhow::anyhow!("community not found").into());
    };

    // Get base URL from configuration
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);

    // Construct check-in URL
    let check_in_url = format!("{base_url}/{community_name}/check-in/{event_id}");

    // Generate QR code
    let code = qrcode::QrCode::new(check_in_url.as_bytes())
        .map_err(|e| anyhow::anyhow!("Failed to generate QR code: {e}"))?;
    let svg = code
        .render()
        .min_dimensions(500, 500)
        .dark_color(svg::Color("#000000"))
        .light_color(svg::Color("#ffffff"))
        .build();

    // Prepare response headers
    let headers = [
        (CACHE_CONTROL, "private, max-age=3600"),
        (CONTENT_TYPE, "image/svg+xml"),
    ];

    // Return SVG response
    Ok((StatusCode::OK, headers, svg))
}

/// Invites a user to attend an event.
#[instrument(skip_all, err)]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn invite_event_attendee(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    Path(event_id): Path<Uuid>,
    ValidatedForm(invitation): ValidatedForm<EventAttendeeInvitation>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate target shape
    if (invitation.user_id.is_none() && invitation.email.is_none())
        || (invitation.user_id.is_some() && invitation.email.is_some())
    {
        return Ok((StatusCode::BAD_REQUEST, "provide exactly one invite target").into_response());
    }

    // Create the pending invitation
    let invited_user_id = db
        .invite_event_attendee(
            user.user_id,
            group_id,
            event_id,
            invitation.user_id,
            invitation.email,
        )
        .await?;

    // Load context and enqueue the invitation notification
    let (site_settings, event) = match tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id)
    ) {
        Ok(context) => context,
        Err(err) => {
            warn!(error = %err, "failed to load event invitation notification context");
            return Ok((
                StatusCode::CREATED,
                [(
                    "HX-Trigger",
                    "refresh-event-attendees, refresh-event-waitlist",
                )],
            )
                .into_response());
        }
    };
    match build_event_invitation_notification(&event, invited_user_id, &server_cfg, &site_settings)
    {
        Ok(notification) => {
            if let Err(err) = notifications_manager.enqueue(&notification).await {
                warn!(error = %err, "failed to enqueue event invitation notification");
            }
        }
        Err(err) => {
            warn!(error = %err, "failed to build event invitation notification");
        }
    }

    Ok((
        StatusCode::CREATED,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-event-waitlist",
        )],
    )
        .into_response())
}

/// Manually checks in a user for an event, bypassing the check-in window validation.
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

    // Check-in with dashboard-specific auditing
    db.manual_check_in_event(user.user_id, community_id, event_id, user_id)
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
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(payments_manager): State<DynPaymentsManager>,
    Path((event_id, user_id)): Path<(Uuid, Uuid)>,
    ValidatedForm(review): ValidatedForm<RefundReviewInput>,
) -> Result<impl IntoResponse, HandlerError> {
    payments_manager
        .reject_refund_request(&RejectRefundRequestInput {
            actor_user_id: user.user_id,
            community_id,
            event_id,
            group_id,
            user_id,

            review_note: review.review_note.clone(),
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-event-attendees")],
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
    ValidatedForm(notification): ValidatedForm<EventCustomNotification>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get event data and site settings
    let (site_settings, event, event_attendees_ids) = tokio::try_join!(
        db.get_site_settings(),
        db.get_event_summary_by_id(community_id, event_id),
        db.list_event_attendees_ids(group_id, event_id),
    )?;

    // Reject empty recipient sets so stale pages cannot report a false success
    if event_attendees_ids.is_empty() {
        return Ok((
            StatusCode::BAD_REQUEST,
            "No confirmed attendees with verified email addresses.",
        )
            .into_response());
    }

    // Build and enqueue the custom notification with its audit entry
    let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
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
    let search_filters = AttendeesFilters {
        event_id,
        limit: None,
        offset: None,
    };
    let (event, search_attendees_results) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id),
        db.search_event_attendees(group_id, &search_filters)
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
    let search_filters = AttendeesFilters {
        event_id,
        limit: None,
        offset: None,
    };
    let (event, registration_questions, search_attendees_results) = tokio::try_join!(
        db.get_event_summary(community_id, group_id, event_id),
        db.get_event_registration_questions(community_id, event_id),
        db.search_event_attendees(group_id, &search_filters)
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
    /// Email address for an unregistered invitee.
    #[garde(email, length(max = MAX_LEN_M))]
    pub email: Option<String>,
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
    /// Subject line for the notification email.
    #[serde(alias = "title")]
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub subject: String,
}

/// Form data for refund reviews.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct RefundReviewInput {
    /// Optional note captured when reviewing a request.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub review_note: Option<String>,
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
        .filter(|attendee| attendee.status == ATTENDEE_STATUS_CONFIRMED)
    {
        let mut row = vec![
            attendee.name.as_deref().unwrap_or(&attendee.username).to_string(),
            attendee.company.clone().unwrap_or_default(),
            attendee.title.clone().unwrap_or_default(),
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
