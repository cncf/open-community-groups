//! This module defines the templates for the event page.

use askama::Template;
use chrono::{DateTime, Datelike, Duration, Timelike, Utc};
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
                self.event.community.name,
                self.event.group.public_slug(),
                self.event.slug
            ),
        )
    }

    /// Returns the download URL for the event's iCalendar (ICS) file.
    pub(crate) fn calendar_ics_url(&self) -> String {
        format!(
            "/{}/event/{}/calendar.ics",
            self.event.community.name, self.event.event_id
        )
    }

    /// Returns a Google Calendar "add event" link for the event.
    pub(crate) fn google_calendar_link(&self) -> Option<String> {
        let start = self.event.starts_at?;
        let end = self.event.ends_at.unwrap_or(start + Duration::hours(1));

        let mut details = String::new();
        if let Some(description_short) = self
            .event
            .description_short
            .as_deref()
            .filter(|value| !value.trim().is_empty())
        {
            details.push_str(description_short.trim());
            details.push_str("\n\n");
        }
        details.push_str(&self.canonical_url());

        let mut url = format!(
            "https://calendar.google.com/calendar/render?action=TEMPLATE&text={}&dates={}/{}&details={}&ctz={}",
            encode_for_url(&self.event.name),
            format_datetime_for_google_calendar(&start),
            format_datetime_for_google_calendar(&end),
            encode_for_url(&details),
            encode_for_url(&self.event.timezone.to_string()),
        );
        if let Some(location) = self.event.location(512) {
            url.push_str("&location=");
            url.push_str(&encode_for_url(&location));
        }

        Some(url)
    }

    /// Returns the Open Graph image URL for the event page.
    pub(crate) fn open_graph_image_url(&self) -> Option<String> {
        self.event
            .group
            .og_image_url
            .as_deref()
            .or(self.event.community.og_image_url.as_deref())
            .map(|image_url| helpers::open_graph_image_url(&self.base_url, image_url))
    }

    /// Returns the preview description for the event page.
    pub(crate) fn preview_description(&self) -> String {
        format!(
            "{} in {} community. Open Community Groups, where Open Source communities thrive.",
            self.event.group.name, self.event.community.display_name
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

/// Percent-encodes a value for use in a URL query string.
fn encode_for_url(value: &str) -> String {
    utf8_percent_encode(value, NON_ALPHANUMERIC).to_string()
}

/// Formats a UTC datetime for the Google Calendar `dates` query parameter (YYYYMMDDTHHMMSSZ).
fn format_datetime_for_google_calendar(dt: &DateTime<Utc>) -> String {
    format!(
        "{:04}{:02}{:02}T{:02}{:02}{:02}Z",
        dt.year(),
        dt.month(),
        dt.day(),
        dt.hour(),
        dt.minute(),
        dt.second()
    )
}

#[cfg(test)]
mod tests {
    use chrono::{DateTime, TimeZone, Utc};
    use chrono_tz::{America::Los_Angeles, Tz};

    use crate::types::{community::CommunitySummary, group::GroupSummary};

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
    fn test_preview_description_uses_group_and_community_names() {
        let page = sample_page(None, chrono_tz::UTC);

        assert_eq!(
            page.preview_description(),
            "Test Group in Test Community community. Open Community Groups, where Open Source communities thrive."
        );
    }

    // Helpers.

    fn sample_page(starts_at: Option<DateTime<Utc>>, timezone: Tz) -> Page {
        Page {
            base_url: "https://example.test".to_string(),
            event: EventFull {
                community: CommunitySummary {
                    display_name: "Test Community".to_string(),
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
            path: "/test-community/group/test-group/event/test-event".to_string(),
            site_settings: SiteSettings::default(),
            user: User::default(),
        }
    }
}
