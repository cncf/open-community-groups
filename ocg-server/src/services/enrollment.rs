//! Event attendance and group membership workflows.
//!
//! The enrollment manager owns the self-service and organizer enrollment
//! operations (attending, leaving, checkout, invitations, and group
//! membership) together with their required and best-effort notifications.
//! The enrollment worker reconciles due reservations in the background.

mod manager;
mod worker;

pub(crate) use manager::{
    AcceptInvitationRequestInput, AdmissionAllocationOutcome, AttendEventInput, AttendOutcome,
    DynEnrollmentManager, EnrollmentError, InviteAttendeeInput, LeaveEventInput,
    OrganizerCancellationInput, PgEnrollmentManager, StartCheckoutInput,
};
pub(crate) use worker::start_enrollment_workers;

#[cfg(test)]
pub(crate) use manager::{EnrollmentManager, MockEnrollmentManager};
