//! Payments service management and provider integrations.
//!
//! OCG uses a provider-agnostic payments domain model while running with a
//! single configured payments provider at a time. Provider-specific behavior
//! should stay isolated inside provider modules, while shared checkout,
//! refund, and webhook flows stay generic.

use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::{
    config::HttpServerConfig, db::DynDB, services::notifications::DynNotificationsManager,
};

mod manager;
mod notification_composer;
mod provider;
mod refund_recorder;
mod webhook_reconciler;
mod workers;

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

#[cfg(test)]
pub(crate) use manager::MockPaymentsManager;
#[cfg(test)]
pub(crate) use manager::PaymentsManager;
#[cfg(test)]
pub(crate) use provider::FinancialDocument;
#[cfg(test)]
pub(crate) use provider::MockPaymentsProvider;

/// Starts all durable payment workers.
pub(crate) fn start_payment_workers(
    db: &DynDB,
    notifications_manager: DynNotificationsManager,
    payments_provider: Option<&DynPaymentsProvider>,
    server_cfg: &HttpServerConfig,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
) {
    // Start provider-mediated application-fee adjustment workers
    workers::application_fee_adjustment::start(
        db,
        payments_provider,
        task_tracker,
        cancellation_token,
    );

    // Start provider-mediated credit-note workers
    workers::credit_note::start(db, payments_provider, task_tracker, cancellation_token);

    // Start provider-independent recovery for every durable payment queue
    workers::recovery::start(db, task_tracker, cancellation_token);

    // Start provider-mediated refunds with their notification boundary
    workers::refund::start(
        db,
        notifications_manager,
        payments_provider,
        server_cfg.clone(),
        task_tracker,
        cancellation_token,
    );
}
