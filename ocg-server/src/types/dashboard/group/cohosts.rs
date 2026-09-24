//! Group dashboard co-hosting types.

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        event::{EventCohostStatus, EventKind},
        pagination::{Pagination, ToRawQuery},
    },
    validation::MAX_PAGINATION_LIMIT,
};

/// Event another group invited the selected group to co-host.
#[skip_serializing_none]
#[allow(clippy::struct_excessive_bools)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CohostedEvent {
    /// Whether the event has been canceled.
    pub canceled: bool,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event attendance mode.
    pub event_kind: EventKind,
    /// URL to the event logo, falling back to the owner group and community logos.
    pub event_logo_url: String,
    /// Event name.
    pub event_name: String,
    /// URL-friendly identifier for the event.
    pub event_slug: String,
    /// Current invitation identifier.
    pub invitation_id: Uuid,
    /// When the current invitation was sent.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub invited_at: DateTime<Utc>,
    /// Display name of the owner group's community.
    pub owner_community_display_name: String,
    /// Name of the owner group's community (slug for URLs).
    pub owner_community_name: String,
    /// URL to the owner group's logo, falling back to its community logo.
    pub owner_group_logo_url: String,
    /// Owner group display name.
    pub owner_group_name: String,
    /// Generated URL-friendly identifier for the owner group.
    pub owner_group_slug: String,
    /// Whether the event is published.
    pub published: bool,
    /// Current co-hosting status.
    pub status: EventCohostStatus,
    /// Timezone in which the event times are displayed.
    pub timezone: Tz,

    /// Event end time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub ends_at: Option<DateTime<Utc>>,
    /// Admin-managed URL-friendly identifier for the owner group.
    pub owner_group_slug_pretty: Option<String>,
    /// When the co-host group or the organizer last responded.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub responded_at: Option<DateTime<Utc>>,
    /// Event start time in UTC.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub starts_at: Option<DateTime<Utc>>,
}

impl CohostedEvent {
    /// Returns true when the co-host group can withdraw its approval.
    pub(crate) fn can_cancel(&self) -> bool {
        self.status == EventCohostStatus::Approved
    }

    /// Returns true when the co-host group can approve or reject the invitation.
    pub(crate) fn can_respond(&self) -> bool {
        self.status == EventCohostStatus::Pending && !self.canceled && !self.published
    }

    /// Returns the owner group slug to use in public URLs.
    pub(crate) fn owner_public_slug(&self) -> &str {
        self.owner_group_slug_pretty
            .as_deref()
            .unwrap_or(&self.owner_group_slug)
    }

    /// Returns the public event URL when the event page is reachable.
    ///
    /// Public event pages require a published event, including canceled ones.
    pub(crate) fn public_url(&self) -> Option<String> {
        self.published.then(|| {
            format!(
                "/{}/group/{}/event/{}",
                self.owner_community_name,
                self.owner_public_slug(),
                self.event_slug
            )
        })
    }

    /// Returns the user-facing label for the co-hosting status.
    pub(crate) fn status_label(&self) -> &'static str {
        self.status.display_name()
    }
}

/// Filter parameters for the co-hosted events list.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CohostedEventsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(CohostedEventsFilters, limit, offset);

/// Paginated co-hosted events response data.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct CohostedEventsOutput {
    /// Co-hosted events in the current page.
    pub events: Vec<CohostedEvent>,
    /// Total number of co-hosted events.
    pub total: usize,
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use uuid::Uuid;

    use crate::types::event::{EventCohostStatus, EventKind};

    use super::CohostedEvent;

    #[test]
    fn cohosted_event_public_url_links_canceled_published_events() {
        let event = CohostedEvent {
            canceled: true,
            published: true,
            ..sample_cohosted_event()
        };

        assert_eq!(
            event.public_url().as_deref(),
            Some("/owner/group/owner-group/event/cloud-native-meetup")
        );
    }

    #[test]
    fn cohosted_event_public_url_links_published_events() {
        let event = CohostedEvent {
            published: true,
            owner_group_slug_pretty: Some("owner".to_string()),
            ..sample_cohosted_event()
        };

        assert_eq!(
            event.public_url().as_deref(),
            Some("/owner/group/owner/event/cloud-native-meetup")
        );
    }

    #[test]
    fn cohosted_event_public_url_skips_canceled_drafts() {
        let event = CohostedEvent {
            canceled: true,
            ..sample_cohosted_event()
        };

        assert_eq!(event.public_url(), None);
    }

    #[test]
    fn cohosted_event_public_url_skips_drafts() {
        assert_eq!(sample_cohosted_event().public_url(), None);
    }

    // Helpers.

    /// Returns a pending invitation to co-host an unpublished event.
    fn sample_cohosted_event() -> CohostedEvent {
        CohostedEvent {
            canceled: false,
            event_id: Uuid::new_v4(),
            event_kind: EventKind::InPerson,
            event_logo_url: "https://example.test/event.png".to_string(),
            event_name: "Cloud Native Meetup".to_string(),
            event_slug: "cloud-native-meetup".to_string(),
            invitation_id: Uuid::new_v4(),
            invited_at: Utc::now(),
            owner_community_display_name: "Owner Community".to_string(),
            owner_community_name: "owner".to_string(),
            owner_group_logo_url: "https://example.test/group.png".to_string(),
            owner_group_name: "Owner Group".to_string(),
            owner_group_slug: "owner-group".to_string(),
            published: false,
            status: EventCohostStatus::Pending,
            timezone: chrono_tz::UTC,

            ends_at: None,
            owner_group_slug_pretty: None,
            responded_at: None,
            starts_at: None,
        }
    }
}
