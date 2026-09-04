-- Records an in-progress provider refund for the current idempotency attempt.
create or replace function record_event_purchase_refund_pending(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_expected_claim_id uuid default null
)
returns jsonb as $$
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

    -- Lock the durable refund row before accepting the provider result
    select *
    into v_refund
    from event_purchase_refund
    where event_purchase_refund_id = p_event_purchase_refund_id
    for update;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    if v_refund.claim_id is distinct from p_expected_claim_id then
        raise exception 'event purchase refund claim is stale';
    end if;

    -- Ignore stale attempts and avoid reviving completed or terminal refunds
    if v_refund.idempotency_key = p_expected_idempotency_key then
        if v_refund.provider_refund_id is not null
           and v_refund.provider_refund_id <> p_provider_refund_id then
            raise exception 'event purchase refund already has a different provider refund id';
        end if;

        if v_refund.status not in ('finalized', 'provider-succeeded')
           and not (
               v_refund.status = 'provider-failed'
               and v_refund.terminal_failure
           ) then
            -- Record provider progress without reviving a terminal refund
            update event_purchase_refund
            set
                claim_id = null,
                claimed_at = null,
                failure_message = null,
                next_attempt_at = current_timestamp + make_interval(
                    mins => least(30, (power(2, greatest(attempt_count - 1, 0)))::int)
                ),
                provider_refund_id = p_provider_refund_id,
                status = 'provider-pending',
                terminal_failure = false,
                updated_at = current_timestamp
            where event_purchase_refund_id = p_event_purchase_refund_id
            returning * into v_refund;
        end if;
    end if;

    -- Return the durable refund state after recording provider progress
    return event_purchase_refund_to_json(v_refund);
end;
$$ language plpgsql;
