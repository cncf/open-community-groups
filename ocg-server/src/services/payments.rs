//! Payments service management and provider integrations.
//!
//! OCG uses a provider-agnostic payments domain model while running with a
//! single configured payments provider at a time. Provider-specific behavior
//! should stay isolated inside provider modules, while shared checkout,
//! refund, and webhook flows stay generic.

mod financial_worker;
mod manager;
mod notification_composer;
mod provider;
mod refund_recorder;
mod refund_worker;
mod webhook_reconciler;

pub(crate) use financial_worker::start_financial_workers;
pub(crate) use manager::{
    ApproveRefundRequestInput, CompleteRefundRecoveryInput, DynPaymentsManager, HandleWebhookError,
    PgPaymentsManager, RejectRefundRequestInput, RequestRefundInput,
};
pub(crate) use provider::{
    ApplicationFeeAdjustmentInput, CheckoutSession, CreateCheckoutSessionInput, CreditNoteInput,
    DynPaymentsProvider, FinancialDocumentKind, FindRefundInput, FiscalSponsorReadinessError,
    FiscalSponsorReadinessInput, GetCheckoutFinancialContextInput, GetFinancialDocumentInput,
    PaymentsWebhookEvent, RefundPaymentInput, RefundPaymentResult, RefundPaymentStatus,
    build_payments_provider,
};
pub(crate) use refund_worker::start_refund_workers;

#[cfg(test)]
pub(crate) use manager::MockPaymentsManager;
#[cfg(test)]
pub(crate) use provider::FinancialDocument;
#[cfg(test)]
pub(crate) use provider::MockPaymentsProvider;
