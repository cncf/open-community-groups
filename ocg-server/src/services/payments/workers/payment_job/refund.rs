//! Refund processing for claimed payment jobs.

use anyhow::{Context, Result, anyhow};

use crate::{
    db::{
        DynDB,
        payments::{ClaimedEventPurchaseRefund, ClaimedPaymentJob},
    },
    services::payments::{
        DynPaymentsProvider, FindRefundInput, RefundPaymentInput,
        notification_composer::PaymentsNotificationComposer,
        refund_recorder::{RecordedProviderRefund, persist_provider_refund_result},
    },
};

/// Finds, creates, or finalizes one provider refund and records it.
pub(super) async fn process(
    db: &DynDB,
    notification_composer: &PaymentsNotificationComposer,
    payments_provider: &DynPaymentsProvider,
    job: &ClaimedPaymentJob,
    refund: &ClaimedEventPurchaseRefund,
) -> Result<()> {
    // Finalize persisted success directly or reconcile the provider first
    if refund.provider_refunded_at.is_some() {
        finalize_refund(db, notification_composer, job, refund).await
    } else {
        reconcile_provider_refund(db, notification_composer, payments_provider, job, refund).await
    }
}

/// Finalizes local state and atomically queues its completion notification.
async fn finalize_refund(
    db: &DynDB,
    notification_composer: &PaymentsNotificationComposer,
    job: &ClaimedPaymentJob,
    refund: &ClaimedEventPurchaseRefund,
) -> Result<()> {
    // Build the durable notification payload before finalizing local state
    let notification_template_data = notification_composer
        .build_refund_approval_template_data(refund.community_id, refund.event_id, false)
        .await
        .context("failed to build refund approval notification")?;

    // Finalize state and enqueue its completion notification atomically
    db.finalize_event_purchase_refund(
        refund.event_purchase_refund_id,
        job.claim_id,
        notification_template_data,
        Some(refund.payment_provider),
    )
    .await
}

/// Finds an existing provider refund or creates it with the stable idempotency key.
async fn reconcile_provider_refund(
    db: &DynDB,
    notification_composer: &PaymentsNotificationComposer,
    payments_provider: &DynPaymentsProvider,
    job: &ClaimedPaymentJob,
    refund: &ClaimedEventPurchaseRefund,
) -> Result<()> {
    // Require the original payment reference before querying the provider
    let provider_payment_reference = refund
        .provider_payment_reference
        .clone()
        .ok_or_else(|| anyhow!("provider payment reference is missing"))?;

    // Reuse provider state when a prior attempt may have created the refund
    let provider_refund = payments_provider
        .find_refund(&FindRefundInput {
            amount_minor: refund.amount_minor,
            connected_seller_id: refund.connected_seller_id.clone(),
            provider_payment_reference: provider_payment_reference.clone(),
            purchase_id: refund.event_purchase_id,

            provider_refund_id: refund.provider_refund_id.clone(),
        })
        .await?;

    // Create only when no provider refund exists and no pinned refund disappeared
    let provider_refund = match provider_refund {
        Some(provider_refund) => provider_refund,
        None if refund.provider_refund_id.is_some() => {
            return Err(anyhow!("provider refund not found"));
        }
        None => {
            payments_provider
                .refund_payment(&RefundPaymentInput {
                    amount_minor: refund.amount_minor,
                    connected_seller_id: refund.connected_seller_id.clone(),
                    idempotency_key: job.idempotency_key.clone(),
                    provider_payment_reference,
                    purchase_id: refund.event_purchase_id,
                })
                .await?
        }
    };

    // Persist the provider result against the claim carried by the refund payload
    match persist_provider_refund_result(db, &refund.refund, provider_refund).await? {
        RecordedProviderRefund::Failed | RecordedProviderRefund::Pending => Ok(()),
        RecordedProviderRefund::Succeeded => {
            finalize_refund(db, notification_composer, job, refund).await
        }
    }
}
