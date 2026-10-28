use anyhow::anyhow;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        error::{HandlerError, INVALID_REQUEST_PAYLOAD},
        tests::*,
    },
    services::payments::{
        AutomaticTaxReadiness, AutomaticTaxReadinessError, FiscalSponsorReadinessError,
        MockPaymentsManager,
    },
    types::{
        dashboard::community::groups::GroupInput,
        group::{GroupFull, GroupParentOption},
        payments::{GroupExternalPaymentsContext, GroupPaymentRecipient, PaymentProvider},
        permissions::GroupPermission,
        utm::GroupUtmSettings,
    },
};

use super::upcoming_event_automatic_tax_error;

/// Route serving the group settings page and update action.
const SETTINGS_URL: &str = "/dashboard/group/settings/update";

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group = GroupFull {
        custom_logo_url: Some("https://example.test/group-logo.png".to_string()),
        description_short: Some("Short group description".to_string()),
        logo_url: "https://example.test/group-logo.png".to_string(),
        ..sample_group_full(ids.community_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(
        &mut db,
        &ids,
        unconfigured_external_payments(),
        group,
        vec![],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_image_field_value(&html, "logo_url", "https://example.test/group-logo.png");
    assert!(html.contains(r#"value="Short group description""#));
    assert!(html.contains(r#"name="utm_present" value="true""#));
    assert!(html.contains(r#"items="[&#34;newsletter&#34;]""#));
    assert!(html.contains(r#"items="[&#34;spring-launch&#34;]""#));
    assert!(html.contains(r#"items="[&#34;podcast&#34;]""#));
    assert!(html.contains(r#"excluded-values="[&#34;email&#34;,&#34;social&#34;]""#));
    assert!(html.contains(">email</li>"));
    assert!(html.contains(">social</li>"));
}

#[tokio::test]
async fn test_update_page_leaves_logo_field_empty_without_own_logo() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let group = GroupFull {
        custom_logo_url: None,
        logo_url: "https://example.test/community-logo.png".to_string(),
        ..sample_group_full(ids.community_id, ids.group_id)
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(
        &mut db,
        &ids,
        unconfigured_external_payments(),
        group,
        vec![],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let html = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the community fallback logo is not prefilled
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert_image_field_value(&html, "logo_url", "");
}

#[tokio::test]
async fn test_update_page_selects_current_inactive_parent_option() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let parent_group_id = Uuid::new_v4();
    let group = sample_group_full(ids.community_id, ids.group_id);
    let parent_option = GroupParentOption {
        active: false,
        group_id: parent_group_id,
        is_current: true,
        is_selectable: false,
        name: "Inactive Parent".to_string(),
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(
        &mut db,
        &ids,
        unconfigured_external_payments(),
        group,
        vec![parent_option],
    );

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let option_start = body
        .find(&format!("value=\"{parent_group_id}\""))
        .expect("parent option should render");
    let option_end = body[option_start..]
        .find("</option>")
        .expect("parent option should close");
    let option_html = &body[option_start..option_start + option_end];
    assert!(option_html.contains("selected"));
    assert!(option_html.contains("(current, no longer selectable)"));
}

#[tokio::test]
async fn test_update_page_hides_fiscal_sponsor_controls_when_onboarding_is_blocked() {
    // Setup an allowlisted group without a stored recipient
    let ids = DashboardIds::new();
    let group = sample_group_full(ids.community_id, ids.group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(
        &mut db,
        &ids,
        allowlisted_external_payments(),
        group,
        vec![],
    );

    // Render the page with Stripe payments enabled
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the notice replaces every payment recipient control
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("A Stripe connected account cannot be added or changed here"));
    assert!(body.contains("United States"));
    assert!(!body.contains("name=\"payment_recipient[provider]\""));
    assert!(!body.contains("name=\"payment_recipient[recipient_id]\""));
    assert!(!body.contains("name=\"payment_recipient[seller_display_name]\""));
    assert!(!body.contains("id=\"payment_recipient_recipient_id\""));
    assert!(body.contains(
        "data-hx-keep-empty=\"external_payments_seller_display_name payment_recipient[recipient_id] payment_recipient[seller_display_name]\""
    ));
}

#[tokio::test]
async fn test_update_page_keeps_fiscal_sponsor_controls_for_stored_recipient_when_blocked() {
    // Setup an allowlisted group with a stored recipient
    let ids = DashboardIds::new();
    let mut group = sample_group_full(ids.community_id, ids.group_id);
    group.payment_recipient = Some(sample_group_payment_recipient());

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(
        &mut db,
        &ids,
        allowlisted_external_payments(),
        group,
        vec![],
    );

    // Render the page with Stripe payments enabled
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the notice and the prefilled controls render together
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("A Stripe connected account cannot be added or changed here"));
    assert!(body.contains("The stored fiscal sponsor can still be used for paid events on Stripe"));
    assert!(body.contains("name=\"payment_recipient[provider]\""));
    assert!(body.contains("name=\"payment_recipient[recipient_id]\""));
    assert!(body.contains("name=\"payment_recipient[seller_display_name]\""));
    assert!(body.contains("value=\"acct_test\""));
    assert!(body.contains("value=\"Test Fiscal Sponsor\""));
}

#[tokio::test]
async fn test_update_page_shows_fiscal_sponsor_controls_when_onboarding_is_open() {
    // Setup a group whose country is not allowlisted
    let ids = DashboardIds::new();
    let group = sample_group_full(ids.community_id, ids.group_id);
    let external_payments = GroupExternalPaymentsContext {
        eligible: false,
        ..allowlisted_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(&mut db, &ids, external_payments, group, vec![]);

    // Render the page with Stripe payments enabled
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the regular Fiscal Sponsor section renders
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(!body.contains("A Stripe connected account cannot be added or changed here"));
    assert!(body.contains("The fiscal sponsor owns Tax Rate definitions in Stripe."));
    assert!(body.contains("name=\"payment_recipient[provider]\""));
    assert!(body.contains("name=\"payment_recipient[recipient_id]\""));
    assert!(body.contains("name=\"payment_recipient[seller_display_name]\""));
}

#[tokio::test]
async fn test_update_page_renders_external_payee_legal_name_for_enabled_group() {
    // Setup an allowlisted group that opted into external payments
    let ids = DashboardIds::new();
    let mut group = sample_group_full(ids.community_id, ids.group_id);
    group.external_payments_enabled = true;
    group.external_payments_seller_display_name = Some("External Payee Co".to_string());
    let external_payments = GroupExternalPaymentsContext {
        enabled: true,
        seller_display_name: Some("External Payee Co".to_string()),
        ..allowlisted_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(&mut db, &ids, external_payments, group, vec![]);

    // Render the page
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the editable legal name input renders with the stored value
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let input = external_payee_input(&body);
    assert!(input.contains("value=\"External Payee Co\""));
    assert!(!input.contains("disabled"));
}

#[tokio::test]
async fn test_update_page_keeps_external_payee_input_editable_for_delisted_enabled_group() {
    // Setup an enabled legacy group whose country left the allowlist without a payee name
    let ids = DashboardIds::new();
    let mut group = sample_group_full(ids.community_id, ids.group_id);
    group.external_payments_enabled = true;
    let external_payments = GroupExternalPaymentsContext {
        eligible: false,
        enabled: true,
        ..allowlisted_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(&mut db, &ids, external_payments, group, vec![]);

    // Render the page
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the legal name stays editable while the toggle is locked on
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("name=\"external_payments_enabled\""));
    let input = external_payee_input(&body);
    assert!(!input.contains("value="));
    assert!(!input.contains("disabled"));
}

#[tokio::test]
async fn test_update_page_disables_external_payee_input_for_ineligible_opted_out_group() {
    // Setup a group that cannot opt into external payments
    let ids = DashboardIds::new();
    let group = sample_group_full(ids.community_id, ids.group_id);
    let external_payments = GroupExternalPaymentsContext {
        eligible: false,
        ..allowlisted_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(&mut db, &ids, external_payments, group, vec![]);

    // Render the page
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the legal name input is disabled alongside the toggle
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let input = external_payee_input(&body);
    assert!(input.contains("disabled"));
}

#[tokio::test]
async fn test_update_page_renders_external_payments_section_for_enabled_group_without_config() {
    // Setup an enabled legacy group after the operator removed the external payments config
    let ids = DashboardIds::new();
    let mut group = sample_group_full(ids.community_id, ids.group_id);
    group.external_payments_enabled = true;
    let external_payments = GroupExternalPaymentsContext {
        enabled: true,
        ..unconfigured_external_payments()
    };

    // Setup database mock
    let mut db = MockDB::new();
    expect_update_page_context(&mut db, &ids, external_payments, group, vec![]);

    // Render the page without Stripe payments enabled
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, get_request(SETTINGS_URL, ids.session_id)).await;
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    // Check the section renders so the missing legal name can be saved
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(body.contains("name=\"external_payments_enabled\""));
    let input = external_payee_input(&body);
    assert!(!input.contains("disabled"));
}

#[tokio::test]
async fn test_update_trims_external_payments_seller_display_name() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.external_payments_enabled = Some(true);
    update.external_payments_seller_display_name = Some("  External Payee Co  ".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.external_payments_enabled == Some(true)
                && group.external_payments_seller_display_name.as_deref()
                    == Some("External Payee Co")
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_keeps_blank_external_payments_seller_display_name_for_clearing() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.external_payments_enabled = Some(false);
    update.external_payments_seller_display_name = Some("   ".to_string());

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.external_payments_seller_display_name.as_deref() == Some("")
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_normalizes_unchanged_payment_recipient() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let payment_recipient = sample_group_payment_recipient();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        recipient_id: format!("  {}  ", payment_recipient.recipient_id),
        seller_display_name: format!("  {}  ", payment_recipient.seller_display_name),
        ..payment_recipient.clone()
    });
    let name = update.name.clone();

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(Some(payment_recipient.clone())));
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.name == name
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.recipient_id == "acct_test"
                        && recipient.seller_display_name == "Test Fiscal Sponsor"
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Keep unchanged provider accounts independent of Stripe availability
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_passes_utm_values() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.utm_campaigns = Some(vec!["spring-launch".to_string()]);
    update.utm_mediums = Some(vec!["podcast".to_string()]);
    update.utm_present = Some(true);
    update.utm_sources = Some(vec!["newsletter".to_string(), "partner.site".to_string()]);

    // Setup database mock
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.utm_campaigns == Some(vec!["spring-launch".to_string()])
                && group.utm_mediums == Some(vec!["podcast".to_string()])
                && group.utm_present == Some(true)
                && group.utm_sources
                    == Some(vec!["newsletter".to_string(), "partner.site".to_string()])
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_rejects_invalid_utm_values() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.utm_present = Some(true);
    update.utm_sources = Some(vec!["News Letter".to_string()]);

    // Setup database mock that must not persist the invalid values
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_update_group().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the validation error is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(String::from_utf8(bytes.to_vec()).unwrap().contains("utm_sources"));
}

#[tokio::test]
async fn test_update_invalid_body() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_update_group().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request("PUT", SETTINGS_URL, ids.session_id, "invalid");
    let (parts, bytes) = send(router, request).await;

    // Check the fixed deserialization body is returned
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, INVALID_REQUEST_PAYLOAD);
}

#[tokio::test]
async fn test_update_binds_changed_sponsor_validation_to_locked_state() {
    // Setup a settings update replacing the fiscal sponsor
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(stripe_recipient("acct_new", "New Sponsor"));

    // Setup database mock loading one upcoming automatic-tax event
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    expect_sponsor_change_reads(
        &mut db,
        &ids,
        Some(stripe_recipient("acct_current", "Current Sponsor")),
        "US",
        false,
    );
    expect_automatic_tax_event_ids(&mut db, &ids, vec![event_id]);
    expect_event_full(&mut db, &ids, event_id);
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.payment_validation.as_ref().is_some_and(|validation| {
                    validation.require_automatic_tax
                        && validation
                            .expected_payment_recipient
                            .as_ref()
                            .is_some_and(|recipient| recipient.recipient_id == "acct_current")
                        && validation
                            .validated_payment_recipient
                            .as_ref()
                            .is_some_and(|recipient| recipient.recipient_id == "acct_new")
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Setup payments manager mock accepting the sponsor and the event venue
    let mut payments_manager = MockPaymentsManager::new();
    expect_validate_fiscal_sponsor(&mut payments_manager, "acct_new", Ok(()));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .withf(|recipient, _| recipient.recipient_id == "acct_new")
        .returning(|_, _| {
            Box::pin(async {
                Ok(AutomaticTaxReadiness {
                    cached: false,
                    fingerprint: "fingerprint".to_string(),
                    provider_tax_location_id: "loc_new".to_string(),
                    state_code: None,
                })
            })
        });

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the validated update is persisted
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_rejects_changed_sponsor_when_upcoming_event_is_not_ready() {
    // Setup a settings update replacing the fiscal sponsor
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(stripe_recipient("acct_new", "New Sponsor"));

    // Setup database mock loading one upcoming automatic-tax event
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    expect_sponsor_change_reads(
        &mut db,
        &ids,
        Some(stripe_recipient("acct_current", "Current Sponsor")),
        "US",
        false,
    );
    expect_automatic_tax_event_ids(&mut db, &ids, vec![event_id]);
    expect_event_full(&mut db, &ids, event_id);
    db.expect_update_group().never();

    // Setup payments manager mock accepting the sponsor and rejecting the event venue
    let mut payments_manager = MockPaymentsManager::new();
    expect_validate_fiscal_sponsor(&mut payments_manager, "acct_new", Ok(()));
    payments_manager
        .expect_ensure_automatic_tax_readiness()
        .times(1)
        .withf(|recipient, _| recipient.recipient_id == "acct_new")
        .returning(|_, _| Box::pin(async { Err(AutomaticTaxReadinessError::InvalidAddress) }));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the event-specific failure is reported without persisting
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes,
        "cannot update fiscal sponsor: upcoming event \"Test Event\" is not ready for payments: the venue address is invalid"
    );
}

#[tokio::test]
async fn test_update_rejects_changed_sponsor_when_provider_reports_not_ready() {
    // Setup a settings update replacing the fiscal sponsor
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let mut update = sample_group_update();
    update.payment_recipient = Some(stripe_recipient("acct_unready", "Unready Sponsor"));

    // Setup database mock that must not load events or persist
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    expect_sponsor_change_reads(
        &mut db,
        &ids,
        Some(stripe_recipient("acct_current", "Current Sponsor")),
        "US",
        false,
    );
    expect_automatic_tax_event_ids(&mut db, &ids, vec![event_id]);
    db.expect_get_event_full().never();
    db.expect_update_group().never();

    // Setup payments manager mock rejecting the sponsor at the provider boundary
    let mut payments_manager = MockPaymentsManager::new();
    expect_validate_fiscal_sponsor(
        &mut payments_manager,
        "acct_unready",
        Err(FiscalSponsorReadinessError::NotReady(
            "Stripe account is not ready".to_string(),
        )),
    );
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the provider rejection is reported without persisting
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes, "Stripe account is not ready");
}

#[tokio::test]
async fn test_update_rejects_new_sponsor_when_resulting_country_is_allowlisted() {
    // Setup a settings update adding a first fiscal sponsor
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.payment_recipient = Some(stripe_recipient("acct_new", "New Sponsor"));

    // Setup database mock reporting the resulting country as allowlisted
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    expect_sponsor_change_reads(&mut db, &ids, None, "US", true);
    db.expect_list_group_automatic_tax_readiness_event_ids().never();
    db.expect_update_group().never();

    // Forbid any provider call for the blocked request
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the policy rejection is reported before any provider call
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes,
        "stripe connected account cannot be added or changed for this group country"
    );
}

#[tokio::test]
async fn test_update_rejects_replacement_sponsor_when_moving_between_allowlisted_countries() {
    // Setup a settings update replacing the sponsor while moving to another allowlisted country
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.country_code = Some("JP".to_string());
    update.country_name = Some("Japan".to_string());
    update.payment_recipient = Some(stripe_recipient("acct_replacement", "Replacement Sponsor"));

    // Setup database mock evaluating the submitted country
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    expect_sponsor_change_reads(
        &mut db,
        &ids,
        Some(sample_group_payment_recipient()),
        "JP",
        true,
    );
    db.expect_list_group_automatic_tax_readiness_event_ids().never();
    db.expect_update_group().never();

    // Forbid any provider call for the blocked request
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();
    payments_manager.expect_ensure_automatic_tax_readiness().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the policy rejection is reported before any provider call
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        bytes,
        "stripe connected account cannot be added or changed for this group country"
    );
}

#[tokio::test]
async fn test_update_validates_sponsor_when_same_save_leaves_allowlist() {
    // Setup a settings update adding a sponsor while moving off the allowlist
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.country_code = Some("US".to_string());
    update.payment_recipient = Some(stripe_recipient("acct_new", "New Sponsor"));

    // Setup database mock reporting the submitted country as not allowlisted
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    expect_sponsor_change_reads(&mut db, &ids, None, "US", false);
    expect_automatic_tax_event_ids(&mut db, &ids, vec![]);
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.country_code.as_deref() == Some("US")
                && group.payment_validation.as_ref().is_some_and(|validation| {
                    !validation.require_automatic_tax
                        && validation.expected_payment_recipient.is_none()
                        && validation
                            .validated_payment_recipient
                            .as_ref()
                            .is_some_and(|recipient| recipient.recipient_id == "acct_new")
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Validate the new sponsor once at the provider boundary
    let mut payments_manager = MockPaymentsManager::new();
    expect_validate_fiscal_sponsor(&mut payments_manager, "acct_new", Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the update is persisted
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_saves_without_recipient_controls() {
    // Setup a settings update that omits every payment recipient field
    let ids = DashboardIds::new();
    let update = sample_group_update();
    assert!(!serde_qs::to_string(&update).unwrap().contains("payment_recipient"));

    // Setup database mock persisting without any recipient reads
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_get_group_payment_recipient().never();
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.description_short.as_deref() == Some("Updated short description")
                && group.payment_recipient.is_none()
                && group.payment_validation.is_none()
        })
        .returning(|_, _, _, _| Ok(()));

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the update is persisted with the recipient left untouched
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_renames_stored_sponsor_without_provider_calls() {
    // Setup a settings update changing only the stored sponsor's legal name
    let ids = DashboardIds::new();
    let stored_recipient = sample_group_payment_recipient();
    let mut update = sample_group_update();
    update.payment_recipient = Some(GroupPaymentRecipient {
        seller_display_name: "Renamed Fiscal Sponsor".to_string(),
        ..stored_recipient.clone()
    });

    // Setup database mock persisting the rename without policy checks
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(Some(stored_recipient.clone())));
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.payment_validation.is_none()
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.recipient_id == "acct_test"
                        && recipient.seller_display_name == "Renamed Fiscal Sponsor"
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the rename is persisted
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_clears_stored_sponsor_without_provider_calls() {
    // Setup a settings update submitting both sponsor fields blank
    let ids = DashboardIds::new();
    let mut update = sample_group_update();
    update.payment_recipient = Some(stripe_recipient("", ""));

    // Setup database mock handing the clearing recipient to the database
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::SettingsWrite);
    db.expect_get_group_payment_recipient().never();
    db.expect_get_group_external_payments_eligibility().never();
    db.expect_update_group()
        .times(1)
        .withf(move |user_id, community_id, group_id, group| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && *group_id == ids.group_id
                && group.payment_validation.is_none()
                && group.payment_recipient.as_ref().is_some_and(|recipient| {
                    recipient.provider == PaymentProvider::Stripe
                        && recipient.recipient_id.is_empty()
                        && recipient.seller_display_name.is_empty()
                })
        })
        .returning(|_, _, _, _| Ok(()));

    // Forbid any provider call
    let mut payments_manager = MockPaymentsManager::new();
    payments_manager.expect_validate_fiscal_sponsor().never();

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_manager(payments_manager)
        .build()
        .await;
    let (parts, bytes) = send(router, update_request(&ids, &update)).await;

    // Check the clear is handed to the database
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[test]
fn test_upcoming_event_automatic_tax_error() {
    let prefix =
        "cannot update fiscal sponsor: upcoming event \"Meetup\" is not ready for payments";
    let cases = [
        (
            "invalid address is prefixed",
            AutomaticTaxReadinessError::InvalidAddress,
            Some(format!("{prefix}: the venue address is invalid")),
        ),
        (
            "fiscal sponsor not ready is prefixed",
            AutomaticTaxReadinessError::FiscalSponsorNotReady(
                "sponsor tax settings are incomplete".to_string(),
            ),
            Some(format!("{prefix}: sponsor tax settings are incomplete")),
        ),
        (
            "unexpected failure passes through",
            AutomaticTaxReadinessError::Unexpected(anyhow!("provider unavailable")),
            None,
        ),
    ];

    for (label, error, expected_message) in cases {
        match (
            upcoming_event_automatic_tax_error("Meetup", error),
            expected_message,
        ) {
            (HandlerError::Rejected(message), Some(expected_message)) => {
                assert_eq!(message, expected_message, "{label}");
            }
            (HandlerError::Other(err), None) => {
                assert_eq!(err.to_string(), "provider unavailable", "{label}");
            }
            (error, expected) => panic!("{label}: got {error:?}, expected {expected:?}"),
        }
    }
}

// Helpers.

/// External-payments context for a group whose country is allowlisted.
fn allowlisted_external_payments() -> GroupExternalPaymentsContext {
    GroupExternalPaymentsContext {
        configured: true,
        eligible: true,
        enabled: false,
        country_code: Some("US".to_string()),
        default_payment_window_hours: Some(72),
        max_payment_window_hours: Some(336),
        seller_display_name: None,
    }
}

/// Expect the list of upcoming events that require automatic tax readiness.
fn expect_automatic_tax_event_ids(db: &mut MockDB, ids: &DashboardIds, event_ids: Vec<Uuid>) {
    let ids = *ids;
    db.expect_list_group_automatic_tax_readiness_event_ids()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(event_ids.clone()));
}

/// Expect the upcoming event rechecked against the new fiscal sponsor.
fn expect_event_full(db: &mut MockDB, ids: &DashboardIds, event_id: Uuid) {
    let ids = *ids;
    db.expect_get_event_full()
        .times(1)
        .withf(move |community_id, group_id, id| {
            *community_id == ids.community_id && *group_id == ids.group_id && *id == event_id
        })
        .returning(move |_, _, _| Ok(sample_event_full(ids.community_id, event_id, ids.group_id)));
}

/// Expect the stored recipient and allowlist reads made for a changed sponsor.
///
/// The current recipient and the allowlist result decide the scenario.
fn expect_sponsor_change_reads(
    db: &mut MockDB,
    ids: &DashboardIds,
    current_recipient: Option<GroupPaymentRecipient>,
    country_code: &'static str,
    allowlisted: bool,
) {
    let ids = *ids;
    db.expect_get_group_payment_recipient()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(current_recipient.clone()));
    db.expect_get_group_external_payments_eligibility()
        .times(1)
        .withf(move |community_id, group_id, submitted_country_code| {
            *community_id == ids.community_id
                && *group_id == ids.group_id
                && submitted_country_code.as_deref() == Some(country_code)
        })
        .returning(move |_, _, _| Ok(allowlisted));
}

/// Expect the session, permissions and reads the settings page always performs.
fn expect_update_page_context(
    db: &mut MockDB,
    ids: &DashboardIds,
    external_payments: GroupExternalPaymentsContext,
    group: GroupFull,
    parent_options: Vec<GroupParentOption>,
) {
    let ids = *ids;
    expect_group_access(db, &ids, GroupPermission::Read);
    expect_group_permission_result(db, &ids, GroupPermission::SettingsWrite, true);
    db.expect_get_group_full()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(group.clone()));
    db.expect_group_has_child_links()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| Ok(false));
    db.expect_list_group_categories()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(|_| Ok(vec![sample_group_category()]));
    db.expect_list_group_parent_options()
        .times(1)
        .withf(move |community_id, user_id, group_id| {
            *community_id == ids.community_id
                && *user_id == ids.user_id
                && *group_id == Some(ids.group_id)
        })
        .returning(move |_, _, _| Ok(parent_options.clone()));
    db.expect_list_regions()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(|_| Ok(vec![sample_group_region()]));
    db.expect_get_group_external_payments_context()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(move |_, _| Ok(external_payments.clone()));
    db.expect_get_group_utm_settings()
        .times(1)
        .withf(move |community_id, group_id| {
            *community_id == ids.community_id && *group_id == ids.group_id
        })
        .returning(|_, _| {
            Ok(GroupUtmSettings {
                campaigns: vec!["spring-launch".to_string()],
                mediums: vec!["podcast".to_string()],
                sources: vec!["newsletter".to_string()],
            })
        });
    db.expect_list_utm_mediums()
        .times(1)
        .returning(|| Ok(vec!["email".to_string(), "social".to_string()]));
}

/// Expect one fiscal sponsor validation for the recipient without a jurisdiction.
fn expect_validate_fiscal_sponsor(
    payments_manager: &mut MockPaymentsManager,
    recipient_id: &'static str,
    result: Result<(), FiscalSponsorReadinessError>,
) {
    payments_manager
        .expect_validate_fiscal_sponsor()
        .times(1)
        .withf(move |recipient, automatic_tax_jurisdiction| {
            recipient.provider == PaymentProvider::Stripe
                && recipient.recipient_id == recipient_id
                && automatic_tax_jurisdiction.is_none()
        })
        .return_once(move |_, _| Box::pin(async move { result }));
}

/// Returns the rendered external payee legal name input tag.
fn external_payee_input(body: &str) -> &str {
    let start = body
        .find("id=\"external_payments_seller_display_name\"")
        .expect("external payee input should render");
    let end = body[start..].find('>').expect("external payee input should close");
    &body[start..start + end]
}

/// Build a Stripe fiscal sponsor recipient.
fn stripe_recipient(recipient_id: &str, seller_display_name: &str) -> GroupPaymentRecipient {
    GroupPaymentRecipient {
        provider: PaymentProvider::Stripe,
        recipient_id: recipient_id.to_string(),
        seller_display_name: seller_display_name.to_string(),
    }
}

/// External-payments context for a community without payments configured.
fn unconfigured_external_payments() -> GroupExternalPaymentsContext {
    GroupExternalPaymentsContext {
        configured: false,
        eligible: false,
        enabled: false,
        country_code: None,
        default_payment_window_hours: None,
        max_payment_window_hours: None,
        seller_display_name: None,
    }
}

/// Build the form request that submits the settings update.
fn update_request(ids: &DashboardIds, update: &GroupInput) -> Request<Body> {
    form_request(
        "PUT",
        SETTINGS_URL,
        ids.session_id,
        serde_qs::to_string(update).unwrap(),
    )
}
