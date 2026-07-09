-- Records a successful provider refund before local finalization.
create or replace function record_event_purchase_refund_succeeded(
    p_event_purchase_refund_id uuid,
    p_provider_refund_id text
)
returns jsonb as $$
declare
    v_refund event_purchase_refund;
begin
    -- Validate the provider refund identifier
    if nullif(btrim(p_provider_refund_id), '') is null then
        raise exception 'provider refund id is required';
    end if;

    -- Lock the durable refund row before accepting the provider result
    select *
    into v_refund
    from event_purchase_refund
    where event_purchase_refund_id = p_event_purchase_refund_id
    for update;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Reject a provider result that conflicts with the pinned refund
    if v_refund.provider_refund_id is not null
       and v_refund.provider_refund_id <> p_provider_refund_id then
        raise exception 'event purchase refund already has a different provider refund id';
    end if;

    -- Record provider success without downgrading a finalized refund
    if v_refund.status <> 'finalized' then
        update event_purchase_refund
        set
            failure_message = null,
            provider_refund_id = p_provider_refund_id,
            provider_refunded_at = coalesce(provider_refunded_at, current_timestamp),
            status = 'provider-succeeded',
            updated_at = current_timestamp
        where event_purchase_refund_id = p_event_purchase_refund_id
        returning * into v_refund;
    end if;

    -- Return the durable refund state after recording provider success
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
