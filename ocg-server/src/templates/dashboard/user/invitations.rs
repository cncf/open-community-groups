//! Templates for the user dashboard invitations tab.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    templates::helpers::DATE_FORMAT_2,
    types::{alliance::AllianceRole, group::GroupRole},
};

// Pages templates.

/// List page showing pending invitations for the user.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/invitations_list.html")]
pub(crate) struct ListPage {
    /// Pending alliance invitations for the current user.
    pub alliance_invitations: Vec<AllianceTeamInvitation>,
    /// Pending event invitations for the current user.
    pub event_invitations: Vec<EventInvitation>,
    /// Pending group invitations for the current user.
    pub group_invitations: Vec<GroupTeamInvitation>,
}

// Types.

/// Alliance team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AllianceTeamInvitation {
    /// Alliance identifier.
    pub alliance_id: Uuid,
    /// Alliance name (slug).
    pub alliance_name: String,
    /// Role within the alliance.
    pub role: AllianceRole,

    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}

/// Organizer-created event invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventInvitation {
    /// Human-readable display name of the alliance.
    pub alliance_display_name: String,
    /// Alliance slug.
    pub alliance_name: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event display name.
    pub event_name: String,
    /// Group display name.
    pub group_name: String,
    /// Timezone in which event dates should be displayed.
    pub timezone: chrono_tz::Tz,

    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Event start time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
}

/// Group team invitation summary information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupTeamInvitation {
    /// Alliance name (slug).
    pub alliance_name: String,
    /// Group identifier.
    pub group_id: Uuid,
    /// Group name.
    pub group_name: String,
    /// Role within the group.
    pub role: GroupRole,

    /// Invitation creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
}
