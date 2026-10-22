//! Event survey types shared by the dashboards.

use serde::{Deserialize, Serialize};

#[cfg(test)]
mod tests;

/// Attendees an event survey is addressed to.
#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    Serialize,
    Deserialize,
    strum::Display,
    strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventSurveyAudience {
    /// Confirmed attendees who checked in.
    CheckedIn,
    /// Confirmed attendees.
    #[default]
    Confirmed,
}

/// Live state of an event survey.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventSurveyState {
    /// Closed manually or past its closing date.
    Closed,
    /// Being prepared by the organizers; never visible to attendees.
    Draft,
    /// Accepting answers.
    Open,
    /// Ready, waiting for the event to end or for its custom opening time.
    Scheduled,
}
