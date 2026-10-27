-- Queues a full credit note for a refunded purchase under its refund-level
-- idempotency key. Returns the new credit note identifier, or null when
-- credit note work already exists for the refund.
create or replace function enqueue_event_purchase_credit_note(
    p_purchase event_purchase,
    p_event_purchase_refund_id uuid
)
returns uuid as $$
declare
    v_event_purchase_credit_note_id uuid;
    v_payment_job_id uuid;
begin
    -- Insert the durable worker job with the stable refund idempotency key
    v_payment_job_id := enqueue_payment_job(
        'event-purchase-credit-note',
        p_purchase.payment_provider_id,
        p_purchase.event_purchase_id,
        format('event-purchase-credit-note-%s', p_event_purchase_refund_id)
    );

    -- Skip refunds whose credit note work already exists
    if v_payment_job_id is null then
        return null;
    end if;

    -- Record the credit note linked to the queued worker job
    insert into event_purchase_credit_note (
        amount_minor,
        currency_code,
        event_purchase_refund_id,
        payment_job_id,
        payment_provider_id,
        provider_object_account_id,
        tax_amount_minor
    ) values (
        p_purchase.provider_total_minor,
        p_purchase.currency_code,
        p_event_purchase_refund_id,
        v_payment_job_id,
        p_purchase.payment_provider_id,
        p_purchase.provider_object_account_id,
        p_purchase.tax_amount_minor
    )
    returning event_purchase_credit_note_id into v_event_purchase_credit_note_id;

    -- Return the new credit note identifier
    return v_event_purchase_credit_note_id;
end;
$$ language plpgsql;
