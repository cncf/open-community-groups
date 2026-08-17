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
    types::payments::{
        FiscalSponsorSeller, PaymentProvider, TicketTaxBehavior, TicketTaxCalculationMode,
        TicketTaxRate, TicketVenue,
    },
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

    /// Creates or reuses an account-scoped automatic-tax performance location.
    async fn ensure_performance_location(
        &self,
        input: &PerformanceLocationInput,
    ) -> std::result::Result<AutomaticTaxReadiness, AutomaticTaxReadinessError>;

    /// Finds an existing provider refund for a purchase when retrying.
    async fn find_refund(&self, input: &FindRefundInput) -> Result<Option<RefundPaymentResult>>;

    /// Retrieves authoritative financial fields for a completed Checkout Session.
    async fn get_checkout_financial_context(
        &self,
        input: &GetCheckoutFinancialContextInput,
    ) -> Result<CheckoutFinancialContext>;

    /// Retrieves the current account-scoped URL for an issued financial document.
    async fn get_financial_document(
        &self,
        input: &GetFinancialDocumentInput,
    ) -> Result<FinancialDocument>;

    /// Lists active Tax Rates in a connected fiscal sponsor account.
    async fn list_tax_rates(&self, input: &ListTaxRatesInput) -> Result<Vec<TicketTaxRate>>;

    /// Returns the configured provider.
    fn provider(&self) -> PaymentProvider;

    /// Finds or creates an idempotent application-fee refund.
    async fn reconcile_application_fee_adjustment(
        &self,
        input: &ApplicationFeeAdjustmentInput,
    ) -> Result<ApplicationFeeAdjustmentResult>;

    /// Finds or creates an idempotent credit note linked to an existing refund.
    async fn reconcile_credit_note(&self, input: &CreditNoteInput) -> Result<CreditNoteResult>;

    /// Refunds a completed payment.
    async fn refund_payment(&self, input: &RefundPaymentInput) -> Result<RefundPaymentResult>;

    /// Validates a fiscal sponsor before paid ticket configuration is persisted.
    async fn validate_fiscal_sponsor(
        &self,
        input: &FiscalSponsorReadinessInput,
    ) -> std::result::Result<(), FiscalSponsorReadinessError>;

    /// Validates selected active Tax Rates in a connected fiscal sponsor account.
    async fn validate_tax_rates(
        &self,
        input: &ValidateTaxRatesInput,
    ) -> std::result::Result<(), FiscalSponsorReadinessError>;

    /// Verifies and parses a webhook payload.
    fn verify_and_parse_webhook(
        &self,
        endpoint: PaymentsWebhookEndpoint,
        headers: &HeaderMap,
        body: &str,
    ) -> Result<PaymentsWebhookEvent>;
}

/// Shared payments provider trait object.
pub(crate) type DynPaymentsProvider = Arc<dyn PaymentsProvider + Send + Sync>;

/// Successful automatic-tax performance-location readiness result.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct AutomaticTaxReadiness {
    /// Whether an existing matching performance location was reused.
    pub cached: bool,
    /// Fingerprint of the normalized venue sent to the provider.
    pub fingerprint: String,
    /// Provider performance-location identifier.
    pub provider_tax_location_id: String,

    /// ISO subdivision code sent to the provider, when available.
    pub state_code: Option<String>,
}

