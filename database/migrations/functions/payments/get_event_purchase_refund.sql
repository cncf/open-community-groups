-- Loads the durable provider refund record for an event purchase.
create or replace function get_event_purchase_refund(
    p_event_purchase_id uuid
)
returns jsonb as $$
declare
    v_refund event_purchase_refund;
begin
    -- Load the durable refund for the requested purchase
    select *
    into v_refund
    from event_purchase_refund
    where event_purchase_id = p_event_purchase_id;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Return the durable provider and local finalization state
    return jsonb_strip_nulls(
        jsonb_build_object(
            'amount_minor', v_refund.amount_minor,
            'currency_code', v_refund.currency_code,
            'event_purchase_id', v_refund.event_purchase_id,
            'event_purchase_refund_id', v_refund.event_purchase_refund_id,
            'idempotency_key', v_refund.idempotency_key,
            'kind', v_refund.kind,
            'payment_provider', v_refund.payment_provider_id,
            'status', v_refund.status,

            'failure_message', v_refund.failure_message,
            'finalized_at', extract(epoch from v_refund.finalized_at)::bigint,
            'provider_refund_id', v_refund.provider_refund_id,
            'provider_refunded_at', extract(epoch from v_refund.provider_refunded_at)::bigint,

            'started_now', false
        )
    );
end;
$$ language plpgsql;
