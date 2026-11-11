//! This module defines the templates for the event page.

use askama::Template;
use serde::Serialize;
use uuid::Uuid;

use crate::{
    templates::{
        PageId,
        auth::UserMenuState,
        filters,
        helpers::{self, user_initials},
    },
    types::{
        event::{
            EventFull, EventKind, EventLabel, EventSummary, LegacyUser, SessionProposal, Speaker,
        },
        inbox::InboxContactContext,
        site::SiteSettings,
        user::User,
    },
};

#[cfg(test)]
mod tests;

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
    pub user: UserMenuState,
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

    /// Returns the featured speakers listed publicly, skipping those without a name.
    pub(crate) fn public_featured_speakers(&self) -> Vec<&User> {
        self.event
            .speakers
            .iter()
            .filter(|speaker| speaker.featured)
            .map(|speaker| &speaker.user)
            .filter(|user| helpers::has_public_name(user.name.as_deref()))
            .collect()
    }

    /// Returns the legacy hosts followed by the hosts, skipping those without a name.
    pub(crate) fn public_hosts(&self) -> Vec<EventPerson<'_>> {
        let legacy_hosts = self
            .event
            .legacy_hosts
            .iter()
            .flatten()
            .filter(|host| helpers::has_public_name(host.name.as_deref()))
            .map(EventPerson::Legacy);
        let hosts = self
            .event
            .hosts
            .iter()
            .filter(|host| helpers::has_public_name(host.name.as_deref()))
            .map(EventPerson::User);
        legacy_hosts.chain(hosts).collect()
    }

    /// Returns the organizers listed publicly, skipping those without a name.
    pub(crate) fn public_organizers(&self) -> Vec<&User> {
        self.event
            .organizers
            .iter()
            .filter(|organizer| helpers::has_public_name(organizer.name.as_deref()))
            .collect()
    }

    /// Returns the legacy speakers followed by the non-featured speakers, skipping
    /// those without a name.
    pub(crate) fn public_regular_speakers(&self) -> Vec<EventPerson<'_>> {
        let legacy_speakers = self
            .event
            .legacy_speakers
            .iter()
            .flatten()
            .filter(|speaker| helpers::has_public_name(speaker.name.as_deref()))
            .map(EventPerson::Legacy);
        let speakers = self
            .event
            .speakers
            .iter()
            .filter(|speaker| !speaker.featured)
            .filter(|speaker| helpers::has_public_name(speaker.user.name.as_deref()))
            .map(|speaker| EventPerson::User(&speaker.user));
        legacy_speakers.chain(speakers).collect()
    }
}

/// Call for speakers modal template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/cfs_modal.html")]
pub(crate) struct CfsModal {
    /// Event summary information.
    pub event: EventSummary,
    /// Labels available for the event.
    pub labels: Vec<EventLabel>,
    /// List of session proposals for the current user.
    pub session_proposals: Vec<SessionProposal>,
    /// Authenticated user information.
    pub user: UserMenuState,

    /// Notice message displayed after submissions.
    pub notice: Option<String>,
}

/// Contact organizers modal template.
#[derive(Debug, Clone, Template)]
#[template(path = "event/contact_modal.html")]
pub(crate) struct ContactModal {
    /// Authenticated user information.
    pub user: UserMenuState,

    /// Contact context of the event, absent after a message was sent.
    pub context: Option<InboxContactContext>,
    /// Conversation started by the sent message.
    pub sent_inbox_conversation_id: Option<Uuid>,
}

// Types.

/// Person listed in a public event people section.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(untagged)]
pub(crate) enum EventPerson<'a> {
    /// Imported person, whose bio is stored as HTML.
    Legacy(&'a LegacyUser),
    /// Platform user.
    User(&'a User),
}

impl EventPerson<'_> {
    /// Returns true when the bio must be rendered as trusted HTML.
    pub(crate) fn bio_is_html(&self) -> bool {
        matches!(self, Self::Legacy(_))
    }
}

// Helpers.

/// Returns the named session speakers, featured first, keeping input order within each group.
pub(crate) fn public_session_speakers(speakers: &[Speaker]) -> Vec<&Speaker> {
    // Keep only speakers with a public name
    let mut named_speakers: Vec<&Speaker> = speakers
        .iter()
        .filter(|speaker| helpers::has_public_name(speaker.user.name.as_deref()))
        .collect();
    // List featured speakers first; the sort is stable, so each group keeps its input order
    named_speakers.sort_by_key(|speaker| !speaker.featured);
    named_speakers
}
