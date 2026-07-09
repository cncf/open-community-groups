-- Records a terminal provider refund failure and prepares a fresh retry attempt.
create or replace function record_event_purchase_refund_terminal_failed(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_failure_message text
)
returns void as $$
declare
    v_refund event_purchase_refund;
begin
    -- Validate the provider attempt identifiers
    if nullif(btrim(p_expected_idempotency_key), '') is null then
        raise exception 'expected idempotency key is required';
    end if;

    if nullif(btrim(p_provider_refund_id), '') is null then
        raise exception 'provider refund id is required';
    end if;

    -- Lock the durable refund row before rotating the provider attempt
    select *
    into v_refund
    from event_purchase_refund
    where event_purchase_refund_id = p_event_purchase_refund_id
    for update;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Ignore stale or completed attempts and reject conflicting provider ids
    if v_refund.idempotency_key <> p_expected_idempotency_key then
        return;
    end if;

    if v_refund.status in ('provider-succeeded', 'finalized') then
        return;
    end if;

    if v_refund.provider_refund_id is not null
       and v_refund.provider_refund_id <> p_provider_refund_id then
        raise exception 'event purchase refund already has a different provider refund id';
    end if;

    -- Rotate the idempotency key so a retry can create a fresh provider refund
    update event_purchase_refund
    set
        failure_message = concat_ws(
            ': ',
            nullif(btrim(p_failure_message), ''),
            p_provider_refund_id
        ),
        idempotency_key = format(
            'event-purchase-refund-%s-%s',
            v_refund.event_purchase_id,
            gen_random_uuid()
        ),
        provider_refund_id = null,
        status = 'provider-failed',
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id;
end;
$$ language plpgsql;
