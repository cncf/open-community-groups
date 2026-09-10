//! Credit-note processing for claimed payment jobs.

use anyhow::Result;

use crate::{
    db::{
        DynDB,
        payments::{ClaimedEventPurchaseCreditNote, ClaimedPaymentJob},
    },
    services::payments::{CreditNoteInput, DynPaymentsProvider},
};

/// Finds or creates one linked provider credit note and records it.
pub(super) async fn process(
    db: &DynDB,
    payments_provider: &DynPaymentsProvider,
    job: &ClaimedPaymentJob,
    credit_note: &ClaimedEventPurchaseCreditNote,
) -> Result<()> {
    // Reconcile the provider document using immutable invoice and refund context
    let result = payments_provider
        .reconcile_credit_note(&CreditNoteInput {
            amount_minor: credit_note.amount_minor,
            connected_seller_id: credit_note.connected_seller_id.clone(),
            event_purchase_id: job.event_purchase_id,
            event_purchase_refund_id: credit_note.event_purchase_refund_id,
            idempotency_key: job.idempotency_key.clone(),
            provider_invoice_id: credit_note.provider_invoice_id.clone(),
            provider_refund_id: credit_note.provider_refund_id.clone(),
            tax_amount_minor: credit_note.tax_amount_minor,
        })
        .await?;

    // Persist the provider document against the current payment job claim
    db.record_event_purchase_credit_note_succeeded(
        credit_note.event_purchase_credit_note_id,
        job.claim_id,
        result.provider_credit_note_id,
        result.provider_hosted_url,
        result.provider_pdf_url,
    )
    .await
}