/// Organizer-facing automatic-tax readiness failure.
#[derive(Debug, thiserror::Error)]
pub(crate) enum AutomaticTaxReadinessError {
    /// Provider rejected the submitted country code.
    #[error("the venue country code {country_code} is invalid")]
    CountryInvalid {
        /// Rejected ISO country code.
        country_code: String,
    },
    /// Fiscal sponsor configuration that an organizer can correct.
    #[error("{0}")]
    FiscalSponsorNotReady(String),
    /// Required physical venue fields are incomplete.
    #[error("the venue address is incomplete")]
    IncompleteVenue {
        /// Form fields that need organizer attention.
        fields: Vec<String>,
    },
    /// Provider rejected the submitted address for a non-state reason.
    #[error("the venue address is invalid")]
    InvalidAddress,
    /// Provider rejected the submitted subdivision code.
    #[error("the state code {state_code} is invalid for {country_code}")]
    StateCodeInvalid {
        /// ISO country code paired with the rejected subdivision.
        country_code: String,
        /// Rejected ISO subdivision suffix.
        state_code: String,
    },
    /// Provider requires a subdivision code for the submitted country.
    #[error("a state code is required for {country_code}")]
    StateCodeRequired {
        /// ISO country code requiring a subdivision.
        country_code: String,
    },
    /// Provider does not support automatic tax at the submitted location.
    #[error(
        "Stripe automatic tax is not supported for this venue country. Select Manual Stripe Tax Rates instead."
    )]
    UnsupportedCountry,
    /// Infrastructure or provider failure that an organizer cannot correct.
    #[error(transparent)]
    Unexpected(#[from] anyhow::Error),
}

impl AutomaticTaxReadinessError {
    /// Returns the stable organizer-facing error code.
    pub(crate) const fn code(&self) -> &'static str {
        match self {
            Self::CountryInvalid { .. } => "country_invalid",
            Self::FiscalSponsorNotReady(_) => "fiscal_sponsor_not_ready",
            Self::IncompleteVenue { .. } => "incomplete_venue",
            Self::InvalidAddress => "invalid_address",
            Self::StateCodeInvalid { .. } => "state_code_invalid",
            Self::StateCodeRequired { .. } => "state_code_required",
            Self::UnsupportedCountry => "unsupported_country",
            Self::Unexpected(_) => "provider_unavailable",
        }
    }

    /// Returns form field names associated with the failure.
    pub(crate) fn fields(&self) -> Vec<String> {
        match self {
            Self::CountryInvalid { .. } | Self::UnsupportedCountry => {
                vec!["venue_country_code".to_string()]
            }
            Self::IncompleteVenue { fields } => fields.clone(),
            Self::InvalidAddress => vec![
                "venue_address".to_string(),
                "venue_city".to_string(),
                "venue_zip_code".to_string(),
                "venue_country_code".to_string(),
            ],
            Self::StateCodeInvalid { .. } | Self::StateCodeRequired { .. } => {
                vec!["venue_state_code".to_string()]
            }
            Self::FiscalSponsorNotReady(_) | Self::Unexpected(_) => Vec::new(),
        }
    }

    /// Returns whether an organizer can correct the failure in OCG.
    pub(crate) const fn is_correctable(&self) -> bool {
        !matches!(self, Self::Unexpected(_))
    }
}

/// Provider input for resolving an automatic-tax performance location.
#[derive(Clone, Debug)]
pub(crate) struct PerformanceLocationInput {
    /// Connected seller account that owns the performance location.
    pub connected_seller_id: String,
    /// Normalized physical venue sent to the provider.
    pub venue: TicketVenue,

    /// Fingerprint of a matching cached location, when available.
    pub cached_fingerprint: Option<String>,
    /// Provider identifier of a matching cached location, when available.
    pub cached_provider_tax_location_id: Option<String>,
}

/// Request used to return part or all of an application fee to a seller.
#[derive(Clone, Debug)]
pub(crate) struct ApplicationFeeAdjustmentInput {
    /// Amount returned to the seller, in minor units.
    pub amount_minor: i64,
    /// Connected seller that received the original application fee deduction.
    pub connected_seller_id: String,
    /// Durable purchase identifier used in provider metadata.
    pub event_purchase_id: Uuid,
    /// Stable idempotency key for provider creation.
    pub idempotency_key: String,
    /// Durable adjustment kind used in provider metadata.
    pub kind: String,
    /// Provider application fee being refunded.
    pub provider_application_fee_id: String,
}

