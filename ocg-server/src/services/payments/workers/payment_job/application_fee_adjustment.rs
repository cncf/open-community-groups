//! Application-fee adjustment processing for claimed payment jobs.

use anyhow::Result;

use crate::{
    db::{
        DynDB,
        payments::{ClaimedEventPurchaseApplicationFeeAdjustment, ClaimedPaymentJob},
    },
    services::payments::{ApplicationFeeAdjustmentInput, DynPaymentsProvider},
};

/// Finds or creates one provider application-fee refund and records it.
pub(super) async fn process(
    db: &DynDB,
    payments_provider: &DynPaymentsProvider,
    job: &ClaimedPaymentJob,
    adjustment: &ClaimedEventPurchaseApplicationFeeAdjustment,
) -> Result<()> {
    // Reconcile the provider object using the durable idempotency key
    let result = payments_provider
        .reconcile_application_fee_adjustment(&ApplicationFeeAdjustmentInput {
            amount_minor: adjustment.amount_minor,
            connected_seller_id: adjustment.connected_seller_id.clone(),
            currency_code: adjustment.currency_code.clone(),
            event_purchase_id: job.event_purchase_id,
            idempotency_key: job.idempotency_key.clone(),
            kind: adjustment.kind.clone(),
            provider_application_fee_id: adjustment.provider_application_fee_id.clone(),
        })
        .await?;

    // Persist the provider outcome against the current payment job claim
    db.record_event_purchase_application_fee_adjustment_succeeded(
        adjustment.event_purchase_application_fee_adjustment_id,
        job.claim_id,
        result.provider_application_fee_refund_id,
    )
    .await
}
