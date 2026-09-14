//! Group dashboard type definitions.

use serde::{Deserialize, Serialize};

pub mod analytics;
pub mod attendees;
pub mod badges;
pub mod check_in;
pub mod events;
pub mod home;
pub mod invitation_requests;
pub mod members;
pub mod refunds;
pub mod sponsors;
pub mod submissions;
pub mod team;
pub mod waitlist;

/// Presence filter for optional database fields.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum PresenceFilter {
    /// Field value must be missing.
    Missing,
    /// Field value must be present.
    Present,
}
