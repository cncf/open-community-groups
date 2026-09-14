//! Services modules.

/// Open Badges credential service module.
pub(crate) mod badges;

/// Bounded blocking work execution module.
pub(crate) mod blocking;

/// Attendee check-in credential service module.
pub(crate) mod check_in;

/// Event attendance and group membership service module.
pub(crate) mod enrollment;

/// Dashboard event management service module.
pub(crate) mod events;

/// Images service module.
pub(crate) mod images;

/// Meetings service module.
pub(crate) mod meetings;

/// Notifications service module.
pub(crate) mod notifications;

/// Payments service module.
pub(crate) mod payments;

/// Shared background worker helpers module.
pub(crate) mod workers;
