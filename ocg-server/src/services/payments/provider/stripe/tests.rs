use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Json, Router,
    http::{HeaderMap, HeaderValue, StatusCode, Uri},
    routing::{get, post},
};
use chrono::{TimeDelta, Utc};
use serde_json::json;
use tokio::time::timeout;
use uuid::Uuid;

use crate::{
    config::{HttpClientConfig, PaymentsStripeConfig},
    services::payments::{
        ApplicationFeeAdjustmentInput, AutomaticTaxReadiness, AutomaticTaxReadinessError,
        CreateCheckoutSessionInput, CreditNoteInput, FinancialDocumentKind, FindRefundInput,
        FiscalSponsorReadinessError, FiscalSponsorReadinessInput, GetCheckoutFinancialContextInput,
        GetFinancialDocumentInput, ListTaxRatesInput, PaymentsWebhookEvent,
        PerformanceLocationInput, RefundPaymentInput, RefundPaymentStatus, ValidateTaxRatesInput,
    },
    types::payments::{
        FiscalSponsorSeller, PaymentMode, PaymentProvider, TicketTaxBehavior,
        TicketTaxCalculationMode, TicketTaxJurisdiction, TicketVenue,
    },
};

use super::{
    PaymentsProvider, PaymentsWebhookEndpoint, StripeApplicationFeeRefund, StripeListedRefund,
    StripeProvider, StripeTaxProductResponse, StripeTaxProductTaxDetailsResponse,
    StripeTaxRegistrationResponse,
};

#[tokio::test]
async fn test_automatic_tax_location_omits_missing_state_code() {
    // Setup a venue in a country without a subdivision
    let mut input = sample_performance_location_input();
    input.venue.country_code = "PT".to_string();
    input.venue.state_code = None;

    // Create the location without inventing a subdivision
    let (readiness, form_fields) = create_location_and_capture_form(&input).await;

    // Check Stripe receives no empty state parameter
    assert_eq!(readiness.provider_tax_location_id, "loc_created");
    assert_eq!(readiness.state_code, None);
    assert!(!form_fields.contains_key("address[state]"));
}

