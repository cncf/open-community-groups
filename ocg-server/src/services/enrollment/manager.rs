//! Enrollment manager for event attendance and group membership workflows.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
#[cfg(test)]
use mockall::automock;
use tracing::warn;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{
        DBExt, DynDB,
        dashboard::group::{
            EventAdmissionAllocationResult, EventAttendeeCancellationStatus,
            EventAttendeeInvitationInput,
        },
        event::AttendEventResult,
    },
    services::{
        notifications::{
            DynNotificationsManager,
            best_effort::enqueue_event_notification_best_effort,
            enqueue::enqueue_event_attendance_cancellation_notifications,
            payloads::{
                build_event_waitlist_joined_notification, build_event_waitlist_left_notification,
            },
        },
        payments::{DynPaymentsManager, PaymentsError, PrepareCheckoutOutcome},
    },
    templates::notifications::GroupWelcome,
    types::{
        event::{EventAttendanceInput, EventEnrollmentStatus, EventLeaveOutcome, EventSummary},
        notifications::{NewNotification, NotificationKind},
        payments::{CheckoutInput, EventPurchaseStatus, PreparedEventCheckout},
        questionnaire::{
            OptionalQuestionnaireAnswersForm, QuestionnaireAnswers, QuestionnaireQuestion,
        },
    },
    util::base_url_without_trailing_slash,
};

#[cfg(test)]
mod contract_tests;
#[cfg(test)]
mod tests;

/// Conflict code returned when a checkout needs answers that were deferred.
const REGISTRATION_ANSWERS_REQUIRED_CONFLICT: &str = "registration-answers-required";

/// Trait implemented by the enrollment manager used by handlers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait EnrollmentManager {
    /// Accepts a pending invitation request and allocates event admission.
    async fn accept_invitation_request(
        &self,
        input: &AcceptInvitationRequestInput,
    ) -> Result<AdmissionAllocationOutcome, EnrollmentError>;

    /// Registers the user's attendance, waitlist entry, or checkout hold.
    async fn attend_event(
        &self,
        input: &AttendEventInput,
    ) -> Result<AttendOutcome, EnrollmentError>;

    /// Cancels an attendee's attendance on behalf of an organizer.
    ///
    /// Free attendance is removed immediately and the attendee is notified; paid
    /// attendance stays active while its refund is queued and sends nothing.
    async fn cancel_attendance_as_organizer(
        &self,
        input: &OrganizerCancellationInput,
    ) -> Result<(), EnrollmentError>;

    /// Invites a registered user or an email address to attend an event.
    async fn invite_event_attendee(
        &self,
        input: &InviteAttendeeInput,
    ) -> Result<AdmissionAllocationOutcome, EnrollmentError>;

    /// Adds the user to the group and welcomes them best-effort.
    async fn join_group(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), EnrollmentError>;

    /// Removes the user's own enrollment from an event.
    ///
    /// Attendees receive the required cancellation notification inside the
    /// same transaction; waitlisted users receive a best-effort confirmation.
    async fn leave_event(
        &self,
        input: &LeaveEventInput,
    ) -> Result<EventLeaveOutcome, EnrollmentError>;

    /// Removes the user from the group.
    async fn leave_group(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), EnrollmentError>;

    /// Starts or resumes checkout for the selected ticket.
    async fn start_checkout(
        &self,
        input: &StartCheckoutInput,
    ) -> Result<AttendOutcome, EnrollmentError>;
}

/// Shared enrollment manager trait object.
pub(crate) type DynEnrollmentManager = Arc<dyn EnrollmentManager + Send + Sync>;

/// PostgreSQL-backed enrollment manager implementation.
pub(crate) struct PgEnrollmentManager {
    /// Database handle for enrollment persistence.
    db: DynDB,
    /// Notifications manager used for best-effort notifications.
    notifications_manager: DynNotificationsManager,
    /// Payments manager used for checkout holds and provider redirects.
    payments_manager: DynPaymentsManager,
    /// Server configuration used to build notification links.
    server_cfg: HttpServerConfig,
}

impl PgEnrollmentManager {
    /// Creates a new `PgEnrollmentManager`.
    pub(crate) fn new(
        db: DynDB,
        notifications_manager: DynNotificationsManager,
        payments_manager: DynPaymentsManager,
        server_cfg: HttpServerConfig,
    ) -> Self {
        Self {
            db,
            notifications_manager,
            payments_manager,
            server_cfg,
        }
    }

