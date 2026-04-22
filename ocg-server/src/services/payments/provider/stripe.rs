//! Stripe-backed payments provider implementation.

use std::collections::BTreeMap;

use anyhow::{Context, Result, bail};
use async_trait::async_trait;
use axum::http::HeaderMap;
use chrono::Utc;
use hmac::{Hmac, Mac};
use reqwest::Client;
use serde::Deserialize;
use sha2::Sha256;
use subtle::ConstantTimeEq;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::PaymentsStripeConfig,
    types::payments::{PaymentMode, PaymentProvider},
};

use super::{
    CheckoutSession, CreateCheckoutSessionInput, PaymentsProvider, PaymentsWebhookEvent, RefundPaymentInput,
    RefundPaymentResult,
};

#[cfg(test)]
mod tests;

/// Stripe Checkout payment methods currently allowed by OCG.
const STRIPE_CHECKOUT_PAYMENT_METHOD_TYPES: [&str; 1] = ["card"];

/// Maximum accepted age for Stripe webhook signatures.
const STRIPE_WEBHOOK_TOLERANCE_SECS: i64 = 300;

/// Stripe-backed payments provider implementation.
pub(crate) struct StripeProvider {
    client: Client,
    cfg: PaymentsStripeConfig,
}

impl StripeProvider {
    /// Creates a new Stripe provider.
    pub(crate) fn new(cfg: PaymentsStripeConfig) -> Self {
        Self {
            client: Client::new(),
            cfg,
        }
    }

