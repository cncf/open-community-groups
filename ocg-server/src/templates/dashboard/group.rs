//! Templates for the group dashboard.

use serde::{Deserialize, Serialize};

pub(crate) mod analytics;
pub(crate) mod attendees;
pub(crate) mod credentials;
pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod invitation_requests;
pub(crate) mod members;
pub(crate) mod settings;
pub(crate) mod sponsors;
pub(crate) mod submissions;
pub(crate) mod team;
pub(crate) mod waitlist;

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
