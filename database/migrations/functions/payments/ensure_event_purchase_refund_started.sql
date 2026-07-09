-- Ensures a durable refund record exists before calling the payments provider.
create or replace function ensure_event_purchase_refund_started(
    p_event_purchase_id uuid,
    p_payment_provider_id text,
    p_kind text
)
returns jsonb as $$
declare
    v_amount_minor bigint;
    v_currency_code text;
    v_event_refund_request_id uuid;
    v_idempotency_key text;
    v_refund event_purchase_refund;
    v_refund_request_status text;
    v_started_now boolean := false;
    v_status text;
begin
    -- Validate the refund handoff inputs
    if nullif(btrim(p_payment_provider_id), '') is null then
        raise exception 'payment provider id is required';
    end if;

    if p_kind is null
       or p_kind not in ('automatic-unfulfillable-checkout', 'refund-request-approval') then
        raise exception 'unsupported refund kind: %', p_kind;
    end if;

    -- Lock and validate the purchase state this refund will reconcile
    select
        ep.amount_minor,
        ep.currency_code,
        err.event_refund_request_id,
        err.status,
        ep.status
    into
        v_amount_minor,
        v_currency_code,
        v_event_refund_request_id,
        v_refund_request_status,
        v_status
    from event_purchase ep
    left join event_refund_request err on err.event_purchase_id = ep.event_purchase_id
    where ep.event_purchase_id = p_event_purchase_id
    for update of ep;

    if not found then
        raise exception 'event purchase not found';
    end if;

    if p_kind = 'refund-request-approval' then
        -- Require the purchase and request states established by the approval handoff
        if v_status <> 'refund-requested'
           or v_event_refund_request_id is null
           or v_refund_request_status <> 'approving' then
            raise exception 'refund request not found';
        end if;
    elsif p_kind = 'automatic-unfulfillable-checkout' then
        -- Require the purchase state established by unfulfillable checkout reconciliation
        if v_status <> 'refund-pending' then
            raise exception 'refund-pending purchase not found';
        end if;
    end if;

    -- Derive the stable provider idempotency key for the first attempt
    v_idempotency_key := format('event-purchase-refund-%s', p_event_purchase_id);

    -- Insert the first local record before any provider side effect happens
    insert into event_purchase_refund (
        amount_minor,
        currency_code,
        event_purchase_id,
        idempotency_key,
        kind,
        payment_provider_id,
        status,

        event_refund_request_id
    ) values (
        v_amount_minor,
        v_currency_code,
        p_event_purchase_id,
        v_idempotency_key,
        p_kind,
        p_payment_provider_id,
        'provider-pending',

        case when p_kind = 'refund-request-approval' then v_event_refund_request_id end
    )
    on conflict (event_purchase_id) do nothing
    returning * into v_refund;

    -- Reuse and lock the durable record when another call already created it
    if found then
        v_started_now := true;
    else
        select *
        into v_refund
        from event_purchase_refund
        where event_purchase_id = p_event_purchase_id
        for update;
    end if;

    -- Reject retries that target a different provider workflow
    if v_refund.payment_provider_id <> p_payment_provider_id
       or v_refund.kind <> p_kind then
        raise exception 'event purchase refund already started with different provider or kind';
    end if;

    -- Return the provider refund state the application should continue from
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

            'started_now', v_started_now
        )
    );
end;
$$ language plpgsql;