/// Result of an idempotent provider application-fee adjustment.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct ApplicationFeeAdjustmentResult {
    /// Provider application-fee refund identifier.
    pub provider_application_fee_refund_id: String,
}

/// Authoritative provider amounts and object references for a completed checkout.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct CheckoutFinancialContext {
    /// Charge created by the Checkout `PaymentIntent`.
    pub provider_charge_id: String,
    /// `PaymentIntent` created by Checkout.
    pub provider_payment_reference: String,
    /// Total amount collected from the attendee.
    pub provider_total_minor: i64,
    /// Tax included in or added to the ticket line.
    pub tax_amount_minor: i64,

    /// Application fee created for the direct charge, when nonzero.
    pub provider_application_fee_id: Option<String>,
}

/// Result returned after creating a checkout session.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct CheckoutSession {
    /// Connected account that owns the Checkout Session.
    pub provider_object_account_id: String,
    /// Provider-specific checkout session identifier.
    pub provider_session_id: String,
    /// Redirect URL for the attendee.
    pub redirect_url: String,

    /// Fingerprint of the immutable performance location inputs.
    pub performance_location_fingerprint: Option<String>,
    /// Fingerprint of the immutable Product inputs.
    pub product_fingerprint: Option<String>,
    /// Provider performance location identifier.
    pub provider_tax_location_id: Option<String>,
    /// Provider ticket Product identifier.
    pub provider_tax_product_id: Option<String>,
}

/// Parameters used to create a checkout session.
#[derive(Clone, Debug)]
pub(crate) struct CreateCheckoutSessionInput {
    /// Total amount in minor units.
    pub amount_minor: i64,
    /// Base URL of the application.
    pub base_url: String,
    /// Community display name shown in invoice context.
    pub community_display_name: String,
    /// Community slug used in return URLs.
    pub community_name: String,
    /// Currency code for the payment.
    pub currency_code: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event display name shown in invoice context.
    pub event_name: String,
    /// Event slug used in return URLs.
    pub event_slug: String,
    /// Event time zone used in provider display context.
    pub event_timezone: String,
    /// Group display name shown in invoice context.
    pub group_name: String,
    /// Generated group slug used in return URLs.
    pub group_slug: String,
    /// Platform fee deducted from the group's proceeds, in minor units.
    pub provisional_platform_fee_amount_minor: i64,
    /// Purchase identifier tracked by OCG.
    pub purchase_id: Uuid,
    /// Fiscal sponsor that owns the Checkout Session and charge.
    pub seller: FiscalSponsorSeller,
    /// Ticket price tax inclusion behavior.
    pub tax_behavior: TicketTaxBehavior,
    /// Selected automatic or manual tax path.
    pub tax_calculation_mode: TicketTaxCalculationMode,
    /// Ticket title shown in the provider checkout.
    pub ticket_title: String,
    /// User identifier for the attendee.
    pub user_id: Uuid,
    /// Physical venue used as the ticket performance location.
    pub venue: TicketVenue,

    /// Fingerprint for a reusable sponsor-scoped performance location.
    pub cached_performance_location_fingerprint: Option<String>,
    /// Fingerprint for a reusable sponsor-scoped ticket Product.
    pub cached_product_fingerprint: Option<String>,
    /// Reusable provider performance location identifier.
    pub cached_provider_tax_location_id: Option<String>,
    /// Reusable provider ticket Product identifier.
    pub cached_provider_tax_product_id: Option<String>,
    /// Discount code applied to the purchase.
    pub discount_code: Option<String>,
    /// Admin-managed group slug used in return URLs.
    pub group_slug_pretty: Option<String>,
    /// Manual Tax Rate identifiers selected for Checkout.
    pub manual_tax_rate_ids: Option<Vec<String>>,
    /// Event ticket tax code used by automatic tax.
    pub tax_code: Option<String>,
}

