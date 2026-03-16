//! Templates and types for the site explore page.

use anyhow::Result;
use askama::Template;
use minify_html::{Cfg as MinifyCfg, minify};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use tracing::instrument;

use crate::{
    db::BBox,
    templates::{
        PageId,
        auth::User,
        community::{EventCard as HomeEventCard, GroupCard as HomeGroupCard},
        filters,
        helpers::user_initials,
    },
    types::{
        event::{EventKind, EventSummary},
        group::GroupSummary,
        pagination::NavigationLinks,
        search::{SearchEventsFilters, SearchGroupsFilters, ViewMode},
        site::SiteSettings,
    },
};

// Pages and sections templates.

/// Template for the explore page.
///
/// This is the root template that renders the explore page with either events or groups
/// content based on the selected entity.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/page.html")]
pub(crate) struct Page {
    /// The type of content being explored (events or groups).
    pub entity: Entity,
    /// Identifier for the current page.
    pub page_id: PageId,
    /// Current URL path.
    pub path: String,
    /// Global site settings.
    pub site_settings: SiteSettings,
    /// Authenticated user information.
    pub user: User,

    /// Events section data, populated when exploring events.
    pub events_section: Option<EventsSection>,
    /// Groups section data, populated when exploring groups.
    pub groups_section: Option<GroupsSection>,
}

/// Template for the events section of the explore page.
///
/// This template renders the events exploration interface, including filters panel and
/// results. It's used when `Entity::Events` is selected.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/events/section.html")]
pub(crate) struct EventsSection {
    /// Active filters for events search.
    pub filters: SearchEventsFilters,
    /// Available filter options (categories, regions, etc.).
    pub filters_options: FiltersOptions,
    /// Results section containing matching events.
    pub results_section: EventsResultsSection,
}

/// Template for displaying event search results.
///
/// This template renders the list of matching events along with pagination controls. It
/// supports different view modes and includes geographic bounds for map display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/events/results.html")]
pub(crate) struct EventsResultsSection {
    /// List of events matching the current filters.
    pub events: Vec<EventCard>,
    /// Pagination links for navigating results.
    pub navigation_links: NavigationLinks,
    /// Total number of matching events (for pagination).
    pub total: usize,

    /// Geographic bounds of all events (for map centering).
    pub bbox: Option<BBox>,
    /// Current pagination offset.
    pub offset: Option<usize>,
    /// Current display mode.
    pub view_mode: Option<ViewMode>,
}

impl EventsResultsSection {
    /// Return the entity to which the results belong.
    #[allow(clippy::unused_self)]
    pub(crate) fn entity(&self) -> Entity {
        Entity::Events
    }
}

/// Event card template for explore page display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/events/event_card.html")]
pub(crate) struct EventCard {
    /// Event data
    #[serde(flatten)]
    pub event: EventSummary,
}

/// Template for the groups section of the explore page.
///
/// This template renders the groups exploration interface, including filters panel and
/// results. It's used when `Entity::Groups` is selected.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/groups/section.html")]
pub(crate) struct GroupsSection {
    /// Active filters for groups search.
    pub filters: SearchGroupsFilters,
    /// Available filter options (categories, regions, etc.).
    pub filters_options: FiltersOptions,
    /// Results section containing matching groups.
    pub results_section: GroupsResultsSection,
}

/// Template for displaying group search results.
///
/// This template renders the list of matching groups along with pagination controls. It
/// supports different view modes and includes geographic bounds for map display.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/groups/results.html")]
pub(crate) struct GroupsResultsSection {
    /// List of groups matching the current filters.
    pub groups: Vec<GroupCard>,
    /// Pagination links for navigating results.
    pub navigation_links: NavigationLinks,
    /// Total number of matching groups (for pagination).
    pub total: usize,

    /// Geographic bounds of all groups (for map centering).
    pub bbox: Option<BBox>,
    /// Current pagination offset.
    pub offset: Option<usize>,
    /// Current display mode.
    pub view_mode: Option<ViewMode>,
}

impl GroupsResultsSection {
    /// Return the entity to which the results belong.
    #[allow(clippy::unused_self)]
    pub(crate) fn entity(&self) -> Entity {
        Entity::Groups
    }
}

/// Group card template for explore page display.
#[skip_serializing_none]
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "site/explore/groups/group_card.html")]
pub(crate) struct GroupCard {
    /// Group data
    #[serde(flatten)]
    pub group: GroupSummary,
}

// Types.

/// Represents the type of content being explored.
///
/// The explore page can display either events or groups. This enum determines which
/// section is shown.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString)]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum Entity {
    /// Explore events (default).
    #[default]
    Events,
    /// Explore groups.
    Groups,
}

impl From<Option<&str>> for Entity {
    fn from(entity: Option<&str>) -> Self {
        entity.and_then(|value| value.parse().ok()).unwrap_or_default()
    }
}

/// Available options for filters.
///
/// This struct provides the lists of available options for some filters.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct FiltersOptions {
    /// Available communities.
    pub communities: Vec<FilterOption>,
    /// Available distance options (e.g., 5km, 10km, 25km).
    pub distance: Vec<FilterOption>,

    /// Available event categories.
    #[serde(default)]
    pub event_category: Option<Vec<FilterOption>>,
    /// Available group categories.
    #[serde(default)]
    pub group_category: Option<Vec<FilterOption>>,
    /// Available groups (only when filtering events within a community).
    #[serde(default)]
    pub groups: Option<Vec<FilterOption>>,
    /// Available geographic regions.
    #[serde(default)]
    pub region: Option<Vec<FilterOption>>,
}

/// Individual filter option with display name and value.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct FilterOption {
    /// Display name shown to users.
    pub name: String,
    /// Technical value used in queries.
    pub value: String,
}

// Helpers for rendering popovers.

/// Render popover HTML for map and calendar views for an event.
#[instrument(skip_all, err)]
pub(crate) fn render_event_popover(event: &EventSummary) -> Result<String> {
    let home_event = HomeEventCard { event: event.clone() };
    let cfg = MinifyCfg::new();
    Ok(String::from_utf8(minify(home_event.render()?.as_bytes(), &cfg))?)
}

/// Render popover HTML for map views for a group.
#[instrument(skip_all, err)]
pub(crate) fn render_group_popover(group: &GroupSummary) -> Result<String> {
    let home_group = HomeGroupCard { group: group.clone() };
    let cfg = MinifyCfg::new();
    Ok(String::from_utf8(minify(home_group.render()?.as_bytes(), &cfg))?)
}
