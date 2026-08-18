use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use axum::{
    Json, Router,
    http::{HeaderMap, HeaderValue, StatusCode, Uri},
    routing::{get, post},
};
use chrono::{TimeDelta, Utc};
use serde_json::json;
use tokio::task::JoinHandle;
use uuid::Uuid;

use crate::{
    config::PaymentsStripeConfig,
    services::payments::{
        ApplicationFeeAdjustmentInput, AutomaticTaxReadinessError, CreateCheckoutSessionInput,
        CreditNoteInput, FinancialDocumentKind, FindRefundInput, FiscalSponsorReadinessError,
        FiscalSponsorReadinessInput, GetCheckoutFinancialContextInput, GetFinancialDocumentInput,
        ListTaxRatesInput, PaymentsWebhookEvent, PerformanceLocationInput, RefundPaymentInput,
        RefundPaymentStatus, ValidateTaxRatesInput,
    },
    types::payments::{
        FiscalSponsorSeller, PaymentMode, PaymentProvider, TicketTaxBehavior,
        TicketTaxCalculationMode, TicketVenue,
    },
};

use super::{
    PaymentsProvider, PaymentsWebhookEndpoint, StripeListedRefund, StripeProvider,
    StripeTaxProductResponse, StripeTaxProductTaxDetailsResponse,
};