    /// Reserves the attendee's checkout hold and resolves it into an outcome.
    ///
    /// Free tickets are completed immediately, external purchases return their
    /// payment snapshot, and provider-collected purchases return the checkout
    /// redirect while the hold remains active.
    async fn complete_checkout(
        &self,
        community_id: Uuid,
        event_id: Uuid,
        user_id: Uuid,
        checkout_input: &CheckoutInput,
    ) -> Result<AttendOutcome, EnrollmentError> {
        // Reserve a purchase hold for the attendee
        let prepared_checkout = match self
            .payments_manager
            .prepare_checkout(community_id, event_id, user_id, checkout_input)
            .await?
        {
            PrepareCheckoutOutcome::Conflict(conflict) => {
                return Ok(AttendOutcome::Conflict(conflict));
            }
            PrepareCheckoutOutcome::Prepared(prepared_checkout) => prepared_checkout,
        };

        // Resolve purchase states that must not reopen checkout
        if let Some(enrollment_status) =
            checkout_enrollment_status(prepared_checkout.purchase.status)?
        {
            return Ok(AttendOutcome::Enrolled(enrollment_status));
        }

        // Finalize zero-price purchases and welcome the attendee
        if prepared_checkout.purchase.amount_minor == 0 {
            self.payments_manager
                .complete_free_checkout(
                    community_id,
                    event_id,
                    prepared_checkout.purchase.event_purchase_id,
                    user_id,
                )
                .await?;
            return Ok(AttendOutcome::Enrolled(EventEnrollmentStatus::Attendee));
        }

        // Return snapshot payment details for external pending purchases
        if prepared_checkout.purchase.charge_model.is_external() {
            return Ok(AttendOutcome::ExternalPendingPayment(prepared_checkout));
        }

        // Create or reuse the provider redirect for a paid pending purchase
        let redirect_url = self
            .payments_manager
            .get_or_create_checkout_redirect_url(&prepared_checkout, user_id)
            .await?;

        Ok(AttendOutcome::CheckoutRedirect {
            hold_expires_at: prepared_checkout.purchase.hold_expires_at,
            redirect_url,
        })
    }

    /// Enqueues the group welcome notification best-effort after joining.
    async fn enqueue_group_welcome_notification(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        user_id: Uuid,
    ) {
        // Load the group and site context and enqueue the welcome
        let result: Result<()> = async {
            let (site_settings, group) = tokio::try_join!(
                self.db.get_site_settings(),
                self.db.get_group_summary(community_id, group_id)
            )?;
            let base_url = base_url_without_trailing_slash(&self.server_cfg.base_url);
            let template_data = GroupWelcome {
                link: format!(
                    "{}/{}/group/{}",
                    base_url,
                    group.community_name,
                    group.public_slug()
                ),
                group,
                theme: site_settings.theme,
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::GroupWelcome,
                recipients: vec![user_id],
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            self.notifications_manager.enqueue(&notification).await
        }
        .await;

        // Log the failure with the identifiers needed to reconstruct it
        if let Err(err) = result {
            warn!(
                error = %err,
                %community_id,
                %group_id,
                %user_id,
                "failed to enqueue group welcome notification"
            );
        }
    }
}

#[async_trait]
impl EnrollmentManager for PgEnrollmentManager {
    /// [`EnrollmentManager::accept_invitation_request`].
    async fn accept_invitation_request(
        &self,
        input: &AcceptInvitationRequestInput,
    ) -> Result<AdmissionAllocationOutcome, EnrollmentError> {
        let allocation = self
            .db
            .accept_event_invitation_request(
                input.actor_user_id,
                input.group_id,
                input.event_id,
                input.user_id,
                input.event_ticket_type_id,
                self.payments_manager.configured_provider(),
            )
            .await?;

        Ok(allocation.into())
    }

