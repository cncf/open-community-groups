-- Records a successful provider refund for the expected attempt.
create or replace function record_event_purchase_refund_succeeded(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text
)
returns jsonb as $$
declare
    v_event_id uuid;
    v_refund event_purchase_refund;
begin
    -- Validate the provider attempt identifiers
    if nullif(btrim(p_expected_idempotency_key), '') is null then
        raise exception 'expected idempotency key is required';
    end if;

    if nullif(btrim(p_provider_refund_id), '') is null then
        raise exception 'provider refund id is required';
    end if;

    -- Resolve and lock the event before its purchase and durable refund
    select ep.event_id
    into v_event_id
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    perform 1
    from event
    where event_id = v_event_id
    for update;

    -- Lock the purchase and durable refund before accepting the provider result
    select epr.*
    into v_refund
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update of ep, epr;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Ignore superseded attempts and delayed success for terminal refunds
    if v_refund.idempotency_key = p_expected_idempotency_key
       and not (
           v_refund.status = 'provider-failed'
           and v_refund.provider_refund_id is not null
       ) then
        -- Reject a result that conflicts with the pinned provider refund
        if v_refund.provider_refund_id is not null
           and v_refund.provider_refund_id <> p_provider_refund_id then
            raise exception 'event purchase refund already has a different provider refund id';
        end if;

        -- Record provider success without downgrading local finalization
        if v_refund.status <> 'finalized' then
            update event_purchase_refund
            set
                failure_message = null,
                provider_refund_id = p_provider_refund_id,
                provider_refunded_at = coalesce(provider_refunded_at, current_timestamp),
                status = case
                    when finalized_at is null then 'provider-succeeded'
                    else 'finalized'
                end,
                updated_at = current_timestamp
            where event_purchase_refund_id = p_event_purchase_refund_id
            returning * into v_refund;
        end if;

        -- Restore the accurate purchase state only when recovery is still pending
        if v_refund.finalized_at is not null then
            update event_purchase
            set
                refunded_at = coalesce(refunded_at, current_timestamp),
                status = 'refunded',
                updated_at = current_timestamp
            where event_purchase_id = v_refund.event_purchase_id
            and status = 'refund-recovery-pending';

            if not found then
                perform 1
                from event_purchase
                where event_purchase_id = v_refund.event_purchase_id
                and status = 'refunded';

                if not found then
                    raise exception 'finalized event purchase not found';
                end if;
            end if;
        end if;
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
