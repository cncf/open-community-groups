//! Stripe-backed payments provider implementation.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context, Result, bail};
use async_trait::async_trait;
use axum::http::HeaderMap;
use chrono::Utc;
use hmac::{Hmac, KeyInit, Mac};
use reqwest::Client;
use serde::Deserialize;
use sha2::Sha256;
use subtle::ConstantTimeEq;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::PaymentsStripeConfig,
    types::payments::{
        PaymentMode, PaymentProvider, TicketTaxBehavior, TicketTaxCalculationMode, TicketTaxRate,
    },
    util::base_url_without_trailing_slash,
};

use super::{
    ApplicationFeeAdjustmentInput, ApplicationFeeAdjustmentResult, CheckoutFinancialContext,
    CheckoutSession, CreateCheckoutSessionInput, CreditNoteInput, CreditNoteResult,
    FinancialDocument, FinancialDocumentKind, FindRefundInput, FiscalSponsorReadinessError,
    FiscalSponsorReadinessInput, GetCheckoutFinancialContextInput, GetFinancialDocumentInput,
    ListTaxRatesInput, PaymentsProvider, PaymentsWebhookEndpoint, PaymentsWebhookEvent,
    RefundPaymentInput, RefundPaymentResult, RefundPaymentStatus, ValidateTaxRatesInput,
};

#[cfg(test)]
mod tests;

/// Readiness error for connected accounts outside OCG's supported controller model.
const STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR: &str = "fiscal sponsor Stripe account must use application control, full Dashboard access, sponsor-paid fees, Stripe-collected requirements, and Stripe liability for payment-related negative balances";

/// Stripe API version used by OCG requests.
const STRIPE_API_VERSION: &str = "2024-10-28.acacia";

/// Stripe Checkout payment methods currently allowed by OCG.
const STRIPE_CHECKOUT_PAYMENT_METHOD_TYPES: [&str; 1] = ["card"];

/// Maximum length accepted by Stripe for Product names.
const STRIPE_PRODUCT_NAME_MAX_LEN: usize = 250;

/// Maximum accepted age for Stripe webhook signatures.
const STRIPE_WEBHOOK_TOLERANCE_SECS: i64 = 300;

/// Stripe-backed payments provider implementation.
pub(crate) struct StripeProvider {
    /// Stripe API base URL.
    api_base_url: String,
    /// Stripe provider configuration.
    cfg: PaymentsStripeConfig,
    /// HTTP client used for Stripe API requests.
    client: Client,
}

impl StripeProvider {
    /// Creates a new Stripe provider.
    pub(crate) fn new(cfg: PaymentsStripeConfig) -> Self {
        Self {
            api_base_url: "https://api.stripe.com/v1".to_string(),
            cfg,
            client: Client::new(),
        }
    }

    /// Returns the Stripe API base URL.
    fn api_base_url(&self) -> &str {
        &self.api_base_url
    }

    /// Builds the Stripe Checkout form body for a purchase.
    fn build_checkout_session_form_fields(
        &self,
        input: &CreateCheckoutSessionInput,
        provider_tax_product_id: Option<&str>,
    ) -> Vec<(String, String)> {
        let mut form_fields = Self::checkout_base_form_fields(input);
        form_fields.extend(Self::checkout_customer_invoice_form_fields(input));
        form_fields.extend(self.checkout_optional_form_fields(input));
        form_fields.extend(Self::checkout_tax_form_fields(
            input,
            provider_tax_product_id,
        ));

        form_fields
    }

    /// Builds the Stripe refund form body for a full purchase refund.
    fn build_refund_form_fields(input: &RefundPaymentInput) -> BTreeMap<String, String> {
        BTreeMap::from([
            ("amount".to_string(), input.amount_minor.to_string()),
            (
                "metadata[event_purchase_id]".to_string(),
                input.purchase_id.to_string(),
            ),
            (
                "payment_intent".to_string(),
                input.provider_payment_reference.clone(),
            ),
        ])
    }

    /// Builds Checkout fields for the ticket price and redirect contract.
    fn checkout_base_form_fields(input: &CreateCheckoutSessionInput) -> Vec<(String, String)> {
        vec![
            (
                "cancel_url".to_string(),
                Self::event_return_url(input, "canceled"),
            ),
            (
                "client_reference_id".to_string(),
                input.purchase_id.to_string(),
            ),
            (
                "line_items[0][price_data][currency]".to_string(),
                Self::normalized_currency_code(&input.currency_code),
            ),
            (
                "line_items[0][price_data][tax_behavior]".to_string(),
                match input.tax_behavior {
                    TicketTaxBehavior::Exclusive => "exclusive",
                    TicketTaxBehavior::Inclusive => "inclusive",
                }
                .to_string(),
            ),
            (
                "line_items[0][price_data][unit_amount]".to_string(),
                input.amount_minor.to_string(),
            ),
            ("line_items[0][quantity]".to_string(), "1".to_string()),
            ("mode".to_string(), "payment".to_string()),
            (
                "success_url".to_string(),
                Self::event_return_url(input, "success"),
            ),
        ]
    }

    /// Builds Checkout fields for billing, invoices, and durable metadata.
    fn checkout_customer_invoice_form_fields(
        input: &CreateCheckoutSessionInput,
    ) -> Vec<(String, String)> {
        vec![
            (
                "billing_address_collection".to_string(),
                "required".to_string(),
            ),
            ("customer_creation".to_string(), "always".to_string()),
            ("invoice_creation[enabled]".to_string(), "true".to_string()),
            (
                "invoice_creation[invoice_data][description]".to_string(),
                Self::invoice_description(input),
            ),
            (
                "invoice_creation[invoice_data][metadata][event_purchase_id]".to_string(),
                input.purchase_id.to_string(),
            ),
            (
                "payment_intent_data[metadata][event_id]".to_string(),
                input.event_id.to_string(),
            ),
            (
                "payment_intent_data[metadata][event_purchase_id]".to_string(),
                input.purchase_id.to_string(),
            ),
            (
                "payment_intent_data[metadata][user_id]".to_string(),
                input.user_id.to_string(),
            ),
            ("tax_id_collection[enabled]".to_string(), "true".to_string()),
        ]
    }

    /// Builds a deterministic idempotency key for Stripe checkout sessions.
    fn checkout_idempotency_key(purchase_id: Uuid) -> String {
        format!("event-purchase-checkout-{purchase_id}")
    }

    /// Builds optional Checkout payment method, discount, fee, and environment fields.
    fn checkout_optional_form_fields(
        &self,
        input: &CreateCheckoutSessionInput,
    ) -> Vec<(String, String)> {
        let mut form_fields = Vec::new();
        for (index, payment_method_type) in STRIPE_CHECKOUT_PAYMENT_METHOD_TYPES.iter().enumerate()
        {
            form_fields.push((
                format!("payment_method_types[{index}]"),
                (*payment_method_type).to_string(),
            ));
        }
        if let Some(discount_code) = &input.discount_code {
            form_fields.push((
                "payment_intent_data[metadata][discount_code]".to_string(),
                discount_code.clone(),
            ));
        }
        if input.provisional_platform_fee_amount_minor > 0 {
            form_fields.push((
                "payment_intent_data[application_fee_amount]".to_string(),
                input.provisional_platform_fee_amount_minor.to_string(),
            ));
        }
        if self.cfg.mode == PaymentMode::Test {
            form_fields.push(("metadata[environment]".to_string(), "test".to_string()));
        }
        form_fields
    }

