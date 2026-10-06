//! Community dashboard contact types.

use std::fmt::Write as _;

use garde::Validate;
use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, utf8_percent_encode};
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{types::group::GroupRole, validation::MAX_CONTACT_FILTER_VALUES};

#[cfg(test)]
mod tests;

/// Characters `URLSearchParams` leaves unescaped when serializing form data.
const FORM_URLENCODED_SAFE: &AsciiSet =
    &NON_ALPHANUMERIC.remove(b'*').remove(b'-').remove(b'.').remove(b'_');

/// Filters used to select the group team members a community email targets.
///
/// An empty list means All for that filter. A team seat matches only when it
/// passes the three filters together.
#[derive(Debug, Clone, Default, Deserialize, Serialize, Validate)]
pub(crate) struct CommunityContactFilters {
    /// Group categories to include.
    #[serde(default)]
    #[garde(length(max = MAX_CONTACT_FILTER_VALUES))]
    pub group_category_ids: Vec<Uuid>,
    /// Regions to include, optionally including groups without a region.
    #[serde(default)]
    #[garde(length(max = MAX_CONTACT_FILTER_VALUES))]
    pub regions: Vec<RegionFilterValue>,
    /// Group team roles to include.
    #[serde(default)]
    #[garde(length(max = MAX_CONTACT_FILTER_VALUES))]
    pub roles: Vec<GroupRole>,
}

impl CommunityContactFilters {
    /// Returns the canonical form-encoded query of the filters.
    ///
    /// Values keep their submitted order and use the same names and encoding
    /// as the dashboard filter inputs serialized with `URLSearchParams`, so the
    /// page can tell which filters a recipients summary was computed for.
    pub(crate) fn to_canonical_query(&self) -> String {
        let pairs = self
            .group_category_ids
            .iter()
            .map(|id| ("filters[group_category_ids][]", id.to_string()))
            .chain(
                self.regions
                    .iter()
                    .map(|region| ("filters[regions][]", String::from(region.clone()))),
            )
            .chain(self.roles.iter().map(|role| ("filters[roles][]", role.to_string())));

        let mut query = String::new();
        for (name, value) in pairs {
            if !query.is_empty() {
                query.push('&');
            }
            let _ = write!(
                query,
                "{}={}",
                utf8_percent_encode(name, FORM_URLENCODED_SAFE),
                utf8_percent_encode(&value, FORM_URLENCODED_SAFE)
            );
        }
        query
    }
}

/// Filter options offered on the community contact page.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub(crate) struct CommunityContactFilterOptions {
    /// Community group categories.
    pub group_categories: Vec<CommunityContactGroupCategoryOption>,
    /// Number of active groups without a region.
    pub no_region_groups_count: usize,
    /// Community regions.
    pub regions: Vec<CommunityContactRegionOption>,
}

/// Group category option for the community contact filters.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct CommunityContactGroupCategoryOption {
    /// Group category identifier.
    pub group_category_id: Uuid,
    /// Number of active groups in the category.
    pub groups_count: usize,
    /// Group category name.
    pub name: String,
}

/// Group contributing matching team seats to a community contact summary.
#[skip_serializing_none]
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct CommunityContactRecipientGroup {
    /// Group category name.
    pub group_category_name: String,
    /// Group identifier.
    pub group_id: Uuid,
    /// Group name.
    pub name: String,
    /// Number of matching team seats in the group.
    pub seats_count: usize,

    /// Group region name.
    pub region_name: Option<String>,
}

/// Recipients matched by a set of community contact filters.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub(crate) struct CommunityContactRecipientsSummary {
    /// Groups contributing matching team seats, ordered by name.
    pub groups: Vec<CommunityContactRecipientGroup>,
    /// Number of groups contributing matching team seats.
    pub groups_count: usize,
    /// Number of distinct people who would receive the email.
    pub people_count: usize,
    /// Number of matching team seats.
    pub seats_count: usize,
}

/// Region option for the community contact filters.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub(crate) struct CommunityContactRegionOption {
    /// Number of active groups in the region.
    pub groups_count: usize,
    /// Region name.
    pub name: String,
    /// Region identifier.
    pub region_id: Uuid,
}

/// Region filter value, either a region or groups without a region.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(into = "String", try_from = "String")]
pub(crate) enum RegionFilterValue {
    /// Groups without a region, encoded as `none`.
    NoRegion,
    /// Groups in the region.
    Region(Uuid),
}

impl From<RegionFilterValue> for String {
    fn from(value: RegionFilterValue) -> Self {
        match value {
            RegionFilterValue::NoRegion => "none".to_string(),
            RegionFilterValue::Region(region_id) => region_id.to_string(),
        }
    }
}

impl TryFrom<String> for RegionFilterValue {
    type Error = uuid::Error;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        if value == "none" {
            return Ok(RegionFilterValue::NoRegion);
        }
        Uuid::parse_str(&value).map(RegionFilterValue::Region)
    }
}
