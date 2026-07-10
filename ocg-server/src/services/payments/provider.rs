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
    async fn create_checkout_session(
        &self,
        input: &CreateCheckoutSessionInput,
    ) -> Result<CheckoutSession>;

    /// Finds an existing provider refund for a purchase when retrying.
    async fn find_refund(&self, input: &FindRefundInput) -> Result<Option<RefundPaymentResult>>;

    /// Returns the configured provider.
    fn provider(&self) -> PaymentProvider;

    /// Refunds a completed payment.
    async fn refund_payment(&self, input: &RefundPaymentInput) -> Result<RefundPaymentResult>;

    /// Verifies and parses a webhook payload.
    fn verify_and_parse_webhook(
        &self,
        headers: &HeaderMap,
        body: &str,
    ) -> Result<PaymentsWebhookEvent>;
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
    /// Generated group slug used in return URLs.
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
    /// Admin-managed group slug used in return URLs.
    pub group_slug_pretty: Option<String>,
}

impl CreateCheckoutSessionInput {
    /// Returns the group slug to use in public URLs.
    pub fn public_group_slug(&self) -> &str {
        self.group_slug_pretty.as_deref().unwrap_or(&self.group_slug)
    }
}

/// Request used to find an existing provider refund.
#[derive(Clone, Debug)]
pub(crate) struct FindRefundInput {
    /// Completed purchase amount in minor units.
    pub amount_minor: i64,
    /// Provider payment reference used for refunds.
    pub provider_payment_reference: String,
    /// Platform purchase identifier.
    pub purchase_id: Uuid,

    /// Provider refund identifier to poll when a refund was already created.
    pub provider_refund_id: Option<String>,
}

/// Supported webhook events normalized across providers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) enum PaymentsWebhookEvent {
    /// A checkout session completed successfully.
    CheckoutCompleted {
        /// Provider-specific checkout session identifier.
        provider_session_id: String,

        /// Provider payment reference used for refunds.
        provider_payment_reference: Option<String>,
    },
    /// A checkout session expired before payment.
    CheckoutExpired {
        /// Provider-specific checkout session identifier.
        provider_session_id: String,
    },
    /// A verified provider event that does not belong to OCG.
    Noop,
    /// A provider refund lifecycle state changed.
    RefundUpdated {
        /// Platform purchase identifier from provider metadata.
        purchase_id: Uuid,
        /// Provider-specific refund identifier.
        provider_refund_id: String,
        /// Current provider refund lifecycle status.
        status: RefundPaymentStatus,
    },
}

/// Request used to refund a completed payment.
#[derive(Clone, Debug)]
pub(crate) struct RefundPaymentInput {
    /// Completed purchase amount in minor units.
    pub amount_minor: i64,
    /// Provider idempotency key used to deduplicate refund creation.
    pub idempotency_key: String,
    /// Provider payment reference used for refunds.
    pub provider_payment_reference: String,
    /// Platform purchase identifier.
    pub purchase_id: Uuid,
}

/// Result returned after a provider refund request or lookup.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct RefundPaymentResult {
    /// Provider-specific refund identifier.
    pub provider_refund_id: String,
    /// Current provider refund lifecycle status.
    pub status: RefundPaymentStatus,
}

/// Provider refund lifecycle status.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum RefundPaymentStatus {
    /// Provider refund did not complete.
    Failed,
    /// Provider refund was created and is not final yet.
    Pending,
    /// Provider refund completed successfully.
    Succeeded,
}

/// Builds a payments provider from configuration.
pub(crate) fn build_payments_provider(cfg: Option<&PaymentsConfig>) -> Option<DynPaymentsProvider> {
    match cfg {
        Some(PaymentsConfig::Stripe(stripe_cfg)) => {
            Some(Arc::new(StripeProvider::new(stripe_cfg.clone())))
        }
        None => None,
    }
}
