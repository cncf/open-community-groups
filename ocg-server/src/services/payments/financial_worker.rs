//! Background processing for application-fee adjustments and credit notes.

use std::time::Duration;

use anyhow::Result;
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, instrument, warn};

use crate::{
    db::{
        DynDB,
        payments::{ClaimedEventPurchaseApplicationFeeAdjustment, ClaimedEventPurchaseCreditNote},
    },
    services::workers::run_until_cancelled,
};

use super::{ApplicationFeeAdjustmentInput, CreditNoteInput, DynPaymentsProvider};

#[cfg(test)]
mod tests;

/// Number of workers processing financial side effects.
const NUM_FINANCIAL_WORKERS: usize = 2;
/// Pause after a worker iteration fails.
const PAUSE_ON_ERROR: Duration = Duration::from_secs(10);
/// Pause when no financial work is available.
const PAUSE_ON_NONE: Duration = Duration::from_secs(15);

/// Starts durable application-fee adjustment and credit-note workers.
pub(crate) fn start_financial_workers(
    db: &DynDB,
    payments_provider: Option<&DynPaymentsProvider>,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
) {
    for _ in 0..NUM_FINANCIAL_WORKERS {
        let worker = FinancialWorker {
            cancellation_token: cancellation_token.clone(),
            db: db.clone(),

            payments_provider: payments_provider.cloned(),
        };
        task_tracker.spawn(async move {
            worker.run().await;
        });
    }
}

/// Processes durable payment-side financial work.
struct FinancialWorker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable financial lifecycle transitions.
    db: DynDB,

    /// Provider used to reconcile external financial objects.
    payments_provider: Option<DynPaymentsProvider>,
}

impl FinancialWorker {
    /// Processes financial jobs until graceful shutdown.
    async fn run(&self) {
        loop {
            // Stop before claiming more work after graceful shutdown begins
            if self.cancellation_token.is_cancelled() {
                break;
            }

            // Process one job while allowing shutdown to leave its claim for recovery
            let Some(result) =
                run_until_cancelled(&self.cancellation_token, self.process_next_financial_work())
                    .await
            else {
                break;
            };

            // Continue after completed work or select the appropriate idle/error backoff
            let pause = match result {
                Ok(true) => None,
                Ok(false) => Some(PAUSE_ON_NONE),
                Err(err) => {
                    error!(error = %err, "error processing purchase financial work");
                    Some(PAUSE_ON_ERROR)
                }
            };

            // Apply the selected backoff without delaying graceful shutdown
            if let Some(pause) = pause {
                tokio::select! {
                    () = sleep(pause) => {},
                    () = self.cancellation_token.cancelled() => break,
                }
            }
        }
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

    /// Finds or creates one linked provider credit note and records it.
    async fn process_credit_note(
        &self,
        payments_provider: &DynPaymentsProvider,
        credit_note: ClaimedEventPurchaseCreditNote,
    ) -> Result<()> {
        // Reconcile the provider document using immutable invoice and refund context
        let result = payments_provider
            .reconcile_credit_note(&CreditNoteInput {
                amount_minor: credit_note.amount_minor,
                connected_seller_id: credit_note.connected_seller_id,
                event_purchase_id: credit_note.event_purchase_id,
                event_purchase_refund_id: credit_note.event_purchase_refund_id,
                idempotency_key: credit_note.idempotency_key,
                provider_invoice_id: credit_note.provider_invoice_id,
                provider_refund_id: credit_note.provider_refund_id,
                tax_amount_minor: credit_note.tax_amount_minor,
            })
            .await;

        // Persist success or release the claim while preserving provider failures
        match result {
            Ok(result) => {
                self.db
                    .record_event_purchase_credit_note_succeeded(
                        credit_note.event_purchase_credit_note_id,
                        credit_note.claim_id,
                        result.provider_credit_note_id,
                        result.provider_hosted_url,
                        result.provider_pdf_url,
                    )
                    .await
            }
            Err(err) => {
                if let Err(record_err) = self
                    .db
                    .record_event_purchase_credit_note_failure(
                        credit_note.event_purchase_credit_note_id,
                        credit_note.claim_id,
                        err.to_string(),
                    )
                    .await
                {
                    warn!(error = %record_err, "failed to release credit-note claim");
                }
                Err(err)
            }
        }
    }

    /// Processes one application-fee adjustment before one credit-note job.
    #[instrument(skip(self), err)]
    async fn process_next_financial_work(&self) -> Result<bool> {
        // Leave durable jobs unclaimed when this deployment has no provider
        let Some(payments_provider) = self.payments_provider.as_ref() else {
            return Ok(false);
        };

        // Give fee corrections priority because they restore seller proceeds
        if let Some(adjustment) = self
            .db
            .claim_event_purchase_application_fee_adjustment(payments_provider.provider())
            .await?
        {
            return self
                .process_application_fee_adjustment(payments_provider, adjustment)
                .await
                .map(|()| true);
        }

        // Claim a credit note only when no fee adjustment is due
        if let Some(credit_note) = self
            .db
            .claim_event_purchase_credit_note(payments_provider.provider())
            .await?
        {
            return self
                .process_credit_note(payments_provider, credit_note)
                .await
                .map(|()| true);
        }

        Ok(false)
    }
}
