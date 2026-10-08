//! Templates for the contact section of the community dashboard.

use askama::Template;
use serde::{Deserialize, Serialize};

use crate::types::{
    dashboard::community::contact::{
        CommunityContactFilterOptions, CommunityContactRecipientsSummary,
    },
    group::GroupRoleSummary,
};

#[cfg(test)]
mod tests;

/// Group role identifiers in the order the role filter displays them.
const ROLES_ORDER: [&str; 4] = ["admin", "events-manager", "check-in-manager", "viewer"];

// Pages templates.

/// Contact page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/contact.html")]
pub(crate) struct Page {
    /// Whether the current user can send emails to group teams.
    pub can_send: bool,
    /// Default subject for the notification email.
    pub default_notification_subject: String,
    /// Filter options available in the community.
    pub filter_options: CommunityContactFilterOptions,
    /// Canonical query of the filters the initial summary was computed for.
    pub filters_key: String,
    /// Group team roles available in the role filter.
    pub roles: Vec<GroupRoleSummary>,
    /// Recipients matching the initial filters.
    pub summary: CommunityContactRecipientsSummary,
}

impl Page {
    /// Returns the group category filter options with their group counts.
    pub(crate) fn category_options(&self) -> Vec<MultiSelectOption> {
        self.filter_options
            .group_categories
            .iter()
            .map(|category| MultiSelectOption {
                name: format!("{} ({})", category.name, category.groups_count),
                value: category.group_category_id.to_string(),
            })
            .collect()
    }

    /// Returns whether the community has regions to filter by.
    pub(crate) fn has_regions(&self) -> bool {
        !self.filter_options.regions.is_empty()
    }

    /// Returns the region filter options with their group counts, followed by
    /// the option selecting groups without a region.
    pub(crate) fn region_options(&self) -> Vec<MultiSelectOption> {
        self.filter_options
            .regions
            .iter()
            .map(|region| MultiSelectOption {
                name: format!("{} ({})", region.name, region.groups_count),
                value: region.region_id.to_string(),
            })
            .chain(std::iter::once(MultiSelectOption {
                name: format!("No region ({})", self.filter_options.no_region_groups_count),
                value: "none".to_string(),
            }))
            .collect()
    }

    /// Returns the group role filter options in their fixed display order.
    pub(crate) fn role_options(&self) -> Vec<MultiSelectOption> {
        let mut roles: Vec<&GroupRoleSummary> = self.roles.iter().collect();
        roles.sort_by_key(|role| {
            ROLES_ORDER
                .iter()
                .position(|id| *id == role.group_role_id)
                .unwrap_or(ROLES_ORDER.len())
        });
        roles
            .into_iter()
            .map(|role| MultiSelectOption {
                name: role.display_name.clone(),
                value: role.group_role_id.clone(),
            })
            .collect()
    }
}

/// Recipients summary partial template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/community/contact_recipients.html")]
pub(crate) struct RecipientsSummary {
    /// Canonical query of the filters the summary was computed for.
    pub filters_key: String,
    /// Recipients matching the filters.
    pub summary: CommunityContactRecipientsSummary,
}

// Types.

/// Option offered by a `<multi-select>` filter.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub(crate) struct MultiSelectOption {
    /// Label shown for the option.
    pub name: String,
    /// Value submitted when the option is selected.
    pub value: String,
}