    /// Builds Checkout tax fields for automatic or manual-rate calculation.
    fn checkout_tax_form_fields(
        input: &CreateCheckoutSessionInput,
        provider_tax_product_id: Option<&str>,
    ) -> Vec<(String, String)> {
        if let Some(provider_tax_product_id) = provider_tax_product_id {
            return vec![
                ("automatic_tax[enabled]".to_string(), "true".to_string()),
                (
                    "line_items[0][price_data][product]".to_string(),
                    provider_tax_product_id.to_string(),
                ),
            ];
        }

        let mut form_fields = vec![(
            "line_items[0][price_data][product_data][name]".to_string(),
            Self::truncate(&input.ticket_title, STRIPE_PRODUCT_NAME_MAX_LEN),
        )];
        for (index, tax_rate_id) in input
            .manual_tax_rate_ids
            .as_deref()
            .unwrap_or_default()
            .iter()
            .enumerate()
        {
            form_fields.push((
                format!("line_items[0][tax_rates][{index}]"),
                tax_rate_id.clone(),
            ));
        }
        form_fields
    }

    /// Builds the signature digest used by Stripe.
    fn compute_signature(secret: &str, payload: &str) -> String {
        type HmacSha256 = Hmac<Sha256>;

        let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
            .expect("HMAC accepts arbitrary key sizes");
        mac.update(payload.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }

    /// Creates or reuses an account-scoped performance location.
    async fn create_performance_location(
        &self,
        input: &CreateCheckoutSessionInput,
        api_version: &str,
    ) -> Result<(String, String)> {
        // Require the ISO subdivision code expected by Stripe Tax
        let state_code = input
            .venue
            .state_code
            .as_deref()
            .filter(|state_code| !state_code.trim().is_empty())
            .context("automatic ticket tax requires a venue state code")?;

        // Fingerprint the complete venue snapshot used by Stripe Tax
        let fingerprint = Self::provider_fingerprint(&[
            &input.venue.address,
            &input.venue.city,
            &input.venue.country_code,
            &input.venue.name,
            state_code,
            &input.venue.zip_code,
        ]);

        // Reuse the persisted location while its source snapshot still matches
        if input.cached_performance_location_fingerprint.as_deref() == Some(fingerprint.as_str())
            && let Some(provider_tax_location_id) = input.cached_provider_tax_location_id.as_ref()
        {
            return Ok((provider_tax_location_id.clone(), fingerprint));
        }

        // Build the performance location request with ISO location codes
        let form_fields = vec![
            ("address[city]", input.venue.city.as_str()),
            ("address[country]", input.venue.country_code.as_str()),
            ("address[line1]", input.venue.address.as_str()),
            ("address[postal_code]", input.venue.zip_code.as_str()),
            ("address[state]", state_code),
            ("description", input.venue.name.as_str()),
            ("type", "performance"),
        ];

        // Create the immutable location with an account-and-address stable key
        let response = self
            .client
            .post(format!("{}/tax/locations", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header("idempotency-key", format!("ocg-tax-location-{fingerprint}"))
            .header("stripe-account", &input.seller.connected_account_id)
            .header("stripe-version", api_version)
            .body(serde_urlencoded::to_string(form_fields)?)
            .send()
            .await
            .context("error creating Stripe performance location")?;

        // Parse the created location identifier
        let response = Self::parse_provider_response::<StripeIdResponse>(
            response,
            "performance location creation",
        )
        .await?;

        Ok((response.id, fingerprint))
    }

    /// Creates or reuses an account-scoped ticket Product.
    async fn create_tax_product(
        &self,
        input: &CreateCheckoutSessionInput,
        api_version: &str,
        provider_tax_location_id: &str,
    ) -> Result<(String, String)> {
        // Validate and fingerprint the immutable Product snapshot
        let tax_code = input
            .tax_code
            .as_deref()
            .context("automatic Stripe Tax checkout is missing a ticket tax code")?;
        let title = Self::truncate(&input.ticket_title, STRIPE_PRODUCT_NAME_MAX_LEN);
        let fingerprint = Self::provider_fingerprint(&[&title, provider_tax_location_id, tax_code]);
        let mut replaced_provider_tax_product_id = None;

        // Revalidate a fingerprint-matched cached Product against Stripe
        if input.cached_product_fingerprint.as_deref() == Some(fingerprint.as_str())
            && let Some(provider_tax_product_id) = input.cached_provider_tax_product_id.as_ref()
        {
            let product = self
                .retrieve_tax_product(
                    &input.seller.connected_account_id,
                    provider_tax_product_id,
                    api_version,
                )
                .await?;

            // Reuse only a complete active Product match
            if product.as_ref().is_some_and(|product| {
                Self::tax_product_matches(product, &title, provider_tax_location_id, tax_code)
            }) {
                return Ok((provider_tax_product_id.clone(), fingerprint));
            }

            // Bind any replacement to the stale Product identifier
            replaced_provider_tax_product_id = Some(provider_tax_product_id.as_str());
        }

        // Build the Product request from the validated snapshot
        let form_fields = [
            ("name", title.as_str()),
            (
                "tax_details[performance_location]",
                provider_tax_location_id,
            ),
            ("tax_details[tax_code]", tax_code),
        ];

        // Keep initial creation stable while rotating a stale cached Product
        let idempotency_fingerprint = replaced_provider_tax_product_id.map_or_else(
            || fingerprint.clone(),
            |provider_tax_product_id| {
                Self::provider_fingerprint(&[&fingerprint, provider_tax_product_id])
            },
        );

        // Create a replacement when the cached Product no longer matches its snapshot
        let response = self
            .client
            .post(format!("{}/products", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header(
                "idempotency-key",
                format!("ocg-tax-product-{idempotency_fingerprint}"),
            )
            .header("stripe-account", &input.seller.connected_account_id)
            .header("stripe-version", api_version)
            .body(serde_urlencoded::to_string(form_fields)?)
            .send()
            .await
            .context("error creating Stripe ticket Product")?;

        // Parse the created Product identifier
        let response =
            Self::parse_provider_response::<StripeIdResponse>(response, "Product creation").await?;

        Ok((response.id, fingerprint))
    }

    /// Formats a checkout return URL.
    fn event_return_url(input: &CreateCheckoutSessionInput, outcome: &str) -> String {
        let base_url = base_url_without_trailing_slash(&input.base_url);
        format!(
            "{base_url}/{}/group/{}/event/{}?payment={outcome}",
            input.community_name,
            input.public_group_slug(),
            input.event_slug
        )
    }

    /// Finds a matching Stripe refund and maps its current status.
    fn find_matching_refund_result(
        input: &FindRefundInput,
        refunds: Vec<StripeListedRefund>,
    ) -> Result<Option<RefundPaymentResult>> {
        // Normalize the purchase and optional provider identifiers used for matching
        let purchase_id = input.purchase_id.to_string();
        let provider_refund_id = input.provider_refund_id.as_deref();

        // Select matching non-terminal attempts unless a specific refund is pinned
        let mut matching_refunds = refunds
            .into_iter()
            .filter(|refund| {
                refund.amount == input.amount_minor
                    && refund.metadata.get("event_purchase_id") == Some(&purchase_id)
                    && provider_refund_id.is_none_or(|id| refund.id == id)
                    && (provider_refund_id.is_some()
                        || !Self::is_terminal_failure_status(&refund.status))
            })
            .collect::<Vec<_>>();

        // Prefer successful refunds over in-progress or terminal results
        matching_refunds.sort_by_key(|refund| Self::refund_status_rank(&refund.status));

        // Map the most useful matching provider refund into the shared result
        matching_refunds
            .into_iter()
            .next()
            .map(|refund| Self::refund_result(refund.id, &refund.status))
            .transpose()
    }

    /// Builds the attendee-visible invoice description from immutable context.
    fn invoice_description(input: &CreateCheckoutSessionInput) -> String {
        Self::truncate(
            &format!(
                "{} — {} / {} — {} ({}) — {}",
                input.ticket_title,
                input.community_display_name,
                input.group_name,
                input.event_name,
                input.event_timezone,
                input.venue.name,
            ),
            500,
        )
    }

    /// Returns whether a Stripe refund status cannot complete later.
    fn is_terminal_failure_status(status: &str) -> bool {
        matches!(status, "canceled" | "failed")
    }

    /// Normalizes a currency code for Stripe requests.
    fn normalized_currency_code(currency_code: &str) -> String {
        currency_code.trim().to_ascii_lowercase()
    }

    /// Parses a platform application-fee event into the shared webhook model.
    fn parse_application_fee_event(event: StripeWebhookEvent) -> Result<PaymentsWebhookEvent> {
        let object = event
            .data
            .object
            .context("Stripe webhook payload is missing object data")?;
        Ok(PaymentsWebhookEvent::ApplicationFeeCreated {
            amount_minor: object
                .amount
                .context("Stripe application-fee webhook is missing amount")?,
            connected_account_id: object
                .account
                .context("Stripe application-fee webhook is missing connected account")?,
            is_live: event.livemode,
            provider_application_fee_id: object.id,
            provider_charge_id: object
                .charge
                .context("Stripe application-fee webhook is missing charge")?,
        })
    }

    /// Parses a completed connected-account Checkout event.
    fn parse_checkout_completed_event(event: StripeWebhookEvent) -> Result<PaymentsWebhookEvent> {
        let connected_account_id = event
            .account
            .context("Stripe checkout webhook is missing connected account")?;
        let object = event
            .data
            .object
            .context("Stripe webhook payload is missing object data")?;
        Ok(PaymentsWebhookEvent::CheckoutCompleted {
            connected_account_id,
            is_live: event.livemode,
            provider_session_id: object.id,
        })
    }

    /// Parses an expired connected-account Checkout event.
    fn parse_checkout_expired_event(event: StripeWebhookEvent) -> Result<PaymentsWebhookEvent> {
        let connected_account_id = event
            .account
            .context("Stripe checkout webhook is missing connected account")?;
        let object = event
            .data
            .object
            .context("Stripe webhook payload is missing object data")?;
        Ok(PaymentsWebhookEvent::CheckoutExpired {
            connected_account_id,
            is_live: event.livemode,
            provider_session_id: object.id,
        })
    }

    /// Parses a connected-account invoice event when it belongs to an OCG purchase.
    fn parse_invoice_event(event: StripeWebhookEvent) -> Result<PaymentsWebhookEvent> {
        let connected_account_id = event
            .account
            .context("Stripe invoice webhook is missing connected account")?;
        let object = event
            .data
            .object
            .context("Stripe webhook payload is missing object data")?;
        let Some(purchase_id) = object.metadata.get("event_purchase_id") else {
            return Ok(PaymentsWebhookEvent::Noop);
        };
        let purchase_id = purchase_id
            .parse::<Uuid>()
            .context("Stripe invoice webhook has invalid event purchase metadata")?;

        Ok(PaymentsWebhookEvent::InvoicePaid {
            connected_account_id,
            hosted_url: object
                .hosted_invoice_url
                .context("Stripe invoice webhook is missing hosted URL")?,
            is_live: event.livemode,
            provider_invoice_id: object.id,
            purchase_id,

            pdf_url: object.invoice_pdf,
        })
    }

    /// Parses a Stripe readiness response and classifies correctable account failures.
    async fn parse_fiscal_sponsor_response<T: for<'de> Deserialize<'de>>(
        response: reqwest::Response,
        operation: &str,
        not_ready_message: &str,
    ) -> std::result::Result<T, FiscalSponsorReadinessError> {
        if matches!(
            response.status(),
            reqwest::StatusCode::BAD_REQUEST | reqwest::StatusCode::NOT_FOUND
        ) {
            return Err(FiscalSponsorReadinessError::NotReady(
                not_ready_message.to_string(),
            ));
        }

        Self::parse_provider_response(response, operation)
            .await
            .map_err(FiscalSponsorReadinessError::Unexpected)
    }

    /// Parses a successful Stripe response while preserving provider errors.
    async fn parse_provider_response<T: for<'de> Deserialize<'de>>(
        response: reqwest::Response,
        operation: &str,
    ) -> Result<T> {
        if !response.status().is_success() {
            let status = response.status();
            let body = response
                .text()
                .await
                .unwrap_or_else(|_| "unable to read Stripe error response".to_string());
            bail!("Stripe {operation} failed ({status}): {body}");
        }

        response
            .json()
            .await
            .with_context(|| format!("error parsing Stripe {operation} response"))
    }

    /// Parses a connected-account refund event when it belongs to an OCG purchase.
    fn parse_refund_event(event: StripeWebhookEvent) -> Result<PaymentsWebhookEvent> {
        let connected_account_id = event
            .account
            .context("Stripe refund webhook is missing connected account")?;
        let object = event
            .data
            .object
            .context("Stripe webhook payload is missing object data")?;
        let Some(purchase_id) = object.metadata.get("event_purchase_id") else {
            return Ok(PaymentsWebhookEvent::Noop);
        };
        let purchase_id = purchase_id
            .parse::<Uuid>()
            .context("Stripe refund webhook has invalid event purchase metadata")?;
        let amount_minor = object.amount.context("Stripe refund webhook is missing amount")?;
        let currency_code = object.currency.context("Stripe refund webhook is missing currency")?;
        let provider_payment_reference = object
            .payment_intent
            .context("Stripe refund webhook is missing payment intent")?;
        let status = object
            .status
            .as_deref()
            .context("Stripe refund webhook is missing status")?;
        let refund = Self::refund_result(object.id, status)?;

        Ok(PaymentsWebhookEvent::RefundUpdated {
            amount_minor,
            connected_account_id,
            currency_code,
            is_live: event.livemode,
            provider_payment_reference,
            provider_refund_id: refund.provider_refund_id,
            purchase_id,
            status: refund.status,
        })
    }

    /// Parses the Stripe webhook signature header.
    fn parse_signature_header(signature_header: &str) -> Result<(String, Vec<String>)> {
        let mut signatures = Vec::new();
        let mut timestamp = None;

        // Extract the signed timestamp and every v1 signature from Stripe's header
        for part in signature_header.split(',') {
            let mut pieces = part.splitn(2, '=');
            let Some(key) = pieces.next() else {
                continue;
            };
            let Some(value) = pieces.next() else {
                continue;
            };

            match key.trim() {
                "t" => timestamp = Some(value.trim().to_string()),
                "v1" => signatures.push(value.trim().to_string()),
                _ => {}
            }
        }

        let Some(timestamp) = timestamp else {
            bail!("missing Stripe webhook timestamp");
        };
        if signatures.is_empty() {
            bail!("missing Stripe webhook signature");
        }

        Ok((timestamp, signatures))
    }

    /// Normalizes a verified Stripe webhook envelope into the shared event model.
    fn parse_webhook_event(
        event: StripeWebhookEvent,
        endpoint: PaymentsWebhookEndpoint,
    ) -> Result<PaymentsWebhookEvent> {
        let event_type = event.event_type.clone();
        match event_type.as_str() {
            "application_fee.created" if endpoint == PaymentsWebhookEndpoint::PlatformAccount => {
                Self::parse_application_fee_event(event)
            }
            "checkout.session.completed" => Self::parse_checkout_completed_event(event),
            "checkout.session.expired" => Self::parse_checkout_expired_event(event),
            "invoice.paid" => Self::parse_invoice_event(event),
            "refund.created" | "refund.failed" | "refund.updated" => {
                Self::parse_refund_event(event)
            }
            _ if endpoint == PaymentsWebhookEndpoint::PlatformAccount => {
                Ok(PaymentsWebhookEvent::Noop)
            }
            unsupported => bail!("unsupported Stripe webhook event: {unsupported}"),
        }
    }

    /// Builds a stable SHA-256 fingerprint for immutable provider inputs.
    fn provider_fingerprint(parts: &[&str]) -> String {
        use sha2::Digest;

        let mut digest = Sha256::new();
        for part in parts {
            digest.update(part.as_bytes());
            digest.update([0]);
        }
        hex::encode(digest.finalize())
    }

    /// Converts a Stripe refund status into the provider result.
    fn refund_result(id: String, status: &str) -> Result<RefundPaymentResult> {
        let status = match status {
            "succeeded" => RefundPaymentStatus::Succeeded,
            "pending" | "requires_action" => RefundPaymentStatus::Pending,
            "canceled" | "failed" => RefundPaymentStatus::Failed,
            unsupported => bail!("unsupported Stripe refund status: {unsupported}"),
        };

        Ok(RefundPaymentResult {
            provider_refund_id: id,
            status,
        })
    }

    /// Ranks matching refund statuses by reconciliation usefulness.
    fn refund_status_rank(status: &str) -> u8 {
        match status {
            "succeeded" => 0,
            "pending" | "requires_action" => 1,
            "canceled" | "failed" => 2,
            _ => 3,
        }
    }

    /// Retrieves a cached Product, treating provider-side deletion as a cache miss.
    async fn retrieve_tax_product(
        &self,
        connected_seller_id: &str,
        provider_tax_product_id: &str,
        api_version: &str,
    ) -> Result<Option<StripeTaxProductResponse>> {
        let response = self
            .client
            .get(format!(
                "{}/products/{provider_tax_product_id}",
                self.api_base_url()
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", connected_seller_id)
            .header("stripe-version", api_version)
            .send()
            .await
            .context("error retrieving cached Stripe ticket Product")?;

        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }

        Self::parse_provider_response(response, "Product retrieval")
            .await
            .map(Some)
    }

    /// Returns whether a cached Product still matches the complete checkout snapshot.
    fn tax_product_matches(
        product: &StripeTaxProductResponse,
        title: &str,
        provider_tax_location_id: &str,
        tax_code: &str,
    ) -> bool {
        product.active
            && product.name == title
            && product.tax_details.as_ref().is_some_and(|tax_details| {
                tax_details.performance_location.as_deref() == Some(provider_tax_location_id)
                    && tax_details.tax_code.as_deref() == Some(tax_code)
            })
    }

    /// Truncates provider display text on a character boundary.
    fn truncate(value: &str, max_chars: usize) -> String {
        value.chars().take(max_chars).collect()
    }

    /// Revalidates the connected seller's charge and responsibility settings.
    async fn validate_connected_seller(
        &self,
        input: &FiscalSponsorReadinessInput,
    ) -> std::result::Result<(), FiscalSponsorReadinessError> {
        // Retrieve the connected account through the configured platform relationship
        let response = self
            .client
            .get(format!(
                "{}/accounts/{}",
                self.api_base_url(),
                input.connected_seller_id
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-version", STRIPE_API_VERSION)
            .send()
            .await
            .context("error retrieving Stripe connected account")
            .map_err(FiscalSponsorReadinessError::Unexpected)?;
        let account = Self::parse_fiscal_sponsor_response::<StripeAccountResponse>(
            response,
            "connected account retrieval",
            "fiscal sponsor Stripe account could not be validated",
        )
        .await?;

        // Require the provider response to match the configured fiscal sponsor
        if account.id != input.connected_seller_id {
            return Err(FiscalSponsorReadinessError::NotReady(
                "Stripe connected account response does not match the fiscal sponsor".to_string(),
            ));
        }

        // Require completed onboarding and current charge capability
        if !account.charges_enabled || !account.details_submitted {
            return Err(FiscalSponsorReadinessError::NotReady(
                "fiscal sponsor Stripe account is not ready to accept charges".to_string(),
            ));
        }

        // Require an application-controlled account relationship
        let Some(controller) = account.controller.as_ref() else {
            return Err(FiscalSponsorReadinessError::NotReady(
                STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR.to_string(),
            ));
        };
        if controller.controller_type != "application" {
            return Err(FiscalSponsorReadinessError::NotReady(
                STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR.to_string(),
            ));
        }

        // Require the Standard-like controller responsibilities used by OCG
        if controller.fees.as_ref().is_none_or(|fees| fees.payer != "account")
            || controller
                .losses
                .as_ref()
                .is_none_or(|losses| losses.payments != "stripe")
            || controller.requirement_collection.as_deref() != Some("stripe")
            || controller
                .stripe_dashboard
                .as_ref()
                .is_none_or(|dashboard| dashboard.dashboard_type != "full")
        {
            return Err(FiscalSponsorReadinessError::NotReady(
                STRIPE_ACCOUNT_CONTROLLER_READINESS_ERROR.to_string(),
            ));
        }

        // Require active sponsor-scoped Tax settings when the event uses automatic tax
        if input.require_automatic_tax {
            self.validate_connected_tax_settings(&input.connected_seller_id)
                .await?;
        }

        Ok(())
    }

    /// Requires active sponsor-scoped Stripe Tax settings for automatic tax.
    async fn validate_connected_tax_settings(
        &self,
        connected_seller_id: &str,
    ) -> std::result::Result<(), FiscalSponsorReadinessError> {
        let response = self
            .client
            .get(format!("{}/tax/settings", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", connected_seller_id)
            .header("stripe-version", STRIPE_API_VERSION)
            .send()
            .await
            .context("error retrieving fiscal sponsor Stripe Tax settings")
            .map_err(FiscalSponsorReadinessError::Unexpected)?;
        let settings = Self::parse_fiscal_sponsor_response::<StripeTaxSettingsResponse>(
            response,
            "Tax settings retrieval",
            "fiscal sponsor Stripe Tax settings could not be validated",
        )
        .await?;

        if settings.status != "active" {
            return Err(FiscalSponsorReadinessError::NotReady(
                "fiscal sponsor Stripe Tax settings are not active".to_string(),
            ));
        }

        Ok(())
    }

    /// Retrieves and validates every selected manual Tax Rate.
    async fn validate_manual_tax_rates(&self, input: &CreateCheckoutSessionInput) -> Result<()> {
        let manual_tax_rate_ids = input
            .manual_tax_rate_ids
            .as_deref()
            .context("manual tax requires at least one Tax Rate")?;

        // Recheck rate ownership, activity, and behavior immediately before Checkout
        self.validate_tax_rates(&ValidateTaxRatesInput {
            connected_seller_id: input.seller.connected_account_id.clone(),
            manual_tax_rate_ids: manual_tax_rate_ids.to_vec(),
            tax_behavior: input.tax_behavior,
        })
        .await?;

        Ok(())
    }

    /// Validates the freshness of a Stripe webhook timestamp.
    fn validate_webhook_timestamp(timestamp: &str) -> Result<()> {
        let timestamp = timestamp.parse::<i64>().context("invalid Stripe webhook timestamp")?;
        let age_secs = Utc::now().timestamp() - timestamp;

        // Reject old or far-future events to reduce replay risk
        if age_secs.abs() > STRIPE_WEBHOOK_TOLERANCE_SECS {
            bail!("stale Stripe webhook timestamp");
        }

        Ok(())
    }

    /// Verifies a connected-account webhook in provider unit tests.
    #[cfg(test)]
    fn verify_and_parse_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> Result<PaymentsWebhookEvent> {
        <Self as PaymentsProvider>::verify_and_parse_webhook(
            self,
            PaymentsWebhookEndpoint::ConnectedAccount,
            headers,
            body,
        )
    }
}

#[async_trait]
impl PaymentsProvider for StripeProvider {
    /// [`PaymentsProvider::create_checkout_session`].
    #[instrument(skip(self, input), err)]
    async fn create_checkout_session(
        &self,
        input: &CreateCheckoutSessionInput,
    ) -> Result<CheckoutSession> {
        // Reject invalid or unsupported checkout requests before contacting Stripe
        if input.amount_minor <= 0 {
            bail!("Stripe checkout requires a positive amount");
        }

        if input.provisional_platform_fee_amount_minor >= input.amount_minor {
            bail!("Stripe application fee must be less than the ticket amount");
        }

        self.validate_fiscal_sponsor(&FiscalSponsorReadinessInput {
            connected_seller_id: input.seller.connected_account_id.clone(),
            provider: input.seller.provider,
            require_automatic_tax: input.tax_calculation_mode
                == TicketTaxCalculationMode::Automatic,
        })
        .await?;

        // Provision and validate the tax resources selected for this purchase
        let (
            provider_tax_location_id,
            performance_location_fingerprint,
            provider_tax_product_id,
            product_fingerprint,
            api_version,
        ) = match input.tax_calculation_mode {
            TicketTaxCalculationMode::Automatic => {
                let api_version = self.cfg.ticket_tax_api_version.as_str();
                let (location_id, location_fingerprint) =
                    self.create_performance_location(input, api_version).await?;
                let (product_id, product_fingerprint) =
                    self.create_tax_product(input, api_version, &location_id).await?;

                (
                    Some(location_id),
                    Some(location_fingerprint),
                    Some(product_id),
                    Some(product_fingerprint),
                    api_version,
                )
            }
            TicketTaxCalculationMode::Manual => {
                self.validate_manual_tax_rates(input).await?;
                (None, None, None, None, STRIPE_API_VERSION)
            }
            TicketTaxCalculationMode::None => {
                // Ensure a no-tax purchase cannot carry a stale manual selection
                if input
                    .manual_tax_rate_ids
                    .as_ref()
                    .is_some_and(|rate_ids| !rate_ids.is_empty())
                {
                    bail!("no-tax checkout cannot include Stripe Tax Rates");
                }
                (None, None, None, None, STRIPE_API_VERSION)
            }
        };

        let form_fields =
            self.build_checkout_session_form_fields(input, provider_tax_product_id.as_deref());

        // Create the hosted Checkout Session directly in the seller account
        let response = self
            .client
            .post(format!("{}/checkout/sessions", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header(
                "idempotency-key",
                Self::checkout_idempotency_key(input.purchase_id),
            )
            .header("stripe-account", &input.seller.connected_account_id)
            .header("stripe-version", api_version)
            .body(serde_urlencoded::to_string(&form_fields)?)
            .send()
            .await
            .context("error creating Stripe checkout session")?;

        // Preserve Stripe's error body to keep failures actionable
        if !response.status().is_success() {
            let status = response.status();
            let body = response
                .text()
                .await
                .unwrap_or_else(|_| "unable to read Stripe error response".to_string());
            bail!("Stripe checkout session creation failed ({status}): {body}");
        }

        // Deserialize the minimal fields OCG needs from the Stripe response
        let response: StripeCheckoutSessionResponse = response
            .json()
            .await
            .context("error parsing Stripe checkout session response")?;

        Ok(CheckoutSession {
            provider_object_account_id: input.seller.connected_account_id.clone(),
            provider_session_id: response.id,
            redirect_url: response.url,

            performance_location_fingerprint,
            product_fingerprint,
            provider_tax_location_id,
            provider_tax_product_id,
        })
    }

    /// [`PaymentsProvider::find_refund`].
    #[instrument(skip(self, input), err)]
    async fn find_refund(&self, input: &FindRefundInput) -> Result<Option<RefundPaymentResult>> {
        // Build the provider query for refunds attached to the payment intent
        let query = serde_urlencoded::to_string([
            ("payment_intent", input.provider_payment_reference.as_str()),
            ("limit", "100"),
        ])?;

        // List refunds for the payment intent before risking another provider refund
        let mut request = self
            .client
            .get(format!("{}/refunds?{query}", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-version", STRIPE_API_VERSION);
        request = request.header("stripe-account", &input.connected_seller_id);
        let response = request.send().await.context("error listing Stripe refunds")?;

        // Preserve Stripe's error body to simplify refund diagnostics
        if !response.status().is_success() {
            let status = response.status();
            let body = response
                .text()
                .await
                .unwrap_or_else(|_| "unable to read Stripe error response".to_string());
            bail!("Stripe refund lookup failed ({status}): {body}");
        }

        // Deserialize and select the most useful matching refund
        let response: StripeRefundListResponse = response
            .json()
            .await
            .context("error parsing Stripe refund list response")?;

        Self::find_matching_refund_result(input, response.data)
    }

    /// [`PaymentsProvider::get_checkout_financial_context`].
    #[instrument(skip(self, input), err)]
    async fn get_checkout_financial_context(
        &self,
        input: &GetCheckoutFinancialContextInput,
    ) -> Result<CheckoutFinancialContext> {
        let query = serde_urlencoded::to_string([("expand[]", "payment_intent.latest_charge")])?;
        let api_version = self.cfg.ticket_tax_api_version.as_str();
        let response = self
            .client
            .get(format!(
                "{}/checkout/sessions/{}?{query}",
                self.api_base_url(),
                input.provider_session_id
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", &input.connected_seller_id)
            .header("stripe-version", api_version)
            .send()
            .await
            .context("error retrieving Stripe Checkout financial context")?;
        let checkout = Self::parse_provider_response::<StripeExpandedCheckoutSessionResponse>(
            response,
            "Checkout Session retrieval",
        )
        .await?;
        let charge = checkout
            .payment_intent
            .latest_charge
            .context("Stripe Checkout PaymentIntent is missing its Charge")?;

        Ok(CheckoutFinancialContext {
            provider_application_fee_id: charge.application_fee,
            provider_charge_id: charge.id,
            provider_payment_reference: checkout.payment_intent.id,
            provider_total_minor: checkout.amount_total,
            tax_amount_minor: checkout.total_details.amount_tax,
        })
    }

    /// [`PaymentsProvider::get_financial_document`].
    #[instrument(skip(self, input), err)]
    async fn get_financial_document(
        &self,
        input: &GetFinancialDocumentInput,
    ) -> Result<FinancialDocument> {
        let resource = match input.kind {
            FinancialDocumentKind::Invoice => "invoices",
            FinancialDocumentKind::CreditNote => "credit_notes",
        };
        let response = self
            .client
            .get(format!(
                "{}/{}/{}",
                self.api_base_url(),
                resource,
                input.provider_document_id
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", &input.connected_seller_id)
            .header("stripe-version", STRIPE_API_VERSION)
            .send()
            .await
            .with_context(|| format!("error retrieving Stripe {resource}"))?;

        match input.kind {
            FinancialDocumentKind::Invoice => {
                let invoice = Self::parse_provider_response::<StripeInvoiceDocumentResponse>(
                    response,
                    "invoice retrieval",
                )
                .await?;
                Ok(FinancialDocument {
                    hosted_url: invoice.hosted_invoice_url,
                    pdf_url: invoice.invoice_pdf,
                })
            }
            FinancialDocumentKind::CreditNote => {
                let credit_note = Self::parse_provider_response::<StripeCreditNoteResponse>(
                    response,
                    "credit-note retrieval",
                )
                .await?;
                Ok(FinancialDocument {
                    hosted_url: None,
                    pdf_url: credit_note.pdf,
                })
            }
        }
    }

    /// [`PaymentsProvider::list_tax_rates`].
    async fn list_tax_rates(&self, input: &ListTaxRatesInput) -> Result<Vec<TicketTaxRate>> {
        let mut rates = Vec::new();
        let mut starting_after: Option<String> = None;

        loop {
            // Request one account-scoped page with provider-side behavior filtering
            let mut query = vec![
                ("active", "true".to_string()),
                (
                    "inclusive",
                    (input.tax_behavior == TicketTaxBehavior::Inclusive).to_string(),
                ),
                ("limit", "100".to_string()),
            ];
            if let Some(starting_after) = starting_after.as_ref() {
                query.push(("starting_after", starting_after.clone()));
            }
            let response = self
                .client
                .get(format!(
                    "{}/tax_rates?{}",
                    self.api_base_url(),
                    serde_urlencoded::to_string(&query)?
                ))
                .basic_auth(&self.cfg.secret_key, Some(""))
                .header("stripe-account", &input.connected_seller_id)
                .header("stripe-version", STRIPE_API_VERSION)
                .send()
                .await
                .context("error listing fiscal sponsor Stripe Tax Rates")?;
            let page = Self::parse_provider_response::<StripeTaxRateListResponse>(
                response,
                "Tax Rate listing",
            )
            .await?;

            // Preserve only active rates matching the requested display behavior
            rates.extend(
                page.data
                    .iter()
                    .filter(|rate| {
                        rate.active
                            && rate.inclusive
                                == (input.tax_behavior == TicketTaxBehavior::Inclusive)
                    })
                    .map(|rate| TicketTaxRate {
                        display_name: rate.display_name.clone(),
                        id: rate.id.clone(),
                        inclusive: rate.inclusive,
                        percentage: rate.percentage.to_string(),

                        jurisdiction: rate.jurisdiction.clone(),
                    }),
            );

            // Continue from the final provider identifier until pagination completes
            if !page.has_more {
                break;
            }
            starting_after = Some(
                page.data
                    .last()
                    .context("Stripe Tax Rate page is empty while has_more is true")?
                    .id
                    .clone(),
            );
        }

        Ok(rates)
    }

    /// [`PaymentsProvider::provider`].
    fn provider(&self) -> PaymentProvider {
        PaymentProvider::Stripe
    }

    /// [`PaymentsProvider::reconcile_application_fee_adjustment`].
    #[instrument(skip(self, input), err)]
    async fn reconcile_application_fee_adjustment(
        &self,
        input: &ApplicationFeeAdjustmentInput,
    ) -> Result<ApplicationFeeAdjustmentResult> {
        if input.amount_minor <= 0 {
            bail!("application-fee adjustment amount must be positive");
        }
        if input.connected_seller_id.trim().is_empty() {
            bail!("application-fee adjustment is missing connected seller account");
        }

        // Reconcile an existing provider side effect before risking a replacement
        let response = self
            .client
            .get(format!(
                "{}/application_fees/{}/refunds?limit=100",
                self.api_base_url(),
                input.provider_application_fee_id
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-version", STRIPE_API_VERSION)
            .send()
            .await
            .context("error listing Stripe application-fee refunds")?;
        let refunds = Self::parse_provider_response::<StripeApplicationFeeRefundList>(
            response,
            "application-fee refund listing",
        )
        .await?;
        let purchase_id = input.event_purchase_id.to_string();
        if let Some(refund) = refunds.data.into_iter().find(|refund| {
            refund.metadata.get("event_purchase_id") == Some(&purchase_id)
                && refund.metadata.get("kind") == Some(&input.kind)
        }) {
            if refund.amount != input.amount_minor {
                bail!("existing Stripe application-fee refund has the wrong amount");
            }
            return Ok(ApplicationFeeAdjustmentResult {
                provider_application_fee_refund_id: refund.id,
            });
        }

        // Create the missing partial or full application-fee refund idempotently
        let form_fields = BTreeMap::from([
            ("amount".to_string(), input.amount_minor.to_string()),
            (
                "metadata[connected_seller_id]".to_string(),
                input.connected_seller_id.clone(),
            ),
            ("metadata[event_purchase_id]".to_string(), purchase_id),
            ("metadata[kind]".to_string(), input.kind.clone()),
        ]);
        let response = self
            .client
            .post(format!(
                "{}/application_fees/{}/refunds",
                self.api_base_url(),
                input.provider_application_fee_id
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header("idempotency-key", &input.idempotency_key)
            .header("stripe-version", STRIPE_API_VERSION)
            .body(serde_urlencoded::to_string(&form_fields)?)
            .send()
            .await
            .context("error refunding Stripe application fee")?;
        let refund = Self::parse_provider_response::<StripeIdResponse>(
            response,
            "application-fee refund creation",
        )
        .await?;

        Ok(ApplicationFeeAdjustmentResult {
            provider_application_fee_refund_id: refund.id,
        })
    }

    /// [`PaymentsProvider::reconcile_credit_note`].
    #[instrument(skip(self, input), err)]
    async fn reconcile_credit_note(&self, input: &CreditNoteInput) -> Result<CreditNoteResult> {
        if input.amount_minor <= 0 || input.tax_amount_minor < 0 {
            bail!("credit-note amounts are invalid");
        }
        let api_version = self.cfg.ticket_tax_api_version.as_str();

        // Reconcile an existing issued document before risking a duplicate
        let query = serde_urlencoded::to_string([
            ("invoice", input.provider_invoice_id.as_str()),
            ("limit", "100"),
        ])?;
        let response = self
            .client
            .get(format!("{}/credit_notes?{query}", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", &input.connected_seller_id)
            .header("stripe-version", api_version)
            .send()
            .await
            .context("error listing Stripe credit notes")?;
        let credit_notes =
            Self::parse_provider_response::<StripeCreditNoteList>(response, "credit-note listing")
                .await?;
        let refund_id = input.event_purchase_refund_id.to_string();
        if let Some(credit_note) = credit_notes.data.into_iter().find(|credit_note| {
            credit_note.metadata.get("event_purchase_refund_id") == Some(&refund_id)
        }) {
            credit_note.validate_expected_amounts(input)?;
            return Ok(credit_note.into_result());
        }

        // Retrieve the one Checkout invoice line that must be credited in full
        let response = self
            .client
            .get(format!(
                "{}/invoices/{}/lines?limit=2",
                self.api_base_url(),
                input.provider_invoice_id
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", &input.connected_seller_id)
            .header("stripe-version", api_version)
            .send()
            .await
            .context("error retrieving Stripe invoice lines")?;
        let invoice_lines = Self::parse_provider_response::<StripeInvoiceLineList>(
            response,
            "invoice-line listing",
        )
        .await?;
        let [invoice_line] = invoice_lines.data.as_slice() else {
            bail!("Stripe ticket invoice must contain exactly one line item");
        };

        let form_fields = vec![
            ("invoice".to_string(), input.provider_invoice_id.clone()),
            (
                "lines[0][invoice_line_item]".to_string(),
                invoice_line.id.clone(),
            ),
            ("lines[0][quantity]".to_string(), "1".to_string()),
            (
                "lines[0][type]".to_string(),
                "invoice_line_item".to_string(),
            ),
            (
                "metadata[event_purchase_id]".to_string(),
                input.event_purchase_id.to_string(),
            ),
            ("metadata[event_purchase_refund_id]".to_string(), refund_id),
            ("reason".to_string(), "order_change".to_string()),
            (
                "refunds[0][amount_refunded]".to_string(),
                input.amount_minor.to_string(),
            ),
            (
                "refunds[0][refund]".to_string(),
                input.provider_refund_id.clone(),
            ),
        ];

        // Require Stripe's preview to confirm the complete gross and tax reversal
        let preview_query = serde_urlencoded::to_string(&form_fields)?;
        let response = self
            .client
            .get(format!(
                "{}/credit_notes/preview?{preview_query}",
                self.api_base_url()
            ))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("stripe-account", &input.connected_seller_id)
            .header("stripe-version", api_version)
            .send()
            .await
            .context("error previewing Stripe credit note")?;
        let preview = Self::parse_provider_response::<StripeCreditNoteResponse>(
            response,
            "credit-note preview",
        )
        .await?;
        preview.validate_expected_amounts(input)?;

        // Issue the previewed document while linking the existing customer refund
        let response = self
            .client
            .post(format!("{}/credit_notes", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header("idempotency-key", &input.idempotency_key)
            .header("stripe-account", &input.connected_seller_id)
            .header("stripe-version", api_version)
            .body(serde_urlencoded::to_string(&form_fields)?)
            .send()
            .await
            .context("error issuing Stripe credit note")?;
        let credit_note = Self::parse_provider_response::<StripeCreditNoteResponse>(
            response,
            "credit-note creation",
        )
        .await?;
        credit_note.validate_expected_amounts(input)?;

        Ok(credit_note.into_result())
    }

    /// [`PaymentsProvider::refund_payment`].
    #[instrument(skip(self, input), err)]
    async fn refund_payment(&self, input: &RefundPaymentInput) -> Result<RefundPaymentResult> {
        // Refuse malformed refund requests before creating an idempotent Stripe call
        if input.amount_minor <= 0 {
            bail!("cannot refund a non-positive purchase amount");
        }

        // Build the direct-charge refund request in the connected account
        let form_fields = Self::build_refund_form_fields(input);

        // Create the refund against the original payment intent
        let mut request = self
            .client
            .post(format!("{}/refunds", self.api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header("idempotency-key", &input.idempotency_key)
            .header("stripe-version", STRIPE_API_VERSION)
            .body(serde_urlencoded::to_string(&form_fields)?);
        request = request.header("stripe-account", &input.connected_seller_id);
        let response = request.send().await.context("error creating Stripe refund")?;

        // Preserve Stripe's error body to simplify refund diagnostics
        if !response.status().is_success() {
            let status = response.status();
            let body = response
                .text()
                .await
                .unwrap_or_else(|_| "unable to read Stripe error response".to_string());
            bail!("Stripe refund failed ({status}): {body}");
        }

        // Deserialize the provider refund identifier returned by Stripe
        let response: StripeRefundResponse = response
            .json()
            .await
            .context("error parsing Stripe refund response")?;

        Self::refund_result(response.id, &response.status)
    }

    /// [`PaymentsProvider::validate_fiscal_sponsor`].
    async fn validate_fiscal_sponsor(
        &self,
        input: &FiscalSponsorReadinessInput,
    ) -> std::result::Result<(), FiscalSponsorReadinessError> {
        if input.provider != PaymentProvider::Stripe {
            return Err(FiscalSponsorReadinessError::NotReady(
                "fiscal sponsor is not configured for Stripe".to_string(),
            ));
        }

        self.validate_connected_seller(input).await
    }

    /// [`PaymentsProvider::validate_tax_rates`].
    async fn validate_tax_rates(
        &self,
        input: &ValidateTaxRatesInput,
    ) -> std::result::Result<(), FiscalSponsorReadinessError> {
        // Reject empty or duplicate selections before contacting Stripe
        let selected_ids = input
            .manual_tax_rate_ids
            .iter()
            .map(String::as_str)
            .collect::<BTreeSet<_>>();
        if selected_ids.is_empty()
            || selected_ids.len() != input.manual_tax_rate_ids.len()
            || selected_ids.iter().any(|id| id.is_empty() || *id != id.trim())
        {
            return Err(FiscalSponsorReadinessError::NotReady(
                "manual ticket tax requires at least one unique Stripe Tax Rate".to_string(),
            ));
        }

        // Load active compatible rates from the selected connected account
        let available_ids = self
            .list_tax_rates(&ListTaxRatesInput {
                connected_seller_id: input.connected_seller_id.clone(),
                tax_behavior: input.tax_behavior,
            })
            .await
            .map_err(FiscalSponsorReadinessError::Unexpected)?
            .into_iter()
            .map(|rate| rate.id)
            .collect::<BTreeSet<_>>();

        // Require every selected identifier to remain available in that account
        if !selected_ids
            .iter()
            .all(|selected_id| available_ids.contains(*selected_id))
        {
            return Err(FiscalSponsorReadinessError::NotReady(
                "manual Stripe Tax Rates must be active in the fiscal sponsor account and match the ticket tax display"
                    .to_string(),
            ));
        }

        Ok(())
    }

    /// [`PaymentsProvider::verify_and_parse_webhook`].
    fn verify_and_parse_webhook(
        &self,
        endpoint: PaymentsWebhookEndpoint,
        headers: &HeaderMap,
        body: &str,
    ) -> Result<PaymentsWebhookEvent> {
        // Require Stripe's signature header before attempting webhook verification
        let Some(signature_header) =
            headers.get("stripe-signature").and_then(|value| value.to_str().ok())
        else {
            bail!("missing Stripe webhook signature header");
        };

        // Verify the webhook signature before trusting the payload contents
        let (timestamp, provided_signatures) = Self::parse_signature_header(signature_header)?;
        Self::validate_webhook_timestamp(&timestamp)?;
        let signed_payload = format!("{timestamp}.{body}");
        let webhook_secret = match endpoint {
            PaymentsWebhookEndpoint::ConnectedAccount => &self.cfg.connected_webhook_secret,
            PaymentsWebhookEndpoint::PlatformAccount => &self.cfg.webhook_secret,
        };
        let expected_signature = Self::compute_signature(webhook_secret, &signed_payload);

        let has_matching_signature = provided_signatures.iter().any(|provided_signature| {
            bool::from(provided_signature.as_bytes().ct_eq(expected_signature.as_bytes()))
        });

        if !has_matching_signature {
            bail!("invalid Stripe webhook signature");
        }

        // Parse the verified Stripe payload into the webhook envelope
        let event: StripeWebhookEvent =
            serde_json::from_str(body).context("error parsing Stripe webhook payload")?;

        // Enforce endpoint account scope and configured live/test mode
        match (endpoint, event.account.as_deref()) {
            (PaymentsWebhookEndpoint::ConnectedAccount, None) => {
                bail!("Stripe Connect webhook is missing connected account")
            }
            (PaymentsWebhookEndpoint::PlatformAccount, Some(_)) => {
                bail!("Stripe platform webhook contains a connected account")
            }
            _ => {}
        }
        if event.livemode != (self.cfg.mode == PaymentMode::Live) {
            bail!("Stripe webhook mode does not match payments configuration");
        }

        Self::parse_webhook_event(event, endpoint)
    }
}

/// Connected account responsibility fields required for direct charges.
#[derive(Debug, Deserialize)]
struct StripeAccountController {
    /// Entity controlling the account relationship.
    #[serde(rename = "type")]
    controller_type: String,

    /// Fee responsibility for direct charges, when visible to the platform.
    fees: Option<StripeAccountFees>,
    /// Negative-balance responsibility for payments, when visible to the platform.
    losses: Option<StripeAccountLosses>,
    /// Entity collecting account requirements, when visible to the platform.
    requirement_collection: Option<String>,
    /// Connected account Dashboard access, when visible to the platform.
    stripe_dashboard: Option<StripeAccountDashboard>,
}

/// Connected account Stripe Dashboard configuration.
#[derive(Debug, Deserialize)]
struct StripeAccountDashboard {
    /// Stripe Dashboard available to the connected account.
    #[serde(rename = "type")]
    dashboard_type: String,
}

/// Connected account fee-payer configuration.
#[derive(Debug, Deserialize)]
struct StripeAccountFees {
    /// Entity that pays Stripe fees.
    payer: String,
}

/// Connected account payment-loss configuration.
#[derive(Debug, Deserialize)]
struct StripeAccountLosses {
    /// Entity responsible when the account cannot cover a negative balance.
    payments: String,
}

/// Minimal connected account response used for seller readiness.
#[derive(Debug, Deserialize)]
struct StripeAccountResponse {
    /// Whether the account can accept charges.
    charges_enabled: bool,
    /// Whether the account has completed onboarding details.
    details_submitted: bool,
    /// Connected account identifier.
    id: String,

    /// Controller settings visible to the requesting platform.
    controller: Option<StripeAccountController>,
}

/// Provider application-fee refund used for lookup-before-create reconciliation.
#[derive(Debug, Deserialize)]
struct StripeApplicationFeeRefund {
    /// Refunded application-fee amount.
    amount: i64,
    /// Provider application-fee refund identifier.
    id: String,
    /// Metadata identifying the durable adjustment.
    #[serde(default)]
    metadata: BTreeMap<String, String>,
}

/// Provider application-fee refund list response.
#[derive(Debug, Deserialize)]
struct StripeApplicationFeeRefundList {
    /// Application-fee refunds returned by Stripe.
    data: Vec<StripeApplicationFeeRefund>,
}

/// Minimal response payload returned by Stripe checkout session creation.
#[derive(Debug, Deserialize)]
struct StripeCheckoutSessionResponse {
    /// Stripe checkout session identifier.
    id: String,
    /// Hosted checkout URL.
    url: String,
}

/// Checkout total breakdown needed for authoritative tax amounts.
#[derive(Debug, Deserialize)]
struct StripeCheckoutTotalDetails {
    /// Total tax included in or added to the ticket amount.
    amount_tax: i64,
}

/// Provider credit-note list response.
#[derive(Debug, Deserialize)]
struct StripeCreditNoteList {
    /// Credit notes returned by Stripe.
    data: Vec<StripeCreditNoteResponse>,
}

/// Provider credit-note fields needed for reconciliation and document access.
#[derive(Debug, Deserialize)]
struct StripeCreditNoteResponse {
    /// Gross amount credited.
    amount: i64,
    /// Provider credit-note identifier.
    id: String,

    /// Metadata identifying the durable credit-note job.
    #[serde(default)]
    metadata: BTreeMap<String, String>,
    /// Current credit-note PDF URL.
    pdf: Option<String>,
    /// Provider-calculated tax credits.
    #[serde(default)]
    total_taxes: Vec<StripeCreditNoteTaxAmount>,
}

impl StripeCreditNoteResponse {
    /// Converts provider fields into the shared issued-document result.
    fn into_result(self) -> CreditNoteResult {
        CreditNoteResult {
            provider_credit_note_id: self.id,

            provider_hosted_url: None,
            provider_pdf_url: self.pdf,
        }
    }

    /// Requires Stripe's preview or issued note to match the full refund snapshot.
    fn validate_expected_amounts(&self, input: &CreditNoteInput) -> Result<()> {
        let tax_amount_minor = self.total_taxes.iter().map(|tax| tax.amount).sum::<i64>();
        if self.amount != input.amount_minor || tax_amount_minor != input.tax_amount_minor {
            bail!("Stripe credit-note preview does not match the full purchase refund");
        }

        Ok(())
    }
}

/// Tax amount included in a provider credit note.
#[derive(Debug, Deserialize)]
struct StripeCreditNoteTaxAmount {
    /// Credited tax amount, in minor units.
    amount: i64,
}

/// Expanded Charge fields required for fee reconciliation.
#[derive(Debug, Deserialize)]
struct StripeExpandedCharge {
    /// Charge identifier.
    id: String,

    /// Application fee created for the direct charge.
    application_fee: Option<String>,
}

/// Account-scoped completed Checkout Session with authoritative amounts.
#[derive(Debug, Deserialize)]
struct StripeExpandedCheckoutSessionResponse {
    /// Total amount collected from the attendee.
    amount_total: i64,
    /// Expanded `PaymentIntent` and Charge.
    payment_intent: StripeExpandedPaymentIntent,
    /// Authoritative total breakdown.
    total_details: StripeCheckoutTotalDetails,
}

/// Expanded `PaymentIntent` fields returned with a Checkout Session.
#[derive(Debug, Deserialize)]
struct StripeExpandedPaymentIntent {
    /// `PaymentIntent` identifier.
    id: String,

    /// Charge created for the completed payment.
    latest_charge: Option<StripeExpandedCharge>,
}

/// Minimal response returned by Stripe create endpoints.
#[derive(Debug, Deserialize)]
struct StripeIdResponse {
    /// Provider object identifier.
    id: String,
}

/// Current provider URLs returned when retrieving an invoice.
#[derive(Debug, Deserialize)]
struct StripeInvoiceDocumentResponse {
    /// Current Stripe-hosted invoice URL.
    hosted_invoice_url: Option<String>,
    /// Current Stripe invoice PDF URL.
    invoice_pdf: Option<String>,
}

/// Provider invoice-line list response.
#[derive(Debug, Deserialize)]
struct StripeInvoiceLineList {
    /// Invoice lines returned by Stripe.
    data: Vec<StripeInvoiceLineResponse>,
}

/// Minimal provider invoice line used to create a full line-item credit.
#[derive(Debug, Deserialize)]
struct StripeInvoiceLineResponse {
    /// Provider invoice-line identifier.
    id: String,
}

/// Minimal refund payload used to reconcile existing Stripe refunds.
#[derive(Debug, Deserialize)]
struct StripeListedRefund {
    /// Refund amount in minor units.
    amount: i64,
    /// Stripe refund identifier.
    id: String,
    /// Stripe refund lifecycle status.
    status: String,

    /// Metadata attached when the refund was created.
    #[serde(default)]
    metadata: BTreeMap<String, String>,
}

/// Minimal response payload returned by Stripe refund listing.
#[derive(Debug, Deserialize)]
struct StripeRefundListResponse {
    /// Stripe refunds returned by the list operation.
    data: Vec<StripeListedRefund>,
}

/// Minimal response payload returned by Stripe refund creation.
#[derive(Debug, Deserialize)]
struct StripeRefundResponse {
    /// Stripe refund identifier.
    id: String,
    /// Stripe refund lifecycle status.
    status: String,
}

/// Minimal Product fields revalidated before automatic-tax Checkout.
#[derive(Debug, Deserialize)]
struct StripeTaxProductResponse {
    /// Whether Stripe currently allows the Product to be used.
    active: bool,
    /// Product name snapshotted from the ticket title.
    name: String,

    /// Stripe Tax inputs attached to the Product.
    tax_details: Option<StripeTaxProductTaxDetailsResponse>,
}

/// Stripe Tax fields attached to an automatic-tax Product.
#[derive(Debug, Deserialize)]
struct StripeTaxProductTaxDetailsResponse {
    /// Connected-account performance-location identifier.
    performance_location: Option<String>,
    /// Stripe tax code selected for the ticket.
    tax_code: Option<String>,
}

/// Paginated Stripe Tax Rate listing response.
#[derive(Debug, Deserialize)]
struct StripeTaxRateListResponse {
    /// Active Tax Rates in this page.
    data: Vec<StripeTaxRateResponse>,
    /// Whether another page is available.
    has_more: bool,
}

/// Minimal Tax Rate fields revalidated before manual-tax Checkout.
#[derive(Debug, Deserialize)]
struct StripeTaxRateResponse {
    /// Whether Stripe currently allows the Tax Rate to be used.
    active: bool,
    /// Customer-facing Tax Rate label.
    display_name: String,
    /// Connected-account Tax Rate identifier.
    id: String,
    /// Whether the rate is included in the configured line-item amount.
    inclusive: bool,
    /// Decimal Tax Rate percentage.
    percentage: serde_json::Number,

    /// Jurisdiction configured on the Tax Rate.
    jurisdiction: Option<String>,
}

/// Minimal Stripe Tax settings response used for automatic-tax readiness.
#[derive(Debug, Deserialize)]
struct StripeTaxSettingsResponse {
    /// Whether the account's Tax settings are ready for calculations.
    status: String,
}

/// Nested webhook event data containing the Stripe object payload.
#[derive(Debug, Deserialize)]
struct StripeWebhookData {
    /// Event object supplied by Stripe when present.
    object: Option<StripeWebhookObject>,
}

/// Stripe webhook event envelope received from the webhook endpoint.
#[derive(Debug, Deserialize)]
struct StripeWebhookEvent {
    /// Data envelope containing the Stripe object.
    data: StripeWebhookData,
    /// Stripe event type.
    #[serde(rename = "type")]
    event_type: String,
    /// Whether the event belongs to live mode.
    livemode: bool,

    /// Connected account that owns the event object.
    account: Option<String>,
}

/// Stripe webhook object used by the supported checkout and refund events.
#[derive(Debug, Deserialize)]
struct StripeWebhookObject {
    /// Stripe object identifier.
    id: String,

    /// Connected account associated with a platform application fee.
    account: Option<String>,
    /// Refund or application-fee amount in minor units.
    amount: Option<i64>,
    /// Direct charge associated with a platform application fee.
    charge: Option<String>,
    /// Refund currency code.
    currency: Option<String>,
    /// Hosted invoice URL when the object is an invoice.
    hosted_invoice_url: Option<String>,
    /// Invoice PDF URL when the object is an invoice.
    invoice_pdf: Option<String>,
    /// Metadata attached to the Stripe object.
    #[serde(default)]
    metadata: BTreeMap<String, String>,
    /// Payment intent associated with a checkout session or refund.
    payment_intent: Option<String>,
    /// Refund lifecycle status when the object is a refund.
    status: Option<String>,
}