#[tokio::test]
async fn automatic_tax_location_omits_missing_state_code() {
    // Capture the performance-location request for a country without a subdivision
    let captured_body = Arc::new(Mutex::new(String::new()));
    let request_body = Arc::clone(&captured_body);
    let router = Router::new().route(
        "/v1/tax/locations",
        post(move |body: String| {
            let request_body = Arc::clone(&request_body);
            async move {
                *request_body
                    .lock()
                    .expect("captured request body lock to be available") = body;
                Json(json!({"id": "loc_created"}))
            }
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let mut input = sample_performance_location_input();
    input.venue.country_code = "PT".to_string();
    input.venue.state_code = None;

    // Create the location without inventing a subdivision
    let readiness = provider
        .create_performance_location(&input, super::STRIPE_API_VERSION)
        .await
        .expect("country without subdivision to create a location");
    server.abort();

    // Check Stripe receives no empty state parameter
    let form_fields: BTreeMap<String, String> = serde_urlencoded::from_str(
        &captured_body
            .lock()
            .expect("captured request body lock to be available"),
    )
    .expect("captured request body to be valid form data");
    assert_eq!(readiness.provider_tax_location_id, "loc_created");
    assert_eq!(readiness.state_code, None);
    assert!(!form_fields.contains_key("address[state]"));
}

#[tokio::test]
async fn automatic_tax_location_reuses_matching_persisted_cache_entry() {
    // Setup a checkout whose location snapshot still matches its persisted cache
    let provider = sample_stripe_provider();
    let mut input = sample_performance_location_input();
    input.venue.state_code = None;
    let location_fingerprint = input.venue.performance_location_fingerprint();
    input.cached_fingerprint = Some(location_fingerprint.clone());
    input.cached_provider_tax_location_id = Some("loc_cached".to_string());

    // Resolve the provider performance location
    let readiness = provider
        .create_performance_location(&input, super::STRIPE_API_VERSION)
        .await
        .expect("matching performance location to be reused");

    // Check no replacement was needed and the durable fingerprint is preserved
    assert!(readiness.cached);
    assert_eq!(readiness.provider_tax_location_id, "loc_cached");
    assert_eq!(readiness.fingerprint, location_fingerprint);
}

#[tokio::test]
async fn automatic_tax_location_sends_iso_country_and_state_codes() {
    // Capture the Stripe performance-location request body
    let captured_body = Arc::new(Mutex::new(String::new()));
    let request_body = Arc::clone(&captured_body);
    let router = Router::new().route(
        "/v1/tax/locations",
        post(move |body: String| {
            let request_body = Arc::clone(&request_body);
            async move {
                *request_body
                    .lock()
                    .expect("captured request body lock to be available") = body;
                Json(json!({"id": "loc_created"}))
            }
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let input = sample_performance_location_input();

    // Create the performance location through the provider boundary
    let readiness = provider
        .create_performance_location(&input, super::STRIPE_API_VERSION)
        .await
        .expect("complete ISO codes to create a performance location");
    server.abort();

    // Check Stripe receives code values rather than display names
    let form_fields: BTreeMap<String, String> = serde_urlencoded::from_str(
        &captured_body
            .lock()
            .expect("captured request body lock to be available"),
    )
    .expect("captured request body to be valid form data");
    assert_eq!(readiness.provider_tax_location_id, "loc_created");
    assert_eq!(
        form_fields.get("address[country]").map(String::as_str),
        Some("US")
    );
    assert_eq!(
        form_fields.get("address[state]").map(String::as_str),
        Some("CA")
    );
    assert!(!form_fields.values().any(|value| value == "California"));
}

#[tokio::test]
async fn automatic_tax_location_classifies_state_errors_only_from_exact_parameter() {
    // Check a missing state is reported only when Stripe identifies address[state]
    let missing = performance_location_error(
        json!({"error": {"message": "State is required", "param": "address[state]"}}),
        None,
    )
    .await;
    assert!(matches!(
        missing,
        AutomaticTaxReadinessError::StateCodeRequired { country_code }
            if country_code == "US"
    ));

    // Check a sent override is named when the same exact parameter is rejected
    let invalid = performance_location_error(
        json!({"error": {"message": "State is invalid", "param": "address[state]"}}),
        Some("ZZ"),
    )
    .await;
    assert!(matches!(
        invalid,
        AutomaticTaxReadinessError::StateCodeInvalid { country_code, state_code }
            if country_code == "US" && state_code == "ZZ"
    ));

    // Check a generic message mentioning state cannot override the structured parameter
    let generic = performance_location_error(
        json!({"error": {"message": "State is required", "param": "address[line1]"}}),
        None,
    )
    .await;
    assert!(matches!(
        generic,
        AutomaticTaxReadinessError::InvalidAddress
    ));
}

#[tokio::test]
async fn automatic_tax_location_keeps_country_and_address_errors_distinct() {
    // Check a rejected country remains distinct from a subdivision failure
    let country = performance_location_error(
        json!({"error": {"message": "Country is invalid", "param": "address[country]"}}),
        None,
    )
    .await;
    assert!(matches!(
        country,
        AutomaticTaxReadinessError::CountryInvalid { country_code }
            if country_code == "US"
    ));

    // Check Stripe's documented unsupported-location response remains distinct
    let unsupported = performance_location_error(
        json!({"error": {
            "message": super::STRIPE_TAX_UNSUPPORTED_COUNTRY_ERROR,
            "param": "address[country]"
        }}),
        None,
    )
    .await;
    assert!(matches!(
        &unsupported,
        AutomaticTaxReadinessError::UnsupportedCountry
    ));
    assert_eq!(
        unsupported.to_string(),
        "Stripe automatic tax is not supported for this venue country. Select Manual Stripe Tax Rates instead."
    );
}

#[test]
fn automatic_tax_product_cache_rejects_each_incomplete_or_changed_field() {
    // Setup mutations covering every Product field used by checkout
    let scenarios = [
        {
            let mut product = sample_stripe_tax_product();
            product.active = false;
            product
        },
        {
            let mut product = sample_stripe_tax_product();
            product.name = "Different ticket".to_string();
            product
        },
        {
            let mut product = sample_stripe_tax_product();
            product.tax_details = None;
            product
        },
        {
            let mut product = sample_stripe_tax_product();
            product
                .tax_details
                .as_mut()
                .expect("sample tax details to exist")
                .performance_location = Some("loc_other".to_string());
            product
        },
        {
            let mut product = sample_stripe_tax_product();
            product
                .tax_details
                .as_mut()
                .expect("sample tax details to exist")
                .tax_code = Some("txcd_other".to_string());
            product
        },
    ];

    for product in scenarios {
        // Compare each changed Product with the persisted snapshot
        assert!(!StripeProvider::tax_product_matches(
            &product,
            "Ticket",
            "loc_cached",
            "txcd_50013001"
        ));
    }
}

#[test]
fn automatic_tax_product_cache_requires_a_complete_active_match() {
    // Setup the complete provider Product expected by the checkout snapshot
    let product = sample_stripe_tax_product();

    // Compare the cached Product with every immutable checkout field
    assert!(StripeProvider::tax_product_matches(
        &product,
        "Ticket",
        "loc_cached",
        "txcd_50013001"
    ));
}

#[tokio::test]
async fn automatic_tax_product_propagates_cached_product_provider_errors() {
    // Setup a matching cache snapshot whose provider lookup fails
    let router = Router::new().route(
        "/v1/products/prod_cached",
        get(|| async { (StatusCode::SERVICE_UNAVAILABLE, "provider unavailable") }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let mut input = sample_checkout_session_input();
    let fingerprint = StripeProvider::provider_fingerprint(&[
        &input.ticket_title,
        "loc_cached",
        input.tax_code.as_deref().expect("sample tax code to exist"),
    ]);
    input.cached_product_fingerprint = Some(fingerprint);
    input.cached_provider_tax_product_id = Some("prod_cached".to_string());

    // Resolve the cached Product through the provider boundary
    let err = provider
        .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
        .await
        .expect_err("provider retrieval failure to remain actionable");
    server.abort();

    // Check transient provider failures are not treated as cache misses
    assert!(format!("{err:#}").contains("Product retrieval failed (503 Service Unavailable)"));
}

#[tokio::test]
async fn automatic_tax_product_replaces_mismatched_cache_with_stable_idempotency_key() {
    // Setup a cached Product that no longer matches the persisted snapshot
    let idempotency_keys = Arc::new(Mutex::new(Vec::new()));
    let captured_keys = Arc::clone(&idempotency_keys);
    let router = Router::new()
        .route(
            "/v1/products/prod_cached",
            get(|| async {
                Json(json!({
                    "active": false,
                    "name": "Ticket",
                    "tax_details": {
                        "performance_location": "loc_cached",
                        "tax_code": "txcd_50013001"
                    }
                }))
            }),
        )
        .route(
            "/v1/products",
            post(move |headers: HeaderMap| {
                let captured_keys = Arc::clone(&captured_keys);
                async move {
                    captured_keys
                        .lock()
                        .expect("captured idempotency keys lock to be available")
                        .push(
                            headers
                                .get("idempotency-key")
                                .expect("replacement request to include idempotency key")
                                .to_str()
                                .expect("idempotency key to be valid text")
                                .to_string(),
                        );
                    Json(json!({"id": "prod_replacement"}))
                }
            }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let mut input = sample_checkout_session_input();
    let fingerprint = StripeProvider::provider_fingerprint(&[
        &input.ticket_title,
        "loc_cached",
        input.tax_code.as_deref().expect("sample tax code to exist"),
    ]);
    input.cached_product_fingerprint = Some(fingerprint.clone());
    input.cached_provider_tax_product_id = Some("prod_cached".to_string());

    // Retry the same replacement operation through the provider boundary
    for _ in 0..2 {
        let (product_id, returned_fingerprint) = provider
            .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
            .await
            .expect("mismatched cached Product to be replaced");
        assert_eq!(product_id, "prod_replacement");
        assert_eq!(returned_fingerprint, fingerprint);
    }
    server.abort();

    // Check replacement attempts use the same cache-identity-derived key
    let replacement_fingerprint =
        StripeProvider::provider_fingerprint(&[&fingerprint, "prod_cached"]);
    assert_eq!(
        *idempotency_keys
            .lock()
            .expect("captured idempotency keys lock to be available"),
        vec![
            format!("ocg-tax-product-{replacement_fingerprint}"),
            format!("ocg-tax-product-{replacement_fingerprint}"),
        ]
    );
}

#[tokio::test]
async fn automatic_tax_product_replaces_provider_deleted_cache_entry() {
    // Setup a matching cache snapshot whose provider Product was deleted
    let router = Router::new()
        .route(
            "/v1/products/prod_cached",
            get(|| async { StatusCode::NOT_FOUND }),
        )
        .route(
            "/v1/products",
            post(|| async { Json(json!({"id": "prod_replacement"})) }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let mut input = sample_checkout_session_input();
    let fingerprint = StripeProvider::provider_fingerprint(&[
        &input.ticket_title,
        "loc_cached",
        input.tax_code.as_deref().expect("sample tax code to exist"),
    ]);
    input.cached_product_fingerprint = Some(fingerprint.clone());
    input.cached_provider_tax_product_id = Some("prod_cached".to_string());

    // Resolve the deleted cached Product through the provider boundary
    let (product_id, returned_fingerprint) = provider
        .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
        .await
        .expect("deleted cached Product to be replaced");
    server.abort();

    // Check provider deletion creates a replacement with the same durable fingerprint
    assert_eq!(product_id, "prod_replacement");
    assert_eq!(returned_fingerprint, fingerprint);
}

#[tokio::test]
async fn automatic_tax_product_reuses_complete_cached_product() {
    // Setup a cached Product that still matches every persisted snapshot field
    let router = Router::new().route(
        "/v1/products/prod_cached",
        get(|| async {
            Json(json!({
                "active": true,
                "name": "Ticket",
                "tax_details": {
                    "performance_location": "loc_cached",
                    "tax_code": "txcd_50013001"
                }
            }))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let mut input = sample_checkout_session_input();
    let fingerprint = StripeProvider::provider_fingerprint(&[
        &input.ticket_title,
        "loc_cached",
        input.tax_code.as_deref().expect("sample tax code to exist"),
    ]);
    input.cached_product_fingerprint = Some(fingerprint.clone());
    input.cached_provider_tax_product_id = Some("prod_cached".to_string());

    // Resolve the matching cached Product through the provider boundary
    let (product_id, returned_fingerprint) = provider
        .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
        .await
        .expect("complete cached Product to be reused");
    server.abort();

    // Check the provider Product and persisted fingerprint remain stable
    assert_eq!(product_id, "prod_cached");
    assert_eq!(returned_fingerprint, fingerprint);
}

#[test]
fn build_checkout_session_form_fields_includes_platform_fee_when_configured() {
    // Setup a checkout with a snapshotted platform fee
    let provider = sample_stripe_provider();
    let mut input = sample_checkout_session_input();
    input.provisional_platform_fee_amount_minor = 62;

    // Build the provider form fields
    let form_fields = checkout_session_form_fields_map(&provider, &input);

    // Check the platform fee is deducted from the sponsor's direct charge
    assert_eq!(
        form_fields.get("payment_intent_data[application_fee_amount]"),
        Some(&"62".to_string())
    );
}

#[test]
fn build_checkout_session_form_fields_omits_platform_fee_when_zero() {
    // Setup a checkout without a platform fee
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    // Build the provider form fields
    let form_fields = checkout_session_form_fields_map(&provider, &input);

    // Check no application fee is sent to Stripe
    assert!(!form_fields.contains_key("payment_intent_data[application_fee_amount]"));
}

#[test]
fn build_checkout_session_form_fields_populates_checkout_metadata() {
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    let form_fields = checkout_session_form_fields_map(&provider, &input);

    assert_eq!(
        form_fields.get("cancel_url"),
        Some(
            &"https://ocg.example.org/community/group/pretty-group/event/event?payment=canceled"
                .to_string()
        )
    );
    assert_eq!(
        form_fields.get("client_reference_id"),
        Some(&input.purchase_id.to_string())
    );
    assert_eq!(
        form_fields.get("line_items[0][price_data][currency]"),
        Some(&"usd".to_string())
    );
    assert_eq!(
        form_fields.get("payment_intent_data[metadata][discount_code]"),
        Some(&"EARLYBIRD".to_string())
    );
    assert!(!form_fields.keys().any(|key| key.starts_with("transfer_data")));
    assert_eq!(
        form_fields.get("metadata[environment]"),
        Some(&"test".to_string())
    );
    assert_eq!(
        form_fields.get("success_url"),
        Some(
            &"https://ocg.example.org/community/group/pretty-group/event/event?payment=success"
                .to_string()
        )
    );
}

#[test]
fn build_checkout_session_form_fields_restricts_checkout_to_card_payments() {
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    let form_fields = provider.build_checkout_session_form_fields(&input, Some("prod_ticket"));

    assert!(form_fields.contains(&("payment_method_types[0]".to_string(), "card".to_string())));
}

#[test]
fn build_refund_form_fields_only_refunds_the_direct_charge() {
    // Setup a refund for a direct charge
    let input = sample_refund_payment_input();

    // Build the provider form fields
    let form_fields = StripeProvider::build_refund_form_fields(&input);

    // Check the refund targets only the connected-account payment
    assert_eq!(form_fields.get("amount"), Some(&"2500".to_string()));
    assert_eq!(
        form_fields.get("metadata[event_purchase_id]"),
        Some(&input.purchase_id.to_string())
    );
    assert_eq!(
        form_fields.get("payment_intent"),
        Some(&"pi_test_123".to_string())
    );
    assert!(!form_fields.contains_key("reverse_transfer"));
    assert!(!form_fields.contains_key("refund_application_fee"));
}

#[tokio::test]
async fn create_checkout_session_scopes_the_direct_charge_and_invoice_request() {
    // Setup a manual-tax checkout and a Stripe-shaped connected-account API
    let mut input = sample_checkout_session_input();
    input.manual_tax_rate_ids = Some(vec!["txr_state".to_string(), "txr_local".to_string()]);
    input.tax_calculation_mode = TicketTaxCalculationMode::Manual;
    input.tax_code = None;
    let purchase_id = input.purchase_id;
    let router = Router::new()
        .route(
            "/v1/accounts/acct_test_123",
            get(|| async { Json(sample_stripe_account_response()) }),
        )
        .route(
            "/v1/tax_rates",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(uri.query(), Some("active=true&inclusive=true&limit=100"));
                Json(json!({
                    "data": [
                        {
                            "active": true,
                            "display_name": "Sales tax",
                            "id": "txr_state",
                            "inclusive": true,
                            "jurisdiction": "California",
                            "percentage": 8.875
                        },
                        {
                            "active": true,
                            "display_name": "District tax",
                            "id": "txr_local",
                            "inclusive": true,
                            "jurisdiction": "Example District",
                            "percentage": 1.25
                        }
                    ],
                    "has_more": false
                }))
            }),
        )
        .route(
            "/v1/checkout/sessions",
            post(move |headers: HeaderMap, body: String| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                assert_eq!(
                    headers["idempotency-key"]
                        .to_str()
                        .expect("idempotency key to be valid text"),
                    format!("event-purchase-checkout-{purchase_id}")
                );
                let form: BTreeMap<String, String> =
                    serde_urlencoded::from_str(&body).expect("checkout form to parse");
                assert_eq!(
                    form.get("invoice_creation[enabled]"),
                    Some(&"true".to_string())
                );
                assert_eq!(
                    form.get("line_items[0][tax_rates][0]"),
                    Some(&"txr_state".to_string())
                );
                assert_eq!(
                    form.get("line_items[0][tax_rates][1]"),
                    Some(&"txr_local".to_string())
                );
                assert!(!form.keys().any(|key| key.starts_with("transfer_data")));

                Json(json!({
                    "id": "cs_test_123",
                    "url": "https://checkout.stripe.test/session"
                }))
            }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Create the connected-account Checkout Session
    let session = provider
        .create_checkout_session(&input)
        .await
        .expect("direct-charge Checkout Session to be created");
    server.abort();

    // Check the account-scoped provider identity is retained for reconciliation
    assert_eq!(session.provider_object_account_id, "acct_test_123");
    assert_eq!(session.provider_session_id, "cs_test_123");
    assert_eq!(session.redirect_url, "https://checkout.stripe.test/session");
}

#[tokio::test]
async fn create_checkout_session_omits_tax_fields_for_no_tax_mode() {
    // Setup a no-tax checkout and a connected-account API
    let mut input = sample_checkout_session_input();
    input.manual_tax_rate_ids = Some(Vec::new());
    input.tax_calculation_mode = TicketTaxCalculationMode::None;
    input.tax_code = None;
    let router = Router::new()
        .route(
            "/v1/accounts/acct_test_123",
            get(|| async { Json(sample_stripe_account_response()) }),
        )
        .route(
            "/v1/checkout/sessions",
            post(|headers: HeaderMap, body: String| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                let form: BTreeMap<String, String> =
                    serde_urlencoded::from_str(&body).expect("checkout form to parse");
                assert!(!form.contains_key("automatic_tax[enabled]"));
                assert!(!form.keys().any(|key| key.contains("[tax_rates]")));
                assert!(form.contains_key("line_items[0][price_data][product_data][name]"));

                Json(json!({
                    "id": "cs_no_tax",
                    "url": "https://checkout.stripe.test/no-tax"
                }))
            }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Create the session without attaching a tax mechanism
    let session = provider
        .create_checkout_session(&input)
        .await
        .expect("no-tax Checkout Session to be created");
    server.abort();

    // Check the connected-account session is returned normally
    assert_eq!(session.provider_session_id, "cs_no_tax");
}

#[test]
fn find_matching_refund_result_ignores_terminal_refunds_when_unpinned() {
    // Setup an unpinned purchase refund lookup
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);

    for status in ["canceled", "failed"] {
        // Find refunds without pinning a provider refund id
        let refunds = vec![sample_listed_refund(purchase_id, "re_test_123", status)];

        // Check terminal refunds do not block a fresh attempt
        assert_eq!(
            StripeProvider::find_matching_refund_result(&input, refunds)
                .expect("refund lookup to parse"),
            None,
            "expected {status} refund to be ignored"
        );
    }
}

#[test]
fn find_matching_refund_result_prefers_succeeded_refunds() {
    // Setup matching pending and successful provider refunds
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);
    let refunds = vec![
        sample_listed_refund(purchase_id, "re_pending_123", "pending"),
        sample_listed_refund(purchase_id, "re_succeeded_123", "succeeded"),
    ];

    // Find the most useful matching provider refund
    let refund = StripeProvider::find_matching_refund_result(&input, refunds)
        .expect("refund lookup to parse")
        .expect("matching refund to exist");

    // Check provider success takes precedence over pending state
    assert_eq!(refund.provider_refund_id, "re_succeeded_123");
    assert_eq!(refund.status, RefundPaymentStatus::Succeeded);
}

#[test]
fn find_matching_refund_result_returns_matching_succeeded_refund() {
    // Setup a matching successful provider refund
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);
    let refunds = vec![sample_listed_refund(
        purchase_id,
        "re_test_123",
        "succeeded",
    )];

    // Find the matching provider refund
    let refund = StripeProvider::find_matching_refund_result(&input, refunds)
        .expect("refund lookup to parse")
        .expect("succeeded refund to match");

    // Check the matching successful refund is returned
    assert_eq!(refund.provider_refund_id, "re_test_123");
    assert_eq!(refund.status, RefundPaymentStatus::Succeeded);
}

#[test]
fn find_matching_refund_result_returns_pending_refund_statuses() {
    // Setup a purchase refund lookup
    let purchase_id = Uuid::new_v4();
    let input = sample_find_refund_input(purchase_id);

    for status in ["pending", "requires_action"] {
        // Find each pending provider refund status
        let refunds = vec![sample_listed_refund(purchase_id, "re_test_123", status)];
        let refund = StripeProvider::find_matching_refund_result(&input, refunds)
            .expect("refund lookup to parse")
            .expect("pending refund to match");

        // Check the provider status maps to a pending refund
        assert_eq!(refund.status, RefundPaymentStatus::Pending);
    }
}

#[test]
fn find_matching_refund_result_returns_terminal_refund_when_pinned() {
    // Setup a lookup pinned to a terminal provider refund
    let purchase_id = Uuid::new_v4();
    let mut input = sample_find_refund_input(purchase_id);
    input.provider_refund_id = Some("re_failed_123".to_string());
    let refunds = vec![sample_listed_refund(purchase_id, "re_failed_123", "failed")];

    // Find the pinned provider refund
    let refund = StripeProvider::find_matching_refund_result(&input, refunds)
        .expect("refund lookup to parse")
        .expect("pinned refund to match");

    // Check the pinned terminal refund is returned for reconciliation
    assert_eq!(refund.provider_refund_id, "re_failed_123");
    assert_eq!(refund.status, RefundPaymentStatus::Failed);
}

#[tokio::test]
async fn get_checkout_financial_context_reads_authoritative_connected_account_amounts() {
    // Setup an expanded Checkout Session response in the connected account
    let router = Router::new().route(
        "/v1/checkout/sessions/cs_test_123",
        get(|headers: HeaderMap, uri: Uri| async move {
            assert_eq!(headers["stripe-account"], "acct_test_123");
            assert_eq!(headers["stripe-version"], "2026-07-29.preview");
            assert_eq!(
                uri.query(),
                Some("expand%5B%5D=payment_intent.latest_charge")
            );

            Json(json!({
                "amount_total": 2750,
                "payment_intent": {
                    "id": "pi_test_123",
                    "latest_charge": {
                        "application_fee": "fee_test_123",
                        "id": "ch_test_123"
                    }
                },
                "payment_status": "paid",
                "total_details": {"amount_tax": 250}
            }))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Retrieve the expanded provider context used by purchase reconciliation
    let context = provider
        .get_checkout_financial_context(&GetCheckoutFinancialContextInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider_session_id: "cs_test_123".to_string(),
        })
        .await
        .expect("Checkout financial context to be retrieved");
    server.abort();

    // Check authoritative tax, total, and object references are preserved
    assert_eq!(
        context.provider_application_fee_id.as_deref(),
        Some("fee_test_123")
    );
    assert_eq!(context.provider_charge_id, "ch_test_123");
    assert_eq!(context.provider_payment_reference, "pi_test_123");
    assert_eq!(context.provider_total_minor, 2750);
    assert_eq!(context.tax_amount_minor, 250);
}

#[tokio::test]
async fn get_checkout_financial_context_rejects_unpaid_session() {
    // Setup an unpaid Checkout Session response
    let router = Router::new().route(
        "/v1/checkout/sessions/cs_test_unpaid",
        get(|| async {
            Json(json!({
                "amount_total": 2750,
                "payment_intent": {
                    "id": "pi_test_unpaid",
                    "latest_charge": null
                },
                "payment_status": "unpaid",
                "total_details": {"amount_tax": 250}
            }))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Retrieve the financial context from the unpaid session
    let error = provider
        .get_checkout_financial_context(&GetCheckoutFinancialContextInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider_session_id: "cs_test_unpaid".to_string(),
        })
        .await
        .expect_err("unpaid Checkout Session to be rejected");

    // Stop the provider fixture after the request completes
    server.abort();

    // Check the unpaid provider state is rejected
    assert!(error.to_string().contains("not paid"));
}

#[tokio::test]
async fn get_financial_document_scopes_invoice_retrieval_to_its_connected_account() {
    // Setup an invoice response in the account that owns the direct charge
    let router = Router::new().route(
        "/v1/invoices/in_test_123",
        get(|headers: HeaderMap| async move {
            assert_eq!(headers["stripe-account"], "acct_test_123");
            assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);

            Json(json!({
                "hosted_invoice_url": "https://invoice.stripe.test/hosted",
                "invoice_pdf": "https://invoice.stripe.test/invoice.pdf"
            }))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Retrieve the current attendee-facing provider document
    let document = provider
        .get_financial_document(&GetFinancialDocumentInput {
            connected_seller_id: "acct_test_123".to_string(),
            kind: FinancialDocumentKind::Invoice,
            provider_document_id: "in_test_123".to_string(),
        })
        .await
        .expect("account-scoped invoice to be retrieved");
    server.abort();

    // Check Stripe's current URLs are returned without exposing the secret key
    assert_eq!(
        document.hosted_url.as_deref(),
        Some("https://invoice.stripe.test/hosted")
    );
    assert_eq!(
        document.pdf_url.as_deref(),
        Some("https://invoice.stripe.test/invoice.pdf")
    );
}

#[tokio::test]
async fn list_tax_rates_scopes_filters_and_paginates() {
    // Setup two provider pages with defensive inactive and incompatible entries
    let router = Router::new().route(
        "/v1/tax_rates",
        get(|headers: HeaderMap, uri: Uri| async move {
            assert_eq!(headers["stripe-account"], "acct_test_123");
            assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
            let query = uri.query().expect("Tax Rate query to be present");
            assert!(query.contains("active=true"));
            assert!(query.contains("inclusive=false"));
            assert!(query.contains("limit=100"));

            if query.contains("starting_after=txr_inclusive") {
                Json(json!({
                    "data": [{
                        "active": true,
                        "display_name": "District tax",
                        "id": "txr_second",
                        "inclusive": false,
                        "jurisdiction": null,
                        "percentage": 1.25
                    }],
                    "has_more": false
                }))
            } else {
                Json(json!({
                    "data": [
                        {
                            "active": true,
                            "display_name": "Sales tax",
                            "id": "txr_first",
                            "inclusive": false,
                            "jurisdiction": "California",
                            "percentage": 8.875
                        },
                        {
                            "active": false,
                            "display_name": "Inactive",
                            "id": "txr_inactive",
                            "inclusive": false,
                            "jurisdiction": null,
                            "percentage": 2
                        },
                        {
                            "active": true,
                            "display_name": "Inclusive",
                            "id": "txr_inclusive",
                            "inclusive": true,
                            "jurisdiction": null,
                            "percentage": 3
                        }
                    ],
                    "has_more": true
                }))
            }
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // List account-owned rates compatible with exclusive ticket prices
    let rates = provider
        .list_tax_rates(&ListTaxRatesInput {
            connected_seller_id: "acct_test_123".to_string(),
            tax_behavior: TicketTaxBehavior::Exclusive,
        })
        .await
        .expect("compatible Tax Rates to be listed");
    server.abort();

    // Check pagination order and provider metadata are preserved
    assert_eq!(
        rates.iter().map(|rate| rate.id.as_str()).collect::<Vec<_>>(),
        vec!["txr_first", "txr_second"]
    );
    assert_eq!(rates[0].jurisdiction.as_deref(), Some("California"));
    assert_eq!(rates[0].percentage, "8.875");
}

#[tokio::test]
async fn list_tax_rates_propagates_provider_errors() {
    // Setup a provider failure from the connected-account Tax Rate endpoint
    let router = Router::new().route(
        "/v1/tax_rates",
        get(|| async {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": {"message": "temporarily unavailable"}})),
            )
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // List the connected account's rates while Stripe is unavailable
    let err = provider
        .list_tax_rates(&ListTaxRatesInput {
            connected_seller_id: "acct_test_123".to_string(),
            tax_behavior: TicketTaxBehavior::Inclusive,
        })
        .await
        .expect_err("provider failure to be returned");
    server.abort();

    // Check the listing error preserves the provider response context
    assert!(err.to_string().contains("temporarily unavailable"));
}

#[tokio::test]
async fn reconcile_application_fee_adjustment_looks_up_before_creating_on_the_platform() {
    // Setup an empty lookup followed by a platform-owned fee refund response
    let router = Router::new().route(
        "/v1/application_fees/fee_test_123/refunds",
        get(|headers: HeaderMap, uri: Uri| async move {
            assert!(!headers.contains_key("stripe-account"));
            assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
            assert_eq!(uri.query(), Some("limit=100"));
            Json(json!({"data": []}))
        })
        .post(|headers: HeaderMap, body: String| async move {
            assert!(!headers.contains_key("stripe-account"));
            assert_eq!(headers["idempotency-key"], "fee-adjustment-test");
            assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
            let form: BTreeMap<String, String> =
                serde_urlencoded::from_str(&body).expect("application-fee form to parse");
            assert_eq!(form.get("amount"), Some(&"125".to_string()));
            assert_eq!(
                form.get("metadata[connected_seller_id]"),
                Some(&"acct_test_123".to_string())
            );
            assert_eq!(
                form.get("metadata[kind]"),
                Some(&"tax-reconciliation".to_string())
            );

            Json(json!({"id": "fr_test_123"}))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Reconcile the durable adjustment through lookup-before-create
    let result = provider
        .reconcile_application_fee_adjustment(&ApplicationFeeAdjustmentInput {
            amount_minor: 125,
            connected_seller_id: "acct_test_123".to_string(),
            event_purchase_id: Uuid::new_v4(),
            idempotency_key: "fee-adjustment-test".to_string(),
            kind: "tax-reconciliation".to_string(),
            provider_application_fee_id: "fee_test_123".to_string(),
        })
        .await
        .expect("application-fee adjustment to be reconciled");
    server.abort();

    // Check the platform-owned provider object is returned for durable storage
    assert_eq!(result.provider_application_fee_refund_id, "fr_test_123");
}

#[tokio::test]
async fn reconcile_credit_note_previews_and_issues_the_full_connected_account_document() {
    // Setup the invoice, preview, and issue endpoints for a full refund document
    let router = Router::new()
        .route(
            "/v1/credit_notes",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], "2026-07-29.preview");
                let query: BTreeMap<String, String> = serde_urlencoded::from_str(
                    uri.query().expect("credit-note list query to exist"),
                )
                .expect("credit-note list query to parse");
                assert_eq!(query.get("invoice"), Some(&"in_test_123".to_string()));
                assert_eq!(query.get("limit"), Some(&"100".to_string()));
                Json(json!({"data": []}))
            })
            .post(|headers: HeaderMap, body: String| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], "2026-07-29.preview");
                assert_eq!(headers["idempotency-key"], "credit-note-test");
                let form: BTreeMap<String, String> =
                    serde_urlencoded::from_str(&body).expect("credit-note form to parse");
                assert_eq!(
                    form.get("lines[0][invoice_line_item]"),
                    Some(&"il_test_123".to_string())
                );
                assert_eq!(
                    form.get("refunds[0][amount_refunded]"),
                    Some(&"2750".to_string())
                );
                assert_eq!(
                    form.get("refunds[0][refund]"),
                    Some(&"re_test_123".to_string())
                );

                Json(json!({
                    "amount": 2750,
                    "id": "cn_test_123",
                    "pdf": "https://credit-note.stripe.test/document.pdf",
                    "total_taxes": [{"amount": 250}]
                }))
            }),
        )
        .route(
            "/v1/credit_notes/preview",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], "2026-07-29.preview");
                let query: BTreeMap<String, String> = serde_urlencoded::from_str(
                    uri.query().expect("credit-note preview query to exist"),
                )
                .expect("credit-note preview query to parse");
                assert_eq!(
                    query.get("refunds[0][refund]"),
                    Some(&"re_test_123".to_string())
                );

                Json(json!({
                    "amount": 2750,
                    "id": "cn_preview",
                    "total_taxes": [{"amount": 250}]
                }))
            }),
        )
        .route(
            "/v1/invoices/in_test_123/lines",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], "2026-07-29.preview");
                assert_eq!(uri.query(), Some("limit=2"));
                Json(json!({"data": [{"id": "il_test_123"}]}))
            }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Reconcile the full credit note against the existing customer refund
    let result = provider
        .reconcile_credit_note(&CreditNoteInput {
            amount_minor: 2750,
            connected_seller_id: "acct_test_123".to_string(),
            event_purchase_id: Uuid::new_v4(),
            event_purchase_refund_id: Uuid::new_v4(),
            idempotency_key: "credit-note-test".to_string(),
            provider_invoice_id: "in_test_123".to_string(),
            provider_refund_id: "re_test_123".to_string(),
            tax_amount_minor: 250,
        })
        .await
        .expect("full credit note to be issued");
    server.abort();

    // Check the issued provider document identity and current PDF are preserved
    assert_eq!(result.provider_credit_note_id, "cn_test_123");
    assert_eq!(
        result.provider_pdf_url.as_deref(),
        Some("https://credit-note.stripe.test/document.pdf")
    );
}

#[tokio::test]
async fn refund_payment_scopes_the_full_refund_to_the_connected_account() {
    // Setup the connected-account refund endpoint and capture its request
    let input = sample_refund_payment_input();
    let purchase_id = input.purchase_id;
    let router = Router::new().route(
        "/v1/refunds",
        post(move |headers: HeaderMap, body: String| async move {
            assert_eq!(headers["stripe-account"], "acct_test_123");
            assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
            assert_eq!(headers["idempotency-key"], "event-purchase-refund-test");
            let form: BTreeMap<String, String> =
                serde_urlencoded::from_str(&body).expect("refund form to parse");
            assert_eq!(form.get("amount"), Some(&"2500".to_string()));
            assert_eq!(
                form.get("metadata[event_purchase_id]"),
                Some(&purchase_id.to_string())
            );
            assert_eq!(form.get("payment_intent"), Some(&"pi_test_123".to_string()));

            Json(json!({"id": "re_test_123", "status": "succeeded"}))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Create the full direct-charge refund
    let result = provider
        .refund_payment(&input)
        .await
        .expect("connected-account refund to be created");
    server.abort();

    // Check the normalized successful provider result
    assert_eq!(result.provider_refund_id, "re_test_123");
    assert_eq!(result.status, RefundPaymentStatus::Succeeded);
}

#[test]
fn refund_result_rejects_unknown_statuses() {
    // Map an unsupported provider refund status
    let err = StripeProvider::refund_result("re_test_123".to_string(), "unknown")
        .expect_err("unknown refund status should be rejected");

    // Check the unsupported status remains actionable
    assert_eq!(err.to_string(), "unsupported Stripe refund status: unknown");
}

#[tokio::test]
async fn validate_fiscal_sponsor_accepts_dashboard_created_account_and_automatic_tax_readiness() {
    // Setup a Dashboard-created connected account with Standard-like responsibilities and Tax
    let router = Router::new()
        .route(
            "/v1/accounts/acct_test_123",
            get(|headers: HeaderMap| async move {
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                Json(sample_stripe_account_response())
            }),
        )
        .route(
            "/v1/tax/settings",
            get(|headers: HeaderMap| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                Json(json!({"status": "active"}))
            }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Validate the exact readiness required by automatic-tax event setup
    let result = provider
        .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider: PaymentProvider::Stripe,
            require_automatic_tax: true,
        })
        .await;
    server.abort();

    // Check both account and Tax readiness are accepted
    result.expect("ready fiscal sponsor to pass validation");
}

#[tokio::test]
async fn validate_fiscal_sponsor_rejects_account_controlled_response_without_conditional_fields() {
    // Setup an OAuth-shaped account response without platform-only controller properties
    let router = Router::new().route(
        "/v1/accounts/acct_test_123",
        get(|| async {
            Json(json!({
                "charges_enabled": true,
                "controller": {"type": "account"},
                "details_submitted": true,
                "id": "acct_test_123"
            }))
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Validate the unsupported account through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider: PaymentProvider::Stripe,
            require_automatic_tax: false,
        })
        .await
        .expect_err("account-controlled sponsor should fail readiness validation");
    server.abort();

    // Keep the unsupported account model organizer-correctable
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == super::STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR
    ));
}

#[tokio::test]
async fn validate_fiscal_sponsor_rejects_inactive_automatic_tax_settings() {
    // Setup a charge-ready connected account whose Tax settings are inactive
    let router = Router::new()
        .route(
            "/v1/accounts/acct_test_123",
            get(|| async { Json(sample_stripe_account_response()) }),
        )
        .route(
            "/v1/tax/settings",
            get(|| async { Json(json!({"status": "pending"})) }),
        );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Validate automatic-tax readiness through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider: PaymentProvider::Stripe,
            require_automatic_tax: true,
        })
        .await
        .expect_err("inactive Stripe Tax settings to fail closed");
    server.abort();

    // Check the actionable provider-readiness error is preserved
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "fiscal sponsor Stripe Tax settings are not active"
    ));
}

#[tokio::test]
async fn validate_fiscal_sponsor_rejects_incompatible_controller_configuration() {
    // Setup every controller property that can violate the required account model
    let scenarios = [
        (
            "application-managed losses",
            "/controller/losses/payments",
            "application",
        ),
        (
            "application-managed requirements",
            "/controller/requirement_collection",
            "application",
        ),
        (
            "application-paid fees",
            "/controller/fees/payer",
            "application",
        ),
        (
            "Express Dashboard access",
            "/controller/stripe_dashboard/type",
            "express",
        ),
    ];

    for (scenario, property_path, incompatible_value) in scenarios {
        // Replace one compatible controller property for this provider response
        let mut account = sample_stripe_account_response();
        *account
            .pointer_mut(property_path)
            .expect("sample controller property to exist") = json!(incompatible_value);
        let router = Router::new().route(
            "/v1/accounts/acct_test_123",
            get(move || {
                let account = account.clone();
                async move { Json(account) }
            }),
        );
        let (api_base_url, server) = spawn_stripe_api(router).await;
        let mut provider = sample_stripe_provider();
        provider.api_base_url = api_base_url;

        // Validate the incompatible account through the public provider boundary
        let err = provider
            .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
                connected_seller_id: "acct_test_123".to_string(),
                provider: PaymentProvider::Stripe,
                require_automatic_tax: false,
            })
            .await
            .expect_err(&format!("{scenario} should fail readiness validation"));
        server.abort();

        // Check every controller mismatch remains an organizer-correctable failure
        assert!(matches!(
            err,
            FiscalSponsorReadinessError::NotReady(ref message)
                if message == super::STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR
        ));
    }
}

#[tokio::test]
async fn validate_fiscal_sponsor_treats_unknown_account_as_not_ready() {
    // Setup the provider response returned for an unknown connected account
    let router = Router::new().route(
        "/v1/accounts/acct_unknown",
        get(|| async { StatusCode::NOT_FOUND }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Validate the unknown account through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: "acct_unknown".to_string(),
            provider: PaymentProvider::Stripe,
            require_automatic_tax: false,
        })
        .await
        .expect_err("unknown Stripe account to fail readiness validation");
    server.abort();

    // Keep organizer-correctable account selection failures user-facing
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "fiscal sponsor Stripe account could not be validated"
    ));
}

#[tokio::test]
async fn validate_fiscal_sponsor_treats_provider_outage_as_unexpected() {
    // Setup a transient provider-side account retrieval failure
    let router = Router::new().route(
        "/v1/accounts/acct_test_123",
        get(|| async { StatusCode::SERVICE_UNAVAILABLE }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Validate the account through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider: PaymentProvider::Stripe,
            require_automatic_tax: false,
        })
        .await
        .expect_err("Stripe outage to fail readiness validation");
    server.abort();

    // Preserve infrastructure failures as internal errors
    assert!(matches!(err, FiscalSponsorReadinessError::Unexpected(_)));
}

#[tokio::test]
async fn validate_tax_rates_rejects_missing_or_incompatible_ids() {
    // Setup an account whose active compatible list does not contain the selection
    let router = Router::new().route(
        "/v1/tax_rates",
        get(|| async { Json(json!({"data": [], "has_more": false})) }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;

    // Revalidate the selected identifier against that connected account
    let err = provider
        .validate_tax_rates(&ValidateTaxRatesInput {
            connected_seller_id: "acct_test_123".to_string(),
            manual_tax_rate_ids: vec!["txr_missing".to_string()],
            tax_behavior: TicketTaxBehavior::Inclusive,
        })
        .await
        .expect_err("missing Tax Rate to be rejected");
    server.abort();

    // Check provider drift remains an organizer-actionable readiness failure
    assert!(matches!(err, FiscalSponsorReadinessError::NotReady(_)));
}

#[test]
fn verify_and_parse_webhook_accepts_recent_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("recent webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_test_123".to_string(),
        }
    );
}

#[test]
fn verify_and_parse_webhook_accepts_rotated_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let timestamp = Utc::now().timestamp();
    let expected_signature =
        StripeProvider::compute_signature("whsec_connect_test", &format!("{timestamp}.{body}"));
    let rotated_signature =
        StripeProvider::compute_signature("whsec_rotated", &format!("{timestamp}.{body}"));
    let signature_header = format!("t={timestamp},v1={expected_signature},v1={rotated_signature}");

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("rotated webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_test_123".to_string(),
        }
    );
}

#[test]
fn verify_and_parse_webhook_maps_application_fee_created_events() {
    // Setup a platform application fee bound to a connected-account charge
    let provider = sample_stripe_provider();
    let body = r#"{"livemode":false,"type":"application_fee.created","data":{"object":{"id":"fee_test_123","account":"acct_test_123","amount":62,"charge":"ch_test_123"}}}"#;
    let signature_header =
        sample_signature_header_with_secret(body, Utc::now().timestamp(), "whsec_test");

    // Verify and normalize the platform-scoped provider event
    let webhook_event = PaymentsProvider::verify_and_parse_webhook(
        &provider,
        PaymentsWebhookEndpoint::PlatformAccount,
        &sample_webhook_headers(&signature_header),
        body,
    )
    .expect("application-fee webhook to verify");

    // Check the immutable charge scope and fee amount are retained
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::ApplicationFeeCreated {
            amount_minor: 62,
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_application_fee_id: "fee_test_123".to_string(),
            provider_charge_id: "ch_test_123".to_string(),
        }
    );
}

#[test]
fn verify_and_parse_webhook_maps_checkout_session_expired_events() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("expired webhook to verify");

    // Check the parsed event matches expectations
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::CheckoutExpired {
            connected_account_id: "acct_test_123".to_string(),
            is_live: false,
            provider_session_id: "cs_test_123".to_string(),
        }
    );
}

#[test]
fn verify_and_parse_webhook_maps_invoice_paid_events() {
    // Setup a paid invoice bound to an OCG purchase
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let body = format!(
        r#"{{"account":"acct_test_123","livemode":false,"type":"invoice.paid","data":{{"object":{{"id":"in_test_123","hosted_invoice_url":"https://stripe.test/invoices/in_test_123","invoice_pdf":"https://stripe.test/invoices/in_test_123.pdf","metadata":{{"event_purchase_id":"{purchase_id}"}}}}}}}}"#
    );
    let signature_header = sample_signature_header(&body, Utc::now().timestamp());

    // Verify and normalize the provider event
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
        .expect("invoice webhook to verify");

    // Check the durable invoice identity and attendee document URLs
    assert_eq!(
        webhook_event,
        PaymentsWebhookEvent::InvoicePaid {
            connected_account_id: "acct_test_123".to_string(),
            hosted_url: "https://stripe.test/invoices/in_test_123".to_string(),
            is_live: false,
            provider_invoice_id: "in_test_123".to_string(),
            purchase_id,
            pdf_url: Some("https://stripe.test/invoices/in_test_123.pdf".to_string()),
        }
    );
}

#[test]
fn verify_and_parse_webhook_rejects_endpoint_scope_mismatch() {
    // Setup a connected-account event signed with the platform endpoint secret
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123"}}}"#;
    let signature_header =
        sample_signature_header_with_secret(body, Utc::now().timestamp(), "whsec_test");

    // Verify through the platform endpoint scope
    let err = PaymentsProvider::verify_and_parse_webhook(
        &provider,
        PaymentsWebhookEndpoint::PlatformAccount,
        &sample_webhook_headers(&signature_header),
        body,
    )
    .expect_err("connected event on platform endpoint to fail");

    // Check endpoint scope is enforced independently of signature validity
    assert_eq!(
        err.to_string(),
        "Stripe platform webhook contains a connected account"
    );
}

#[test]
fn verify_and_parse_webhook_rejects_mode_mismatch() {
    // Setup a live event for a test-mode deployment
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":true,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify the signed event against configured payment mode
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("live event in test mode to fail");

    // Check the mode mismatch cannot reach reconciliation
    assert_eq!(
        err.to_string(),
        "Stripe webhook mode does not match payments configuration"
    );
}

#[test]
fn verify_and_parse_webhook_returns_noop_for_unsupported_platform_events() {
    // Setup a valid platform event that does not belong to payment reconciliation
    let provider = sample_stripe_provider();
    let body =
        r#"{"livemode":false,"type":"account.updated","data":{"object":{"id":"acct_test_123"}}}"#;
    let signature_header =
        sample_signature_header_with_secret(body, Utc::now().timestamp(), "whsec_test");

    // Verify the event through the platform endpoint
    let webhook_event = PaymentsProvider::verify_and_parse_webhook(
        &provider,
        PaymentsWebhookEndpoint::PlatformAccount,
        &sample_webhook_headers(&signature_header),
        body,
    )
    .expect("irrelevant platform event to verify");

    // Check valid irrelevant platform deliveries are acknowledged without retries
    assert_eq!(webhook_event, PaymentsWebhookEvent::Noop);
}

#[test]
fn verify_and_parse_webhook_supports_refund_lifecycle_events() {
    // Setup provider and refund lifecycle scenarios
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let scenarios = [
        ("refund.created", "pending", RefundPaymentStatus::Pending),
        ("refund.failed", "failed", RefundPaymentStatus::Failed),
        (
            "refund.updated",
            "succeeded",
            RefundPaymentStatus::Succeeded,
        ),
    ];

    for (event_type, status, expected_status) in scenarios {
        let body = format!(
            r#"{{"account":"acct_test_123","livemode":false,"type":"{event_type}","data":{{"object":{{"id":"re_test_123","amount":2500,"currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"{status}"}}}}}}"#
        );
        let signature_header = sample_signature_header(&body, Utc::now().timestamp());

        // Verify and parse the webhook payload
        let webhook_event = provider
            .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
            .expect("refund webhook to verify");

        // Check the parsed event matches expectations
        assert_eq!(
            webhook_event,
            PaymentsWebhookEvent::RefundUpdated {
                amount_minor: 2_500,
                connected_account_id: "acct_test_123".to_string(),
                currency_code: "usd".to_string(),
                is_live: false,
                provider_payment_reference: "pi_test_123".to_string(),
                provider_refund_id: "re_test_123".to_string(),
                purchase_id,
                status: expected_status,
            }
        );
    }
}

#[test]
fn verify_and_parse_webhook_supports_refunds_without_purchase_metadata_as_noop() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"refund.updated","data":{"object":{"id":"re_test_123","status":"succeeded"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("unrelated refund webhook to verify");

    // Check the unrelated refund is acknowledged without reconciliation
    assert_eq!(webhook_event, PaymentsWebhookEvent::Noop);
}

#[test]
fn verify_and_parse_webhook_validates_incomplete_refund_events() {
    // Setup provider and incomplete OCG refund payloads
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let scenarios = [
        (
            format!(
                r#"{{"account":"acct_test_123","livemode":false,"type":"refund.updated","data":{{"object":{{"id":"re_test_123","currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"succeeded"}}}}}}"#
            ),
            "Stripe refund webhook is missing amount",
        ),
        (
            format!(
                r#"{{"account":"acct_test_123","livemode":false,"type":"refund.updated","data":{{"object":{{"id":"re_test_123","amount":2500,"metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"succeeded"}}}}}}"#
            ),
            "Stripe refund webhook is missing currency",
        ),
        (
            format!(
                r#"{{"account":"acct_test_123","livemode":false,"type":"refund.updated","data":{{"object":{{"id":"re_test_123","amount":2500,"currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"status":"succeeded"}}}}}}"#
            ),
            "Stripe refund webhook is missing payment intent",
        ),
    ];

    for (body, expected_error) in scenarios {
        // Sign and parse each incomplete provider payload
        let signature_header = sample_signature_header(&body, Utc::now().timestamp());
        let err = provider
            .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
            .expect_err("incomplete refund webhook to fail");

        // Check the missing financial field is identified
        assert_eq!(err.to_string(), expected_error);
    }
}

#[test]
fn verify_and_parse_webhook_validates_invalid_signature() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = format!("t={},v1=invalid", Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("invalid webhook signature to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "invalid Stripe webhook signature");
}

#[test]
fn verify_and_parse_webhook_validates_missing_payload_object() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":null}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without object data to be rejected");

    // Check the returned error matches expectations
    assert_eq!(
        err.to_string(),
        "Stripe webhook payload is missing object data"
    );
}

#[test]
fn verify_and_parse_webhook_validates_missing_signature_header() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = format!("t={}", Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without signature to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "missing Stripe webhook signature");
}

