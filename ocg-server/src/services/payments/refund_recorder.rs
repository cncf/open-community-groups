//! Shared persistence for normalized provider refund results.

use anyhow::{Context, Result};
use tracing::warn;

use crate::db::{
    DynDB,
    payments::{EventPurchaseRefund, EventPurchaseRefundStatus},
};

use super::{RefundPaymentResult, RefundPaymentStatus};

/// Durable outcome after recording a normalized provider refund result.
pub(super) enum RecordedProviderRefund {
    /// The provider-confirmed terminal failure is durable.
    Failed,
    /// The provider reported progress and the durable refund state was returned.
    Pending(EventPurchaseRefund),
    /// The provider reported success and the durable refund state was returned.
    Succeeded(EventPurchaseRefund),
}

/// Reconciles a normalized provider refund result with durable state.
pub(super) async fn persist_provider_refund_result(
    db: &DynDB,
    refund: &EventPurchaseRefund,
    provider_refund: RefundPaymentResult,
) -> Result<RecordedProviderRefund> {
    // Persist the provider lifecycle transition against the expected attempt
    match provider_refund.status {
        RefundPaymentStatus::Failed => {
            let provider_refund_id = provider_refund.provider_refund_id;

            // Acknowledge an already pinned terminal result without rewriting or re-alerting
            if refund.status == EventPurchaseRefundStatus::ProviderFailed
                && refund.provider_refund_id.as_deref() == Some(provider_refund_id.as_str())
            {
                return Ok(RecordedProviderRefund::Failed);
            }

            db.record_event_purchase_refund_terminal_failed(
                refund.event_purchase_refund_id,
                refund.idempotency_key.clone(),
                provider_refund_id.clone(),
                "provider refund failed".to_string(),
            )
            .await
            .context("failed to record terminal provider refund failure")?;

            // Alert operators after the terminal failure is durable
            warn!(
                event_purchase_id = %refund.event_purchase_id,
                event_purchase_refund_id = %refund.event_purchase_refund_id,
                provider_refund_id = %provider_refund_id,
                "provider refund requires manual recovery"
            );

            Ok(RecordedProviderRefund::Failed)
        }
        RefundPaymentStatus::Pending => {
            let refund = db
                .record_event_purchase_refund_pending(
                    refund.event_purchase_refund_id,
                    refund.idempotency_key.clone(),
                    provider_refund.provider_refund_id,
                )
                .await
                .context("failed to record pending provider refund")?;

            Ok(RecordedProviderRefund::Pending(refund))
        }
        RefundPaymentStatus::Succeeded => {
            let refund = db
                .record_event_purchase_refund_succeeded(
                    refund.event_purchase_refund_id,
                    refund.idempotency_key.clone(),
                    provider_refund.provider_refund_id,
                )
                .await
                .context("failed to record successful provider refund")?;

            Ok(RecordedProviderRefund::Succeeded(refund))
        }
    }
}
