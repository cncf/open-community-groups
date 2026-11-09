//! Templates for the group dashboard settings page.

use askama::Template;

use crate::types::{
    group::{GroupCategory, GroupFull, GroupParentOption, GroupRegion},
    payments::GroupExternalPaymentsContext,
    utm::GroupUtmSettings,
};

#[cfg(test)]
mod tests;

// Pages templates.

/// Update page template for group settings.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage settings.
    pub can_manage_settings: bool,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
    /// UTM mediums every group accepts by default.
    pub default_utm_mediums: Vec<String>,
    /// Group-level external-payments eligibility and window limits.
    pub external_payments: GroupExternalPaymentsContext,
    /// Group information.
    pub group: GroupFull,
    /// Whether this group has non-deleted child links.
    pub has_child_links: bool,
    /// List of groups that can be selected as parents.
    pub parent_options: Vec<GroupParentOption>,
    /// Whether payments are globally enabled.
    pub payments_enabled: bool,
    /// List of available regions.
    pub regions: Vec<GroupRegion>,
    /// UTM values the group accepts for its event page views.
    pub utm: GroupUtmSettings,
}

impl UpdatePage {
    /// Returns true when the Fiscal Sponsor controls are rendered: either the
    /// group country allows Stripe onboarding, or a stored recipient can still
    /// be renamed or cleared.
    pub(crate) fn shows_fiscal_sponsor_fields(&self) -> bool {
        !self.external_payments.stripe_onboarding_blocked()
            || self.group.payment_recipient.is_some()
    }
}