    /// [`EnrollmentManager::attend_event`].
    async fn attend_event(
        &self,
        input: &AttendEventInput,
    ) -> Result<AttendOutcome, EnrollmentError> {
        let AttendEventInput {
            community_id,
            event_id,
            user_id,
            ..
        } = *input;

        // Validate that the event is still attendee-visible before loading its state
        self.db.ensure_event_is_active(community_id, event_id).await?;
        let event = self.db.get_event_summary_by_id(community_id, event_id).await?;

        // Match the database fallback for clients that omit the sole public tier
        let event_ticket_type_id = input.attendance.event_ticket_type_id.or_else(|| {
            event
                .single_public_ticket_type()
                .map(|ticket_type| ticket_type.event_ticket_type_id)
        });

        // Defer waitlisted users' registration answers until promotion
        let registration_answers =
            input.attendance.registration_answers.registration_answers.clone();
        let waitlist_join_without_answers =
            should_defer_registration_answers(&event, event_ticket_type_id);
        if !waitlist_join_without_answers {
            let registration_questions = self
                .db
                .get_event_registration_questions(community_id, event_id)
                .await?;
            validate_registration_answers(registration_answers.as_ref(), &registration_questions)?;
        }

        // Register the attendance, waitlist entry, or checkout requirement
        let enrollment_status = match self
            .db
            .attend_event(
                community_id,
                event_id,
                user_id,
                registration_answers.clone(),
                event_ticket_type_id,
            )
            .await?
        {
            AttendEventResult::Conflict(conflict) => {
                return Ok(AttendOutcome::Conflict(conflict.to_string()));
            }
            AttendEventResult::Enrollment(enrollment_status) => enrollment_status,
        };

        // Recollect answers when authoritative inventory changed from waitlist to checkout
        if waitlist_join_without_answers
            && enrollment_status == EventEnrollmentStatus::PendingPayment
        {
            let registration_questions = self
                .db
                .get_event_registration_questions(community_id, event_id)
                .await?;
            if registration_answers.is_none() && !registration_questions.is_empty() {
                return Ok(AttendOutcome::Conflict(
                    REGISTRATION_ANSWERS_REQUIRED_CONFLICT.to_string(),
                ));
            }
            validate_registration_answers(registration_answers.as_ref(), &registration_questions)?;
        }

        // Complete or redirect every newly available direct ticket through checkout
        if enrollment_status == EventEnrollmentStatus::PendingPayment {
            let checkout_input = CheckoutInput {
                event_ticket_type_id,
                registration_answers: OptionalQuestionnaireAnswersForm {
                    registration_answers,
                },
                ..CheckoutInput::default()
            };
            return self
                .complete_checkout(community_id, event_id, user_id, &checkout_input)
                .await;
        }

        // Confirm the waitlist entry best-effort when this request created it
        if enrollment_status == EventEnrollmentStatus::Waitlisted {
            enqueue_event_notification_best_effort(
                self.db.as_ref(),
                &self.notifications_manager,
                &self.server_cfg,
                community_id,
                event_id,
                |event, server_cfg, site_settings| {
                    build_event_waitlist_joined_notification(
                        event,
                        user_id,
                        server_cfg,
                        site_settings,
                    )
                },
            )
            .await;
        }

        Ok(AttendOutcome::Enrolled(enrollment_status))
    }

