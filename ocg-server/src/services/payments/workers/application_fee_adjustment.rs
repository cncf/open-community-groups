//! Background processing for durable application-fee adjustments.

use anyhow::Result;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument, warn};

use crate::{
    db::{DynDB, payments::ClaimedEventPurchaseApplicationFeeAdjustment},
    services::workers::claim_loop::{self, ClaimLoopConfig},
};

use super::super::{ApplicationFeeAdjustmentInput, DynPaymentsProvider};

#[cfg(test)]
mod tests;

/// Number of workers processing application-fee adjustments.
const NUM_WORKERS: usize = 1;

/// Starts durable application-fee adjustment workers.
pub(in crate::services::payments) fn start(
    db: &DynDB,
    payments_provider: Option<&DynPaymentsProvider>,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
) {
    // Start dedicated processors with shared graceful-shutdown coordination
    for _ in 0..NUM_WORKERS {
        let worker = Worker {
            cancellation_token: cancellation_token.clone(),
            db: db.clone(),

            payments_provider: payments_provider.cloned(),
        };
        task_tracker.spawn(async move {
            worker.run().await;
        });
    }
}

/// Processes durable application-fee adjustment jobs.
struct Worker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable application-fee adjustment transitions.
    db: DynDB,

    /// Provider used to reconcile application-fee refunds.
    payments_provider: Option<DynPaymentsProvider>,
}

impl Worker {
    /// Processes application-fee adjustments until graceful shutdown.
    async fn run(&self) {
        // Delegate payment-specific claim cadence while preserving this error boundary
        claim_loop::run(
            &self.cancellation_token,
            ClaimLoopConfig::default(),
            || self.process_next_application_fee_adjustment(),
            |err| {
                error!(
                    error = %err,
                    "error processing event purchase application-fee adjustment"
                );
                None
            },
        )
        .await;
    }

    /// Finds or creates one provider application-fee refund and records it.
    async fn process_application_fee_adjustment(
        &self,
        payments_provider: &DynPaymentsProvider,
        adjustment: ClaimedEventPurchaseApplicationFeeAdjustment,
    ) -> Result<()> {
        // Reconcile the provider object using the durable idempotency key
        let result = payments_provider
            .reconcile_application_fee_adjustment(&ApplicationFeeAdjustmentInput {
                amount_minor: adjustment.amount_minor,
                connected_seller_id: adjustment.connected_seller_id,
                event_purchase_id: adjustment.event_purchase_id,
                idempotency_key: adjustment.idempotency_key,
                kind: adjustment.kind,
                provider_application_fee_id: adjustment.provider_application_fee_id,
            })
            .await;

        // Persist success or release the claim while preserving provider failures
        match result {
            Ok(result) => {
                self.db
                    .record_event_purchase_application_fee_adjustment_succeeded(
                        adjustment.event_purchase_application_fee_adjustment_id,
                        adjustment.claim_id,
                        result.provider_application_fee_refund_id,
                    )
                    .await
            }
            Err(err) => {
                if let Err(record_err) = self
                    .db
                    .record_event_purchase_application_fee_adjustment_failure(
                        adjustment.event_purchase_application_fee_adjustment_id,
                        adjustment.claim_id,
                        err.to_string(),
                    )
                    .await
                {
                    warn!(error = %record_err, "failed to release application-fee adjustment claim");
                }
                Err(err)
            }
        }
    }

    /// Claims and processes one durable application-fee adjustment.
    #[instrument(skip(self), err)]
    async fn process_next_application_fee_adjustment(&self) -> Result<bool> {
        // Leave durable jobs unclaimed when this deployment has no provider
        let Some(payments_provider) = self.payments_provider.as_ref() else {
            return Ok(false);
        };

        // Claim one provider-specific adjustment before reconciling external state
        let Some(adjustment) = self
            .db
            .claim_event_purchase_application_fee_adjustment(payments_provider.provider())
            .await?
        else {
            return Ok(false);
        };

        // Reconcile the claimed adjustment and record its durable outcome
        self.process_application_fee_adjustment(payments_provider, adjustment)
            .await
            .map(|()| true)
    }
}
