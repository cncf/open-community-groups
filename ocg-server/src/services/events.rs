//! Dashboard event management workflows.
//!
//! The events manager owns the organizer-facing event mutations (creating,
//! updating, publishing, unpublishing, canceling, and deleting events and
//! event series) together with their provider validations and required
//! notifications.

mod manager;
mod recurrence;

pub(crate) use manager::{
    AddEventInput, AutomaticTaxCheckError, DynEventsManager, EventActionInput, EventsError,
    PgEventsManager, UpdateEventInput,
};

#[cfg(test)]
pub(crate) use manager::{EventsManager, MockEventsManager};
