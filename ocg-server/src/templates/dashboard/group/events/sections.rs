//! Event editor tab catalog shared by the add and update pages.
//!
//! The catalog is the single ordered definition of the event editor tabs. Both
//! pages derive their grouped navigation from it, so the sidebar list, the
//! compact section select and the Next button order always agree. The Next
//! button follows the order of the rendered tab buttons, so it walks the
//! catalog order across groups.

use uuid::Uuid;

#[cfg(test)]
mod tests;

/// Ordered event editor tab catalog, grouped by event lifecycle.
pub(crate) const EVENT_FORM_TABS: &[EventFormTab] = &[
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Event,
        icon: "event",
        label: "Details",
        section: EventFormSection::Details,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Event,
        icon: "calendar",
        label: "Date & Venue",
        section: EventFormSection::DateVenue,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Event,
        icon: "cohosts",
        label: "Co-hosts",
        section: EventFormSection::Cohosts,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Event,
        icon: "user-plus",
        label: "Contributors",
        section: EventFormSection::HostsSponsors,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Registration,
        icon: "ticket",
        label: "Tickets",
        section: EventFormSection::Payments,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Registration,
        icon: "list-check",
        label: "Questions",
        section: EventFormSection::Questions,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Program,
        icon: "tag",
        label: "Labels",
        section: EventFormSection::Labels,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Program,
        icon: "megaphone",
        label: "CFS",
        section: EventFormSection::Cfs,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::UpdateOnly,
        group: EventFormTabGroupKind::Program,
        icon: "submission",
        label: "Submissions",
        section: EventFormSection::Submissions,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::AddAndUpdate,
        group: EventFormTabGroupKind::Program,
        icon: "presentation",
        label: "Sessions",
        section: EventFormSection::Sessions,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::UpdateOnly,
        group: EventFormTabGroupKind::People,
        icon: "attendees",
        label: "Attendees",
        section: EventFormSection::Attendees,

        visibility: None,
    },
    EventFormTab {
        availability: EventFormTabAvailability::UpdateOnly,
        group: EventFormTabGroupKind::People,
        icon: "request-invitation",
        label: "Requests",
        section: EventFormSection::InvitationRequests,

        visibility: Some(EventFormTabVisibility::InvitationRequests),
    },
    EventFormTab {
        availability: EventFormTabAvailability::UpdateOnly,
        group: EventFormTabGroupKind::People,
        icon: "waitlist",
        label: "Waitlist",
        section: EventFormSection::Waitlist,

        visibility: Some(EventFormTabVisibility::Waitlist),
    },
    EventFormTab {
        availability: EventFormTabAvailability::UpdateOnly,
        group: EventFormTabGroupKind::FollowUp,
        icon: "survey",
        label: "Surveys",
        section: EventFormSection::Surveys,

        visibility: Some(EventFormTabVisibility::Surveys),
    },
    EventFormTab {
        availability: EventFormTabAvailability::UpdateOnly,
        group: EventFormTabGroupKind::FollowUp,
        icon: "charts",
        label: "Analytics",
        section: EventFormSection::Analytics,

        visibility: None,
    },
];

/// Event editor page the tab navigation is rendered for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EventFormMode {
    /// Add page, which shows only the authoring tabs.
    Add,
    /// Update page of an existing event.
    Update {
        /// Whether the event requires organizer approval for attendance.
        attendee_approval_required: bool,
        /// Identifier of the event being updated.
        event_id: Uuid,
    },
}

/// Event editor section shared by tab controls and content regions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, strum::Display)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventFormSection {
    /// Event analytics.
    Analytics,
    /// Event attendees.
    Attendees,
    /// Call for speakers settings.
    Cfs,
    /// Event co-hosts.
    Cohosts,
    /// Event schedule and venue.
    DateVenue,
    /// Event details.
    Details,
    /// Event hosts, speakers and sponsors.
    HostsSponsors,
    /// Attendance invitation requests.
    InvitationRequests,
    /// Event labels.
    Labels,
    /// Event tickets.
    Payments,
    /// Registration questions.
    Questions,
    /// Event sessions.
    Sessions,
    /// Call for speakers submissions.
    Submissions,
    /// Post-event surveys.
    Surveys,
    /// Event waitlist.
    Waitlist,
}

/// Event editor tab catalog entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct EventFormTab {
    /// Pages the tab is available on.
    pub availability: EventFormTabAvailability,
    /// Lifecycle group the tab belongs to.
    pub group: EventFormTabGroupKind,
    /// Icon name rendered in the sidebar tab button.
    pub icon: &'static str,
    /// Tab label.
    pub label: &'static str,
    /// Section the tab activates.
    pub section: EventFormSection,

    /// Page flag that controls whether the tab is shown.
    pub visibility: Option<EventFormTabVisibility>,
}

/// Pages an event editor tab is available on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EventFormTabAvailability {
    /// Tab shown on both the add and update pages.
    AddAndUpdate,
    /// Tab shown only on the update page.
    UpdateOnly,
}

/// Page flags for event editor tabs that are shown conditionally.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct EventFormTabFlags {
    /// Whether the invitation requests tab is shown.
    pub invitation_requests: bool,
    /// Whether the surveys tab is shown.
    pub surveys: bool,
    /// Whether the waitlist tab is shown.
    pub waitlist: bool,
}

impl EventFormTabFlags {
    /// Returns true when the given visibility key is enabled.
    pub(crate) fn is_visible(self, visibility: EventFormTabVisibility) -> bool {
        match visibility {
            EventFormTabVisibility::InvitationRequests => self.invitation_requests,
            EventFormTabVisibility::Surveys => self.surveys,
            EventFormTabVisibility::Waitlist => self.waitlist,
        }
    }
}