    /// [`EnrollmentManager::cancel_attendance_as_organizer`].
    async fn cancel_attendance_as_organizer(
        &self,
        input: &OrganizerCancellationInput,
    ) -> Result<(), EnrollmentError> {
        let OrganizerCancellationInput {
            actor_user_id,
            community_id,
            event_id,
            group_id,
            user_id,
        } = *input;
        let payment_provider = self.payments_manager.configured_provider();
        let server_cfg = self.server_cfg.clone();

        // Apply the cancellation and any immediate notification atomically
        self.db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    // Cancel free attendance or queue a paid refund
                    let outcome = tx
                        .cancel_event_attendee_attendance(
                            actor_user_id,
                            group_id,
                            event_id,
                            user_id,
                            payment_provider,
                        )
                        .await?;

                    // Notify only when attendance was removed immediately
                    if outcome.cancellation_status
                        == EventAttendeeCancellationStatus::AttendanceCanceled
                    {
                        enqueue_event_attendance_cancellation_notifications(
                            tx,
                            &server_cfg,
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

        Ok(())
    }

    /// [`EnrollmentManager::invite_event_attendee`].
    async fn invite_event_attendee(
        &self,
        input: &InviteAttendeeInput,
    ) -> Result<AdmissionAllocationOutcome, EnrollmentError> {
        let allocation = self
            .db
            .invite_event_attendee(
                input.actor_user_id,
                input.group_id,
                input.event_id,
                &EventAttendeeInvitationInput {
                    email: input.email.clone(),
                    event_ticket_type_id: input.event_ticket_type_id,
                    user_id: input.user_id,
                },
                self.payments_manager.configured_provider(),
            )
            .await?;

        Ok(allocation.into())
    }

    /// [`EnrollmentManager::join_group`].
    async fn join_group(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), EnrollmentError> {
        // Persist the membership before any notification work
        self.db.join_group(community_id, group_id, user_id).await?;

        // Welcome the new member best-effort
        self.enqueue_group_welcome_notification(community_id, group_id, user_id)
            .await;

        Ok(())
    }

    /// [`EnrollmentManager::leave_event`].
    async fn leave_event(
        &self,
        input: &LeaveEventInput,
    ) -> Result<EventLeaveOutcome, EnrollmentError> {
        let LeaveEventInput {
            community_id,
            event_id,
            user_id,
        } = *input;
        let payment_provider = self.payments_manager.configured_provider();
        let server_cfg = self.server_cfg.clone();

        // Leave the event and enqueue the required cancellation notification atomically
        let outcome = self
            .db
            .as_ref()
            .transaction(|tx| {
                Box::pin(async move {
                    // Remove the enrollment, rejecting paid attendees in the database
                    let outcome = tx
                        .leave_event(community_id, event_id, user_id, payment_provider)
                        .await?;

                    // Confirm the cancellation to attendees before committing
                    if outcome.left_status == EventEnrollmentStatus::Attendee {
                        enqueue_event_attendance_cancellation_notifications(
                            tx,
                            &server_cfg,
                            community_id,
                            event_id,
                            user_id,
                        )
                        .await?;
                    }

                    Ok(outcome)
                })
            })
            .await?;

        // Confirm the waitlist exit best-effort after commit
        if outcome.left_status == EventEnrollmentStatus::Waitlisted {
            enqueue_event_notification_best_effort(
                self.db.as_ref(),
                &self.notifications_manager,
                &self.server_cfg,
                community_id,
                event_id,
                |event, server_cfg, site_settings| {
                    build_event_waitlist_left_notification(
                        event,
                        user_id,
                        server_cfg,
                        site_settings,
                    )
                },
            )
            .await;
        }

        Ok(outcome)
    }

    /// [`EnrollmentManager::leave_group`].
    async fn leave_group(
        &self,
        community_id: Uuid,
        group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), EnrollmentError> {
        self.db.leave_group(community_id, group_id, user_id).await?;

        Ok(())
    }

    /// [`EnrollmentManager::start_checkout`].
    async fn start_checkout(
        &self,
        input: &StartCheckoutInput,
    ) -> Result<AttendOutcome, EnrollmentError> {
        let StartCheckoutInput {
            community_id,
            event_id,
            user_id,
            ..
        } = *input;

        // Stop checkout when the event is no longer attendee-visible
        self.db.ensure_event_is_active(community_id, event_id).await?;

        // Validate the submitted answers against the event questionnaire
        let registration_questions = self
            .db
            .get_event_registration_questions(community_id, event_id)
            .await?;
        validate_registration_answers(
            input.checkout.registration_answers.registration_answers.as_ref(),
            &registration_questions,
        )?;

        // Reserve the hold and resolve it into the attendee-facing outcome
        self.complete_checkout(community_id, event_id, user_id, &input.checkout)
            .await
    }
}

// Types.

/// Parameters used to accept a pending event invitation request.
#[derive(Clone, Debug)]
pub(crate) struct AcceptInvitationRequestInput {
    /// Organizer accepting the request.
    pub actor_user_id: Uuid,
    /// Event the request belongs to.
    pub event_id: Uuid,
    /// Group organizing the event.
    pub group_id: Uuid,
    /// User whose request is accepted.
    pub user_id: Uuid,

    /// Invitation-only ticket type assigned to a generic ticket request.
    pub event_ticket_type_id: Option<Uuid>,
}

/// Outcome of an organizer-controlled admission allocation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum AdmissionAllocationOutcome {
    /// Admission was allocated.
    Allocated,
    /// Admission could not be allocated; carries the stable conflict code.
    Conflict(String),
}

impl From<EventAdmissionAllocationResult> for AdmissionAllocationOutcome {
    fn from(result: EventAdmissionAllocationResult) -> Self {
        match result {
            EventAdmissionAllocationResult::Conflict(conflict) => {
                Self::Conflict(conflict.to_string())
            }
            EventAdmissionAllocationResult::Success(_) => Self::Allocated,
        }
    }
}

/// Parameters used to register a user's attendance.
#[derive(Clone, Debug)]
pub(crate) struct AttendEventInput {
    /// Validated attendance form.
    pub attendance: EventAttendanceInput,
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event being attended.
    pub event_id: Uuid,
    /// User attending the event.
    pub user_id: Uuid,
}

/// Outcome of an attendance or checkout request.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum AttendOutcome {
    /// A paid pending purchase must continue at the provider checkout.
    CheckoutRedirect {
        /// Instant the checkout hold expires, when the purchase has one.
        hold_expires_at: Option<DateTime<Utc>>,
        /// Provider checkout URL.
        redirect_url: String,
    },
    /// The request could not be registered; carries the stable conflict code.
    Conflict(String),
    /// The user is enrolled with the returned status.
    Enrolled(EventEnrollmentStatus),
    /// An external pending purchase whose payment details the attendee needs.
    ExternalPendingPayment(Box<PreparedEventCheckout>),
}

/// Errors returned by enrollment workflows.
#[derive(Debug, thiserror::Error)]
pub(crate) enum EnrollmentError {
    /// Internal failure, including database and provider errors.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
    /// User-facing business rejection decided by the manager.
    #[error("{0}")]
    Rejected(String),
}

impl From<PaymentsError> for EnrollmentError {
    fn from(err: PaymentsError) -> Self {
        match err {
            PaymentsError::Other(err) => Self::Other(err),
            PaymentsError::Rejected(message) => Self::Rejected(message),
        }
    }
}

/// Parameters used to invite a user or email address to an event.
#[derive(Clone, Debug)]
pub(crate) struct InviteAttendeeInput {
    /// Organizer creating the invitation.
    pub actor_user_id: Uuid,
    /// Event the invitation is for.
    pub event_id: Uuid,
    /// Group organizing the event.
    pub group_id: Uuid,