    /// Returns the Stripe API base URL.
    fn api_base_url() -> &'static str {
        "https://api.stripe.com/v1"
    }

    /// Builds the Stripe Checkout form body for a purchase.
    fn build_checkout_session_form_fields(
        &self,
        input: &CreateCheckoutSessionInput,
    ) -> Vec<(String, String)> {
        let mut form_fields: Vec<(String, String)> = vec![
            (
                "cancel_url".to_string(),
                Self::event_return_url(input, "canceled"),
            ),
            ("client_reference_id".to_string(), input.purchase_id.to_string()),
            (
                "line_items[0][price_data][currency]".to_string(),
                Self::normalized_currency_code(&input.currency_code),
            ),
            (
                "line_items[0][price_data][product_data][name]".to_string(),
                input.ticket_title.clone(),
            ),
            (
                "line_items[0][price_data][unit_amount]".to_string(),
                input.amount_minor.to_string(),
            ),
            ("line_items[0][quantity]".to_string(), "1".to_string()),
            ("mode".to_string(), "payment".to_string()),
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
            (
                "payment_intent_data[transfer_data][destination]".to_string(),
                input.recipient.recipient_id.clone(),
            ),
            (
                "success_url".to_string(),
                Self::event_return_url(input, "success"),
            ),
        ];

        // Add the payment methods currently supported by OCG
        for (index, payment_method_type) in STRIPE_CHECKOUT_PAYMENT_METHOD_TYPES.iter().enumerate() {
            form_fields.push((
                format!("payment_method_types[{index}]"),
                (*payment_method_type).to_string(),
            ));
        }

        // Forward the applied discount code into Stripe metadata when present
        if let Some(discount_code) = &input.discount_code {
            form_fields.push((
                "payment_intent_data[metadata][discount_code]".to_string(),
                discount_code.clone(),
            ));
        }

        // Mark test-mode checkouts so webhook consumers can identify them
        if self.cfg.mode == PaymentMode::Test {
            form_fields.push(("metadata[environment]".to_string(), "test".to_string()));
        }

        form_fields
    }

    /// Builds a deterministic idempotency key for Stripe checkout sessions.
    fn checkout_idempotency_key(purchase_id: Uuid) -> String {
        format!("event-purchase-checkout-{purchase_id}")
    }

    /// Builds the signature digest used by Stripe.
    fn compute_signature(secret: &str, payload: &str) -> String {
        type HmacSha256 = Hmac<Sha256>;

        let mut mac =
            HmacSha256::new_from_slice(secret.as_bytes()).expect("HMAC accepts arbitrary key sizes");
        mac.update(payload.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }

    /// Formats a checkout return URL.
    fn event_return_url(input: &CreateCheckoutSessionInput, outcome: &str) -> String {
        let base_url = input.base_url.trim_end_matches('/');
        format!(
            "{base_url}/{}/group/{}/event/{}?payment={outcome}",
            input.community_name, input.group_slug, input.event_slug
        )
    }

    /// Normalizes a currency code for Stripe requests.
    fn normalized_currency_code(currency_code: &str) -> String {
        currency_code.trim().to_ascii_lowercase()
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

    /// Builds a deterministic idempotency key for Stripe refunds.
    fn refund_idempotency_key(purchase_id: Uuid) -> String {
        format!("event-purchase-refund-{purchase_id}")
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
}

#[async_trait]
impl PaymentsProvider for StripeProvider {
    /// [`PaymentsProvider::create_checkout_session`].
    #[instrument(skip(self, input), err)]
    async fn create_checkout_session(&self, input: &CreateCheckoutSessionInput) -> Result<CheckoutSession> {
        // Reject invalid or unsupported checkout requests before contacting Stripe
        if input.amount_minor <= 0 {
            bail!("Stripe checkout requires a positive amount");
        }

        if input.recipient.provider != PaymentProvider::Stripe {
            bail!("group recipient is not configured for Stripe");
        }

        let form_fields = self.build_checkout_session_form_fields(input);

        // Create the hosted Stripe Checkout session
        let response = self
            .client
            .post(format!("{}/checkout/sessions", Self::api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header(
                "idempotency-key",
                Self::checkout_idempotency_key(input.purchase_id),
            )
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
            provider_session_id: response.id,
            redirect_url: response.url,
        })
    }

    /// [`PaymentsProvider::provider`].
    fn provider(&self) -> PaymentProvider {
        PaymentProvider::Stripe
    }

    /// [`PaymentsProvider::refund_payment`].
    #[instrument(skip(self, input), err)]
    async fn refund_payment(&self, input: &RefundPaymentInput) -> Result<RefundPaymentResult> {
        // Refuse malformed refund requests before creating an idempotent Stripe call
        if input.amount_minor <= 0 {
            bail!("cannot refund a non-positive purchase amount");
        }

        // Send the purchase metadata Stripe needs to process and deduplicate refunds
        let mut form_fields = BTreeMap::from([
            (
                "payment_intent".to_string(),
                input.provider_payment_reference.clone(),
            ),
            (
                "metadata[event_purchase_id]".to_string(),
                input.purchase_id.to_string(),
            ),
        ]);

        form_fields.insert("amount".to_string(), input.amount_minor.to_string());

        // Create the refund against the original payment intent
        let response = self
            .client
            .post(format!("{}/refunds", Self::api_base_url()))
            .basic_auth(&self.cfg.secret_key, Some(""))
            .header("content-type", "application/x-www-form-urlencoded")
            .header("idempotency-key", Self::refund_idempotency_key(input.purchase_id))
            .body(serde_urlencoded::to_string(&form_fields)?)
            .send()
            .await
            .context("error creating Stripe refund")?;

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

        Ok(RefundPaymentResult {
            provider_refund_id: response.id,
        })
    }

    /// [`PaymentsProvider::verify_and_parse_webhook`].
    fn verify_and_parse_webhook(&self, headers: &HeaderMap, body: &str) -> Result<PaymentsWebhookEvent> {
        // Require Stripe's signature header before attempting webhook verification
        let Some(signature_header) = headers.get("stripe-signature").and_then(|value| value.to_str().ok())
        else {
            bail!("missing Stripe webhook signature header");
        };

        // Verify the webhook signature before trusting the payload contents
        let (timestamp, provided_signatures) = Self::parse_signature_header(signature_header)?;
        Self::validate_webhook_timestamp(&timestamp)?;
        let signed_payload = format!("{timestamp}.{body}");
        let expected_signature = Self::compute_signature(&self.cfg.webhook_secret, &signed_payload);

        let has_matching_signature = provided_signatures.iter().any(|provided_signature| {
            bool::from(provided_signature.as_bytes().ct_eq(expected_signature.as_bytes()))
        });

        if !has_matching_signature {
            bail!("invalid Stripe webhook signature");
        }

        // Parse the verified Stripe payload into the webhook envelope
        let event: StripeWebhookEvent =
            serde_json::from_str(body).context("error parsing Stripe webhook payload")?;

        // Normalize the supported Stripe events into OCG's internal webhook model
        match event.event_type.as_str() {
            "checkout.session.completed" => {
                let Some(object) = event.data.object else {
                    bail!("Stripe webhook payload is missing object data");
                };

                Ok(PaymentsWebhookEvent::CheckoutCompleted {
                    provider_payment_reference: object.payment_intent,
                    provider_session_id: object.id,
                })
            }
            "checkout.session.expired" => {
                let Some(object) = event.data.object else {
                    bail!("Stripe webhook payload is missing object data");
                };

                Ok(PaymentsWebhookEvent::CheckoutExpired {
                    provider_session_id: object.id,
                })
            }
            unsupported => bail!("unsupported Stripe webhook event: {unsupported}"),
        }
    }
}

/// Minimal response payload returned by Stripe checkout session creation.
#[derive(Debug, Deserialize)]
struct StripeCheckoutSessionResponse {
    id: String,
    url: String,
}

/// Minimal response payload returned by Stripe refund creation.
#[derive(Debug, Deserialize)]
struct StripeRefundResponse {
    id: String,
}

/// Nested webhook event data containing the Stripe object payload.
#[derive(Debug, Deserialize)]
struct StripeWebhookData {
    object: Option<StripeWebhookObject>,
}

/// Stripe webhook event envelope received from the webhook endpoint.
#[derive(Debug, Deserialize)]
struct StripeWebhookEvent {
    #[serde(rename = "type")]
    event_type: String,
    data: StripeWebhookData,
}

/// Stripe webhook object used by the supported checkout session events.
#[derive(Debug, Deserialize)]
struct StripeWebhookObject {
    id: String,
    payment_intent: Option<String>,
}
