//! Site explore page types.

use serde::{Deserialize, Serialize};

/// Represents the type of content being explored.
///
/// The explore page can display either events or groups. This enum determines which
/// section is shown.
#[derive(
    Debug, Clone, Default, PartialEq, Serialize, Deserialize, strum::Display, strum::EnumString,
)]
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

/// Individual filter option with display name and value.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct FilterOption {
    /// Display name shown to users.
    pub name: String,
    /// Technical value used in queries.
    pub value: String,
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
