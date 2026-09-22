//! Templates for the group dashboard settings page.

use askama::Template;

use crate::types::{
    group::{GroupCategory, GroupFull, GroupParentOption, GroupRegion},
    payments::GroupExternalPaymentsContext,
};

// Pages templates.

/// Update page template for group settings.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/settings_update.html")]
pub(crate) struct UpdatePage {
    /// Whether the current user can manage settings.
    pub can_manage_settings: bool,
    /// List of available group categories.
    pub categories: Vec<GroupCategory>,
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

#[cfg(test)]
mod tests {
    use crate::types::{
        group::GroupFull,
        payments::{GroupExternalPaymentsContext, GroupPaymentRecipient, PaymentProvider},
    };

    use super::UpdatePage;

    #[test]
    fn test_shows_fiscal_sponsor_fields_hides_controls_when_blocked_without_recipient() {
        let page = sample_page(allowlisted_context(), None);

        assert!(!page.shows_fiscal_sponsor_fields());
    }

    #[test]
    fn test_shows_fiscal_sponsor_fields_keeps_controls_for_stored_recipient_when_blocked() {
        let page = sample_page(allowlisted_context(), Some(sample_recipient()));

        assert!(page.shows_fiscal_sponsor_fields());
    }

    #[test]
    fn test_shows_fiscal_sponsor_fields_shows_controls_when_not_blocked() {
        let page = sample_page(GroupExternalPaymentsContext::default(), None);

        assert!(page.shows_fiscal_sponsor_fields());
    }

    // Helpers.

    /// Context for a group whose country is on the operator allowlist.
    fn allowlisted_context() -> GroupExternalPaymentsContext {
        GroupExternalPaymentsContext {
            configured: true,
            eligible: true,
            enabled: false,
            country_code: Some("KR".to_string()),
            default_payment_window_hours: Some(72),
            max_payment_window_hours: Some(336),
            seller_display_name: None,
        }
    }

    /// Settings page with the given external-payments context and recipient.
    fn sample_page(
        external_payments: GroupExternalPaymentsContext,
        payment_recipient: Option<GroupPaymentRecipient>,
    ) -> UpdatePage {
        UpdatePage {
            can_manage_settings: true,
            categories: Vec::new(),
            external_payments,
            group: GroupFull {
                payment_recipient,
                ..GroupFull::default()
            },
            has_child_links: false,
            parent_options: Vec::new(),
            payments_enabled: true,
            regions: Vec::new(),
        }
    }

    /// Stored Stripe fiscal sponsor.
    fn sample_recipient() -> GroupPaymentRecipient {
        GroupPaymentRecipient {
            provider: PaymentProvider::Stripe,
            recipient_id: "acct_stored".to_string(),
            seller_display_name: "Stored Fiscal Sponsor".to_string(),
        }
    }
}
