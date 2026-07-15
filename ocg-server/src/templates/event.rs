//! This module defines the templates for the event page.

use askama::Template;
use chrono::{DateTime, Utc};
use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::User,
        filters,
        helpers::{self, user_initials},
    },
    types::{
        event::{EventCfsLabel, EventFull, EventKind, EventSummary},
        site::SiteSettings,
        user::UserSummary,
    },
};

// Pages and sections templates.

/// Event page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/page.html")]
pub(crate) struct Page {
    /// Configured public base URL.
    pub base_url: String,
    /// Detailed information about the event.
    pub event: EventFull,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
}

impl Page {
    /// Returns the canonical public URL for the event page.
    pub(crate) fn canonical_url(&self) -> String {
        helpers::absolute_url(
            &self.base_url,
            &format!(
                "/{}/group/{}/event/{}",
                self.event.alliance.name,
                self.event.group.public_slug(),
                self.event.slug
            ),
        )
    }

    /// Returns a `LinkedIn` share URL for the event page.
    pub(crate) fn linkedin_share_url(&self) -> String {
        format!(
            "https://www.linkedin.com/sharing/share-offsite/?url={}",
            utf8_percent_encode(&self.canonical_url(), NON_ALPHANUMERIC)
        )
    }

    /// Returns suggested caption text for Instagram.
    pub(crate) fn instagram_caption(&self) -> String {
        format!("{}\n\n{}", self.preview_title(), self.preview_description())
    }

    /// Returns the Open Graph image URL for the event page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.event
            .group
            .og_image_url
            .as_deref()
            .or(self.event.alliance.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview description for the event page.
    pub(crate) fn preview_description(&self) -> String {
        format!(
            "{} in {} alliance. Open Alliance Groups, where Open Source alliances thrive.",
            self.event.group.name, self.event.alliance.display_name
        )
    }

    /// Returns the preview title for the event page.
    pub(crate) fn preview_title(&self) -> String {
        if let Some(starts_at) = self.event.starts_at {
            let starts_at = starts_at.with_timezone(&self.event.timezone);
            format!("{} - {}", self.event.name, starts_at.format("%B %-d"))
        } else {
            self.event.name.clone()
        }
    }
}

/// Event check-in page template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/check_in_page.html")]
pub(crate) struct CheckInPage {
    /// Whether the check-in window is open.
    pub check_in_window_open: bool,
    /// Event summary being checked into.
    pub event: EventSummary,
    /// Identifier for the current page.
    #[allow(dead_code)]
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,
    /// Whether the user is an attendee of the event.
    pub user_is_attendee: bool,
    /// Whether the user is already checked in to the event.
    pub user_is_checked_in: bool,
}

/// Call for speakers modal template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/cfs_modal.html")]
pub(crate) struct CfsModal {
    /// Event summary information.
    pub event: EventSummary,
    /// Labels available for the event.
    pub labels: Vec<EventCfsLabel>,
    /// List of session proposals for the current user.
    pub session_proposals: Vec<SessionProposal>,
    /// Authenticated user information.
    pub user: User,

    /// Notice message displayed after submissions.
    pub notice: Option<String>,
}

/// Session proposal details for CFS modal.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SessionProposal {
    /// Proposal creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Proposal description.
    pub description: String,
    /// Duration in minutes.
    pub duration_minutes: i32,
    /// Whether the proposal has already been submitted.
    pub is_submitted: bool,
    /// Session proposal identifier.
    pub session_proposal_id: Uuid,
    /// Session proposal level identifier.
    pub session_proposal_level_id: String,
    /// Session proposal level display name.
    pub session_proposal_level_name: String,
    /// Proposal status identifier.
    pub session_proposal_status_id: String,
    /// Proposal status name.
    pub status_name: String,
    /// Proposal title.
    pub title: String,

    /// Co-speaker information.
    pub co_speaker: Option<UserSummary>,
    /// Submission status identifier.
    pub submission_status_id: Option<String>,
    /// Submission status name.
    pub submission_status_name: Option<String>,
    /// Proposal last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

#[cfg(test)]
mod tests {
    use chrono::{DateTime, TimeZone, Utc};
    use chrono_tz::{America::Los_Angeles, Tz};

    use crate::types::{alliance::AllianceSummary, group::GroupSummary};

    use super::*;

    #[test]
    fn test_preview_title_uses_event_date_in_event_timezone() {
        let page = sample_page(
            Some(Utc.with_ymd_and_hms(2030, 3, 6, 7, 30, 0).unwrap()),
            Los_Angeles,
        );

        assert_eq!(page.preview_title(), "Test Event - March 5");
    }

    #[test]
    fn test_preview_title_without_start_date_uses_event_name() {
        let page = sample_page(None, chrono_tz::UTC);

        assert_eq!(page.preview_title(), "Test Event");
    }

    #[test]
    fn test_preview_description_uses_group_and_alliance_names() {
        let page = sample_page(None, chrono_tz::UTC);

        assert_eq!(
            page.preview_description(),
            "Test Group in Test Alliance alliance. Open Alliance Groups, where Open Source alliances thrive."
        );
    }

    // Helpers.

    fn sample_page(starts_at: Option<DateTime<Utc>>, timezone: Tz) -> Page {
        Page {
            base_url: "https://example.test".to_string(),
            event: EventFull {
                alliance: AllianceSummary {
                    display_name: "Test Alliance".to_string(),
                    ..Default::default()
                },
                group: GroupSummary {
                    name: "Test Group".to_string(),
                    ..Default::default()
                },
                name: "Test Event".to_string(),
                starts_at,
                timezone,
                ..Default::default()
            },
            page_id: PageId::Event,
            path: "/test-alliance/group/test-group/event/test-event".to_string(),
            site_settings: SiteSettings::default(),
            user: User::default(),
        }
    }
}
