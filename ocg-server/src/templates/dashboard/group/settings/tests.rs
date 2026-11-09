use askama::Template;
use uuid::Uuid;

use crate::{
    test_util::{normalize_whitespace, opening_tag_with},
    types::{
        group::GroupFull,
        payments::{GroupExternalPaymentsContext, GroupPaymentRecipient, PaymentProvider},
        utm::GroupUtmSettings,
    },
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

#[test]
fn test_update_page_explains_locked_external_payments_toggle() {
    // Setup the external payments states to render
    let not_configured_message = "External payments are not configured for this deployment, so \
                                  this option cannot be changed.";
    let cases = [
        (
            "not configured while enabled",
            GroupExternalPaymentsContext::default(),
            true,
            true,
            true,
        ),
        (
            "configured and eligible",
            allowlisted_context(),
            false,
            false,
            false,
        ),
        (
            "configured, ineligible and not enabled",
            GroupExternalPaymentsContext {
                configured: true,
                ..GroupExternalPaymentsContext::default()
            },
            false,
            false,
            true,
        ),
    ];

    for (name, external_payments, group_enabled, shows_message, toggle_disabled) in cases {
        // Render the update page for this state
        let mut page = sample_page(external_payments, None);
        page.group.external_payments_enabled = group_enabled;
        let html = page.render().unwrap();

        // Check the not configured explanation
        assert_eq!(
            normalize_whitespace(&html).contains(not_configured_message),
            shows_message,
            "{name}: not configured explanation"
        );

        // Check whether the toggle can be changed
        let toggle = opening_tag_with(&html, r#"id="external_payments_enabled""#);
        assert_eq!(
            toggle.contains(" disabled"),
            toggle_disabled,
            "{name}: toggle disabled state"
        );
    }
}

#[test]
fn test_update_page_keeps_cleared_payment_fields_in_submission() {
    // Render the update page
    let html = sample_page(GroupExternalPaymentsContext::default(), None)
        .render()
        .unwrap();

    // Check the form keeps blank payment fields in the submitted parameters
    let form = opening_tag_with(&html, r#"id="groups-form""#);
    assert!(form.contains(
        r#"data-hx-keep-empty="external_payments_seller_display_name payment_recipient[recipient_id] payment_recipient[seller_display_name]""#
    ));
}

#[test]
fn test_update_page_renders_group_id_in_details() {
    // Setup page for one group
    let group_id = Uuid::from_u128(7);
    let mut page = sample_page(GroupExternalPaymentsContext::default(), None);
    page.group.group_id = group_id;

    // Render the page
    let html = normalize_whitespace(&page.render().unwrap());

    // Check the details title shows the group id
    assert!(html.contains("(ID: "));
    assert!(html.contains(&format!(">{group_id}</span>)")));
}

#[test]
fn test_update_page_shows_payee_required_hint_only_when_editable() {
    let required_hint = "(required while enabled)";

    // Check an eligible group sees the required hint
    let html = sample_page(allowlisted_context(), None).render().unwrap();
    assert!(html.contains(required_hint));

    // Render an ineligible group that has not enabled external payments
    let ineligible = GroupExternalPaymentsContext {
        configured: true,
        ..GroupExternalPaymentsContext::default()
    };
    let html = sample_page(ineligible, None).render().unwrap();

    // Check the disabled payee field has no required hint
    let payee = opening_tag_with(&html, r#"id="external_payments_seller_display_name""#);
    assert!(payee.contains(" disabled"));
    assert!(!html.contains(required_hint));
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
        default_utm_mediums: Vec::new(),
        external_payments,
        group: GroupFull {
            payment_recipient,
            ..GroupFull::default()
        },
        has_child_links: false,
        parent_options: Vec::new(),
        payments_enabled: true,
        regions: Vec::new(),
        utm: GroupUtmSettings::default(),
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