/// Event editor tab group rendered under one heading.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EventFormTabGroup {
    /// Lifecycle group identifier.
    pub kind: EventFormTabGroupKind,
    /// Group heading label.
    pub label: &'static str,
    /// Tabs shown in the group, in catalog order.
    pub tabs: Vec<EventFormTabLink>,
}

/// Lifecycle group of event editor tabs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, strum::Display)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum EventFormTabGroupKind {
    /// Event identity, schedule, venue and contributors.
    Event,
    /// Post-event surveys and analytics.
    FollowUp,
    /// Attendees and enrollment queues.
    People,
    /// Labels, call for speakers and sessions.
    Program,
    /// Tickets and registration questions.
    Registration,
}

impl EventFormTabGroupKind {
    /// Returns the group heading label.
    pub(crate) fn label(self) -> &'static str {
        match self {
            EventFormTabGroupKind::Event => "Event",
            EventFormTabGroupKind::FollowUp => "Follow-up",
            EventFormTabGroupKind::People => "People",
            EventFormTabGroupKind::Program => "Program",
            EventFormTabGroupKind::Registration => "Registration",
        }
    }
}

/// Event editor tab rendered in the navigation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EventFormTabLink {
    /// Whether the tab is selected when the page loads.
    pub active: bool,
    /// Icon name rendered in the sidebar tab button.
    pub icon: &'static str,
    /// Tab label.
    pub label: &'static str,
    /// Section the tab activates.
    pub section: EventFormSection,

    /// Request that lazy-loads the section content on first open.
    pub lazy_load: Option<EventFormTabLazyLoad>,
}

/// Request that loads the content of an event editor section the first time
/// its tab is opened. The template turns it into escaped HTMX attributes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EventFormTabLazyLoad {
    /// Selector of the loading indicator.
    pub indicator: String,
    /// Selector of the element receiving the content.
    pub target: String,
    /// URL of the content.
    pub url: String,
}

/// Visibility key of an event editor tab shown conditionally.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EventFormTabVisibility {
    /// Shown while invitation requests are enabled or rows remain.
    InvitationRequests,
    /// Shown while surveys are available for the event.
    Surveys,
    /// Shown while the waitlist is enabled or rows remain.
    Waitlist,
}

/// Returns the event editor tab groups for the given page and flags.
///
/// Tabs keep the catalog order, the first tab starts active, and groups left
/// without tabs are dropped.
pub(crate) fn form_tab_groups(
    mode: &EventFormMode,
    flags: EventFormTabFlags,
) -> Vec<EventFormTabGroup> {
    let mut groups: Vec<EventFormTabGroup> = Vec::new();

    for tab in EVENT_FORM_TABS {
        // Skip tabs not available on this page or hidden by a page flag
        if !is_tab_available(tab, mode)
            || tab.visibility.is_some_and(|visibility| !flags.is_visible(visibility))
        {
            continue;
        }

        // Prepare the tab link, activating the first visible tab
        let link = EventFormTabLink {
            active: groups.is_empty(),
            icon: tab.icon,
            label: tab.label,
            section: tab.section,

            lazy_load: lazy_load(tab.section, mode),
        };

        // Append the tab to its group, opening the group when it changes
        match groups.last_mut() {
            Some(group) if group.kind == tab.group => group.tabs.push(link),
            _ => groups.push(EventFormTabGroup {
                kind: tab.group,
                label: tab.group.label(),
                tabs: vec![link],
            }),
        }
    }

    groups
}

/// Returns true when the tab is available on the given page.
fn is_tab_available(tab: &EventFormTab, mode: &EventFormMode) -> bool {
    match (tab.availability, mode) {
        (EventFormTabAvailability::AddAndUpdate, _)
        | (EventFormTabAvailability::UpdateOnly, EventFormMode::Update { .. }) => true,
        (EventFormTabAvailability::UpdateOnly, EventFormMode::Add) => false,
    }
}

/// Returns the request that lazy-loads a section the first time its tab is
/// opened on the update page.
fn lazy_load(section: EventFormSection, mode: &EventFormMode) -> Option<EventFormTabLazyLoad> {
    // Only existing events have review content to load
    let EventFormMode::Update {
        attendee_approval_required,
        event_id,
    } = mode
    else {
        return None;
    };

    // Resolve the route and the content block of each lazy-loaded section
    let (path, content) = match section {
        EventFormSection::Attendees => ("attendees".to_string(), "attendees"),
        // Open every status when no request can be pending approval
        EventFormSection::InvitationRequests => {
            let query = if *attendee_approval_required {
                ""
            } else {
                "?status=all"
            };
            (format!("invitation-requests{query}"), "invitation-requests")
        }
        EventFormSection::Submissions => ("submissions".to_string(), "submissions"),
        EventFormSection::Surveys => ("surveys".to_string(), "surveys"),
        EventFormSection::Waitlist => ("waitlist".to_string(), "waitlist"),
        // Other sections render with the page or are loaded by page scripts
        EventFormSection::Analytics
        | EventFormSection::Cfs
        | EventFormSection::Cohosts
        | EventFormSection::DateVenue
        | EventFormSection::Details
        | EventFormSection::HostsSponsors
        | EventFormSection::Labels
        | EventFormSection::Payments
        | EventFormSection::Questions
        | EventFormSection::Sessions => return None,
    };

    Some(EventFormTabLazyLoad {
        indicator: format!("#{content}-loading"),
        target: format!("#{content}-content"),
        url: format!("/dashboard/group/events/{event_id}/{path}"),
    })
}
