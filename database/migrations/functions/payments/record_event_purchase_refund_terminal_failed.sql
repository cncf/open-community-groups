-- Records a terminal provider refund failure for manual recovery.
create or replace function record_event_purchase_refund_terminal_failed(
    p_event_purchase_refund_id uuid,
    p_expected_idempotency_key text,
    p_provider_refund_id text,
    p_failure_message text
)
returns void as $$
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

    -- Lock the purchase and durable refund before recording terminal failure
    select epr.*
    into v_refund
    from event_purchase_refund epr
    join event_purchase ep on ep.event_purchase_id = epr.event_purchase_id
    where epr.event_purchase_refund_id = p_event_purchase_refund_id
    for update of ep, epr;

    if not found then
        raise exception 'event purchase refund not found';
    end if;

    -- Ignore stale attempts and reject conflicting provider ids
    if v_refund.idempotency_key <> p_expected_idempotency_key then
        return;
    end if;

    if v_refund.provider_refund_id is not null
       and v_refund.provider_refund_id <> p_provider_refund_id then
        raise exception 'event purchase refund already has a different provider refund id';
    end if;

    -- Treat the repeated terminal result for a pinned attempt as an idempotent replay
    if v_refund.status = 'provider-failed'
       and v_refund.provider_refund_id = p_provider_refund_id then
        return;
    end if;

    -- Pin the terminal provider attempt so it cannot be retried automatically
    update event_purchase_refund
    set
        failure_message = concat_ws(
            ': ',
            nullif(btrim(p_failure_message), ''),
            p_provider_refund_id
        ),
        provider_refund_id = p_provider_refund_id,
        provider_refunded_at = null,
        status = 'provider-failed',
        updated_at = current_timestamp
    where event_purchase_refund_id = p_event_purchase_refund_id;

    -- Expose post-finalization failures and block another checkout during recovery
    if v_refund.finalized_at is not null then
        update event_purchase
        set
            status = 'refund-recovery-pending',
            updated_at = current_timestamp
        where event_purchase_id = v_refund.event_purchase_id
        and status in ('refunded', 'refund-recovery-pending');

        if not found then
            raise exception 'finalized event purchase not found';
        end if;
    end if;
end;
$$ language plpgsql;
