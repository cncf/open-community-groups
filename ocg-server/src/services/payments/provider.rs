//! Payments provider abstraction.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use axum::http::HeaderMap;
#[cfg(test)]
use mockall::automock;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    config::PaymentsConfig,
    types::payments::{GroupPaymentRecipient, PaymentProvider},
};

pub(super) mod stripe;

use self::stripe::StripeProvider;

/// Trait implemented by payments providers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait PaymentsProvider {
    /// Creates a checkout session for a paid event purchase.
    async fn create_checkout_session(&self, input: &CreateCheckoutSessionInput) -> Result<CheckoutSession>;

    /// Returns the configured provider.
    fn provider(&self) -> PaymentProvider;

    /// Refunds a completed payment.
    async fn refund_payment(&self, input: &RefundPaymentInput) -> Result<RefundPaymentResult>;

    /// Verifies and parses a webhook payload.
    fn verify_and_parse_webhook(&self, headers: &HeaderMap, body: &str) -> Result<PaymentsWebhookEvent>;
}

/// Shared payments provider trait object.
pub(crate) type DynPaymentsProvider = Arc<dyn PaymentsProvider + Send + Sync>;

/// Result returned after creating a checkout session.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct CheckoutSession {
    /// Provider-specific checkout session identifier.
    pub provider_session_id: String,
    /// Redirect URL for the attendee.
    pub redirect_url: String,
}

/// Parameters used to create a checkout session.
#[derive(Clone, Debug)]
pub(crate) struct CreateCheckoutSessionInput {
    /// Total amount in minor units.
    pub amount_minor: i64,
    /// Base URL of the application.
    pub base_url: String,
    /// Community slug used in return URLs.
    pub community_name: String,
    /// Currency code for the payment.
    pub currency_code: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event slug used in return URLs.
    pub event_slug: String,
    /// Group slug used in return URLs.
    pub group_slug: String,
    /// Purchase identifier tracked by OCG.
    pub purchase_id: Uuid,
    /// Recipient account for the group.
    pub recipient: GroupPaymentRecipient,
    /// Ticket title shown in the provider checkout.
    pub ticket_title: String,
    /// User identifier for the attendee.
    pub user_id: Uuid,

    /// Discount code applied to the purchase.
    pub discount_code: Option<String>,
}

/// Supported webhook events normalized across providers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) enum PaymentsWebhookEvent {
    /// A checkout session completed successfully.
    CheckoutCompleted {
        provider_payment_reference: Option<String>,
        provider_session_id: String,
    },
    /// A checkout session expired before payment.
    CheckoutExpired { provider_session_id: String },
}

/// Request used to refund a completed payment.
#[derive(Clone, Debug)]
pub(crate) struct RefundPaymentInput {
    /// Completed purchase amount in minor units.
    pub amount_minor: i64,
    /// Provider payment reference used for refunds.
    pub provider_payment_reference: String,
    /// Platform purchase identifier.
    pub purchase_id: Uuid,
}

/// Result returned after a provider refund succeeds.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct RefundPaymentResult {
    /// Provider-specific refund identifier.
    pub provider_refund_id: String,
}

/// Builds a payments provider from configuration.
pub(crate) fn build_payments_provider(cfg: Option<&PaymentsConfig>) -> Option<DynPaymentsProvider> {
    match cfg {
        Some(PaymentsConfig::Stripe(stripe_cfg)) => Some(Arc::new(StripeProvider::new(stripe_cfg.clone()))),
        None => None,
    }
}