    /// Email address used to create or reissue an invitation.
    pub email: Option<String>,
    /// Ticket type assigned to the invitation.
    pub event_ticket_type_id: Option<Uuid>,
    /// Existing registered user identifier.
    pub user_id: Option<Uuid>,
}

/// Parameters used by a user to leave an event.
#[derive(Clone, Copy, Debug)]
pub(crate) struct LeaveEventInput {
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event being left.
    pub event_id: Uuid,
    /// User leaving the event.
    pub user_id: Uuid,
}

/// Parameters used by an organizer to cancel an attendee's attendance.
#[derive(Clone, Copy, Debug)]
pub(crate) struct OrganizerCancellationInput {
    /// Organizer canceling the attendance.
    pub actor_user_id: Uuid,
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event the attendance belongs to.
    pub event_id: Uuid,
    /// Group organizing the event.
    pub group_id: Uuid,
    /// Attendee whose attendance is canceled.
    pub user_id: Uuid,
}

/// Parameters used to start or resume a ticket checkout.
#[derive(Clone, Debug)]
pub(crate) struct StartCheckoutInput {
    /// Validated checkout form.
    pub checkout: CheckoutInput,
    /// Community containing the event.
    pub community_id: Uuid,
    /// Event whose ticket is purchased.
    pub event_id: Uuid,
    /// User purchasing the ticket.
    pub user_id: Uuid,
}

// Helpers.

/// Returns the enrollment status when the purchase state must not reopen checkout.
fn checkout_enrollment_status(
    purchase_status: EventPurchaseStatus,
) -> Result<Option<EventEnrollmentStatus>, EnrollmentError> {
    match purchase_status {
        EventPurchaseStatus::Completed => Ok(Some(EventEnrollmentStatus::Attendee)),
        EventPurchaseStatus::Pending => Ok(None),
        EventPurchaseStatus::RefundRecoveryPending => Err(EnrollmentError::Rejected(
            "checkout is unavailable while refund recovery is in progress".to_string(),
        )),
        EventPurchaseStatus::RefundRequested => Err(EnrollmentError::Rejected(
            "checkout is unavailable while a refund is in progress".to_string(),
        )),
        _ => Err(EnrollmentError::Rejected(
            "checkout is unavailable for this purchase".to_string(),
        )),
    }
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

/// Validates submitted registration answers against the event questionnaire.
fn validate_registration_answers(
    registration_answers: Option<&QuestionnaireAnswers>,
    registration_questions: &[QuestionnaireQuestion],
) -> Result<(), EnrollmentError> {
    match registration_answers {
        Some(answers) => answers
            .validate_against_questions(registration_questions)
            .map_err(EnrollmentError::Rejected),
        None if registration_questions.is_empty() => Ok(()),
        None => Err(EnrollmentError::Rejected(
            "questionnaire answers are required".to_string(),
        )),
    }
}