impl CreateCheckoutSessionInput {
    /// Returns the group slug to use in public URLs.
    pub fn public_group_slug(&self) -> &str {
        self.group_slug_pretty.as_deref().unwrap_or(&self.group_slug)
    }
}

/// Request used to issue a full credit note linked to an existing refund.
#[derive(Clone, Debug)]
pub(crate) struct CreditNoteInput {
    /// Expected gross credit-note amount, in minor units.
    pub amount_minor: i64,
    /// Connected account that owns every provider object.
    pub connected_seller_id: String,
    /// Durable purchase identifier used in provider metadata.
    pub event_purchase_id: Uuid,
    /// Durable refund identifier used in provider metadata.
    pub event_purchase_refund_id: Uuid,
    /// Stable idempotency key for provider creation.
    pub idempotency_key: String,
    /// Provider invoice receiving the credit note.
    pub provider_invoice_id: String,
    /// Existing customer refund linked to the credit note.
    pub provider_refund_id: String,
    /// Expected tax amount in the full credit, in minor units.
    pub tax_amount_minor: i64,
}

/// Issued provider credit note and its current document URLs.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct CreditNoteResult {
    /// Provider credit-note identifier.
    pub provider_credit_note_id: String,

    /// Current provider-hosted credit-note URL when available.
    pub provider_hosted_url: Option<String>,
    /// Current provider credit-note PDF URL when available.
    pub provider_pdf_url: Option<String>,
}

/// Issued provider document returned through its connected-account scope.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct FinancialDocument {
    /// Current provider-hosted document URL when available.
    pub hosted_url: Option<String>,
    /// Current provider PDF URL when available.
    pub pdf_url: Option<String>,
}

impl FinancialDocument {
    /// Selects the best current attendee-facing provider URL.
    pub(crate) fn url(self) -> Option<String> {
        self.hosted_url.or(self.pdf_url)
    }
}

/// Provider financial-document type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum FinancialDocumentKind {
    /// Credit note linked to a completed refund.
    CreditNote,
    /// Post-payment invoice.
    Invoice,
}

/// Request used to find an existing provider refund.
#[derive(Clone, Debug)]
pub(crate) struct FindRefundInput {
    /// Completed purchase amount in minor units.
    pub amount_minor: i64,
    /// Connected account that owns the refund.
    pub connected_seller_id: String,
    /// Provider payment reference used for refunds.
    pub provider_payment_reference: String,
    /// Platform purchase identifier.
    pub purchase_id: Uuid,

    /// Provider refund identifier to poll when a refund was already created.
    pub provider_refund_id: Option<String>,
}

/// Failure returned while validating a fiscal sponsor for paid event setup.
#[derive(Debug, thiserror::Error)]
pub(crate) enum FiscalSponsorReadinessError {
    /// Sponsor configuration that an organizer can correct.
    #[error("{0}")]
    NotReady(String),
    /// Infrastructure or provider failure that an organizer cannot correct.
    #[error(transparent)]
    Unexpected(#[from] anyhow::Error),
}

/// Fiscal-sponsor readiness required before paid ticket configuration is saved.
#[derive(Clone, Debug)]
pub(crate) struct FiscalSponsorReadinessInput {
    /// Connected account selected as the legal seller.
    pub connected_seller_id: String,
    /// Payments provider that owns the connected account.
    pub provider: PaymentProvider,
    /// Whether active automatic-tax settings are required.
    pub require_automatic_tax: bool,
}

/// Request used to retrieve authoritative Checkout financial fields.
#[derive(Clone, Debug)]
pub(crate) struct GetCheckoutFinancialContextInput {
    /// Connected account that owns the Checkout Session and charge.
    pub connected_seller_id: String,
    /// Provider-specific Checkout Session identifier.
    pub provider_session_id: String,
}

/// Request used to retrieve a current account-scoped document URL.
#[derive(Clone, Debug)]
pub(crate) struct GetFinancialDocumentInput {
    /// Connected account that owns the document.
    pub connected_seller_id: String,
    /// Provider document type.
    pub kind: FinancialDocumentKind,
    /// Durable provider invoice or credit-note identifier.
    pub provider_document_id: String,
}

/// Request used to list active connected-account Tax Rates.
#[derive(Clone, Debug)]
pub(crate) struct ListTaxRatesInput {
    /// Connected account that owns the Tax Rates.
    pub connected_seller_id: String,
    /// Inclusive or exclusive rates to return.
    pub tax_behavior: TicketTaxBehavior,
}

/// Stripe webhook endpoint scope used to select the signing secret.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum PaymentsWebhookEndpoint {
    /// Events emitted for connected accounts.
    ConnectedAccount,
    /// Events emitted for the platform account.
    PlatformAccount,
}

