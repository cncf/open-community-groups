//! Payments service management and provider integrations.
//!
//! OCG uses a provider-agnostic payments domain model while running with a
//! single configured payments provider at a time. Provider-specific behavior
//! should stay isolated inside provider modules, while shared checkout,
//! refund, and webhook flows stay generic.

mod manager;
mod notification_composer;
mod provider;
mod webhook_reconciler;

pub(crate) use manager::{
    ApproveRefundRequestInput, DynPaymentsManager, HandleWebhookError, PgPaymentsManager,
    RejectRefundRequestInput, RequestRefundInput,
};
pub(crate) use provider::{
    CheckoutSession, CreateCheckoutSessionInput, DynPaymentsProvider, PaymentsWebhookEvent,
    RefundPaymentInput, build_payments_provider,
};

#[cfg(test)]
pub(crate) use manager::MockPaymentsManager;
#[cfg(test)]
pub(crate) use provider::{MockPaymentsProvider, PaymentsProvider, RefundPaymentResult};
