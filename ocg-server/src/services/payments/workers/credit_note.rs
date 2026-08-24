//! Background processing for durable credit notes.

use anyhow::Result;
use tokio_util::sync::CancellationToken;
use tracing::{error, instrument, warn};

use crate::{
    db::{DynDB, payments::ClaimedEventPurchaseCreditNote},
    services::workers::{
        BackgroundTasks,
        claim_loop::{self, ClaimLoopConfig},
    },
};

use super::super::{CreditNoteInput, DynPaymentsProvider};

#[cfg(test)]
mod tests;

/// Number of workers processing credit notes.
const NUM_WORKERS: usize = 1;

/// Starts durable credit-note workers.
pub(in crate::services::payments) fn start(
    db: &DynDB,
    payments_provider: Option<&DynPaymentsProvider>,
    background_tasks: &BackgroundTasks,
) {
    // Start dedicated processors with shared graceful-shutdown coordination
    for _ in 0..NUM_WORKERS {
        let worker = Worker {
            cancellation_token: background_tasks.cancellation_token(),
            db: db.clone(),

            payments_provider: payments_provider.cloned(),
        };
        background_tasks.spawn(async move {
            worker.run().await;
        });
    }
}

/// Processes durable credit-note jobs.
struct Worker {
    /// Coordinates graceful worker shutdown.
    cancellation_token: CancellationToken,
    /// Persists durable credit-note transitions.
    db: DynDB,

    /// Provider used to reconcile credit-note documents.
    payments_provider: Option<DynPaymentsProvider>,
}

impl Worker {
    /// Processes credit notes until graceful shutdown.
    async fn run(&self) {
        // Delegate payment-specific claim cadence while preserving this error boundary
        claim_loop::run(
            &self.cancellation_token,
            ClaimLoopConfig::default(),
            || self.process_next_credit_note(),
            |err| {
                error!(error = %err, "error processing event purchase credit note");
                None
            },
        )
        .await;
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

    /// Claims and processes one durable credit note.
    #[instrument(skip(self), err)]
    async fn process_next_credit_note(&self) -> Result<bool> {
        // Leave durable jobs unclaimed when this deployment has no provider
        let Some(payments_provider) = self.payments_provider.as_ref() else {
            return Ok(false);
        };

        // Claim one provider-specific credit note before reconciling external state
        let Some(credit_note) = self
            .db
            .claim_event_purchase_credit_note(payments_provider.provider())
            .await?
        else {
            return Ok(false);
        };

        // Reconcile the claimed credit note and record its durable outcome
        self.process_credit_note(payments_provider, credit_note)
            .await
            .map(|()| true)
    }
}