/// Supported webhook events normalized across providers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) enum PaymentsWebhookEvent {
    /// A direct-charge application fee was created asynchronously.
    ApplicationFeeCreated {
        /// Application fee amount in minor units.
        amount_minor: i64,
        /// Connected account whose direct charge created the fee.
        connected_account_id: String,
        /// Whether the provider event belongs to live mode.
        is_live: bool,
        /// Provider application-fee identifier.
        provider_application_fee_id: String,
        /// Connected-account charge that created the application fee.
        provider_charge_id: String,
    },
    /// A checkout session completed successfully.
    CheckoutCompleted {
        /// Connected account that owns the Checkout Session.
        connected_account_id: String,
        /// Whether the provider event belongs to live mode.
        is_live: bool,
        /// Provider-specific checkout session identifier.
        provider_session_id: String,
    },
    /// A checkout session expired before payment.
    CheckoutExpired {
        /// Connected account that owns the Checkout Session.
        connected_account_id: String,
        /// Whether the provider event belongs to live mode.
        is_live: bool,
        /// Provider-specific checkout session identifier.
        provider_session_id: String,
    },
    /// A paid invoice was issued for an OCG purchase.
    InvoicePaid {
        /// Connected account that owns the invoice.
        connected_account_id: String,
        /// Current hosted invoice URL.
        hosted_url: String,
        /// Whether the provider event belongs to live mode.
        is_live: bool,
        /// Provider invoice identifier.
        provider_invoice_id: String,
        /// Platform purchase identifier from invoice metadata.
        purchase_id: Uuid,

        /// Current invoice PDF URL.
        pdf_url: Option<String>,
    },
    /// A verified provider event that does not belong to OCG.
    Noop,
    /// A provider refund lifecycle state changed.
    RefundUpdated {
        /// Refunded amount in minor units.
        amount_minor: i64,
        /// Connected account that owns a direct-charge refund.
        connected_account_id: String,
        /// Refund currency code.
        currency_code: String,
        /// Whether the provider event belongs to live mode.
        is_live: bool,
        /// Provider payment reference owning the refund.
        provider_payment_reference: String,
        /// Provider-specific refund identifier.
        provider_refund_id: String,
        /// Platform purchase identifier from provider metadata.
        purchase_id: Uuid,
        /// Current provider refund lifecycle status.
        status: RefundPaymentStatus,
    },
}

/// Request used to refund a completed payment.
#[derive(Clone, Debug)]
pub(crate) struct RefundPaymentInput {
    /// Completed purchase amount in minor units.
    pub amount_minor: i64,
    /// Connected account that owns the refund.
    pub connected_seller_id: String,
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

/// Request used to validate selected connected-account Tax Rates.
#[derive(Clone, Debug)]
pub(crate) struct ValidateTaxRatesInput {
    /// Connected account that owns the Tax Rates.
    pub connected_seller_id: String,
    /// Tax Rate identifiers selected by the event.
    pub manual_tax_rate_ids: Vec<String>,
    /// Inclusive or exclusive behavior required by the event.
    pub tax_behavior: TicketTaxBehavior,
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
