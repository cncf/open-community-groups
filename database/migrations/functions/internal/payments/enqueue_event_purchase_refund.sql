-- Queues provider refund work for a purchase under its purchase-level
-- idempotency key. Returns the new refund identifier, or null when refund
-- work already exists for the purchase.
create or replace function enqueue_event_purchase_refund(
    p_purchase event_purchase,
    p_kind text,
    p_amount_minor bigint,
    p_event_refund_request_id uuid default null,
    p_initiated_by_user_id uuid default null,
    p_review_note text default null
)
returns uuid as $$
declare
    v_event_purchase_refund_id uuid;
    v_payment_job_id uuid;
begin
    -- Insert the durable worker job with the stable purchase idempotency key
    v_payment_job_id := enqueue_payment_job(
        'event-purchase-refund',
        p_purchase.payment_provider_id,
        p_purchase.event_purchase_id,
        format('event-purchase-refund-%s', p_purchase.event_purchase_id)
    );

    -- Skip purchases whose refund work already exists
    if v_payment_job_id is null then
        return null;
    end if;

    -- Record the refund linked to the queued worker job
    insert into event_purchase_refund (
        amount_minor,
        currency_code,
        event_purchase_id,
        event_refund_request_id,
        initiated_by_user_id,
        kind,
        payment_job_id,
        payment_provider_id,
        review_note,
        status
    ) values (
        p_amount_minor,
        p_purchase.currency_code,
        p_purchase.event_purchase_id,
        p_event_refund_request_id,
        p_initiated_by_user_id,
        p_kind,
        v_payment_job_id,
        p_purchase.payment_provider_id,
        p_review_note,
        'provider-pending'
    )
    returning event_purchase_refund_id into v_event_purchase_refund_id;

    -- Return the new refund identifier
    return v_event_purchase_refund_id;
end;
$$ language plpgsql;
