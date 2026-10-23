-- Queues an application fee adjustment for a purchase under the
-- purchase-level idempotency key of its kind. Returns the new adjustment
-- identifier, or null when adjustment work of that kind already exists.
create or replace function enqueue_event_purchase_application_fee_adjustment(
    p_purchase event_purchase,
    p_kind text,
    p_amount_minor bigint
)
returns uuid as $$
declare
    v_event_purchase_application_fee_adjustment_id uuid;
    v_idempotency_key text;
    v_payment_job_id uuid;
begin
    -- Derive the idempotency key from the adjustment kind
    case p_kind
        -- Key the fee returned with a refunded charge
        when 'purchase-refund' then
            v_idempotency_key := format('event-purchase-refund-fee-adjustment-%s', p_purchase.event_purchase_id);

        -- Key the fee returned when tax lowered the final platform fee
        when 'tax-reconciliation' then
            v_idempotency_key := format('event-purchase-tax-fee-adjustment-%s', p_purchase.event_purchase_id);

        -- Reject kinds without an idempotency key contract
        else
            raise exception 'unsupported application fee adjustment kind';
    end case;

    -- Insert the durable worker job with the derived idempotency key
    v_payment_job_id := enqueue_payment_job(
        'event-purchase-application-fee-adjustment',
        p_purchase.payment_provider_id,
        p_purchase.event_purchase_id,
        v_idempotency_key
    );

    -- Skip purchases whose adjustment work of this kind already exists
    if v_payment_job_id is null then
        return null;
    end if;

    -- Record the adjustment linked to the queued worker job
    insert into event_purchase_application_fee_adjustment (
        amount_minor,
        event_purchase_id,
        kind,
        payment_job_id
    ) values (
        p_amount_minor,
        p_purchase.event_purchase_id,
        p_kind,
        v_payment_job_id
    )
    returning event_purchase_application_fee_adjustment_id into v_event_purchase_application_fee_adjustment_id;

    -- Return the new adjustment identifier
    return v_event_purchase_application_fee_adjustment_id;
end;
$$ language plpgsql;