#[tokio::test]
async fn test_automatic_tax_location_reuses_matching_persisted_cache_entry() {
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
async fn test_automatic_tax_location_sends_iso_country_and_state_codes() {
    // Create the performance location through the provider boundary
    let input = sample_performance_location_input();
    let (readiness, form_fields) = create_location_and_capture_form(&input).await;

    // Check Stripe receives code values rather than display names
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
async fn test_automatic_tax_location_classifies_state_errors_only_from_exact_parameter() {
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
async fn test_automatic_tax_location_keeps_country_and_address_errors_distinct() {
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
fn test_automatic_tax_product_cache_matches_only_a_complete_active_product() {
    // Check the complete provider Product matches the checkout snapshot
    assert!(StripeProvider::tax_product_matches(
        &sample_stripe_tax_product(),
        "Ticket",
        "loc_cached",
        "txcd_50013001"
    ));

    // Setup mutations covering every Product field used by checkout
    let cases: [(&str, Mutation<StripeTaxProductResponse>); 5] = [
        ("inactive product", |product| product.active = false),
        ("changed name", |product| {
            product.name = "Different ticket".to_string();
        }),
        ("missing tax details", |product| product.tax_details = None),
        ("changed performance location", |product| {
            product
                .tax_details
                .as_mut()
                .expect("sample tax details to exist")
                .performance_location = Some("loc_other".to_string());
        }),
        ("changed tax code", |product| {
            product
                .tax_details
                .as_mut()
                .expect("sample tax details to exist")
                .tax_code = Some("txcd_other".to_string());
        }),
    ];

    for (case, mutate) in cases {
        // Compare each changed Product with the persisted snapshot
        let mut product = sample_stripe_tax_product();
        mutate(&mut product);
        assert!(
            !StripeProvider::tax_product_matches(&product, "Ticket", "loc_cached", "txcd_50013001"),
            "{case}"
        );
    }
}

#[tokio::test]
async fn test_automatic_tax_product_propagates_cached_product_provider_errors() {
    // Setup a matching cache snapshot whose provider lookup fails
    let router = Router::new().route(
        "/v1/products/prod_cached",
        get(|| async { (StatusCode::SERVICE_UNAVAILABLE, "provider unavailable") }),
    );
    let provider = spawn_stripe_provider(router).await;
    let (input, _) = cached_tax_product_input();

    // Resolve the cached Product through the provider boundary
    let err = provider
        .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
        .await
        .expect_err("provider retrieval failure to remain actionable");

    // Check transient provider failures are not treated as cache misses
    assert!(format!("{err:#}").contains("Product retrieval failed (503 Service Unavailable)"));
}

#[tokio::test]
async fn test_automatic_tax_product_replaces_mismatched_cache_with_stable_idempotency_key() {
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
    let provider = spawn_stripe_provider(router).await;
    let (input, fingerprint) = cached_tax_product_input();

    // Retry the same replacement operation through the provider boundary
    for _ in 0..2 {
        let (product_id, returned_fingerprint) = provider
            .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
            .await
            .expect("mismatched cached Product to be replaced");
        assert_eq!(product_id, "prod_replacement");
        assert_eq!(returned_fingerprint, fingerprint);
    }

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
async fn test_automatic_tax_product_replaces_provider_deleted_cache_entry() {
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
    let provider = spawn_stripe_provider(router).await;
    let (input, fingerprint) = cached_tax_product_input();

    // Resolve the deleted cached Product through the provider boundary
    let (product_id, returned_fingerprint) = provider
        .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
        .await
        .expect("deleted cached Product to be replaced");

    // Check provider deletion creates a replacement with the same durable fingerprint
    assert_eq!(product_id, "prod_replacement");
    assert_eq!(returned_fingerprint, fingerprint);
}

#[tokio::test]
async fn test_automatic_tax_product_reuses_complete_cached_product() {
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
    let provider = spawn_stripe_provider(router).await;
    let (input, fingerprint) = cached_tax_product_input();

    // Resolve the matching cached Product through the provider boundary
    let (product_id, returned_fingerprint) = provider
        .create_tax_product(&input, super::STRIPE_API_VERSION, "loc_cached")
        .await
        .expect("complete cached Product to be reused");

    // Check the provider Product and persisted fingerprint remain stable
    assert_eq!(product_id, "prod_cached");
    assert_eq!(returned_fingerprint, fingerprint);
}

#[test]
fn test_build_application_fee_refund_form_fields_records_request_identity() {
    // Setup an adjustment with an upper-case purchase currency
    let purchase_id = Uuid::new_v4();
    let input = sample_application_fee_adjustment_input(purchase_id);

    // Build the refund creation form
    let form_fields = StripeProvider::build_application_fee_refund_form_fields(&input);

    // Check the amount and every durable identity field are recorded
    assert_eq!(form_fields.len(), 7);
    assert_eq!(form_fields.get("amount"), Some(&"125".to_string()));
    assert_eq!(
        form_fields.get("metadata[connected_seller_id]"),
        Some(&"acct_test_123".to_string())
    );
    assert_eq!(
        form_fields.get("metadata[event_purchase_id]"),
        Some(&purchase_id.to_string())
    );
    assert_eq!(
        form_fields.get("metadata[idempotency_key]"),
        Some(&"fee-adjustment-test".to_string())
    );
    assert_eq!(
        form_fields.get("metadata[kind]"),
        Some(&"tax-reconciliation".to_string())
    );
    assert_eq!(
        form_fields.get("metadata[requested_amount_minor]"),
        Some(&"125".to_string())
    );
    assert_eq!(
        form_fields.get("metadata[requested_currency]"),
        Some(&"usd".to_string())
    );
}

#[test]
fn test_build_checkout_session_form_fields_includes_platform_fee_when_configured() {
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
fn test_build_checkout_session_form_fields_populates_checkout_contract() {
    // Setup a checkout without a platform fee
    let provider = sample_stripe_provider();
    let input = sample_checkout_session_input();

    // Build the provider form fields
    let form_fields = checkout_session_form_fields_map(&provider, &input);

    // Check the return URLs, metadata and line item identify the purchase
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

    // Check the direct charge carries no transfer or zero application fee
    assert!(!form_fields.keys().any(|key| key.starts_with("transfer_data")));
    assert!(!form_fields.contains_key("payment_intent_data[application_fee_amount]"));

    // Check checkout is restricted to card payments only
    assert_eq!(
        form_fields.get("payment_method_types[0]"),
        Some(&"card".to_string())
    );
    assert!(!form_fields.contains_key("payment_method_types[1]"));
}

#[test]
fn test_build_refund_form_fields_only_refunds_the_direct_charge() {
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
async fn test_create_checkout_session_enforces_venue_tax_registration() {
    // Setup a sponsor registered only in New York and count tax and Checkout writes
    let input = sample_checkout_session_input();
    let writes = Arc::new(AtomicUsize::new(0));
    let (location_writes, product_writes, session_writes) = (
        Arc::clone(&writes),
        Arc::clone(&writes),
        Arc::clone(&writes),
    );
    let router = tax_ready_account_router()
        .route(
            "/v1/tax/registrations",
            get(|| async {
                Json(json!({
                    "data": [{
                        "country": "US",
                        "country_options": {"us": {"state": "NY"}},
                        "id": "taxreg_us_ny",
                        "status": "active"
                    }],
                    "has_more": false
                }))
            }),
        )
        .route(
            "/v1/tax/locations",
            post(move || {
                location_writes.fetch_add(1, Ordering::SeqCst);
                async { Json(json!({"id": "loc_us_ca"})) }
            }),
        )
        .route(
            "/v1/products",
            post(move || {
                product_writes.fetch_add(1, Ordering::SeqCst);
                async { Json(json!({"id": "prod_ticket"})) }
            }),
        )
        .route(
            "/v1/checkout/sessions",
            post(move || {
                session_writes.fetch_add(1, Ordering::SeqCst);
                async {
                    Json(json!({"id": "cs_unexpected", "url": "https://checkout.stripe.test/x"}))
                }
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Try to create Checkout for the California venue
    let err = provider
        .create_checkout_session(&input)
        .await
        .expect_err("missing venue registration to block Checkout");

    // Check readiness fails before any tax resource or session is created
    assert!(
        format!("{err:#}")
            .contains("fiscal sponsor Stripe account needs an active tax registration for US-CA"),
        "{err:#}"
    );
    assert_eq!(writes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn test_create_checkout_session_provisions_automatic_tax_resources() {
    // Setup a complete automatic-tax Checkout API for a California venue
    let input = sample_checkout_session_input();
    let router = tax_ready_account_router()
        .route(
            "/v1/tax/registrations",
            get(|headers: HeaderMap| async move {
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                Json(json!({
                    "data": [{
                        "country": "US",
                        "country_options": {"us": {"state": "CA"}},
                        "id": "taxreg_us_ca",
                        "status": "active"
                    }],
                    "has_more": false
                }))
            }),
        )
        .route(
            "/v1/tax/locations",
            post(|headers: HeaderMap| async move {
                assert_eq!(headers["stripe-version"], "2026-07-29.preview");
                Json(json!({"id": "loc_us_ca"}))
            }),
        )
        .route(
            "/v1/products",
            post(|| async { Json(json!({"id": "prod_ticket"})) }),
        )
        .route(
            "/v1/checkout/sessions",
            post(|body: String| async move {
                let form: BTreeMap<String, String> =
                    serde_urlencoded::from_str(&body).expect("checkout form to parse");
                assert_eq!(
                    form.get("automatic_tax[enabled]"),
                    Some(&"true".to_string())
                );
                assert_eq!(
                    form.get("line_items[0][price_data][product]"),
                    Some(&"prod_ticket".to_string())
                );
                assert!(!form.keys().any(|key| key.contains("[tax_rates]")));

                Json(json!({
                    "id": "cs_automatic_tax",
                    "url": "https://checkout.stripe.test/automatic-tax"
                }))
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Create Checkout after revalidating the snapshotted venue jurisdiction
    let session = provider
        .create_checkout_session(&input)
        .await
        .expect("matching venue registration to allow Checkout");

    // Check the provisioned tax resources are returned for caching
    assert_eq!(session.provider_session_id, "cs_automatic_tax");
    assert_eq!(
        session.provider_tax_location_id.as_deref(),
        Some("loc_us_ca")
    );
    assert_eq!(
        session.provider_tax_product_id.as_deref(),
        Some("prod_ticket")
    );
}

#[tokio::test]
async fn test_create_checkout_session_rejects_invalid_input_before_contacting_stripe() {
    // Setup inputs that every checkout must reject locally
    let cases: [(&str, Mutation<CreateCheckoutSessionInput>, &str); 3] = [
        (
            "zero amount",
            |input| input.amount_minor = 0,
            "Stripe checkout requires a positive amount",
        ),
        (
            "fee equal to amount",
            |input| input.provisional_platform_fee_amount_minor = input.amount_minor,
            "Stripe application fee must be less than the ticket amount",
        ),
        (
            "fee above amount",
            |input| input.provisional_platform_fee_amount_minor = input.amount_minor + 1,
            "Stripe application fee must be less than the ticket amount",
        ),
    ];
    let provider = spawn_stripe_provider(Router::new()).await;

    for (case, mutate, expected) in cases {
        let mut input = sample_checkout_session_input();
        mutate(&mut input);

        // Create the checkout against an API with no routes
        let err = provider.create_checkout_session(&input).await.expect_err(case);

        // Check the local guard rejects the input
        assert_eq!(err.to_string(), expected, "{case}");
    }
}

#[tokio::test]
async fn test_create_checkout_session_rejects_no_tax_checkout_with_tax_rates() {
    // Setup a no-tax checkout that still carries a stale manual Tax Rate
    let mut input = sample_checkout_session_input();
    input.manual_tax_rate_ids = Some(vec!["txr_stale".to_string()]);
    input.tax_calculation_mode = TicketTaxCalculationMode::None;
    input.tax_code = None;
    let router = Router::new().route(
        "/v1/accounts/acct_test_123",
        get(|| async { Json(sample_stripe_account_response()) }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Try to create the session
    let err = provider
        .create_checkout_session(&input)
        .await
        .expect_err("no-tax checkout with Tax Rates to be rejected");

    // Check the stale selection is rejected before Checkout is created
    assert_eq!(
        err.to_string(),
        "no-tax checkout cannot include Stripe Tax Rates"
    );
}

#[tokio::test]
async fn test_create_checkout_session_scopes_the_direct_charge_and_invoice_request() {
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
                            "country": "US",
                            "display_name": "Sales tax",
                            "id": "txr_state",
                            "inclusive": true,
                            "jurisdiction": "California",
                            "percentage": 8.875,
                            "state": "CA"
                        },
                        {
                            "active": true,
                            "country": "US",
                            "display_name": "District tax",
                            "id": "txr_local",
                            "inclusive": true,
                            "jurisdiction": "Example District",
                            "percentage": 1.25,
                            "state": "CA"
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
    let provider = spawn_stripe_provider(router).await;

    // Create the connected-account Checkout Session
    let session = provider
        .create_checkout_session(&input)
        .await
        .expect("direct-charge Checkout Session to be created");

    // Check the account-scoped provider identity is retained for reconciliation
    assert_eq!(session.provider_object_account_id, "acct_test_123");
    assert_eq!(session.provider_session_id, "cs_test_123");
    assert_eq!(session.redirect_url, "https://checkout.stripe.test/session");
}

#[tokio::test]
async fn test_create_checkout_session_omits_tax_fields_for_no_tax_mode() {
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
    let provider = spawn_stripe_provider(router).await;

    // Create the session without attaching a tax mechanism
    let session = provider
        .create_checkout_session(&input)
        .await
        .expect("no-tax Checkout Session to be created");

    // Check the connected-account session is returned normally
    assert_eq!(session.provider_session_id, "cs_no_tax");
}

#[test]
fn test_find_matching_application_fee_refund_adopts_matching_refunds() {
    // Setup an adjustment and listed refunds for its purchase and kind
    let purchase_id = Uuid::new_v4();
    let input = sample_application_fee_adjustment_input(purchase_id);
    let refund =
        |id: &str, amount_minor| sample_application_fee_refund(purchase_id, id, amount_minor);
    let cases = [
        (
            "keyed converted refund with recorded request",
            vec![recorded(
                keyed(in_currency(refund("fr_keyed_123", 105), "eur"), &input),
                125,
                "usd",
            )],
            "fr_keyed_123",
        ),
        (
            "legacy converted refund with recorded request",
            vec![recorded(
                in_currency(refund("fr_legacy_123", 105), "eur"),
                125,
                "usd",
            )],
            "fr_legacy_123",
        ),
        (
            "idempotency key wins over an earlier legacy match",
            vec![
                refund("fr_other_123", 125),
                keyed(refund("fr_keyed_123", 125), &input),
            ],
            "fr_keyed_123",
        ),
        (
            "legacy amount match",
            vec![refund("fr_legacy_123", 125)],
            "fr_legacy_123",
        ),
        (
            "matching idempotency key",
            vec![keyed(refund("fr_keyed_123", 125), &input)],
            "fr_keyed_123",
        ),
        (
            "legacy mismatch skipped when a later amount matches",
            vec![refund("fr_wrong_123", 10), refund("fr_legacy_123", 125)],
            "fr_legacy_123",
        ),
    ];

    for (case, refunds, expected_id) in cases {
        // Match the listed refunds against the adjustment
        let matched = StripeProvider::find_matching_application_fee_refund(&input, refunds)
            .unwrap_or_else(|err| panic!("{case}: {err:#}"))
            .unwrap_or_else(|| panic!("{case}: expected a matching refund"));

        // Check the expected provider refund is adopted
        assert_eq!(matched.id, expected_id, "{case}");
    }
}

#[test]
fn test_find_matching_application_fee_refund_rejects_divergent_refunds() {
    // Setup an adjustment and listed refunds whose provider fields diverge
    let purchase_id = Uuid::new_v4();
    let input = sample_application_fee_adjustment_input(purchase_id);
    let refund =
        |id: &str, amount_minor| sample_application_fee_refund(purchase_id, id, amount_minor);
    let keyed_rejection = |reported: &str, reason: &str| {
        format!(
            "existing Stripe application-fee refund fr_keyed_123 has {reported} but the adjustment requests 125 usd ({reason}); inspect it in the Stripe Dashboard and record the verified return through financial recovery"
        )
    };
    let cases = [
        (
            "converted keyed refund with recorded request mismatch",
            vec![recorded(
                keyed(in_currency(refund("fr_keyed_123", 105), "eur"), &input),
                99,
                "usd",
            )],
            keyed_rejection("105 eur (recorded request 99 usd)", "recorded request differs"),
        ),
        (
            "keyed amount mismatch is not replaced by a sibling",
            vec![
                keyed(refund("fr_keyed_123", 10), &input),
                refund("fr_other_123", 125),
            ],
            keyed_rejection("10 usd", "provider amount differs"),
        ),
        (
            "keyed currency mismatch without recorded request",
            vec![keyed(in_currency(refund("fr_keyed_123", 105), "eur"), &input)],
            keyed_rejection(
                "105 eur",
                "provider currency differs and no recorded request is available",
            ),
        ),
        (
            "legacy amount mismatch",
            vec![refund("fr_wrong_123", 10)],
            "existing Stripe application-fee refund has the wrong amount (fr_wrong_123 has 10 usd; expected 125 usd)"
                .to_string(),
        ),
        (
            "legacy currency mismatch",
            vec![in_currency(refund("fr_legacy_123", 125), "eur")],
            "existing Stripe application-fee refund has the wrong amount (fr_legacy_123 has 125 eur; expected 125 usd)"
                .to_string(),
        ),
        (
            "multiple legacy amount matches",
            vec![refund("fr_first_123", 125), refund("fr_second_123", 125)],
            "multiple Stripe application-fee refunds match this adjustment (fr_first_123, fr_second_123)"
                .to_string(),
        ),
        (
            "keyed recorded request mismatch",
            vec![recorded(keyed(refund("fr_keyed_123", 125), &input), 99, "usd")],
            keyed_rejection("125 usd (recorded request 99 usd)", "recorded request differs"),
        ),
    ];

    for (case, refunds, expected) in cases {
        // Match the listed refunds against the adjustment
        let Err(err) = StripeProvider::find_matching_application_fee_refund(&input, refunds) else {
            panic!("{case}: expected the refund to be rejected");
        };

        // Check the failure names the divergent provider refund
        assert_eq!(err.to_string(), expected, "{case}");
    }
}

#[test]
fn test_find_matching_application_fee_refund_returns_none_when_unmatched() {
    // Setup refunds that share some metadata but not this adjustment
    let purchase_id = Uuid::new_v4();
    let other_purchase_id = Uuid::new_v4();
    let input = sample_application_fee_adjustment_input(purchase_id);
    let mut other_kind = sample_application_fee_refund(purchase_id, "fr_kind_123", 125);
    other_kind
        .metadata
        .insert("kind".to_string(), "purchase-refund".to_string());
    let other_purchase = sample_application_fee_refund(other_purchase_id, "fr_purchase_123", 125);

    // Look up an adjustment that has not been created on Stripe
    let refund = StripeProvider::find_matching_application_fee_refund(
        &input,
        vec![other_kind, other_purchase],
    )
    .expect("application-fee refund lookup to parse");

    // Check unmatched listings leave the caller free to create
    assert!(refund.is_none());
}

#[test]
fn test_find_matching_refund_result_selects_matching_refunds() {
    // Setup listed refunds for the purchase and the lookups they answer
    let purchase_id = Uuid::new_v4();
    let listed = |id: &str, status: &str| sample_listed_refund(purchase_id, id, status);
    let mut wrong_amount = listed("re_test_123", "succeeded");
    wrong_amount.amount = 2_400;
    let cases = [
        (
            "succeeded refund",
            vec![listed("re_test_123", "succeeded")],
            None,
            Some(("re_test_123", RefundPaymentStatus::Succeeded)),
        ),
        (
            "pending refund",
            vec![listed("re_test_123", "pending")],
            None,
            Some(("re_test_123", RefundPaymentStatus::Pending)),
        ),
        (
            "refund requiring action",
            vec![listed("re_test_123", "requires_action")],
            None,
            Some(("re_test_123", RefundPaymentStatus::Pending)),
        ),
        (
            "canceled refund when unpinned",
            vec![listed("re_test_123", "canceled")],
            None,
            None,
        ),
        (
            "failed refund when unpinned",
            vec![listed("re_test_123", "failed")],
            None,
            None,
        ),
        (
            "failed refund when pinned",
            vec![listed("re_failed_123", "failed")],
            Some("re_failed_123"),
            Some(("re_failed_123", RefundPaymentStatus::Failed)),
        ),
        (
            "succeeded refund preferred over pending",
            vec![
                listed("re_pending_123", "pending"),
                listed("re_succeeded_123", "succeeded"),
            ],
            None,
            Some(("re_succeeded_123", RefundPaymentStatus::Succeeded)),
        ),
        ("refund with another amount", vec![wrong_amount], None, None),
        (
            "refund for another purchase",
            vec![sample_listed_refund(
                Uuid::new_v4(),
                "re_other_123",
                "succeeded",
            )],
            None,
            None,
        ),
        (
            "pinned refund absent from the listing",
            vec![listed("re_test_123", "succeeded")],
            Some("re_missing_123"),
            None,
        ),
    ];

    for (case, refunds, pinned, expected) in cases {
        // Find the matching refund for the optionally pinned lookup
        let mut input = sample_find_refund_input(purchase_id);
        input.provider_refund_id = pinned.map(str::to_string);
        let refund = StripeProvider::find_matching_refund_result(&input, refunds)
            .unwrap_or_else(|err| panic!("{case}: {err:#}"));

        // Check the selected refund and its mapped status
        assert_eq!(
            refund
                .as_ref()
                .map(|refund| (refund.provider_refund_id.as_str(), refund.status)),
            expected,
            "{case}"
        );
    }
}

#[tokio::test]
async fn test_find_refund_scopes_the_lookup_to_the_connected_account_payment() {
    // Setup the connected-account refund listing for the payment intent
    let purchase_id = Uuid::new_v4();
    let router = Router::new().route(
        "/v1/refunds",
        get(move |headers: HeaderMap, uri: Uri| async move {
            assert_eq!(headers["stripe-account"], "acct_test_123");
            assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
            assert_eq!(uri.query(), Some("payment_intent=pi_test_123&limit=100"));
            Json(json!({
                "data": [{
                    "amount": 2500,
                    "id": "re_test_123",
                    "metadata": {"event_purchase_id": purchase_id},
                    "status": "pending"
                }]
            }))
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Look up the purchase refund through the provider boundary
    let refund = provider
        .find_refund(&sample_find_refund_input(purchase_id))
        .await
        .expect("refund lookup to succeed")
        .expect("listed refund to match");

    // Check the listed refund is mapped
    assert_eq!(refund.provider_refund_id, "re_test_123");
    assert_eq!(refund.status, RefundPaymentStatus::Pending);
}

#[tokio::test]
async fn test_get_checkout_financial_context_reads_authoritative_connected_account_amounts() {
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
    let provider = spawn_stripe_provider(router).await;

    // Retrieve the expanded provider context used by purchase reconciliation
    let context = provider
        .get_checkout_financial_context(&GetCheckoutFinancialContextInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider_session_id: "cs_test_123".to_string(),
        })
        .await
        .expect("Checkout financial context to be retrieved");

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
async fn test_get_checkout_financial_context_rejects_unpaid_session() {
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
    let provider = spawn_stripe_provider(router).await;

    // Retrieve the financial context from the unpaid session
    let error = provider
        .get_checkout_financial_context(&GetCheckoutFinancialContextInput {
            connected_seller_id: "acct_test_123".to_string(),
            provider_session_id: "cs_test_unpaid".to_string(),
        })
        .await
        .expect_err("unpaid Checkout Session to be rejected");

    // Check the unpaid provider state is rejected
    assert_eq!(
        error.to_string(),
        "Stripe Checkout Session is not paid (status: unpaid)"
    );
}

#[tokio::test]
async fn test_get_financial_document_scopes_invoice_retrieval_to_its_connected_account() {
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
    let provider = spawn_stripe_provider(router).await;

    // Retrieve the current attendee-facing provider document
    let document = provider
        .get_financial_document(&GetFinancialDocumentInput {
            connected_seller_id: "acct_test_123".to_string(),
            kind: FinancialDocumentKind::Invoice,
            provider_document_id: "in_test_123".to_string(),
        })
        .await
        .expect("account-scoped invoice to be retrieved");

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
async fn test_list_tax_rates_scopes_filters_and_paginates() {
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
    let provider = spawn_stripe_provider(router).await;

    // List account-owned rates compatible with exclusive ticket prices
    let rates = provider
        .list_tax_rates(&ListTaxRatesInput {
            connected_seller_id: "acct_test_123".to_string(),
            tax_behavior: TicketTaxBehavior::Exclusive,
        })
        .await
        .expect("compatible Tax Rates to be listed");

    // Check pagination order and provider metadata are preserved
    assert_eq!(
        rates.iter().map(|rate| rate.id.as_str()).collect::<Vec<_>>(),
        vec!["txr_first", "txr_second"]
    );
    assert_eq!(rates[0].jurisdiction.as_deref(), Some("California"));
    assert_eq!(rates[0].percentage, "8.875");
}

#[tokio::test]
async fn test_list_tax_rates_propagates_provider_errors() {
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
    let provider = spawn_stripe_provider(router).await;

    // List the connected account's rates while Stripe is unavailable
    let err = provider
        .list_tax_rates(&ListTaxRatesInput {
            connected_seller_id: "acct_test_123".to_string(),
            tax_behavior: TicketTaxBehavior::Inclusive,
        })
        .await
        .expect_err("provider failure to be returned");

    // Check the listing error preserves the provider response context
    assert!(err.to_string().contains("temporarily unavailable"));
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_accepts_created_refund_converted_to_platform_currency()
 {
    // Setup an empty lookup, a purchase-currency fee, and a creation response Stripe converted
    let purchase_id = Uuid::new_v4();
    let router = Router::new()
        .route(
            "/v1/application_fees/fee_test_123",
            get(|| async { Json(json!({"amount": 125, "amount_refunded": 0, "currency": "usd"})) }),
        )
        .route(
            "/v1/application_fees/fee_test_123/refunds",
            get(|| async { Json(json!({"data": [], "has_more": false})) }).post(
                move |body: String| async move {
                    // Echo the request metadata back the way Stripe stores it
                    let form: BTreeMap<String, String> =
                        serde_urlencoded::from_str(&body).expect("application-fee form to parse");
                    assert_eq!(form.get("amount"), Some(&"125".to_string()));
                    Json(json!({
                        "amount": 105,
                        "currency": "eur",
                        "id": "fr_converted_123",
                        "metadata": {
                            "event_purchase_id": purchase_id,
                            "idempotency_key": "fee-adjustment-test",
                            "kind": "tax-reconciliation",
                            "requested_amount_minor": "125",
                            "requested_currency": "usd"
                        }
                    }))
                },
            ),
        );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile an adjustment whose refund Stripe reports in the platform currency
    let result = provider
        .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(purchase_id))
        .await
        .expect("converted created refund to be accepted");

    // Check the created refund is accepted through its recorded request
    assert_eq!(
        result.provider_application_fee_refund_id,
        "fr_converted_123"
    );
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_adopts_stale_claim_refund_after_remaining_rejection()
 {
    // Setup a listing that gains the keyed refund after the first attempt and a fully refunded fee
    let purchase_id = Uuid::new_v4();
    let input = sample_application_fee_adjustment_input(purchase_id);
    let listed_refunds = Arc::new(Mutex::new(Vec::<serde_json::Value>::new()));
    let fee_retrievals = Arc::new(AtomicUsize::new(0));
    let refund_creations = Arc::new(AtomicUsize::new(0));
    let router = Router::new()
        .route(
            "/v1/application_fees/fee_test_123",
            get({
                let fee_retrievals = Arc::clone(&fee_retrievals);
                move || {
                    let fee_retrievals = Arc::clone(&fee_retrievals);
                    async move {
                        fee_retrievals.fetch_add(1, Ordering::SeqCst);
                        Json(json!({"amount": 125, "amount_refunded": 125, "currency": "usd"}))
                    }
                }
            }),
        )
        .route(
            "/v1/application_fees/fee_test_123/refunds",
            get({
                let listed_refunds = Arc::clone(&listed_refunds);
                move || {
                    let listed_refunds = Arc::clone(&listed_refunds);
                    async move {
                        let data = listed_refunds
                            .lock()
                            .expect("listed refunds lock to be available")
                            .clone();
                        Json(json!({"data": data, "has_more": false}))
                    }
                }
            })
            .post({
                let refund_creations = Arc::clone(&refund_creations);
                move || {
                    let refund_creations = Arc::clone(&refund_creations);
                    async move {
                        refund_creations.fetch_add(1, Ordering::SeqCst);
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            "application-fee refund must not be created",
                        )
                    }
                }
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile while the stale claim's refund is not listed yet
    let err = provider
        .reconcile_application_fee_adjustment(&input)
        .await
        .expect_err("insufficient remaining amount to be rejected");

    // Check the attempt fails without creating another refund
    assert!(err.to_string().contains("fee_test_123 has 0 usd unrefunded"));
    assert!(err.to_string().contains("may already exist"));
    assert_eq!(fee_retrievals.load(Ordering::SeqCst), 1);
    assert_eq!(refund_creations.load(Ordering::SeqCst), 0);

    // Surface the keyed refund the stale claim created and reconcile again
    let mut keyed = sample_application_fee_refund_json("fr_stale_123", 125, "usd");
    keyed["metadata"]["event_purchase_id"] = json!(purchase_id);
    keyed["metadata"]["idempotency_key"] = json!(input.idempotency_key);
    keyed["metadata"]["kind"] = json!(input.kind);
    listed_refunds
        .lock()
        .expect("listed refunds lock to be available")
        .push(keyed);
    let result = provider
        .reconcile_application_fee_adjustment(&input)
        .await
        .expect("keyed refund to be adopted");

    // Check the existing refund is adopted without retrieving the fee or creating again
    assert_eq!(result.provider_application_fee_refund_id, "fr_stale_123");
    assert_eq!(fee_retrievals.load(Ordering::SeqCst), 1);
    assert_eq!(refund_creations.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_creates_refund_within_remaining_fee() {
    // Setup fees that cover the adjustment in every settlement representation
    let cases = [
        (
            "eur settlement transaction",
            json!({
                "amount": 125,
                "amount_refunded": 0,
                "balance_transaction": {"amount": 105, "currency": "eur"},
                "currency": "usd"
            }),
        ),
        (
            "settlement transaction id",
            json!({
                "amount": 125,
                "amount_refunded": 0,
                "balance_transaction": "txn_test_123",
                "currency": "usd"
            }),
        ),
        (
            "null settlement transaction",
            json!({
                "amount": 125,
                "amount_refunded": 0,
                "balance_transaction": null,
                "currency": "usd"
            }),
        ),
        (
            "absent settlement transaction",
            json!({"amount": 125, "amount_refunded": 0, "currency": "usd"}),
        ),
        (
            "exact remaining amount",
            json!({"amount": 200, "amount_refunded": 75, "currency": "usd"}),
        ),
    ];

    for (case, fee) in cases {
        let (provider, fee_retrievals, refund_creations) =
            spawn_application_fee_api(fee, json!({"data": [], "has_more": false})).await;

        // Reconcile the adjustment against the fee's own denomination
        let result = provider
            .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(
                Uuid::new_v4(),
            ))
            .await
            .unwrap_or_else(|err| panic!("{case}: {err:#}"));

        // Check one refund is created in the purchase currency without clamping
        assert_eq!(
            result.provider_application_fee_refund_id, "fr_test_123",
            "{case}"
        );
        assert_eq!(fee_retrievals.load(Ordering::SeqCst), 1, "{case}");
        assert_eq!(refund_creations.load(Ordering::SeqCst), 1, "{case}");
    }
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_looks_up_before_creating_on_the_platform() {
    // Setup an empty lookup, the fee retrieval, and the creation response
    let purchase_id = Uuid::new_v4();
    let router = Router::new()
        .route(
            "/v1/application_fees/fee_test_123",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert!(!headers.contains_key("stripe-account"));
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                assert!(uri.query().is_none());
                Json(json!({"amount": 125, "amount_refunded": 0, "currency": "usd"}))
            }),
        )
        .route(
            "/v1/application_fees/fee_test_123/refunds",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert!(!headers.contains_key("stripe-account"));
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                assert_eq!(uri.query(), Some("limit=100"));
                Json(json!({"data": [], "has_more": false}))
            })
            .post(move |headers: HeaderMap, body: String| async move {
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
                    form.get("metadata[event_purchase_id]"),
                    Some(&purchase_id.to_string())
                );
                assert_eq!(
                    form.get("metadata[idempotency_key]"),
                    Some(&"fee-adjustment-test".to_string())
                );
                assert_eq!(
                    form.get("metadata[kind]"),
                    Some(&"tax-reconciliation".to_string())
                );
                assert_eq!(
                    form.get("metadata[requested_amount_minor]"),
                    Some(&"125".to_string())
                );
                assert_eq!(
                    form.get("metadata[requested_currency]"),
                    Some(&"usd".to_string())
                );

                Json(sample_application_fee_refund_json(
                    "fr_test_123",
                    125,
                    "usd",
                ))
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile the durable adjustment through lookup-before-create
    let result = provider
        .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(purchase_id))
        .await
        .expect("application-fee adjustment to be reconciled");

    // Check the platform-owned provider object is returned for durable storage
    assert_eq!(result.provider_application_fee_refund_id, "fr_test_123");
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_rejects_fee_without_room_before_creating() {
    // Setup fees that cannot absorb the 125 usd adjustment
    let cases = [
        (
            "amount above remaining fee",
            json!({"amount": 125, "amount_refunded": 25, "currency": "usd"}),
            [
                "fee_test_123 has 100 usd unrefunded",
                "requests 125 usd",
                "may already exist, retry the adjustment",
            ],
        ),
        (
            "fee currency mismatch",
            json!({
                "amount": 105,
                "amount_refunded": 0,
                "balance_transaction": {"amount": 125, "currency": "usd"},
                "currency": "eur"
            }),
            [
                "fee_test_123 is denominated in eur",
                "requests 125 usd",
                "record it through financial recovery",
            ],
        ),
        (
            "invalid refunded balance",
            json!({"amount": 125, "amount_refunded": 150, "currency": "usd"}),
            [
                "fee_test_123 reports an invalid refunded amount",
                "(150 of 125)",
                "inspect it in the Stripe Dashboard",
            ],
        ),
    ];

    for (case, fee, expected_fragments) in cases {
        let (provider, fee_retrievals, refund_creations) =
            spawn_application_fee_api(fee, json!({"data": [], "has_more": false})).await;

        // Reconcile the adjustment against the fee
        let Err(err) = provider
            .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(
                Uuid::new_v4(),
            ))
            .await
        else {
            panic!("{case}: expected the adjustment to be rejected");
        };

        // Check the failure is actionable and no refund is created
        for fragment in expected_fragments {
            assert!(err.to_string().contains(fragment), "{case}: {err}");
        }
        assert_eq!(fee_retrievals.load(Ordering::SeqCst), 1, "{case}");
        assert_eq!(refund_creations.load(Ordering::SeqCst), 0, "{case}");
    }
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_rejects_invalid_input_before_contacting_stripe()
{
    // Setup adjustments that must be rejected locally
    let cases: [(&str, Mutation<ApplicationFeeAdjustmentInput>, &str); 3] = [
        (
            "zero amount",
            |input| input.amount_minor = 0,
            "application-fee adjustment amount must be positive",
        ),
        (
            "negative amount",
            |input| input.amount_minor = -1,
            "application-fee adjustment amount must be positive",
        ),
        (
            "blank connected seller",
            |input| input.connected_seller_id = " ".to_string(),
            "application-fee adjustment is missing connected seller account",
        ),
    ];
    let provider = spawn_stripe_provider(Router::new()).await;

    for (case, mutate, expected) in cases {
        let mut input = sample_application_fee_adjustment_input(Uuid::new_v4());
        mutate(&mut input);

        // Reconcile against an API with no routes
        let err = provider
            .reconcile_application_fee_adjustment(&input)
            .await
            .expect_err(case);

        // Check the local guard rejects the adjustment
        assert_eq!(err.to_string(), expected, "{case}");
    }
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_rejects_truncated_refund_listing() {
    // Setup a truncated listing ahead of the fee retrieval and creation endpoints
    let (provider, fee_retrievals, refund_creations) = spawn_application_fee_api(
        json!({"amount": 125, "amount_refunded": 0, "currency": "usd"}),
        json!({"data": [], "has_more": true}),
    )
    .await;

    // Reconcile an adjustment whose existing refunds cannot be fully listed
    let err = provider
        .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(
            Uuid::new_v4(),
        ))
        .await
        .expect_err("truncated listing to fail closed");

    // Check the failure stops before retrieving the fee or creating a refund
    assert!(
        err.to_string().contains("fee_test_123 has more than 100 refunds"),
        "{err}"
    );
    assert_eq!(fee_retrievals.load(Ordering::SeqCst), 0);
    assert_eq!(refund_creations.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_rejects_created_refund_with_unexpected_amount() {
    // Setup an empty lookup, a matching fee, and a creation response in another denomination
    let router = Router::new()
        .route(
            "/v1/application_fees/fee_test_123",
            get(|| async { Json(json!({"amount": 125, "amount_refunded": 0, "currency": "usd"})) }),
        )
        .route(
            "/v1/application_fees/fee_test_123/refunds",
            get(|| async { Json(json!({"data": [], "has_more": false})) }).post(|| async {
                Json(sample_application_fee_refund_json(
                    "fr_test_123",
                    105,
                    "eur",
                ))
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile an adjustment whose created refund diverges from the request
    let err = provider
        .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(
            Uuid::new_v4(),
        ))
        .await
        .expect_err("unexpected created refund to be rejected");

    // Check the failure names the created refund for operator inspection
    assert!(
        err.to_string()
            .contains("created application-fee refund fr_test_123 with 105 eur"),
        "{err}"
    );
    assert!(
        err.to_string()
            .contains("requests 125 usd (recorded request differs); inspect it"),
        "{err}"
    );
}

#[tokio::test]
async fn test_reconcile_application_fee_adjustment_reuses_matching_listed_refund() {
    // Setup a listed refund stored under this adjustment's durable identity
    let purchase_id = Uuid::new_v4();
    let router = Router::new()
        .route(
            "/v1/application_fees/fee_test_123",
            get(|| async {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "matching application-fee refund must not fetch the fee",
                )
            }),
        )
        .route(
            "/v1/application_fees/fee_test_123/refunds",
            get(move |headers: HeaderMap, uri: Uri| async move {
                assert!(!headers.contains_key("stripe-account"));
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                assert_eq!(uri.query(), Some("limit=100"));
                Json(json!({
                    "data": [{
                        "amount": 125,
                        "currency": "usd",
                        "id": "fr_existing_123",
                        "metadata": {
                            "event_purchase_id": purchase_id,
                            "idempotency_key": "fee-adjustment-test",
                            "kind": "tax-reconciliation"
                        }
                    }],
                    "has_more": false
                }))
            })
            .post(|| async {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "matching application-fee refund must not be created again",
                )
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile the durable adjustment against the existing provider object
    let result = provider
        .reconcile_application_fee_adjustment(&sample_application_fee_adjustment_input(purchase_id))
        .await
        .expect("application-fee adjustment to be reused");

    // Check the listed provider object is returned without another create
    assert_eq!(result.provider_application_fee_refund_id, "fr_existing_123");
}

#[tokio::test]
async fn test_reconcile_credit_note_previews_and_issues_the_full_connected_account_document() {
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
    let provider = spawn_stripe_provider(router).await;

    // Reconcile the full credit note against the existing customer refund
    let result = provider
        .reconcile_credit_note(&sample_credit_note_input())
        .await
        .expect("full credit note to be issued");

    // Check the issued provider document identity and current PDF are preserved
    assert_eq!(result.provider_credit_note_id, "cn_test_123");
    assert_eq!(
        result.provider_pdf_url.as_deref(),
        Some("https://credit-note.stripe.test/document.pdf")
    );
}

#[tokio::test]
async fn test_reconcile_credit_note_adopts_existing_document_for_the_refund() {
    // Setup a listing that already holds the credit note issued for this refund
    let input = sample_credit_note_input();
    let refund_id = input.event_purchase_refund_id;
    let router = Router::new().route(
        "/v1/credit_notes",
        get(move || async move {
            Json(json!({"data": [
                {
                    "amount": 2750,
                    "id": "cn_other_refund",
                    "metadata": {"event_purchase_refund_id": Uuid::new_v4()},
                    "pdf": null,
                    "total_taxes": [{"amount": 250}]
                },
                {
                    "amount": 2750,
                    "id": "cn_existing_123",
                    "metadata": {"event_purchase_refund_id": refund_id},
                    "pdf": "https://credit-note.stripe.test/existing.pdf",
                    "total_taxes": [{"amount": 250}]
                }
            ]}))
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile the credit note without the invoice-line, preview or issue routes
    let result = provider
        .reconcile_credit_note(&input)
        .await
        .expect("existing credit note to be adopted");

    // Check the listed document for this refund is adopted
    assert_eq!(result.provider_credit_note_id, "cn_existing_123");
    assert_eq!(
        result.provider_pdf_url.as_deref(),
        Some("https://credit-note.stripe.test/existing.pdf")
    );
}

#[tokio::test]
async fn test_reconcile_credit_note_rejects_existing_document_with_mismatched_amounts() {
    // Setup a listed credit note for this refund whose tax credit diverges
    let input = sample_credit_note_input();
    let refund_id = input.event_purchase_refund_id;
    let router = Router::new().route(
        "/v1/credit_notes",
        get(move || async move {
            Json(json!({"data": [{
                "amount": 2750,
                "id": "cn_existing_123",
                "metadata": {"event_purchase_refund_id": refund_id},
                "pdf": null,
                "total_taxes": [{"amount": 200}]
            }]}))
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Reconcile the credit note against the divergent document
    let err = provider
        .reconcile_credit_note(&input)
        .await
        .expect_err("mismatched existing credit note to be rejected");

    // Check the divergent document is not adopted
    assert_eq!(
        err.to_string(),
        "Stripe credit-note preview does not match the full purchase refund"
    );
}

#[tokio::test]
async fn test_reconcile_credit_note_rejects_invalid_amounts_before_contacting_stripe() {
    // Setup credit notes that must be rejected locally
    let cases: [(&str, Mutation<CreditNoteInput>); 3] = [
        ("zero amount", |input| input.amount_minor = 0),
        ("negative amount", |input| input.amount_minor = -1),
        ("negative tax amount", |input| input.tax_amount_minor = -1),
    ];
    let provider = spawn_stripe_provider(Router::new()).await;

    for (case, mutate) in cases {
        let mut input = sample_credit_note_input();
        mutate(&mut input);

        // Reconcile against an API with no routes
        let err = provider.reconcile_credit_note(&input).await.expect_err(case);

        // Check the local guard rejects the amounts
        assert_eq!(err.to_string(), "credit-note amounts are invalid", "{case}");
    }
}

#[tokio::test]
async fn test_refund_payment_fails_within_the_request_deadline_when_the_provider_stalls() {
    // Setup a provider endpoint that accepts connections and never answers
    let api_base_url = spawn_stalled_stripe_api().await;
    let mut provider = sample_stripe_provider_with_deadlines(HttpClientConfig {
        connect_timeout_secs: 1,
        request_timeout_secs: 1,
    });
    provider.api_base_url = api_base_url;

    // Create the refund against the stalled endpoint, bounding the test itself
    let result = timeout(
        Duration::from_secs(5),
        provider.refund_payment(&sample_refund_payment_input()),
    )
    .await
    .expect("refund call to return within the configured deadline");

    // Check the failure is the client deadline rather than a provider response
    let err = result.expect_err("stalled provider to fail the refund");
    assert!(
        err.chain().any(|cause| cause
            .downcast_ref::<reqwest::Error>()
            .is_some_and(reqwest::Error::is_timeout)),
        "expected a request timeout, got: {err:#}"
    );
}

#[tokio::test]
async fn test_refund_payment_scopes_the_full_refund_to_the_connected_account() {
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
    let provider = spawn_stripe_provider(router).await;

    // Create the full direct-charge refund
    let result = provider
        .refund_payment(&input)
        .await
        .expect("connected-account refund to be created");

    // Check the normalized successful provider result
    assert_eq!(result.provider_refund_id, "re_test_123");
    assert_eq!(result.status, RefundPaymentStatus::Succeeded);
}

#[test]
fn test_refund_result_rejects_unknown_statuses() {
    // Map an unsupported provider refund status
    let err = StripeProvider::refund_result("re_test_123".to_string(), "unknown")
        .expect_err("unknown refund status should be rejected");

    // Check the unsupported status remains actionable
    assert_eq!(err.to_string(), "unsupported Stripe refund status: unknown");
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_accepts_dashboard_created_account_and_automatic_tax_readiness()
 {
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
        )
        .route(
            "/v1/tax/registrations",
            get(|headers: HeaderMap, uri: Uri| async move {
                assert_eq!(headers["stripe-account"], "acct_test_123");
                assert_eq!(headers["stripe-version"], super::STRIPE_API_VERSION);
                assert!(uri.query().is_some_and(|query| query.contains("status=active")));
                assert!(uri.query().is_some_and(|query| query.contains("limit=100")));
                assert!(uri.query().is_none_or(|query| !query.contains("country")));
                Json(json!({
                    "data": [{
                        "country": "PT",
                        "country_options": {},
                        "id": "taxreg_pt",
                        "status": "active"
                    }],
                    "has_more": false
                }))
            }),
        );
    let provider = spawn_stripe_provider(router).await;

    // Validate the exact readiness required by automatic-tax event setup
    let result = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("PT", None))))
        .await;

    // Check both account and Tax readiness are accepted
    result.expect("ready fiscal sponsor to pass validation");
}

#[test]
fn test_tax_registration_matches_canadian_country_wide_and_province_registrations() {
    // Setup country-wide and province-specific active Canadian registrations
    let country_wide: StripeTaxRegistrationResponse = serde_json::from_value(json!({
        "country": "CA",
        "country_options": {"ca": {"type": "standard"}},
        "id": "taxreg_ca",
        "status": "active"
    }))
    .expect("country-wide Canadian registration to deserialize");
    let province: StripeTaxRegistrationResponse = serde_json::from_value(json!({
        "country": "CA",
        "country_options": {
            "ca": {
                "province_standard": {"province": "BC"},
                "type": "province_standard"
            }
        },
        "id": "taxreg_ca_bc",
        "status": "active"
    }))
    .expect("province-specific Canadian registration to deserialize");
    let ontario = jurisdiction("CA", Some("ON"));
    let british_columbia = jurisdiction("CA", Some("BC"));

    // Check country-wide registrations cover Canada while province registrations remain exact
    assert!(StripeProvider::tax_registration_matches(
        &country_wide,
        &ontario
    ));
    assert!(StripeProvider::tax_registration_matches(
        &province,
        &british_columbia
    ));
    assert!(!StripeProvider::tax_registration_matches(
        &province, &ontario
    ));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_accepts_us_registration_without_venue_state() {
    // Setup a ready sponsor with an active state registration
    let router = tax_ready_account_router().route(
        "/v1/tax/registrations",
        get(|| async {
            Json(json!({
                "data": [{
                    "country": "US",
                    "country_options": {"us": {"state": "CA"}},
                    "id": "taxreg_us_ca",
                    "status": "active"
                }],
                "has_more": false
            }))
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate country-level registration coverage until the venue state is known
    let result = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("US", None))))
        .await;

    // Allow performance-location validation to report the missing venue state
    result.expect("active US registration to pass when the venue state is not known");
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_paginates_active_tax_registrations() {
    // Setup a matching United States registration on the second provider page
    let router = tax_ready_account_router().route(
        "/v1/tax/registrations",
        get(|uri: Uri| async move {
            let query = uri.query().expect("registration query to be present");
            if query.contains("starting_after=taxreg_es") {
                Json(json!({
                    "data": [{
                        "country": "US",
                        "country_options": {"us": {"state": "CA"}},
                        "id": "taxreg_us_ca",
                        "status": "active"
                    }],
                    "has_more": false
                }))
            } else {
                assert!(query.contains("limit=100"));
                assert!(query.contains("status=active"));
                Json(json!({
                    "data": [{
                        "country": "ES",
                        "country_options": {},
                        "id": "taxreg_es",
                        "status": "active"
                    }],
                    "has_more": true
                }))
            }
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate a subdivision-scoped venue through both registration pages
    let result = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("US", Some("CA")))))
        .await;

    // Check a later matching registration satisfies readiness
    result.expect("matching paginated registration to pass readiness");
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_rejects_account_controlled_response_without_conditional_fields()
 {
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
    let provider = spawn_stripe_provider(router).await;

    // Validate the unsupported account through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&readiness_input(None))
        .await
        .expect_err("account-controlled sponsor should fail readiness validation");

    // Keep the unsupported account model organizer-correctable
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == super::STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR
    ));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_rejects_empty_incomplete_registration_page() {
    // Setup an internally inconsistent paginated registration response
    let router = tax_ready_account_router().route(
        "/v1/tax/registrations",
        get(|| async { Json(json!({"data": [], "has_more": true})) }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate readiness without allowing an unsafe pagination loop
    let err = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("PT", None))))
        .await
        .expect_err("malformed registration pagination to fail closed");

    // Preserve malformed provider responses as internal failures
    assert!(matches!(err, FiscalSponsorReadinessError::Unexpected(_)));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_rejects_inactive_automatic_tax_settings() {
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
    let provider = spawn_stripe_provider(router).await;

    // Validate automatic-tax readiness through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("PT", None))))
        .await
        .expect_err("inactive Stripe Tax settings to fail closed");

    // Check the actionable provider-readiness error is preserved
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "fiscal sponsor Stripe Tax settings are not active"
    ));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_rejects_incompatible_controller_configuration() {
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
        let provider = spawn_stripe_provider(router).await;

        // Validate the incompatible account through the public provider boundary
        let err = provider
            .validate_fiscal_sponsor(&readiness_input(None))
            .await
            .expect_err(&format!("{scenario} should fail readiness validation"));

        // Check every controller mismatch remains an organizer-correctable failure
        assert!(
            matches!(
                err,
                FiscalSponsorReadinessError::NotReady(ref message)
                    if message == super::STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR
            ),
            "{scenario}"
        );
    }
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_rejects_missing_us_state_registration() {
    // Setup active registrations that do not cover the event's United States state
    let router = tax_ready_account_router().route(
        "/v1/tax/registrations",
        get(|| async {
            Json(json!({
                "data": [
                    {
                        "country": "US",
                        "country_options": {"us": {"state": "NY"}},
                        "id": "taxreg_us_ny",
                        "status": "active"
                    },
                    {
                        "country": "US",
                        "country_options": {"us": {}},
                        "id": "taxreg_us_missing_state",
                        "status": "active"
                    }
                ],
                "has_more": false
            }))
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate an event whose state is absent from the sponsor's registrations
    let err = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("US", Some("CA")))))
        .await
        .expect_err("wrong or missing state registrations to fail readiness");

    // Check the missing jurisdiction remains organizer-actionable
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "fiscal sponsor Stripe account needs an active tax registration for US-CA"
    ));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_treats_provider_outage_as_unexpected() {
    // Setup a transient provider-side account retrieval failure
    let router = Router::new().route(
        "/v1/accounts/acct_test_123",
        get(|| async { StatusCode::SERVICE_UNAVAILABLE }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate the account through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&readiness_input(None))
        .await
        .expect_err("Stripe outage to fail readiness validation");

    // Preserve infrastructure failures as internal errors
    assert!(matches!(err, FiscalSponsorReadinessError::Unexpected(_)));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_treats_tax_registration_outage_as_unexpected() {
    // Setup a provider outage after account and Tax settings validation succeeds
    let router = tax_ready_account_router().route(
        "/v1/tax/registrations",
        get(|| async { StatusCode::SERVICE_UNAVAILABLE }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate readiness while the registration endpoint is unavailable
    let err = provider
        .validate_fiscal_sponsor(&readiness_input(Some(jurisdiction("PT", None))))
        .await
        .expect_err("Stripe registration outage to fail readiness");

    // Preserve transient provider failures as internal errors
    assert!(matches!(err, FiscalSponsorReadinessError::Unexpected(_)));
}

#[tokio::test]
async fn test_validate_fiscal_sponsor_treats_unknown_account_as_not_ready() {
    // Setup the provider response returned for an unknown connected account
    let router = Router::new().route(
        "/v1/accounts/acct_unknown",
        get(|| async { StatusCode::NOT_FOUND }),
    );
    let provider = spawn_stripe_provider(router).await;

    // Validate the unknown account through the public provider boundary
    let err = provider
        .validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: "acct_unknown".to_string(),
            ..readiness_input(None)
        })
        .await
        .expect_err("unknown Stripe account to fail readiness validation");

    // Keep organizer-correctable account selection failures user-facing
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "fiscal sponsor Stripe account could not be validated"
    ));
}

#[tokio::test]
async fn test_validate_tax_rates_accepts_active_rate_without_valid_venue_jurisdiction() {
    // Validate an active countryless rate while the event form has no valid country yet
    let result = validate_tax_rates_against(
        json!([{
            "active": true,
            "display_name": "Custom tax",
            "id": "txr_custom",
            "inclusive": true,
            "percentage": 5.0
        }]),
        &["txr_custom"],
        TicketTaxBehavior::Inclusive,
        None,
    )
    .await;

    // Defer venue errors to the event validation boundary
    result.expect("active Tax Rate to pass while the venue jurisdiction is invalid");
}

#[tokio::test]
async fn test_validate_tax_rates_accepts_matching_country_and_state() {
    // Revalidate country-wide and state-specific exclusive rates against the venue
    let result = validate_tax_rates_against(
        json!([
            {
                "active": true,
                "country": "US",
                "display_name": "Sales tax",
                "id": "txr_country",
                "inclusive": false,
                "percentage": 8.0
            },
            {
                "active": true,
                "country": "US",
                "display_name": "State tax",
                "id": "txr_state",
                "inclusive": false,
                "percentage": 1.0,
                "state": "CA"
            }
        ]),
        &["txr_country", "txr_state"],
        TicketTaxBehavior::Exclusive,
        Some(jurisdiction("US", Some("CA"))),
    )
    .await;

    // Check both compatible jurisdiction shapes remain selectable
    result.expect("matching Tax Rates to pass readiness");
}

#[tokio::test]
async fn test_validate_tax_rates_accepts_state_rate_without_venue_state() {
    // Revalidate a state-specific rate at country level for a venue without a stored state
    let result = validate_tax_rates_against(
        json!([{
            "active": true,
            "country": "US",
            "display_name": "State tax",
            "id": "txr_state",
            "inclusive": true,
            "percentage": 8.0,
            "state": "CA"
        }]),
        &["txr_state"],
        TicketTaxBehavior::Inclusive,
        Some(jurisdiction("US", None)),
    )
    .await;

    // Preserve compatibility for stored venues without subdivision codes
    result.expect("state-specific Tax Rate to pass when the venue state is unknown");
}

#[tokio::test]
async fn test_validate_tax_rates_rejects_countryless_rate() {
    // Revalidate an active rate without jurisdiction metadata against a known venue
    let err = validate_tax_rates_against(
        json!([{
            "active": true,
            "display_name": "Custom tax",
            "id": "txr_countryless",
            "inclusive": true,
            "percentage": 5.0
        }]),
        &["txr_countryless"],
        TicketTaxBehavior::Inclusive,
        Some(jurisdiction("PT", None)),
    )
    .await
    .expect_err("countryless Tax Rate to fail readiness");

    // Check the organizer is told to declare the venue country
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "manual Stripe Tax Rate txr_countryless must declare a country matching the event venue"
    ));
}

#[tokio::test]
async fn test_validate_tax_rates_rejects_empty_or_duplicate_selection_before_contacting_stripe() {
    // Setup selections that cannot identify a unique set of Tax Rates
    let cases: [(&str, Vec<String>); 4] = [
        ("empty selection", vec![]),
        (
            "duplicate selection",
            vec!["txr_state".to_string(), "txr_state".to_string()],
        ),
        ("blank identifier", vec![String::new()]),
        ("padded identifier", vec![" txr_state".to_string()]),
    ];
    let provider = spawn_stripe_provider(Router::new()).await;

    for (case, manual_tax_rate_ids) in cases {
        // Validate the selection against an API with no routes
        let err = provider
            .validate_tax_rates(&ValidateTaxRatesInput {
                connected_seller_id: "acct_test_123".to_string(),
                manual_tax_rate_ids,
                tax_behavior: TicketTaxBehavior::Inclusive,

                jurisdiction: None,
            })
            .await
            .expect_err(case);

        // Check the local guard rejects the selection
        assert!(
            matches!(
                err,
                FiscalSponsorReadinessError::NotReady(ref message)
                    if message == "manual ticket tax requires at least one unique Stripe Tax Rate"
            ),
            "{case}: {err:?}"
        );
    }
}

#[tokio::test]
async fn test_validate_tax_rates_rejects_missing_ids() {
    // Revalidate a selection absent from the account's active compatible rates
    let err = validate_tax_rates_against(
        json!([]),
        &["txr_missing"],
        TicketTaxBehavior::Inclusive,
        Some(jurisdiction("PT", None)),
    )
    .await
    .expect_err("missing Tax Rate to be rejected");

    // Check provider drift remains an organizer-actionable readiness failure
    assert!(matches!(
        err,
        FiscalSponsorReadinessError::NotReady(ref message)
            if message == "manual Stripe Tax Rates must be active in the fiscal sponsor account and match the ticket tax display"
    ));
}

#[tokio::test]
async fn test_validate_tax_rates_rejects_wrong_country_or_state() {
    // Setup active rates whose country and state each conflict with the venue
    let rates = json!([
        {
            "active": true,
            "country": "IE",
            "display_name": "Irish VAT",
            "id": "txr_ie",
            "inclusive": true,
            "percentage": 23.0
        },
        {
            "active": true,
            "country": "US",
            "display_name": "New York tax",
            "id": "txr_ny",
            "inclusive": true,
            "percentage": 8.875,
            "state": "NY"
        }
    ]);

    // Validate each mismatched selection against a California venue
    for rate_id in ["txr_ie", "txr_ny"] {
        let err = validate_tax_rates_against(
            rates.clone(),
            &[rate_id],
            TicketTaxBehavior::Inclusive,
            Some(jurisdiction("US", Some("CA"))),
        )
        .await
        .expect_err("mismatched Tax Rate to fail readiness");
        let expected =
            format!("manual Stripe Tax Rate {rate_id} does not cover the event venue US-CA");
        assert!(
            matches!(
                err,
                FiscalSponsorReadinessError::NotReady(ref message) if *message == expected
            ),
            "{rate_id}: {err:?}"
        );
    }
}

#[test]
fn test_verify_and_parse_webhook_accepts_rotated_signature() {
    // Setup a header whose matching signature follows one from a rotated secret
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let timestamp = Utc::now().timestamp();
    let expected_signature =
        StripeProvider::compute_signature("whsec_connect_test", &format!("{timestamp}.{body}"));
    let rotated_signature =
        StripeProvider::compute_signature("whsec_rotated", &format!("{timestamp}.{body}"));
    let signature_header = format!("t={timestamp},v1={rotated_signature},v1={expected_signature}");

    // Verify and parse the webhook payload
    let webhook_event = provider
        .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        .expect("rotated webhook to verify");

    // Check any matching v1 signature is accepted
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
fn test_verify_and_parse_webhook_maps_application_fee_created_events() {
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
fn test_verify_and_parse_webhook_maps_connected_events() {
    // Setup signed connected-account payloads and the events they normalize to
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let refund_body = |event_type: &str, status: &str| {
        format!(
            r#"{{"account":"acct_test_123","livemode":false,"type":"{event_type}","data":{{"object":{{"id":"re_test_123","amount":2500,"currency":"usd","metadata":{{"event_purchase_id":"{purchase_id}"}},"payment_intent":"pi_test_123","status":"{status}"}}}}}}"#
        )
    };
    let refund_event = |status| PaymentsWebhookEvent::RefundUpdated {
        amount_minor: 2_500,
        connected_account_id: "acct_test_123".to_string(),
        currency_code: "usd".to_string(),
        is_live: false,
        provider_payment_reference: "pi_test_123".to_string(),
        provider_refund_id: "re_test_123".to_string(),
        purchase_id,
        status,
    };
    let cases = [
        (
            "completed checkout",
            r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#.to_string(),
            PaymentsWebhookEvent::CheckoutCompleted {
                connected_account_id: "acct_test_123".to_string(),
                is_live: false,
                provider_session_id: "cs_test_123".to_string(),
            },
        ),
        (
            "expired checkout",
            r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.expired","data":{"object":{"id":"cs_test_123","payment_intent":null}}}"#.to_string(),
            PaymentsWebhookEvent::CheckoutExpired {
                connected_account_id: "acct_test_123".to_string(),
                is_live: false,
                provider_session_id: "cs_test_123".to_string(),
            },
        ),
        (
            "paid invoice",
            format!(
                r#"{{"account":"acct_test_123","livemode":false,"type":"invoice.paid","data":{{"object":{{"id":"in_test_123","hosted_invoice_url":"https://stripe.test/invoices/in_test_123","invoice_pdf":"https://stripe.test/invoices/in_test_123.pdf","metadata":{{"event_purchase_id":"{purchase_id}"}}}}}}}}"#
            ),
            PaymentsWebhookEvent::InvoicePaid {
                connected_account_id: "acct_test_123".to_string(),
                hosted_url: "https://stripe.test/invoices/in_test_123".to_string(),
                is_live: false,
                provider_invoice_id: "in_test_123".to_string(),
                purchase_id,
                pdf_url: Some("https://stripe.test/invoices/in_test_123.pdf".to_string()),
            },
        ),
        (
            "created refund",
            refund_body("refund.created", "pending"),
            refund_event(RefundPaymentStatus::Pending),
        ),
        (
            "failed refund",
            refund_body("refund.failed", "failed"),
            refund_event(RefundPaymentStatus::Failed),
        ),
        (
            "succeeded refund update",
            refund_body("refund.updated", "succeeded"),
            refund_event(RefundPaymentStatus::Succeeded),
        ),
        (
            "refund without purchase metadata",
            r#"{"account":"acct_test_123","livemode":false,"type":"refund.updated","data":{"object":{"id":"re_test_123","status":"succeeded"}}}"#.to_string(),
            PaymentsWebhookEvent::Noop,
        ),
    ];

    for (case, body, expected) in cases {
        // Sign and parse the connected-account payload
        let signature_header = sample_signature_header(&body, Utc::now().timestamp());
        let webhook_event = provider
            .verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
            .unwrap_or_else(|err| panic!("{case}: {err:#}"));

        // Check the normalized provider event
        assert_eq!(webhook_event, expected, "{case}");
    }
}

#[test]
fn test_verify_and_parse_webhook_rejects_endpoint_scope_mismatch() {
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
fn test_verify_and_parse_webhook_rejects_invalid_connected_payloads() {
    // Setup signed connected-account payloads that must not reach reconciliation
    let provider = sample_stripe_provider();
    let purchase_id = Uuid::new_v4();
    let refund_body = |object: &str| {
        format!(
            r#"{{"account":"acct_test_123","livemode":false,"type":"refund.updated","data":{{"object":{{"id":"re_test_123",{object},"metadata":{{"event_purchase_id":"{purchase_id}"}},"status":"succeeded"}}}}}}"#
        )
    };
    let cases = [
        (
            "live event in test mode",
            r#"{"account":"acct_test_123","livemode":true,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123"}}}"#.to_string(),
            "Stripe webhook mode does not match payments configuration",
        ),
        (
            "missing mode",
            r#"{"account":"acct_test_123","type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#.to_string(),
            "error parsing Stripe webhook payload: missing field `livemode` at line 1 column 133",
        ),
        (
            "missing payload object",
            r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":null}}"#.to_string(),
            "Stripe webhook payload is missing object data",
        ),
        (
            "unsupported event type",
            r#"{"account":"acct_test_123","livemode":false,"type":"payment_intent.succeeded","data":{"object":{"id":"pi_test_123","payment_intent":"pi_test_123"}}}"#.to_string(),
            "unsupported Stripe webhook event: payment_intent.succeeded",
        ),
        (
            "refund missing amount",
            refund_body(r#""currency":"usd","payment_intent":"pi_test_123""#),
            "Stripe refund webhook is missing amount",
        ),
        (
            "refund missing currency",
            refund_body(r#""amount":2500,"payment_intent":"pi_test_123""#),
            "Stripe refund webhook is missing currency",
        ),
        (
            "refund missing payment intent",
            refund_body(r#""amount":2500,"currency":"usd""#),
            "Stripe refund webhook is missing payment intent",
        ),
    ];

    for (case, body, expected) in cases {
        // Sign and parse the payload
        let signature_header = sample_signature_header(&body, Utc::now().timestamp());
        let Err(err) =
            provider.verify_and_parse_webhook(&sample_webhook_headers(&signature_header), &body)
        else {
            panic!("{case}: expected the webhook to be rejected");
        };

        // Check the full error chain identifies the rejected payload
        assert_eq!(format!("{err:#}"), expected, "{case}");
    }
}

#[test]
fn test_verify_and_parse_webhook_rejects_invalid_signature_headers() {
    // Setup signature headers that must not authenticate a valid payload
    let provider = sample_stripe_provider();
    let body = r#"{"account":"acct_test_123","livemode":false,"type":"checkout.session.completed","data":{"object":{"id":"cs_test_123","payment_intent":"pi_test_123"}}}"#;
    let now = Utc::now().timestamp();
    let signature =
        StripeProvider::compute_signature("whsec_connect_test", &format!("{now}.{body}"));
    let ten_minutes = TimeDelta::minutes(10).num_seconds();
    let cases = [
        (
            "invalid signature",
            format!("t={now},v1=invalid"),
            "invalid Stripe webhook signature",
        ),
        (
            "missing signature",
            format!("t={now}"),
            "missing Stripe webhook signature",
        ),
        (
            "missing timestamp",
            format!("v1={signature}"),
            "missing Stripe webhook timestamp",
        ),
        (
            "stale timestamp",
            sample_signature_header(body, now - ten_minutes),
            "stale Stripe webhook timestamp",
        ),
        (
            "future timestamp",
            sample_signature_header(body, now + ten_minutes),
            "stale Stripe webhook timestamp",
        ),
    ];

    for (case, signature_header, expected) in cases {
        // Verify the payload with the signature header
        let Err(err) =
            provider.verify_and_parse_webhook(&sample_webhook_headers(&signature_header), body)
        else {
            panic!("{case}: expected the webhook to be rejected");
        };

        // Check the header failure is identified
        assert_eq!(err.to_string(), expected, "{case}");
    }
}

#[test]
fn test_verify_and_parse_webhook_returns_noop_for_unsupported_platform_events() {
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

// Helpers.

/// Mutation a table case applies to a sample input.
type Mutation<T> = fn(&mut T);

/// Returns checkout input whose cached Product snapshot matches `loc_cached`, and its fingerprint.
fn cached_tax_product_input() -> (CreateCheckoutSessionInput, String) {
    let mut input = sample_checkout_session_input();
    let fingerprint = StripeProvider::provider_fingerprint(&[
        &input.ticket_title,
        "loc_cached",
        input.tax_code.as_deref().expect("sample tax code to exist"),
    ]);
    input.cached_product_fingerprint = Some(fingerprint.clone());
    input.cached_provider_tax_product_id = Some("prod_cached".to_string());

    (input, fingerprint)
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

/// Creates a performance location against a mocked Stripe API and returns the sent form.
async fn create_location_and_capture_form(
    input: &PerformanceLocationInput,
) -> (AutomaticTaxReadiness, BTreeMap<String, String>) {
    let captured_body = Arc::new(Mutex::new(String::new()));
    let request_body = Arc::clone(&captured_body);
    let router = Router::new().route(
        "/v1/tax/locations",
        post(move |body: String| {
            *request_body
                .lock()
                .expect("captured request body lock to be available") = body;
            async { Json(json!({"id": "loc_created"})) }
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    let readiness = provider
        .create_performance_location(input, super::STRIPE_API_VERSION)
        .await
        .expect("performance location to be created");
    let form_fields = serde_urlencoded::from_str(
        &captured_body
            .lock()
            .expect("captured request body lock to be available"),
    )
    .expect("captured request body to be valid form data");

    (readiness, form_fields)
}

/// Returns an application-fee refund reported in another currency.
fn in_currency(
    mut refund: StripeApplicationFeeRefund,
    currency: &str,
) -> StripeApplicationFeeRefund {
    refund.currency = currency.to_string();
    refund
}

/// Returns a venue tax jurisdiction.
fn jurisdiction(country_code: &str, state_code: Option<&str>) -> TicketTaxJurisdiction {
    TicketTaxJurisdiction {
        country_code: country_code.to_string(),
        state_code: state_code.map(str::to_string),
    }
}

/// Stores an application-fee refund under the adjustment's idempotency key.
fn keyed(
    mut refund: StripeApplicationFeeRefund,
    input: &ApplicationFeeAdjustmentInput,
) -> StripeApplicationFeeRefund {
    refund
        .metadata
        .insert("idempotency_key".to_string(), input.idempotency_key.clone());
    refund
}

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
    let provider = spawn_stripe_provider(router).await;
    let mut input = sample_performance_location_input();
    input.venue.state_code = state_code.map(str::to_string);

    provider
        .create_performance_location(&input, super::STRIPE_API_VERSION)
        .await
        .expect_err("mocked Stripe error to be classified")
}

/// Returns readiness input for the sample connected account.
fn readiness_input(
    automatic_tax_jurisdiction: Option<TicketTaxJurisdiction>,
) -> FiscalSponsorReadinessInput {
    FiscalSponsorReadinessInput {
        connected_seller_id: "acct_test_123".to_string(),
        provider: PaymentProvider::Stripe,

        automatic_tax_jurisdiction,
    }
}

/// Adds a recorded creation request to an application-fee refund.
fn recorded(
    mut refund: StripeApplicationFeeRefund,
    amount_minor: i64,
    currency: &str,
) -> StripeApplicationFeeRefund {
    refund.metadata.insert(
        "requested_amount_minor".to_string(),
        amount_minor.to_string(),
    );
    refund
        .metadata
        .insert("requested_currency".to_string(), currency.to_string());
    refund
}

/// Creates sample application-fee adjustment input.
fn sample_application_fee_adjustment_input(purchase_id: Uuid) -> ApplicationFeeAdjustmentInput {
    ApplicationFeeAdjustmentInput {
        amount_minor: 125,
        connected_seller_id: "acct_test_123".to_string(),
        currency_code: "USD".to_string(),
        event_purchase_id: purchase_id,
        idempotency_key: "fee-adjustment-test".to_string(),
        kind: "tax-reconciliation".to_string(),
        provider_application_fee_id: "fee_test_123".to_string(),
    }
}

/// Creates a listed application-fee refund for matcher tests.
fn sample_application_fee_refund(
    purchase_id: Uuid,
    id: &str,
    amount_minor: i64,
) -> StripeApplicationFeeRefund {
    StripeApplicationFeeRefund {
        amount: amount_minor,
        currency: "usd".to_string(),
        id: id.to_string(),

        metadata: BTreeMap::from([
            ("event_purchase_id".to_string(), purchase_id.to_string()),
            ("kind".to_string(), "tax-reconciliation".to_string()),
        ]),
    }
}

/// Creates the JSON Stripe returns for an application-fee refund created by OCG.
fn sample_application_fee_refund_json(
    id: &str,
    amount_minor: i64,
    currency: &str,
) -> serde_json::Value {
    json!({
        "amount": amount_minor,
        "currency": currency,
        "id": id,
        "metadata": {
            "requested_amount_minor": amount_minor.to_string(),
            "requested_currency": currency
        }
    })
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

/// Creates sample credit-note input for a full purchase refund.
fn sample_credit_note_input() -> CreditNoteInput {
    CreditNoteInput {
        amount_minor: 2750,
        connected_seller_id: "acct_test_123".to_string(),
        event_purchase_id: Uuid::new_v4(),
        event_purchase_refund_id: Uuid::new_v4(),
        idempotency_key: "credit-note-test".to_string(),
        provider_invoice_id: "in_test_123".to_string(),
        provider_refund_id: "re_test_123".to_string(),
        tax_amount_minor: 250,
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

/// Creates a sample Stripe provider with the default request deadlines.
fn sample_stripe_provider() -> StripeProvider {
    sample_stripe_provider_with_deadlines(HttpClientConfig::default())
}

/// Creates a sample Stripe provider with the given request deadlines.
fn sample_stripe_provider_with_deadlines(http_client: HttpClientConfig) -> StripeProvider {
    StripeProvider::new(PaymentsStripeConfig {
        connected_webhook_secret: "whsec_connect_test".to_string(),
        mode: PaymentMode::Test,
        secret_key: "sk_test".to_string(),
        ticket_tax_api_version: "2026-07-29.preview".to_string(),
        webhook_secret: "whsec_test".to_string(),

        http_client,
        platform_fee_bps: 0,
    })
    .expect("sample Stripe provider to build")
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

/// Starts an application-fee API serving `fee` and `listing`.
///
/// Returns the provider plus fee-retrieval and refund-creation counters. Refund creation
/// requires the 125 minor-unit request and returns the created 125 usd refund.
async fn spawn_application_fee_api(
    fee: serde_json::Value,
    listing: serde_json::Value,
) -> (StripeProvider, Arc<AtomicUsize>, Arc<AtomicUsize>) {
    let fee_retrievals = Arc::new(AtomicUsize::new(0));
    let refund_creations = Arc::new(AtomicUsize::new(0));
    let router = Router::new()
        .route(
            "/v1/application_fees/fee_test_123",
            get({
                let fee_retrievals = Arc::clone(&fee_retrievals);
                move || {
                    fee_retrievals.fetch_add(1, Ordering::SeqCst);
                    let fee = fee.clone();
                    async move { Json(fee) }
                }
            }),
        )
        .route(
            "/v1/application_fees/fee_test_123/refunds",
            get(move || {
                let listing = listing.clone();
                async move { Json(listing) }
            })
            .post({
                let refund_creations = Arc::clone(&refund_creations);
                move |body: String| {
                    refund_creations.fetch_add(1, Ordering::SeqCst);
                    async move {
                        let form: BTreeMap<String, String> = serde_urlencoded::from_str(&body)
                            .expect("application-fee form to parse");
                        assert_eq!(form.get("amount"), Some(&"125".to_string()));
                        Json(sample_application_fee_refund_json(
                            "fr_test_123",
                            125,
                            "usd",
                        ))
                    }
                }
            }),
        );

    (
        spawn_stripe_provider(router).await,
        fee_retrievals,
        refund_creations,
    )
}

/// Spawns a listener that accepts connections and never responds, returning its base URL.
async fn spawn_stalled_stripe_api() -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("stalled Stripe API listener to bind");
    let address = listener
        .local_addr()
        .expect("stalled Stripe API listener address to exist");
    tokio::spawn(async move {
        // Keep every accepted connection open without writing a response
        let mut connections = Vec::new();
        loop {
            let (stream, _) = listener.accept().await.expect("stalled Stripe API to accept");
            connections.push(stream);
        }
    });

    format!("http://{address}/v1")
}

/// Starts a local Stripe-shaped API and returns a provider pointed at it.
///
/// The server task is detached; the test runtime stops it when the test ends.
async fn spawn_stripe_provider(router: Router) -> StripeProvider {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("test Stripe API listener to bind");
    let address = listener
        .local_addr()
        .expect("test Stripe API listener address to exist");
    tokio::spawn(async move {
        axum::serve(listener, router).await.expect("test Stripe API to serve");
    });

    let mut provider = sample_stripe_provider();
    provider.api_base_url = format!("http://{address}/v1");
    provider
}

/// Returns a router serving a ready sample connected account with active Stripe Tax settings.
fn tax_ready_account_router() -> Router {
    Router::new()
        .route(
            "/v1/accounts/acct_test_123",
            get(|| async { Json(sample_stripe_account_response()) }),
        )
        .route(
            "/v1/tax/settings",
            get(|| async { Json(json!({"status": "active"})) }),
        )
}

/// Validates selected Tax Rates against a mocked connected-account rate listing.
///
/// The listing route checks the account scope and the inclusive filter for `tax_behavior`.
async fn validate_tax_rates_against(
    rates: serde_json::Value,
    manual_tax_rate_ids: &[&str],
    tax_behavior: TicketTaxBehavior,
    jurisdiction: Option<TicketTaxJurisdiction>,
) -> Result<(), FiscalSponsorReadinessError> {
    let inclusive = format!("inclusive={}", tax_behavior == TicketTaxBehavior::Inclusive);
    let router = Router::new().route(
        "/v1/tax_rates",
        get(move |headers: HeaderMap, uri: Uri| async move {
            assert_eq!(headers["stripe-account"], "acct_test_123");
            assert!(
                uri.query().is_some_and(|query| query.contains(&inclusive)),
                "expected {inclusive} in {uri}"
            );
            Json(json!({"data": rates, "has_more": false}))
        }),
    );
    let provider = spawn_stripe_provider(router).await;

    provider
        .validate_tax_rates(&ValidateTaxRatesInput {
            connected_seller_id: "acct_test_123".to_string(),
            manual_tax_rate_ids: manual_tax_rate_ids.iter().map(ToString::to_string).collect(),
            tax_behavior,

            jurisdiction,
        })
        .await
}