#[test]
fn verify_and_parse_webhook_validates_missing_webhook_mode() {
    // Setup a signed provider payload without its required mode marker
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the incomplete webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without livemode to be rejected");

    // Check the missing provider mode cannot silently become test mode
    assert!(format!("{err:#}").contains("missing field `livemode`"));
}

#[test]
fn verify_and_parse_webhook_validates_webhook_timestamp_missing() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature = StripeProvider::compute_signature(
        "whsec_connect_test",
        &format!("{}.{body}", Utc::now().timestamp()),
    );
    let signature_header = format!("v1={signature}");

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("webhook without timestamp to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "missing Stripe webhook timestamp");
}

#[test]
fn verify_and_parse_webhook_validates_webhook_timestamp_staleness() {
    // Setup provider and stale webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#;
    let signature_header =
        sample_signature_header(body, (Utc::now() - TimeDelta::minutes(10)).timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("stale webhook to be rejected");

    // Check the returned error matches expectations
    assert_eq!(err.to_string(), "stale Stripe webhook timestamp");
}

#[test]
fn verify_and_parse_webhook_validates_webhook_type() {
    // Setup provider and webhook payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"payment_intent.succeeded","data":{"object":{"id":"pi_test_123","payment_intent":"pi_test_123"}}}"#;
    let signature_header = sample_signature_header(body, Utc::now().timestamp());

    // Verify and parse the webhook payload
    let err = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect_err("unsupported webhook event to be rejected");

    // Check the returned error matches expectations
    assert_eq!(
        err.to_string(),
        "unsupported Stripe webhook event: payment_intent.succeeded"
    );
}

// Helpers.

/// Returns the classified error from a mocked Stripe performance-location response.
async fn performance_location_error(
    response: serde_json::Value,
    state_code: Option<&str>,
) -> AutomaticTaxReadinessError {
    let router = Router::new().route(
        "/v1/tax/locations",
        post(move || {
            let response = response.clone();
            async move { (StatusCode::BAD_REQUEST, Json(response)) }
        }),
    );
    let (api_base_url, server) = spawn_stripe_api(router).await;
    let mut provider = sample_stripe_provider();
    provider.api_base_url = api_base_url;
    let mut input = sample_performance_location_input();
    input.venue.state_code = state_code.map(str::to_string);

    let error = provider
        .create_performance_location(&input, super::STRIPE_API_VERSION)
        .await
        .expect_err("mocked Stripe error to be classified");
    server.abort();

    error
}

/// Converts checkout session form fields into a map for assertions.
fn checkout_session_form_fields_map(
    provider: &StripeProvider,
    input: &CreateCheckoutSessionInput,
) -> BTreeMap<String, String> {
    provider
        .build_checkout_session_form_fields(input, Some("prod_ticket"))
        .into_iter()
        .collect()
}

/// Creates sample performance-location input.
fn sample_performance_location_input() -> PerformanceLocationInput {
    let checkout = sample_checkout_session_input();

    PerformanceLocationInput {
        connected_seller_id: checkout.seller.connected_account_id,
        venue: checkout.venue,

        cached_fingerprint: None,
        cached_provider_tax_location_id: None,
    }
}

/// Creates sample checkout session input.
fn sample_checkout_session_input() -> CreateCheckoutSessionInput {
    CreateCheckoutSessionInput {
        amount_minor: 2_500,
        base_url: "https://ocg.example.org".to_string(),
        community_display_name: "Community".to_string(),
        community_name: "community".to_string(),
        currency_code: "USD".to_string(),
        event_id: Uuid::new_v4(),
        event_name: "Event".to_string(),
        event_slug: "event".to_string(),
        event_timezone: "UTC".to_string(),
        group_name: "Group".to_string(),
        group_slug: "group".to_string(),
        provisional_platform_fee_amount_minor: 0,
        purchase_id: Uuid::new_v4(),
        seller: FiscalSponsorSeller {
            connected_account_id: "acct_test_123".to_string(),
            display_name: "Fiscal sponsor".to_string(),
            provider: PaymentProvider::Stripe,
        },
        tax_behavior: TicketTaxBehavior::Inclusive,
        tax_calculation_mode: TicketTaxCalculationMode::Automatic,
        ticket_title: "Ticket".to_string(),
        user_id: Uuid::new_v4(),
        venue: TicketVenue {
            address: "123 Example Street".to_string(),
            city: "Example City".to_string(),
            country_code: "US".to_string(),
            name: "Example Venue".to_string(),
            zip_code: "12345".to_string(),
            state_code: Some("CA".to_string()),
            state_name: Some("California".to_string()),
        },

        cached_performance_location_fingerprint: None,
        cached_product_fingerprint: None,
        cached_provider_tax_location_id: None,
        cached_provider_tax_product_id: None,
        discount_code: Some("EARLYBIRD".to_string()),
        group_slug_pretty: Some("pretty-group".to_string()),
        manual_tax_rate_ids: None,
        tax_code: Some("txcd_50013001".to_string()),
    }
}

/// Creates sample refund lookup input.
fn sample_find_refund_input(purchase_id: Uuid) -> FindRefundInput {
    FindRefundInput {
        amount_minor: 2_500,
        connected_seller_id: "acct_test_123".to_string(),
        provider_payment_reference: "pi_test_123".to_string(),
        purchase_id,

        provider_refund_id: None,
    }
}

/// Creates sample Stripe refund list item.
fn sample_listed_refund(purchase_id: Uuid, id: &str, status: &str) -> StripeListedRefund {
    StripeListedRefund {
        amount: 2_500,
        id: id.to_string(),
        status: status.to_string(),

        metadata: BTreeMap::from([("event_purchase_id".to_string(), purchase_id.to_string())]),
    }
}

/// Creates sample refund payment input.
fn sample_refund_payment_input() -> RefundPaymentInput {
    RefundPaymentInput {
        amount_minor: 2_500,
        connected_seller_id: "acct_test_123".to_string(),
        idempotency_key: "event-purchase-refund-test".to_string(),
        provider_payment_reference: "pi_test_123".to_string(),
        purchase_id: Uuid::new_v4(),
    }
}

/// Builds a signed Stripe webhook header for tests.
fn sample_signature_header(body: &str, timestamp: i64) -> String {
    sample_signature_header_with_secret(body, timestamp, "whsec_connect_test")
}

/// Builds a signed Stripe webhook header with the selected endpoint secret.
fn sample_signature_header_with_secret(body: &str, timestamp: i64, secret: &str) -> String {
    let signature = StripeProvider::compute_signature(secret, &format!("{timestamp}.{body}"));
    format!("t={timestamp},v1={signature}")
}

/// Creates a Dashboard-created connected account with Standard-like responsibilities.
fn sample_stripe_account_response() -> serde_json::Value {
    json!({
        "charges_enabled": true,
        "controller": {
            "type": "application",
            "fees": {"payer": "account"},
            "losses": {"payments": "stripe"},
            "requirement_collection": "stripe",
            "stripe_dashboard": {"type": "full"}
        },
        "details_submitted": true,
        "id": "acct_test_123"
    })
}

/// Creates a sample Stripe provider.
fn sample_stripe_provider() -> StripeProvider {
    StripeProvider::new(PaymentsStripeConfig {
        connected_webhook_secret: "whsec_connect_test".to_string(),
        mode: PaymentMode::Test,
        secret_key: "sk_test".to_string(),
        ticket_tax_api_version: "2026-07-29.preview".to_string(),
        webhook_secret: "whsec_test".to_string(),

        platform_fee_bps: 0,
    })
}

/// Creates a complete automatic-tax Product response.
fn sample_stripe_tax_product() -> StripeTaxProductResponse {
    StripeTaxProductResponse {
        active: true,
        name: "Ticket".to_string(),
        tax_details: Some(StripeTaxProductTaxDetailsResponse {
            performance_location: Some("loc_cached".to_string()),
            tax_code: Some("txcd_50013001".to_string()),
        }),
    }
}

/// Creates sample webhook headers with the given signature header value.
fn sample_webhook_headers(signature_header: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        "stripe-signature",
        HeaderValue::from_str(signature_header).expect("Stripe signature header to be valid"),
    );
    headers
}

/// Starts a local Stripe-shaped API for provider-boundary tests.
async fn spawn_stripe_api(router: Router) -> (String, JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("test Stripe API listener to bind");
    let address = listener
        .local_addr()
        .expect("test Stripe API listener address to exist");
    let server = tokio::spawn(async move {
        axum::serve(listener, router).await.expect("test Stripe API to serve");
    });

    (format!("http://{address}/v1"), server)
}
